#!/usr/bin/env python3
"""
Convert hardcoded inline colour spans in docs/ into the design system's
semantic classes.

Background
----------
The docs used raw HTML spans to colour text, e.g.

    # **<span style="color:#009688;">Proxmox VE Installation</span>**
    ... integrating **<span style="color:#009688;">Bookstack</span>** with
        **<span style="color:red;">Authentik</span>** ...

Two different jobs were being done with one mechanism:

1. Headings were tinted teal purely for decoration. The theme now styles
   headings, so the span (and the redundant ``**`` bold wrapper) is dropped.

2. Body text used colour semantically in the integration guides: teal for the
   application being configured, red for the identity provider. That is a real
   convention, so it is promoted to ``attr_list`` spans that the stylesheet
   themes for both colour schemes:

       [Bookstack]{.prod-app}   [Authentik]{.prod-idp}

Anything that cannot be converted safely (unbalanced tags, unrecognised
colours) is reported and left untouched for a human to look at.

Usage
-----
    python tools/normalize_spans.py --check    # report only, no writes
    python tools/normalize_spans.py            # apply
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"

# colour value (normalised to lowercase, no spaces) -> attr_list class
COLOUR_CLASS = {
    "#009688": "prod-app",   # the application being configured
    "#43a047": "prod-app",   # same role, a stray second green
    "red": "prod-idp",       # Authentik, the identity provider
}

# off-palette one-offs used for plain emphasis; the surrounding bold label
# already carries the structure, so the colour is simply dropped.
COLOUR_STRIP = {"orange", "purple"}

# The colour was doing two unrelated jobs. Only one of them is a system:
# naming the product whose console a step belongs to. The rest was decoration
# on ordinary labels and sentences, and simply loses its colour.
#
# A span becomes a token only when its text names a product below. Everything
# else keeps its text and drops the markup, which is what keeps a coloured word
# on the page meaning "this is a product".
PRODUCTS = {
    "audiobookshelf", "bookstack", "nextcloud", "paperless-ngx", "paperless",
    "pairdrop", "snipe-it", "mailcow", "mailcow: dockerized",
    "cloudflare", "cloudflare access", "cloudflare zero trust",
    "cloudflare tunnel", "docker", "docker compose",
    "proxmox", "proxmox ve", "proxmox virtual environment (proxmox ve)",
    "proxmox datacenter manager", "lxc (linux containers)",
    "sccm", "mecm", "sccm (system center configuration manager)",
    "vmware esxi", "openvpn", "zabbix", "tanium", "wazuh",
}

# identity-provider side of an integration guide
IDPS = {"authentik"}

# clear misspellings of a product name, corrected on the way through
SPELLING = {"aunthentik": "Authentik"}

SPAN_OPEN = re.compile(r'<span\s+style="([^"]*)"\s*>', re.IGNORECASE)
# `?` as well as `>`: two headings close the tag with `</span?`
SPAN_CLOSE = re.compile(r"</span\s*[>?]", re.IGNORECASE)
# a complete, non-nested span
SPAN_PAIR = re.compile(
    r'<span\s+style="([^"]*)"\s*>(.*?)</span\s*[>?]', re.IGNORECASE | re.DOTALL
)
# `**<span style="...">Some Text**` — span opened inside bold and never closed,
# with the bold marker standing in for the missing `</span>`. The text may not
# contain `<`, so a properly closed span inside bold is never swallowed here.
BOLD_UNCLOSED = re.compile(
    r'\*\*<span\s+style="([^"]*)"\s*>([^<]+?)\*\*', re.IGNORECASE
)
HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
COLOUR_IN_STYLE = re.compile(r"color\s*:\s*([^;\"]+)", re.IGNORECASE)


def colour_of(style: str) -> str | None:
    m = COLOUR_IN_STYLE.search(style)
    return m.group(1).strip().lower() if m else None


def clean_heading(line: str) -> str:
    """Strip every span and the redundant bold wrapper from a heading."""
    line = SPAN_PAIR.sub(lambda m: m.group(2), line)
    line = SPAN_OPEN.sub("", line)
    line = SPAN_CLOSE.sub("", line)

    m = re.match(r"^(\s{0,3}#{1,6}\s+)(.*)$", line)
    if not m:
        return line
    prefix, text = m.group(1), m.group(2).rstrip()

    # `## **Title**` -> `## Title`, only when the bold wraps the whole heading
    inner = text
    while True:
        stripped = inner.strip()
        if len(stripped) > 4 and stripped.startswith("**") and stripped.endswith("**"):
            candidate = stripped[2:-2]
            if "**" not in candidate:
                inner = candidate
                continue
        break

    # tidy any bold markers left unbalanced by a removed span
    if inner.count("**") % 2 == 1:
        inner = inner.replace("**", "", 1)

    return prefix + inner.strip()


def render(text: str, colour: str | None, report: list[str],
           path: Path, lineno: int, stats: dict[str, int]) -> str | None:
    """Return replacement markup for span content, or None to leave it alone."""
    if colour in COLOUR_STRIP:
        stats["decolour"] += 1
        return text
    cls = COLOUR_CLASS.get(colour)
    if cls is None:
        report.append(f"{path}:{lineno}: unmapped colour {colour!r} left as-is")
        return None
    if "<span" in text.lower():
        report.append(f"{path}:{lineno}: nested span left as-is")
        return None

    # is this actually naming a product, or just decorated prose?
    key = text.strip().strip("*_`").strip().rstrip(":.").strip().lower()
    corrected = SPELLING.get(key)
    if corrected:
        text, key = corrected, corrected.lower()

    if key in IDPS:
        cls = "prod-idp"
    elif key in PRODUCTS:
        cls = "prod-app"
    else:
        stats["decolour"] += 1
        return text  # decoration, not a product: keep the words, drop the colour

    # A span it stays. attr_list's `[text]{.class}` looks tidier but Python-
    # Markdown only attaches attribute lists to elements it already produced,
    # so bracketed plain text is emitted literally.
    stats["token"] += 1
    return f'<span class="{cls}">{text}</span>'


def convert_body(line: str, report: list[str], path: Path, lineno: int,
                 depth: list[int], stats: dict[str, int]) -> str:
    """Rewrite spans in body text as attr_list spans.

    ``depth`` is a single-element list carrying the count of spans left open by
    earlier lines, so an orphaned ``</span>`` can be recognised and dropped.
    """

    def repl_bold(m: re.Match) -> str:
        out = render(m.group(2), colour_of(m.group(1)), report, path, lineno,
                     stats)
        return f"**{out}**" if out is not None else m.group(0)

    def repl_pair(m: re.Match) -> str:
        out = render(m.group(2), colour_of(m.group(1)), report, path, lineno,
                     stats)
        return out if out is not None else m.group(0)

    # complete pairs first, so only genuinely unclosed spans reach the bold rule
    line = SPAN_PAIR.sub(repl_pair, line)
    line = BOLD_UNCLOSED.sub(repl_bold, line)

    # drop a `</span>` whose opening tag was already removed from a heading
    def repl_close(m: re.Match) -> str:
        if depth[0] > 0:
            depth[0] -= 1
            return m.group(0)
        return ""

    line = SPAN_CLOSE.sub(repl_close, line)
    depth[0] += len(SPAN_OPEN.findall(line))
    return line


def process(path: Path, report: list[str], stats: dict[str, int]) -> tuple[str, int]:
    original = path.read_text(encoding="utf-8")
    out: list[str] = []
    changes = 0

    in_fence = False
    fence = ""
    depth = [0]

    for lineno, line in enumerate(original.splitlines(keepends=True), start=1):
        body = line.rstrip("\r\n")
        eol = line[len(body):]

        # never touch anything inside a fenced code block
        m = re.match(r"^\s*(`{3,}|~{3,})", body)
        if m:
            token = m.group(1)[0] * 3
            if not in_fence:
                in_fence, fence = True, token
            elif token == fence:
                in_fence, fence = False, ""
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue

        if HEADING.match(body):
            new = clean_heading(body)
        else:
            new = convert_body(body, report, path, lineno, depth, stats)
            # an opening tag surviving the pass means we could not pair it
            if SPAN_OPEN.search(new):
                report.append(
                    f"{path}:{lineno}: unpaired span, needs a human: "
                    f"{body.strip()[:90]}"
                )

        if new != body:
            changes += 1
        # a line that held nothing but an orphaned `</span>` is now empty
        if new.strip() == "" and body.strip() != "":
            continue
        out.append(new + eol)

    return "".join(out), changes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report only, do not write")
    args = ap.parse_args()

    report: list[str] = []
    stats = {"token": 0, "decolour": 0}
    touched = 0
    total_lines = 0

    for path in sorted(DOCS.rglob("*.md")):
        new_text, changes = process(path, report, stats)
        if changes:
            touched += 1
            total_lines += changes
            if not args.check:
                path.write_text(new_text, encoding="utf-8")

    verb = "would change" if args.check else "changed"
    print(f"{verb} {total_lines} lines across {touched} files")
    print(f"  {stats['token']} spans became product tokens")
    print(f"  {stats['decolour']} spans were decoration and just lost the colour")

    if report:
        print(f"\n{len(report)} item(s) need review:")
        for line in report:
            print("  " + line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
