#!/usr/bin/env python3
#
# Prints the .ui files the gresource manifests reference, one per line, relative
# to the project root. They are named there rather than in any meson.build.

from __future__ import annotations

import sys
import xml.etree.ElementTree as Et
from pathlib import Path


def ui_files(root: Path):
    for manifest in root.glob("src/**/*.gresource.xml"):
        try:
            tree = Et.parse(manifest)
        except Et.ParseError as e:
            print(f"{manifest}: {e}", file=sys.stderr)
            raise SystemExit(1) from e

        for element in tree.getroot().iter("file"):
            name = (element.text or "").strip()
            if name.endswith(".ui"):
                yield (manifest.parent / name).resolve().relative_to(root)


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else ".").resolve()

    for path in sorted({p.as_posix() for p in ui_files(root)}):
        print(path)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
