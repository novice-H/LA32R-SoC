"""Check sampled RGB332 frames and export a reproducible PNG preview."""
from pathlib import Path
import hashlib
import json
import sys

from PIL import Image


def read_frame(path):
    words = path.read_text(encoding="utf-8").split()
    if len(words) != 120000:
        raise ValueError(f"{path}: expected 120000 words, got {len(words)}")
    return b"".join(int(word, 16).to_bytes(4, "little") for word in words)


def rgb888(color):
    red, green, blue = color >> 5, (color >> 2) & 7, color & 3
    return bytes(((red << 5) | (red << 2) | (red >> 1),
                  (green << 5) | (green << 2) | (green >> 1),
                  (blue << 6) | (blue << 4) | (blue << 2) | blue))


def main():
    golden_dir, sampled_dir, output_dir = map(Path, sys.argv[1:4])
    summaries = []
    for variant in range(2):
        expected = read_frame(golden_dir / f"expected{variant}.hex")
        actual = read_frame(sampled_dir / f"actual{variant}.hex")
        mismatches = sum(a != b for a, b in zip(expected, actual))
        summaries.append({"frame": variant, "pixels": len(actual),
                          "mismatches": mismatches,
                          "sampled_sha256": hashlib.sha256(actual).hexdigest()})
        rgb = b"".join(rgb888(pixel) for pixel in actual)
        Image.frombytes("RGB", (800, 600), rgb).save(output_dir / f"actual{variant}.png")
        print(f"FRAMEBUFFER_COMPARE frame {variant}: {len(actual)-mismatches}/480000 pixels match")
    (output_dir / "comparison.json").write_text(
        json.dumps(summaries, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 1 if any(frame["mismatches"] for frame in summaries) else 0


if __name__ == "__main__":
    raise SystemExit(main())
