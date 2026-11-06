#!/usr/bin/env python3
"""Bounded, advisory comparisons of declared feature contracts. No dispatch."""

import argparse
import fnmatch
import hashlib
import json
import math
import os
import re
import stat
import sys
from dataclasses import dataclass

MAX_BYTES = 1048576
MAX_LINES = 10000
MAX_LINE = 16384
MAX_TASKS = 256
MAX_FINDINGS = 256
MAX_SCAN = 20000
MAX_MATCHES = 2048
MAX_PATHS = 512
RULE_VERSION = "feature-analysis-2"
REQUIREMENT_ID = r"(?:FR-?\d+|US-?\d+|B\d+)"
TASK_ID = re.compile(r"^T\d{1,9}$")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def manifest_analysis_inputs(manifest):
    """Administrative receipts do not make a new artifact revision."""
    def authors(value):
        if not isinstance(value, list):
            return value
        identities = [{key: item.get(key) for key in ("provider", "model")} if isinstance(item, dict) else item
                      for item in value]
        return sorted(identities, key=lambda item: canonical(item))

    artifacts = manifest.get("artifacts", {})
    artifact_authors = {}
    if isinstance(artifacts, dict):
        artifact_authors = {key: authors(value.get("authors")) for key, value in artifacts.items()
                            if isinstance(value, dict) and "authors" in value}
        artifacts = {key: {"path": value.get("path"), "authors": authors(value.get("authors"))} if isinstance(value, dict) else value
                     for key, value in artifacts.items() if key in ("spec", "plan", "tasks")}
    return {"feature_id": manifest.get("feature_id", manifest.get("id")),
            "artifacts": artifacts, "authors": {"feature": authors(manifest.get("authors")), "artifacts": artifact_authors},
            "complexity": manifest.get("complexity"), "task_history": manifest.get("task_history"),
            "policy": manifest.get("policy")}


def json_object(text):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result
    def invalid_constant(_):
        raise ValueError("nonfinite JSON number")
    def finite_float(text):
        value = float(text)
        if not math.isfinite(value):
            raise ValueError("nonfinite JSON number")
        return value
    return json.loads(text, object_pairs_hook=pairs, parse_constant=invalid_constant,
                      parse_float=finite_float)


def relative_parts(path, patterns=False):
    if not isinstance(path, str) or not path or len(path) > 2048:
        raise ValueError("invalid relative path")
    if path.startswith("/") or "\\" in path or any(not c.isprintable() for c in path):
        raise ValueError("invalid relative path")
    parts = path.split("/")
    if any(p in ("", ".", "..") or p.lower() == ".git" for p in parts):
        raise ValueError("unsafe path component")
    if len(parts) > 64 or (not patterns and any(c in path for c in "*?[]")):
        raise ValueError("invalid path pattern")
    return parts


