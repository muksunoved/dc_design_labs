#!/usr/bin/env python3
"""
Post-process netlab topology graph:
- Remove spine/leaf icons, paint leaf nodes light green, spine nodes orange
- IP subnet labels AND endpoint IPs in white boxes with gray borders
- Subnet label font size reduced by 20%
"""

import re
import subprocess
import sys
from pathlib import Path

DOT_FILE = Path("img/topology.dot")
OUTPUT_PNG = Path("img/topology.png")

SUBNET_FONTSIZE = 6
IP_FONTSIZE = 6
SPINE_COLOR = "#ff9f01"
LEAF_COLOR = "#27ae60"


def wrap_html(text: str, fontsize: int) -> str:
    return (
        f'<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" '
        f'COLOR="#888888" BGCOLOR="white">'
        f'<TR><TD><FONT FACE="Verdana" POINT-SIZE="{fontsize}">{text}</FONT></TD></TR>'
        f'</TABLE>>'
    )


def is_closing_bracket(line: str) -> bool:
    """Check if line is a standalone closing bracket (not inside an attribute value)."""
    return re.match(r'^\s*\]\s*$', line) is not None


def is_single_line_node(line: str) -> bool:
    """Check if a node definition is entirely on one line (e.g. \"spine1\" [label=\"x\"])."""
    return bool(re.search(r'\]\s*$', line))


def process_dot(dot_content: str) -> str:
    lines = dot_content.splitlines()
    result = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # --- Override ranksep: more vertical space for xlabels ---
        if re.match(r'^\s*ranksep\s*=', line):
            result.append('  ranksep="3.0"')
            i += 1
            continue

        # --- Override nodesep: more horizontal space between nodes ---
        if re.match(r'^\s*nodesep\s*=', line):
            result.append('  nodesep="2.5"')
            i += 1
            continue

        # --- Override background: light gray instead of transparent ---
        if re.match(r'^\s*bgcolor\s*=', line):
            result.append('  bgcolor="#f0f0f0"')
            i += 1
            continue

        # --- Override splines: force curved instead of straight lines ---
        if re.match(r'^\s*splines\s*=', line):
            result.append('  splines="curved"')
            i += 1
            continue

        # --- Node definition ---
        node_m = re.match(r'^(\s*)"((?:spine|leaf)\d+)" \[', line)
        if node_m:
            indent = node_m.group(1)
            node_name = node_m.group(2)
            is_leaf = node_name.startswith("leaf")
            color = LEAF_COLOR if is_leaf else SPINE_COLOR

            # Check if the entire node definition is on one line
            if is_single_line_node(line):
                block = line
                i += 1
            else:
                # Collect the full node block — stop at standalone "]"
                block = line
                i += 1
                while i < len(lines) and not is_closing_bracket(lines[i]):
                    block += "\n" + lines[i]
                    i += 1
                i += 1  # skip the "]" line

            # Extract label
            label_m = re.search(r'label="([^"]*)"', block)
            label = label_m.group(1) if label_m else node_name

            result.append(
                f'{indent}"{node_name}" [fillcolor="{color}" style="rounded,filled" '
                f'shape="box" label="{label}"]'
            )
            continue

        # --- Edge definition: use xlabel instead of label/taillabel/headlabel
        # to avoid "edge labels with splines=curved not supported" warning
        edge_m = re.match(
            r'^(\s*)"(\w+)" -- "(\w+)" \[label="([^"]*)"'
            r'(?:\s+taillabel="([^"]*)")?'
            r'(?:\s+headlabel="([^"]*)")?\]',
            line,
        )
        if edge_m:
            indent, src, dst, subnet, tail_ip, head_ip = edge_m.groups()
            # All labels in one white box, one row per line
            rows = [
                f'<TR><TD><FONT FACE="Verdana" POINT-SIZE="{SUBNET_FONTSIZE}">{subnet}</FONT></TD></TR>'
            ]
            if tail_ip and head_ip:
                rows.append(
                    f'<TR><TD><FONT FACE="Verdana" POINT-SIZE="{IP_FONTSIZE}" COLOR="#666666">'
                    f'{tail_ip} — {head_ip}</FONT></TD></TR>'
                )
            elif tail_ip:
                rows.append(
                    f'<TR><TD><FONT FACE="Verdana" POINT-SIZE="{IP_FONTSIZE}" COLOR="#666666">{tail_ip}'
                    f'</FONT></TD></TR>'
                )
            elif head_ip:
                rows.append(
                    f'<TR><TD><FONT FACE="Verdana" POINT-SIZE="{IP_FONTSIZE}" COLOR="#666666">{head_ip}'
                    f'</FONT></TD></TR>'
                )
            combined = (
                f'<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0">'
                f'<TR><TD HEIGHT="16"></TD></TR>'
                f'<TR><TD><TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" '
                f'COLOR="#888888" BGCOLOR="white">'
                + "".join(rows)
                + '</TABLE></TD></TR>'
                f'<TR><TD HEIGHT="16"></TD></TR>'
                f'</TABLE>>'
            )
            result.append(f'{indent}"{src}" -- "{dst}" [xlabel={combined}]')
            i += 1
            continue

        result.append(line)
        i += 1

    return "\n".join(result)


def main():
    if not DOT_FILE.exists():
        print(f"ERROR: {DOT_FILE} not found. Run 'netlab graph img/topology.dot' first.")
        sys.exit(1)

    dot_content = DOT_FILE.read_text()
    processed = process_dot(dot_content)

    processed_dot = DOT_FILE.with_suffix(".styled.dot")
    processed_dot.write_text(processed)

    cmd = ["dot", str(processed_dot), "-T", "png", "-o", str(OUTPUT_PNG)]
    print(f"Rendering: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
    print(f"Created {OUTPUT_PNG}")


if __name__ == "__main__":
    main()
