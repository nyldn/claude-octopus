#!/usr/bin/env python3
"""Fetch a bounded set of search suggestions, never page contents or model output."""
import ipaddress
import json
import os
import re
import signal
import sys
import urllib.request
from urllib.parse import urlsplit

MAX_QUERY_BYTES = 16384
MAX_RESPONSE_BYTES = 65536


class DeadlineExceeded(Exception):
    """Escape socket address retries, which catch OSError and TimeoutError."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        """Refuse redirects so search credentials never reach another origin."""
        return None


def validated_hostname(parsed):
    """Validate bracketed hosts independently of the interpreter patch level."""
    hostname = parsed.hostname
    if hostname and "[" in parsed.netloc and not re.fullmatch(r"v[0-9a-f]+\..+", hostname):
        if ipaddress.ip_address(hostname).version != 6:
            raise ValueError("invalid bracketed host")
    return hostname


def search(query):
    """Make one fixed-origin request; results remain untrusted citation candidates."""
    if not query.strip() or len(query.encode("utf-8")) > MAX_QUERY_BYTES:
        raise ValueError("invalid search query")
    key = os.environ.get("KEENABLE_API_KEY", "").strip()
    endpoint = "https://api.keenable.ai/v1/search" + ("" if key else "/public")
    headers = {"Content-Type": "application/json", "X-Keenable-Title": "Claude Octopus"}
    if key:
        headers["X-API-Key"] = key
    payload = {"query": query, "max_results": 5, "snippet_max_length": 500}
    request = urllib.request.Request(endpoint, data=json.dumps(payload).encode("utf-8"),
                                     headers=headers, method="POST")
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=15) as response:
        raw = response.read(MAX_RESPONSE_BYTES + 1)
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ValueError("search response exceeds limit")
    data = json.loads(raw)
    if not isinstance(data, dict) or not isinstance(data.get("results"), list):
        raise ValueError("invalid search results")
    results = []
    for item in data["results"][:5]:
        if not isinstance(item, dict):
            continue
        title, url, snippet = (item.get(field) for field in ("title", "url", "snippet"))
        if not all(isinstance(value, str) for value in (title, url, snippet)):
            continue
        if len(url) > 2048 or any(character.isspace() or ord(character) < 32 for character in url):
            continue
        try:
            parsed = urlsplit(url)
            hostname = validated_hostname(parsed)
        except ValueError:
            continue
        if parsed.scheme not in {"https", "http"} or not hostname or parsed.username or parsed.password:
            continue
        results.append(f"{len(results) + 1}. {' '.join(title.split())[:300]}\n{url}\n{' '.join(snippet.split())[:500]}")
    return "\n\n".join(results)


def deadline(signum, frame):
    """Abort total request time without entering socket retry handling."""
    raise DeadlineExceeded("search deadline exceeded")


def main():
    """Emit bounded search suggestions or a diagnostic that contains no secrets."""
    alarm_armed = False
    try:
        if not hasattr(signal, "SIGALRM") or not callable(getattr(signal, "alarm", None)):
            raise OSError("total search deadline unavailable")
        signal.signal(signal.SIGALRM, deadline)
        signal.alarm(15)
        alarm_armed = True
        query = sys.stdin.buffer.read(MAX_QUERY_BYTES + 1).decode("utf-8")
        output = search(query)
    except (OSError, ValueError, DeadlineExceeded):
        print("Optional Keenable search unavailable; continuing without search suggestions.", file=sys.stderr)
        return 1
    finally:
        if alarm_armed:
            signal.alarm(0)
    if output:
        print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