class ConfinedRoot:
    """Keep traversal and reads on non-link directory descriptors."""

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW

    def __init__(self, root):
        root = os.path.abspath(root)
        self.fd = os.open(os.sep, self.flags)
        self.scan_count = 0
        try:
            for part in root.split(os.sep):
                if not part:
                    continue
                child = os.open(part, self.flags, dir_fd=self.fd)
                os.close(self.fd)
                self.fd = child
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def directory(self, parts):
        current = os.dup(self.fd)
        try:
            for part in parts:
                child = os.open(part, self.flags, dir_fd=current)
                os.close(current)
                current = child
            return current
        except BaseException:
            os.close(current)
            raise

    def read(self, path):
        parts = relative_parts(path)
        parent = self.directory(parts[:-1])
        try:
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        finally:
            os.close(parent)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_BYTES:
                raise ValueError("not a bounded regular file")
            chunks, length = [], 0
            while length <= MAX_BYTES:
                chunk = os.read(fd, min(65536, MAX_BYTES + 1 - length))
                if not chunk:
                    break
                chunks.append(chunk)
                length += len(chunk)
            data = b"".join(chunks)
            after = os.fstat(fd)
            if len(data) > MAX_BYTES or (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValueError("file exceeded bound or changed during read")
        finally:
            os.close(fd)
        text = data.decode("utf-8")
        if any(c not in "\n\r\t" and not c.isprintable() for c in text):
            raise ValueError("text contains control characters")
        lines = text.splitlines()
        if len(lines) > MAX_LINES or any(len(line) > MAX_LINE for line in lines):
            raise ValueError("text exceeded line bounds")
        return Document(path, text, data)

    def scope(self, path, create=False):
        parts = relative_parts(path)
        current = os.dup(self.fd)
        try:
            for index, part in enumerate(parts):
                try:
                    info = os.stat(part, dir_fd=current, follow_symlinks=False)
                except FileNotFoundError:
                    if create:
                        return
                    raise ValueError("declared file does not exist")
                if stat.S_ISLNK(info.st_mode):
                    raise ValueError("declared path contains a link")
                if index < len(parts) - 1:
                    child = os.open(part, self.flags, dir_fd=current)
                    os.close(current)
                    current = child
                elif not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
                    raise ValueError("declared path is not a regular file or directory")
        finally:
            os.close(current)

    def expand(self, pattern):
        parts = relative_parts(pattern, patterns=True)
        if not any(c in pattern for c in "*?["):
            self.scope(pattern)
            return [pattern]
        matches = set()

        def walk(fd, index, prefix):
            if len(prefix) > 64:
                raise ValueError("file pattern exceeds depth bound")
            if index == len(parts):
                matches.add("/".join(prefix))
                if len(matches) > MAX_MATCHES:
                    raise ValueError("file pattern exceeds match bound")
                return
            token = parts[index]
            if token == "**":
                walk(fd, index + 1, prefix)
            with os.scandir(fd) as entries:
                names = []
                for entry in entries:
                    self.scan_count += 1
                    if self.scan_count > MAX_SCAN:
                        raise ValueError("file pattern exceeds scan bound")
                    names.append(entry.name)
            for name in sorted(names):
                if name.lower() == ".git" or (name.startswith(".") and not token.startswith(".")):
                    continue
                if token != "**" and not fnmatch.fnmatchcase(name, token):
                    continue
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode):
                    raise ValueError("file pattern matches a link")
                if token == "**" or index < len(parts) - 1:
                    if stat.S_ISDIR(info.st_mode):
                        child = os.open(name, self.flags, dir_fd=fd)
                        try:
                            walk(child, index if token == "**" else index + 1, prefix + [name])
                        finally:
                            os.close(child)
                    elif token == "**" and index == len(parts) - 1 and stat.S_ISREG(info.st_mode):
                        matches.add("/".join(prefix + [name]))
                        if len(matches) > MAX_MATCHES:
                            raise ValueError("file pattern exceeds match bound")
                elif stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode):
                    walk(fd, index + 1, prefix + [name])

        walk(self.fd, 0, [])
        matches.discard("")
        if not matches:
            raise ValueError("file pattern has no matches")
        return sorted(matches)


@dataclass
class Document:
    path: str
    text: str
    data: bytes

    @property
    def lines(self):
        return self.text.splitlines()

    @property
    def digest(self):
        return digest(self.data)

    def source(self, start, end=None):
        end = start if end is None else end
        if type(start) is not int or type(end) is not int or not 1 <= start <= end <= len(self.lines):
            raise ValueError("invalid source line range")
        quote = "\n".join(self.lines[start-1:end])
        if len(quote) > MAX_LINE:
            raise ValueError("source quotation exceeds bound")
        return {"path": self.path, "line_start": start, "line_end": end, "quote": quote}

    def task_source(self, task_id):
        for number, line in enumerate(self.lines, 1):
            if re.search(r'"id"\s*:\s*' + re.escape(json.dumps(task_id)) + r'(?:\s*[,}])', line):
                # Include the object fields after the ID, with an exact bounded quote.
                end = number
                while end < len(self.lines) and end - number < 50:
                    if "}" in self.lines[end-1]:
                        break
                    end += 1
                try:
                    return self.source(number, end)
                except ValueError:
                    return self.source(number)
            if re.match(r"\s*-\s*\[[ xX]\]\s+" + re.escape(task_id) + r"\b", line):
                return self.source(number)
        return self.source(1) if self.lines else None


def runtime_document(root, filename, label):
    """Only explicit CLI arguments may select a separate runtime parent."""
    if not os.path.isabs(filename):
        document = root.read(filename)
    else:
        parent = ConfinedRoot(os.path.dirname(filename))
        try:
            document = parent.read(os.path.basename(filename))
        finally:
            parent.close()
    return Document(label, document.text, document.data)


