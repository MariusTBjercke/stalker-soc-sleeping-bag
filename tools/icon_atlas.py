"""Development tool for the sleeping-bag inventory icon.

`encode` turns the icon PNG into the raw DXT5 blocks the deployer ships
(art/icon/sleeping-bag-2x2.dxt5). Players never run this: tools/deploy.ps1
splices those blocks into EE's atlas itself. `splice` builds a full patched
atlas with the same block layout, for eyeballing and for cross-checking the
deployer's output byte for byte.

The engine draws inventory icons from one DXT5 atlas (50 px grid cells) and
has no per-item icon setting, so the icon has to live inside that atlas.
Only the DXT5 blocks under the icon are replaced; every other byte of the
atlas stays exactly as the game shipped it (no re-encode of other icons).

    python tools/icon_atlas.py encode --icon art/icon/sleeping-bag-2x2-100x100.png \
        --out art/icon/sleeping-bag-2x2.dxt5
    python tools/icon_atlas.py splice --atlas <game ui_icon_equipment.dds> \
        --icon art/icon/sleeping-bag-2x2-100x100.png --out <output.dds>

Requires Pillow. The atlas is an input from the game install and is never
committed; see AGENTS.md.
"""

import argparse
import io
import struct
import sys

from PIL import Image

DDS_HEADER = 128
BLOCK = 4
BLOCK_BYTES = 16  # DXT5
CELL = 50
# Free 2x2 area of EE's atlas (rows 38-39, columns 2-3): empty in the shipped
# texture, and its pixel offsets are multiples of the 4 px DXT block.
DEFAULT_CELL = (2, 38)


def read_atlas(path):
    with open(path, "rb") as handle:
        data = bytearray(handle.read())
    if data[:4] != b"DDS " or data[84:88] != b"DXT5":
        raise SystemExit("atlas is not a DXT5 DDS file")
    height, width = struct.unpack("<II", data[12:20])
    if struct.unpack("<I", data[28:32])[0] > 1:
        raise SystemExit("atlas has mipmaps; this tool expects a single level")
    return data, width, height


def encode_blocks(icon):
    """Returns the DXT5 block rows of the icon as a list of bytes."""
    buffer = io.BytesIO()
    icon.save(buffer, format="DDS", pixel_format="DXT5")
    raw = buffer.getvalue()
    width, height = icon.size
    blocks_x = width // BLOCK
    payload = raw[DDS_HEADER:]
    if raw[84:88] != b"DXT5":
        raise SystemExit("encoder did not produce DXT5")
    row_size = blocks_x * BLOCK_BYTES
    return [payload[i * row_size:(i + 1) * row_size] for i in range(height // BLOCK)]


def splice(atlas_path, icon_path, out_path, cell):
    data, width, height = read_atlas(atlas_path)
    icon = Image.open(icon_path).convert("RGBA")
    x, y = cell[0] * CELL, cell[1] * CELL
    if x % BLOCK or y % BLOCK or icon.width % BLOCK or icon.height % BLOCK:
        raise SystemExit("icon and cell must be aligned to 4 px blocks")
    if x + icon.width > width or y + icon.height > height:
        raise SystemExit("icon does not fit inside the atlas")

    atlas_blocks_x = width // BLOCK
    for row, block_row in enumerate(encode_blocks(icon)):
        offset = DDS_HEADER + ((y // BLOCK + row) * atlas_blocks_x + x // BLOCK) * BLOCK_BYTES
        data[offset:offset + len(block_row)] = block_row

    with open(out_path, "wb") as handle:
        handle.write(data)
    return width, height


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    encode = sub.add_parser("encode", help="write the icon as raw DXT5 blocks")
    encode.add_argument("--icon", required=True)
    encode.add_argument("--out", required=True)
    splice_cmd = sub.add_parser("splice", help="write a full patched atlas")
    splice_cmd.add_argument("--atlas", required=True)
    splice_cmd.add_argument("--icon", required=True)
    splice_cmd.add_argument("--out", required=True)
    splice_cmd.add_argument("--cell", type=int, nargs=2, default=DEFAULT_CELL, metavar=("X", "Y"))
    args = parser.parse_args()
    if args.command == "encode":
        blocks = b"".join(encode_blocks(Image.open(args.icon).convert("RGBA")))
        with open(args.out, "wb") as handle:
            handle.write(blocks)
        print("wrote %s (%d bytes)" % (args.out, len(blocks)))
        return
    width, height = splice(args.atlas, args.icon, args.out, args.cell)
    print("wrote %s (%dx%d), icon at cell %d,%d" % (args.out, width, height, args.cell[0], args.cell[1]))


if __name__ == "__main__":
    sys.exit(main())
