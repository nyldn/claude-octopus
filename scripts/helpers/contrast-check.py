#!/usr/bin/env python3
"""WCAG 2.x contrast-ratio checker. Zero dependencies (stdlib only).

Usage:
  contrast-check.py FG:BG [FG:BG ...] [--large] [--json]
  contrast-check.py --pairs-file FILE      # one FG:BG pair per line, # comments ok

Each pair is two hex colors separated by ':' (e.g. '#1D4ED8:#FFFFFF').
Normal text needs >= 4.5:1 (AA); large text / UI components need >= 3:1.
A pair may carry a per-pair size suffix: '#666:#FFF:large'.

Exit codes: 0 = all pairs pass, 1 = at least one failure, 2 = usage error.
"""
import argparse
import json
import re
import sys

HEX_RE = re.compile(r"^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")


def parse_hex(color: str):
    m = HEX_RE.match(color.strip())
    if not m:
        raise ValueError(f"invalid hex color: {color!r}")
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def channel(c: int) -> float:
    s = c / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def luminance(rgb) -> float:
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: str, bg: str) -> float:
    l1 = luminance(parse_hex(fg))
    l2 = luminance(parse_hex(bg))
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def check_pair(spec: str, default_large: bool):
    parts = spec.split(":")
    if len(parts) == 2:
        fg, bg = parts
        large = default_large
    elif len(parts) == 3 and parts[2].lower() in ("large", "normal"):
        fg, bg = parts[0], parts[1]
        large = parts[2].lower() == "large"
    else:
        raise ValueError(f"invalid pair (want FG:BG or FG:BG:large): {spec!r}")
    ratio = contrast_ratio(fg, bg)
    threshold = 3.0 if large else 4.5
    return {
        "fg": fg if fg.startswith("#") else f"#{fg}",
        "bg": bg if bg.startswith("#") else f"#{bg}",
        "ratio": round(ratio, 2),
        "threshold": threshold,
        "size": "large" if large else "normal",
        "pass": ratio >= threshold,
    }


def main(argv):
    ap = argparse.ArgumentParser(description="WCAG AA contrast checker")
    ap.add_argument("pairs", nargs="*", help="FG:BG hex pairs, optional :large suffix")
    ap.add_argument("--pairs-file", help="file with one FG:BG pair per line")
    ap.add_argument("--large", action="store_true",
                    help="treat all pairs as large text / UI components (3:1)")
    ap.add_argument("--json", action="store_true", help="emit JSON results")
    args = ap.parse_args(argv)

    specs = list(args.pairs)
    if args.pairs_file:
        try:
            with open(args.pairs_file, encoding="utf-8") as f:
                for line in f:
                    raw = line.strip()
                    # comment/blank lines: hex pairs always contain ':'
                    if not raw or ":" not in raw:
                        continue
                    specs.append(raw)
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            return 2

    if not specs:
        ap.print_usage(sys.stderr)
        return 2

    results = []
    for spec in specs:
        try:
            results.append(check_pair(spec, args.large))
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 2

    failed = [r for r in results if not r["pass"]]
    if args.json:
        print(json.dumps({"results": results, "failed": len(failed)}, indent=2))
    else:
        for r in results:
            mark = "PASS" if r["pass"] else "FAIL"
            print(f"{mark}  {r['fg']} on {r['bg']}  ratio {r['ratio']}:1  "
                  f"(needs {r['threshold']}:1, {r['size']} text)")
        print(f"\n{len(results) - len(failed)}/{len(results)} pairs pass WCAG AA")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