def fences(document, label, warnings):
    lines, index = document.lines, 0
    while index < len(lines):
        match = re.fullmatch(r"\s*(`{3,}|~{3,})" + re.escape(label) + r"\s*", lines[index])
        if not match:
            other = re.match(r"^\s*(`{3,}|~{3,})", lines[index])
            if other:
                marker = other.group(1)
                index += 1
                while index < len(lines) and not re.fullmatch(r"\s*" + re.escape(marker) + r"\s*", lines[index]):
                    index += 1
            index += 1
            continue
        first, marker = index + 1, match.group(1)
        index += 1
        while index < len(lines) and not re.fullmatch(r"\s*" + re.escape(marker) + r"\s*", lines[index]):
            index += 1
        if index == len(lines):
            warnings.append(f"{document.path}: unclosed {label} block")
            return
        try:
            value = json_object("\n".join(lines[first:index]))
            try:
                source = document.source(first + 1, index)
            except ValueError:
                source = document.source(first + 1)
            yield value, source
        except (ValueError, RecursionError):
            warnings.append(f"{document.path}: invalid or oversized {label} block")
        index += 1


def prose_lines(document):
    """Ignore examples in code blocks when reading Markdown declarations."""
    marker = None
    for number, line in enumerate(document.lines, 1):
        match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker is not None:
            if re.fullmatch(r"\s*" + re.escape(marker) + r"\s*", line):
                marker = None
            continue
        if match:
            marker = match.group(1)
            continue
        yield number, line


def requirements(document):
    result = {}
    table = False
    for number, line in prose_lines(document):
        if line.strip().startswith("|"):
            cells = [c.strip().strip("`*") for c in line.strip().strip("|").split("|")]
            if cells and cells[0].lower() in ("id", "requirement", "requirement id", "story id"):
                table = True
            elif table and cells and re.fullmatch(REQUIREMENT_ID, cells[0]):
                result[cells[0]] = document.source(number)
            continue
        table = False
        match = re.match(r"^\s*(?:#{1,6}\s+|[-*]\s+|\d+\.\s+|\*\*|`)(?:\*\*|`)?(" + REQUIREMENT_ID + r")(?:\*\*|`)?(?:\s*[:.)-]|\s+|$)", line)
        if match:
            result[match.group(1)] = document.source(number)
    return result


def declaration_value(kind, value):
    if kind == "enum":
        if isinstance(value, str):
            value = [v.strip().strip("`\"'") for v in value.strip("[]{} ").split(",")]
        if not isinstance(value, list) or not value or len(value) > MAX_TASKS or not all(isinstance(v, str) and v and len(v) <= 128 for v in value):
            raise ValueError("enum must be a nonempty string list")
        return sorted(set(value))
    if kind == "count":
        if type(value) is int:
            return value
        if isinstance(value, str) and re.fullmatch(r"\d{1,9}", value.strip("` ")):
            return int(value.strip("` "))
        raise ValueError("count must be an integer")
    if not isinstance(value, str) or not value.strip() or len(value) > MAX_LINE:
        raise ValueError("declaration must be text")
    return value.strip().strip("`")


