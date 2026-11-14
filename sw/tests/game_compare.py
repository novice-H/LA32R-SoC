"""Compare a full VGA frame sampled while the integrated game is idle."""
from pathlib import Path
import json
import sys

from PIL import Image


def pixels(path):
    words = path.read_text(encoding="utf-8").split()
    if len(words) != 120000:
        raise SystemExit(f"invalid frame length: {path}: {len(words)} words")
    return b"".join(int(word, 16).to_bytes(4, "little") for word in words)


root = Path(sys.argv[1])
expected = pixels(root / "game-frame.hex")
actual = pixels(root / "soc" / "game-actual.hex")
differences = sum(a != b for a, b in zip(expected, actual))
rgb = bytes(component for p in actual for component in
            (((p >> 5) & 7) * 255 // 7, ((p >> 2) & 7) * 255 // 7,
             (p & 3) * 255 // 3))
Image.frombytes("RGB", (800, 600), rgb).save(root / "game-actual.png")
result = {"pixels": len(actual), "different_pixels": differences,
          "source": "actual SoC VGA RGB ports", "seed": 123}
(root / "game-comparison.json").write_text(
    json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
print(json.dumps(result))
if differences:
    raise SystemExit("GAME VGA comparison failed")
