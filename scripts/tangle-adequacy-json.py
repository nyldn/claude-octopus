#!/usr/bin/env python3
from __future__ import annotations
import json, re, sys

PATH_RE=re.compile(r"^[A-Za-z0-9_.@%+/-]+$")
ACTIONS={"move_to_reads","remove_write","add_write"}

def safe_relative_path(value:str):
    normalized=value[2:] if value.startswith("./") else value
    if normalized.endswith("/"):
        normalized=normalized[:-1]
    if not normalized or not normalized.strip() or not PATH_RE.fullmatch(normalized):
        return False
    if normalized.startswith("/") or any(part in {".",".."} for part in normalized.split("/")):
        return False
    if any(part.lower()==".git" for part in normalized.split("/")):
        return False
    return True

def extract(raw:str):
    raw=raw.strip()
    if raw.startswith("```"):
        lines=raw.splitlines()
        if lines and lines[0].strip() in {"```","```json","```JSON"}:
            raw="\n".join(lines[1:-1] if lines[-1].strip()=="```" else lines[1:]).strip()
    try:
        obj=json.loads(raw)
        return obj if isinstance(obj,dict) else None
    except json.JSONDecodeError:
        pass
    dec=json.JSONDecoder(); found=[]
    for i,ch in enumerate(raw):
        if ch!="{": continue
        try: obj,end=dec.raw_decode(raw[i:])
        except json.JSONDecodeError: continue
        if isinstance(obj,dict): found.append((i,i+end,obj))
    maximal=[]
    for candidate in found:
        st,en,_=candidate
        if any(ost<=st and en<=oen and (ost,oen)!=(st,en) for ost,oen,_ in found):
            continue
        maximal.append(candidate)
    return maximal[0][2] if len(maximal)==1 else None

def valid(obj):
    if not isinstance(obj,dict) or set(obj)!={"schema_version","verdict","reasons","scope_review"}: return False
    if isinstance(obj["schema_version"], bool) or obj["schema_version"]!=1 or obj["verdict"] not in {"pass","fail"}: return False
    reasons=obj["reasons"]; review=obj["scope_review"]
    if not isinstance(reasons,list) or not reasons or not all(isinstance(x,str) and x.strip() for x in reasons): return False
    if not isinstance(review,list): return False
    for item in review:
        if not isinstance(item,dict) or set(item)!={"action","path","reason"}: return False
        if item["action"] not in ACTIONS: return False
        if not isinstance(item["path"],str) or not safe_relative_path(item["path"]) or any(x in item["path"] for x in "*?[]"): return False
        if not isinstance(item["reason"],str) or not item["reason"].strip(): return False
    if obj["verdict"]=="pass" and review: return False
    if obj["verdict"]=="fail" and not review and not reasons: return False
    return True

def render(obj):
    print("VERDICT: "+obj["verdict"].upper())
    print("REASONS:")
    for r in obj["reasons"]: print("- "+re.sub(r"\s+"," ",r.strip()))
    if not obj["scope_review"]:
        print("SCOPE_REVIEW: NONE")
        return
    print("SCOPE_REVIEW:")
    names={"move_to_reads":"MOVE_TO_READS","remove_write":"REMOVE_WRITE","add_write":"ADD_WRITE"}
    for item in obj["scope_review"]:
        reason=re.sub(r"\s+"," ",item["reason"].strip())
        print(f"- {names[item['action']]}: {item['path']} — {reason}")

raw=sys.stdin.read(); obj=extract(raw)
# A PASS verdict cannot carry scope actions, so a reviewer that omits the
# empty scope_review list has still returned an unambiguous verdict.
if isinstance(obj,dict) and obj.get("verdict")=="pass" and "scope_review" not in obj:
    obj["scope_review"]=[]
if obj is None or not valid(obj): raise SystemExit(1)
if len(sys.argv)>1 and sys.argv[1]=="render": render(obj)
else: sys.stdout.write(json.dumps(obj,ensure_ascii=False,separators=(",",":"))+"\n")