def declarations(document, warnings):
    result, table_kind = [], None
    kinds = {"term": "term", "terminology": "term", "enum": "enum", "count": "count", "identifier": "identifier"}

    def add(kind, key, value, source):
        try:
            if not isinstance(key, str) or not key.strip() or len(key) > 128:
                raise ValueError("invalid declaration key")
            if len(result) >= MAX_TASKS:
                raise ValueError("declaration bound reached")
            result.append((kind, key.strip().strip("`"), declaration_value(kind, value), source))
        except ValueError:
            warnings.append(f"{document.path}: unsupported {kind} declaration")

    for number, line in prose_lines(document):
        if line.strip().startswith("|"):
            cells = [c.strip().strip("*") for c in line.strip().strip("|").split("|")]
            if len(cells) == 2 and cells[0].lower() in kinds:
                table_kind = kinds[cells[0].lower()]
            elif table_kind and len(cells) == 2 and not all(re.fullmatch(r":?-+:?", c) for c in cells):
                add(table_kind, cells[0], cells[1], document.source(number))
            elif table_kind:
                warnings.append(f"{document.path}: unsupported declaration table row")
            continue
        table_kind = None
        match = re.match(r"^\s*[-*]\s*(?:\*\*)?(Term|Terminology|Enum|Count|Identifier)(?:\*\*)?\s*:\s*([^=]+?)\s*=\s*(.+?)\s*$", line, re.I)
        if match:
            add(kinds[match.group(1).lower()], match.group(2), match.group(3), document.source(number))
    for value, source in fences(document, "octopus-declarations", warnings):
        if not isinstance(value, dict):
            warnings.append(f"{document.path}: declarations block must be an object")
            continue
        groups = {"terms": "term", "terminology": "term", "enums": "enum", "counts": "count", "identifiers": "identifier"}
        for group, mapping in value.items():
            if group not in groups or not isinstance(mapping, dict) or len(mapping) > MAX_TASKS:
                warnings.append(f"{document.path}: unsupported declarations group")
                continue
            for key, item in mapping.items():
                # A large structured block still needs the exact declaration usage.
                key_source = source
                group_seen = False
                for number, line in enumerate(document.lines, 1):
                    if number < source["line_start"]:
                        continue
                    if re.match(r"\s*(?:`{3,}|~{3,})\s*$", line):
                        break
                    if re.search(re.escape(json.dumps(group)) + r"\s*:\s*\{", line):
                        group_seen = True
                    if not group_seen:
                        continue
                    if re.search(re.escape(json.dumps(key)) + r"\s*:", line):
                        end = number
                        if isinstance(item, list) and "]" not in line:
                            while end < len(document.lines) and end - number < MAX_TASKS:
                                end += 1
                                if "]" in document.lines[end-1]:
                                    break
                        try:
                            key_source = document.source(number, end)
                        except ValueError:
                            warnings.append(f"{document.path}: declaration quote exceeds bound")
                            key_source = None
                        break
                if key_source:
                    add(groups[group], key, item, key_source)
    return result


def task_contract(value, warnings):
    if not isinstance(value, dict) or type(value.get("schema_version")) is not int or value.get("schema_version") != 1 or not isinstance(value.get("tasks"), list):
        warnings.append("unsupported task contract; coverage and identity checks skipped")
        return None
    if len(value["tasks"]) > MAX_TASKS:
        warnings.append("task contract exceeds task bound; coverage and identity checks skipped")
        return None
    ids, identities, paths = set(), set(), 0
    for task in value["tasks"]:
        if not isinstance(task, dict) or not isinstance(task.get("id"), str) or not TASK_ID.fullmatch(task["id"]):
            warnings.append("invalid task identity; task contract checks skipped")
            return None
        identity = task.get("identity")
        if identity is not None and (not isinstance(identity, str) or not identity or len(identity) > 128):
            warnings.append("invalid persistent task identity; task contract checks skipped")
            return None
        if task["id"] in ids or (identity and identity in identities):
            warnings.append("duplicate task identity; task contract checks skipped")
            return None
        ids.add(task["id"])
        if identity:
            identities.add(identity)
        for key in ("requirements", "reads", "files", "creates", "dependencies"):
            items = task.get(key, [])
            if not isinstance(items, list) or len(items) > MAX_TASKS or not all(isinstance(v, str) and len(v) <= 2048 for v in items):
                warnings.append("unsupported task fields; task contract checks skipped")
                return None
            if key in ("files", "creates"):
                paths += len(items)
        if paths > MAX_PATHS or "requirements" not in task:
            warnings.append("task path bound exceeded or requirement metadata absent; task contract checks skipped")
            return None
        if not all(re.fullmatch(REQUIREMENT_ID, v) for v in task.get("requirements", [])):
            warnings.append("unsupported requirement identifier; task contract checks skipped")
            return None
    return value


def legacy_tasks(document, warnings):
    tasks = []
    for _, line in prose_lines(document):
        match = re.match(r"^\s*-\s*\[[ xX]\]\s+(T\d{1,9})\b(.*)$", line)
        if not match:
            continue
        refs = re.findall(r"\[(" + REQUIREMENT_ID + r")\]", match.group(2))
        if not refs:
            warnings.append(f"{document.path}: legacy task lacks structured requirement provenance")
            return None
        tasks.append({"id": match.group(1), "requirements": refs})
    return task_contract({"schema_version": 1, "tasks": tasks}, warnings) if tasks else None


