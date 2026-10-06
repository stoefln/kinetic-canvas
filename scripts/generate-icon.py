#!/usr/bin/env python3
"""Render the Kinetic Canvas SVG and package PNG icon sizes into an ICNS file."""

from pathlib import Path
import shutil
import struct
import subprocess


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Assets" / "KineticCanvasIcon.svg"
PREVIEW = ROOT / "Assets" / "KineticCanvasIcon.png"
ICON = ROOT / "Assets" / "KineticCanvasIcon.icns"

# Modern ICNS entries contain ordinary PNG data at each resolution.
SIZES = {
    16: b"icp4",
    32: b"icp5",
    64: b"icp6",
    128: b"ic07",
    256: b"ic08",
    512: b"ic09",
    1024: b"ic10",
}


def render(size: int) -> bytes:
    return subprocess.check_output(
        ["rsvg-convert", "-w", str(size), "-h", str(size), str(SOURCE)]
    )


def main() -> None:
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("rsvg-convert is required to generate the icon")

    chunks = []
    for size, kind in SIZES.items():
        data = render(size)
        chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
        if size == 1024:
            PREVIEW.write_bytes(data)

    payload = b"".join(chunks)
    ICON.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(ICON)


if __name__ == "__main__":
    main()
