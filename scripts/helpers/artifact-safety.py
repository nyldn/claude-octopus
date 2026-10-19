#!/usr/bin/env python3
"""Redact recognizable credentials and certify portable artifact text silently."""

import re
import sys

MAX_BYTES = 1048576
PROVIDER = re.compile(r"(?:pplx-|sk-(?:ant-|proj-)?|sk_live_|rk_live_|gh[pousr]_|github_pat_|glpat-|xox[baprs]-|hf_|AIza)[A-Za-z0-9._-]{16,}|(?:AKIA|ASIA)[0-9A-Z]{16}")
PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----.*?-----END (?:[A-Z0-9 ]+ )?PRIVATE KEY-----", re.S)
BEARER = re.compile(r"\b(?:Bearer|Basic)[ \t]+([A-Za-z0-9._~+/-]+={0,2})", re.I)
JWT = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
URL_AUTH = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://[^\s@/:]*:[^\s@/]+@")
AUTH_HEADER = re.compile(r"Authorization[\"']?\s*:\s*[\"']?(?:Bearer|Basic)\s+[A-Za-z0-9._~+/-]+={0,2}", re.I)
PRIVATE_START = re.compile(r'-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----')
ASSIGNMENT = re.compile(r'''(?im)["']?\b([A-Za-z][A-Za-z0-9_]*(?:API_KEY|ACCESS_TOKEN|REFRESH_TOKEN|SECRET|PASSWORD|PRIVATE_KEY)|API_KEY|ACCESS_TOKEN|REFRESH_TOKEN|PRIVATE_KEY|TOKEN|SECRET|PASSWORD)["']?\s*[:=]\s*(.*)''')


def placeholder(value):
    value = value.strip().strip('"\'`*_ ,;')
    return (value.lower() in ('', 'redacted', '<redacted>', 'example', '***')
            or re.fullmatch(r'\[REDACTED(?:-[A-Z-]+)?\]', value)
            or re.fullmatch(r'\$\{?[A-Za-z][A-Za-z0-9_]*\}?', value)
            or re.fullmatch(r'\$\{\{\s*(?:secrets|vars|env)\.[A-Za-z][A-Za-z0-9_]*\s*\}\}', value, re.I))


def auth_prose(match):
    # Keep these documentation phrases; headers are always credentials.
    scheme = match.group(0).split()[0].lower()
    value = match.group(1).lower()
    if scheme == 'basic' and value in ('authentication', 'usage', 'example'):
        return True
    return (scheme == 'bearer' and value == 'of'
            and re.search(r'\bthe[ \t]+$', match.string[:match.start()], re.I)
            and re.match(r'[ \t]+the[ \t]+token\b', match.string[match.end():], re.I))


def policy_prose(match):
    # Only unquoted bare prose keys and complete policy phrases qualify.
    # Unknown values, quoted assignments and environment identifiers fail closed.
    name = match.group(1)
    prefix = match.string[match.string.rfind('\n', 0, match.start()) + 1:match.start()]
    if (match.group(0).startswith(('"', "'")) or name.isupper()
            or not re.fullmatch(r'[ \t]*(?:[-*][ \t]+)?', prefix)):
        return False
    value = match.group(2).strip()
    patterns = {'password': r'(?:must contain )?[0-9]+ characters\.?',
                'secret': r'rotated monthly\.?'}
    pattern = patterns.get(name.lower())
    return bool(pattern and re.fullmatch(pattern, value, re.I))


def clean_text(text):
    """Return a redacted copy. Call certify afterwards; redaction is not proof."""
    text = PRIVATE_KEY.sub('[REDACTED-PRIVATE-KEY]', text)
    text = PROVIDER.sub('[REDACTED-API-KEY]', text)
    text = AUTH_HEADER.sub('[REDACTED-AUTHORIZATION]', text)
    text = BEARER.sub(lambda match: match.group(0) if auth_prose(match)
                      else '[REDACTED-AUTHORIZATION]', text)
    text = JWT.sub('[REDACTED-JWT]', text)
    text = URL_AUTH.sub('[REDACTED-URL]@', text)
    return text


def certify(text):
    if not isinstance(text, str) or len(text.encode('utf-8')) > MAX_BYTES:
        return False
    if any(ord(c) < 32 and c not in '\n\r\t' or ord(c) == 127 for c in text):
        return False
    if any(p.search(text) for p in (PROVIDER, PRIVATE_KEY, JWT, URL_AUTH)):
        return False
    if AUTH_HEADER.search(text):
        return False
    if any(not auth_prose(m) and not placeholder(m.group(1)) for m in BEARER.finditer(text)):
        return False
    if re.search(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----', text):
        return False
    for match in ASSIGNMENT.finditer(text):
        if policy_prose(match):
            continue
        tail = match.group(2).strip()
        if not tail:
            return False
        if tail.startswith(('"', "'")):
            quote = tail[0]
            end = tail.find(quote, 1)
            if end < 0 or not placeholder(tail[1:end]):
                return False
        elif not placeholder(tail.split(' #', 1)[0].rstrip(',}')):
            return False
    return True


def main():
    try:
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            return 65
        text = data.decode('utf-8', errors='strict')
        if '--recognizable-only' in sys.argv[1:]:
            return 65 if any(pattern.search(text) for pattern in (PROVIDER, PRIVATE_START, AUTH_HEADER, JWT, URL_AUTH)) else 0
        if '--redact' in sys.argv[1:]:
            text = clean_text(text)
        if not certify(text):
            return 65
        if '--redact' in sys.argv[1:]:
            sys.stdout.write(text)
        return 0
    except (OSError, UnicodeError, ValueError):
        return 65


if __name__ == '__main__':
    sys.exit(main())