def policy_snapshot(value, warnings):
    if not isinstance(value, dict) or type(value.get("schema_version")) is not int or value.get("schema_version") != 1 or not value.get("source"):
        warnings.append("no bound policy source found")
        return None
    text = value.get("text")
    try:
        relative_parts(value["source"])
        if not isinstance(text, str) or len(text.encode()) > MAX_BYTES or any(c not in "\r\n\t" and not c.isprintable() for c in text):
            raise ValueError("invalid policy text")
        if digest(text.encode("utf-8")) != value.get("digest"):
            raise ValueError("policy digest mismatch")
        document = Document(value["source"], text, text.encode("utf-8"))
        if len(document.lines) > MAX_LINES or any(len(line) > MAX_LINE for line in document.lines):
            raise ValueError("policy text exceeded bounds")
        return document
    except (ValueError, UnicodeError):
        warnings.append("bound policy snapshot failed source/digest/text validation")
        return None


def analyze(args, *, digest_only=False):
    root = ConfinedRoot(args.root)
    warnings, artifacts, manifest, inputs = [], {}, {}, {}
    try:
        feature_parts = [] if args.feature in ("", ".") else relative_parts(args.feature)
        feature = "/".join(feature_parts)
        feature_prefix = feature + "/" if feature else ""
        directory = root.directory(feature_parts)
        os.close(directory)
        try:
            manifest_doc = root.read(feature_prefix + "feature.json")
            manifest = json_object(manifest_doc.text)
            if not isinstance(manifest, dict) or type(manifest.get("schema_version", 1)) is not int or manifest.get("schema_version", 1) != 1:
                raise ValueError("invalid feature manifest")
            inputs["manifest"] = digest(canonical(manifest_analysis_inputs(manifest)))
        except FileNotFoundError:
            pass
        except (OSError, ValueError, RecursionError):
            manifest = {}
            warnings.append("feature manifest unavailable or unsupported; using standard artifact names")
        declared = manifest.get("artifacts", {})
        if not isinstance(declared, dict):
            declared = {}
            warnings.append("unsupported artifact map; using standard artifact names")
        for kind in ("spec", "plan", "tasks"):
            entry = declared.get(kind, kind + ".md")
            path = entry.get("path") if isinstance(entry, dict) else entry
            try:
                relative_parts(path)
                if "/" not in path:
                    path = feature_prefix + path
                # Repository content cannot select a different feature or an external file.
                if not path.startswith(feature_prefix):
                    raise ValueError("artifact outside selected feature")
                artifacts[kind] = root.read(path)
            except FileNotFoundError:
                pass
            except (OSError, ValueError, UnicodeError):
                warnings.append(f"{kind} artifact unavailable or unsafe")
        runtime = {}
        for name in ("contract", "policy", "previous", "findings"):
            filename = getattr(args, name)
            if filename:
                document = runtime_document(root, filename, "runtime:" + name)
                runtime[name] = (json_object(document.text), document)
                inputs[name] = document.digest
        distinct_artifacts = {d.path for d in artifacts.values()}
        if len(distinct_artifacts) != len(artifacts):
            warnings.append("artifact map repeats a path; repeated files count once")
        report = {"schema_version": 1, "feature_id": manifest.get("feature_id", manifest.get("id")),
                  "eligible": len(distinct_artifacts) >= 2, "analysis_digest": "",
                  "artifact_digests": {d.path: d.digest for d in artifacts.values()},
                  "findings": [], "warnings": warnings, "escalate": {"eligible": False, "trigger": "none"}}
        report["analysis_digest"] = digest(canonical({"rules": RULE_VERSION, "feature": feature,
                                                     "artifacts": report["artifact_digests"], "inputs": inputs}))
        if digest_only or not report["eligible"]:
            return report
        findings = report["findings"]
        seen = set()

        def finding(kind, severity, sources, requirement_ids=None, task_ids=None, **details):
            if len(findings) >= MAX_FINDINGS:
                warnings.append("finding bound reached; report is partial")
                return
            item = {"kind": kind, "severity": severity, "requirement_ids": sorted(set(requirement_ids or [])),
                    "task_ids": sorted(set(task_ids or [])), "sources": [s for s in sources if s], **details}
            identity = digest(canonical(item))
            if identity not in seen:
                seen.add(identity)
                findings.append(item)

        spec = artifacts.get("spec")
        reqs = requirements(spec) if spec else {}
        if spec and not reqs:
            warnings.append(f"{spec.path}: no explicit requirement IDs; requirement coverage checks skipped")
        tasks_doc, contract = artifacts.get("tasks"), None
        if "contract" in runtime:
            value, contract_doc = runtime["contract"]
            contract = task_contract(value, warnings)
            if contract is not None:
                tasks_doc = contract_doc
        elif tasks_doc:
            warning_count = len(warnings)
            blocks = list(fences(tasks_doc, "octopus-tasks", warnings))
            if len(blocks) == 1:
                contract = task_contract(blocks[0][0], warnings)
            elif len(blocks) > 1:
                warnings.append("multiple task contracts; task contract checks skipped")
            elif len(warnings) == warning_count:
                contract = legacy_tasks(tasks_doc, warnings)
                if contract is None:
                    warnings.append(f"{tasks_doc.path}: no supported task contract; coverage checks skipped")
        if contract is not None:
            if contract.get("feature_id") and report["feature_id"] and contract["feature_id"] != report["feature_id"]:
                warnings.append("task contract feature identity differs; contract checks skipped")
                contract = None
        if contract is not None:
            linked = set()
            for task in contract["tasks"]:
                refs = task.get("requirements", [])
                source = tasks_doc.task_source(task["id"])
                linked.update(refs)
                if not refs:
                    finding("task_unlinked", "medium", [source], task_ids=[task["id"]])
                elif spec and reqs:
                    for ref in refs:
                        if ref not in reqs:
                            finding("task_requirement_unknown", "high", [source], requirement_ids=[ref], task_ids=[task["id"]])
                for key in ("files", "creates"):
                    for path in task.get(key, []):
                        try:
                            root.scope(path, create=True) if key == "creates" else root.expand(path)
                        except (OSError, ValueError, RecursionError):
                            finding("path_unresolved", "medium", [source], task_ids=[task["id"]], field=key, path=path)
            for ref in sorted(set(reqs) - linked):
                finding("requirement_uncovered", "high", [reqs[ref]], requirement_ids=[ref])
            if "previous" in runtime:
                previous_value, previous_doc = runtime["previous"]
                previous = task_contract(previous_value, warnings)
                if previous is not None:
                    if previous.get("feature_id") and contract.get("feature_id") and previous["feature_id"] != contract["feature_id"]:
                        warnings.append("previous contract belongs to a different feature; history checks skipped")
                    else:
                        history_checks(contract, previous, tasks_doc, previous_doc, finding, warnings)
        groups = {}
        for document in artifacts.values():
            for kind, key, value, source in declarations(document, warnings):
                entries = groups.setdefault((kind, key), [])
                for old_value, old_source in entries:
                    if old_value != value and old_source["path"] != source["path"]:
                        finding("declaration_conflict", "medium", [old_source, source], declaration_kind=kind, key=key)
                        break
                entries.append((value, source))
        policy = policy_snapshot(runtime["policy"][0], warnings) if "policy" in runtime else None
        if "findings" in runtime:
            value, document = runtime["findings"]
            candidates = value.get("findings") if isinstance(value, dict) else value
            if not isinstance(candidates, list) or len(candidates) > MAX_TASKS:
                warnings.append("unsupported explicit policy findings snapshot")
            else:
                try:
                    source = document.source(1, len(document.lines))
                except ValueError:
                    source = document.source(1) if document.lines else None
                for candidate in candidates:
                    verify_policy_reference(candidate, policy, artifacts.get("plan"), source, finding)
        for document in artifacts.values():
            for value, source in fences(document, "octopus-policy-findings", warnings):
                candidates = value.get("findings") if isinstance(value, dict) else value
                if not isinstance(candidates, list) or len(candidates) > MAX_TASKS:
                    warnings.append(f"{document.path}: unsupported policy findings block")
                    continue
                for candidate in candidates:
                    verify_policy_reference(candidate, policy, artifacts.get("plan"), source, finding)
        complexity = manifest.get("complexity")
        complex_feature = complexity == "complex" or (isinstance(complexity, dict) and (complexity.get("level") == "complex" or complexity.get("complex") is True))
        unresolved = {digest(canonical({k: v for k, v in f.items() if k != "sources"})) for f in findings}
        if len(unresolved) >= 2:
            report["escalate"] = {"eligible": True, "trigger": "two_distinct_findings"}
        elif findings and complex_feature and any(f["severity"] == "high" and f["kind"] in ("requirement_uncovered", "task_requirement_unknown", "policy_violation") for f in findings):
            report["escalate"] = {"eligible": True, "trigger": "complex_high_impact_finding"}
        report["warnings"] = list(dict.fromkeys(warnings))[:64]
        return report
    finally:
        root.close()


