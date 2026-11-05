"""Print the CHANGELOG.md section for a version, for GitHub release notes.

Usage: python3 scripts/release_notes.py 0.24.0 [CHANGELOG.md]
Exits with an error when the version has no section, so a release cannot
be published without notes.
"""
import re
import sys


def section(text: str, version: str) -> str:
    heading = re.compile(r'^## ' + re.escape(version) + r'(?=[,\s]|$)', re.M)
    match = heading.search(text)
    if not match:
        raise SystemExit(f'CHANGELOG.md has no "## {version}" section.')
    rest = text[match.end():]
    nxt = re.search(r'^## ', rest, re.M)
    body = rest[: nxt.start()] if nxt else rest
    # Drop the remainder of the heading line (the date), keep the entries.
    body = body.split('\n', 1)[1] if '\n' in body else ''
    body = body.strip()
    if not body:
        raise SystemExit(f'The "## {version}" section in CHANGELOG.md is empty.')
    return body


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[2] if len(sys.argv) > 2 else 'CHANGELOG.md'
    with open(path, encoding='utf-8') as f:
        print(section(f.read(), sys.argv[1]))
