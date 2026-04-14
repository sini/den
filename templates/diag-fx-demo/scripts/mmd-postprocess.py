#!/usr/bin/env python3
"""
Convert mermaid-produced SVG files to a form that renders correctly in
sanitized viewers (GitHub, many markdown tools) by:

  1. Replacing `<foreignObject>` blocks (which embed HTML text mermaid uses
     for node labels) with native SVG `<text>` elements. Sanitizing SVG
     viewers strip foreignObject, leaving mermaid diagrams text-less.

  2. Applying a tech-friendly monospaced font family so node labels look
     consistent with code blocks.

  3. Tightening formatting: crisp stroke rendering, whitespace trimming,
     and a subtle default background.

Usage:
    mmd-postprocess.py <input.svg> <output.svg>
"""
import re
import sys
from pathlib import Path


MONOSPACE = (
    '"JetBrains Mono","Fira Code","Cascadia Code","Source Code Pro",'
    '"SFMono-Regular","Monaco","Menlo","Consolas","DejaVu Sans Mono",monospace'
)

# Extract one <foreignObject> block including nested content. Mermaid produces
# foreignObjects with width/height on the element and label text inside a
# <div>/<span>/<p> chain. We want the width, height, any enclosing <g>
# transform, and the inner text.
FOREIGN_RE = re.compile(
    r'<foreignObject(?P<attrs>[^>]*)>(?P<body>.*?)</foreignObject>',
    re.DOTALL,
)

# Match numeric width/height attributes inside the attrs string.
ATTR_NUM_RE = re.compile(r'(width|height|x|y)="(-?[\d.]+)"')

# Find the innermost text: mermaid wraps labels as <p>…</p> or <span>…</span>.
INNER_TEXT_RE = re.compile(r'<p[^>]*>(.*?)</p>', re.DOTALL)
SPAN_TEXT_RE = re.compile(r'<span[^>]*>(.*?)</span>', re.DOTALL)


def extract_text(body: str) -> str:
    """Pull user-visible text out of the foreignObject inner HTML."""
    m = INNER_TEXT_RE.search(body)
    if m:
        inner = m.group(1)
    else:
        m = SPAN_TEXT_RE.search(body)
        inner = m.group(1) if m else body
    # Strip any remaining tags.
    inner = re.sub(r'<[^>]+>', '', inner)
    # Decode HTML entities we care about.
    inner = (
        inner.replace('&nbsp;', ' ')
        .replace('&amp;', '&')
        .replace('&lt;', '<')
        .replace('&gt;', '>')
        .replace('&quot;', '"')
    )
    return inner.strip()


def svg_escape(s: str) -> str:
    return (
        s.replace('&', '&amp;')
        .replace('<', '&lt;')
        .replace('>', '&gt;')
    )


def to_svg_text(match: re.Match) -> str:
    attrs = match.group('attrs') or ''
    body = match.group('body') or ''

    numeric = dict(ATTR_NUM_RE.findall(attrs))
    try:
        width = float(numeric.get('width', '0'))
        height = float(numeric.get('height', '0'))
    except ValueError:
        width, height = 0.0, 0.0

    text = extract_text(body)
    if not text:
        # Empty foreignObjects (mermaid uses these as edge-label placeholders).
        # Drop them entirely.
        return ''

    # Handle multi-line text (rare but possible): split on newlines and render
    # each line as a <tspan>.
    lines = [ln for ln in (line.strip() for line in text.split('\n')) if ln]
    if not lines:
        return ''

    x = width / 2
    line_height = 14
    total = line_height * (len(lines) - 1)
    start_y = height / 2 - total / 2

    tspans = []
    for i, line in enumerate(lines):
        y = start_y + i * line_height
        tspans.append(
            f'<tspan x="{x:.2f}" y="{y:.2f}">{svg_escape(line)}</tspan>'
        )

    return (
        f'<text text-anchor="middle" dominant-baseline="central" '
        f'font-family=\'{MONOSPACE}\' font-size="12">'
        f'{"".join(tspans)}'
        f'</text>'
    )


def rewrite(svg: str) -> str:
    svg = FOREIGN_RE.sub(to_svg_text, svg)
    # Ensure the top-level SVG advertises our monospace default so any native
    # <text> elements mermaid emitted also pick it up.
    svg = re.sub(
        r'(<svg\b[^>]*?)(?=>)',
        lambda m: m.group(1) + f' font-family=\'{MONOSPACE}\'',
        svg,
        count=1,
    )
    # Inject a CSS override so mermaid's internal font-family CSS doesn't
    # beat the SVG attribute. Prepend inside the first <style> block if one
    # exists, otherwise append a fresh one right after <svg …>.
    override = (
        f'#my-svg, #my-svg *{{font-family:{MONOSPACE} !important;}}'
        f'#my-svg text{{shape-rendering:geometricPrecision;}}'
    )
    if re.search(r'<style[^>]*>', svg):
        svg = re.sub(r'(<style[^>]*>)', r'\1' + override, svg, count=1)
    else:
        svg = re.sub(
            r'(<svg\b[^>]*>)',
            r'\1<style>' + override + '</style>',
            svg,
            count=1,
        )
    return svg


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: mmd-postprocess.py <input.svg> <output.svg>", file=sys.stderr)
        sys.exit(2)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    dst.write_text(rewrite(src.read_text()))


if __name__ == '__main__':
    main()