def history_checks(contract, previous, current_doc, previous_doc, finding, warnings):
    old_ids = {t["id"]: t for t in previous["tasks"]}
    old_identities = {t["identity"]: t for t in previous["tasks"] if t.get("identity")}
    tombstones = previous.get("tombstones", [])
    if not isinstance(tombstones, list) or len(tombstones) > MAX_TASKS:
        warnings.append("unsupported task tombstones; tombstone checks skipped")
        tombstones = []
    retired = set()
    for item in tombstones:
        task_id = item if isinstance(item, str) else item.get("id") if isinstance(item, dict) else None
        if isinstance(task_id, str) and TASK_ID.fullmatch(task_id):
            retired.add(task_id)
        else:
            warnings.append("unsupported task tombstone; invalid history entry ignored")
    watermark = previous.get("high_watermark", 0)
    if type(watermark) is not int or watermark < 0:
        warnings.append("unsupported task high watermark; monotonic ID check skipped")
        watermark = 0
    for task in contract["tasks"]:
        task_id, identity = task["id"], task.get("identity")
        old = old_ids.get(task_id)
        sources = [current_doc.task_source(task_id)]
        if old:
            sources.append(previous_doc.task_source(task_id))
        if task_id in retired or (old and identity and old.get("identity") and old["identity"] != identity):
            finding("task_id_reused", "high", sources, task_ids=[task_id])
        if identity and identity in old_identities and old_identities[identity]["id"] != task_id:
            old_id = old_identities[identity]["id"]
            finding("task_id_drift", "high", [current_doc.task_source(task_id), previous_doc.task_source(old_id)], task_ids=[old_id, task_id])
        elif not old and task_id not in retired and int(task_id[1:]) <= watermark:
            finding("task_id_reused", "high", sources, task_ids=[task_id], reason="below_previous_high_watermark")


def verify_policy_reference(candidate, policy, plan, source, finding):
    try:
        if not isinstance(candidate, dict) or policy is None or plan is None:
            raise ValueError("no verified policy or plan snapshot")
        if candidate.get("source") != policy.path or candidate.get("digest") != policy.digest or candidate.get("plan_digest") != plan.digest:
            raise ValueError("snapshot reference mismatch")
        policy_source = policy.source(candidate.get("line_start"), candidate.get("line_end"))
        plan_source = plan.source(candidate.get("plan_line_start"), candidate.get("plan_line_end"))
        if candidate.get("quote") != policy_source["quote"] or candidate.get("plan_action") != plan_source["quote"]:
            raise ValueError("quote mismatch")
        # The author supplied the semantic claim. This helper only verifies evidence.
        finding("policy_violation", "high", [policy_source, plan_source], policy_digest=policy.digest, plan_digest=plan.digest)
    except (ValueError, TypeError):
        finding("policy_reference_invalid", "medium", [source], reason="unverified_source_digest_or_quote")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("analyze")
    command.add_argument("--root", required=True)
    command.add_argument("--feature", required=True)
    for name in ("contract", "policy", "previous", "findings"):
        command.add_argument("--" + name)
    args = parser.parse_args()
    try:
        report = analyze(args)
    except (OSError, ValueError, UnicodeError, RecursionError):
        # Do not echo unreadable paths, file contents or exception values.
        print("feature analysis: invalid root, feature or explicit runtime snapshot", file=sys.stderr)
        return 2
    print(json.dumps(report, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
