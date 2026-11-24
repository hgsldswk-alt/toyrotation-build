"""Fetch the explicitly named UI test PNGs from an xcresult bundle."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
from tempfile import TemporaryDirectory


SHOT = re.compile(r"(?:store-(?:en|zh-Hans|zh-Hant)-\d{2}-[a-z-]+|paid-01-paywall)")
EXPECTED = {
    f"store-{lang}-{index:02d}-{scene}"
    for lang in ("en", "zh-Hans", "zh-Hant")
    for index, scene in enumerate(("home", "swap", "bin", "share", "settings"), 1)
} | {"paid-01-paywall"}


def export_named(folder, output):
    manifest = folder / "manifest.json"
    if manifest.is_file():
        groups = json.loads(manifest.read_text(encoding="utf-8"))
        for group in groups:
            for attachment in group.get("attachments", []):
                name = SHOT.search(attachment.get("suggestedHumanReadableName") or "")
                exported = attachment.get("exportedFileName") or ""
                path = folder / Path(exported).name
                if name and path.is_file() and path.suffix.lower() == ".png":
                    shutil.copyfile(path, output / f"{name.group()}.png")

    for path in folder.glob("**/*.png"):
        if SHOT.fullmatch(path.stem):
            target = output / path.name
            if not target.is_file():
                shutil.copyfile(path, target)

    return {
        path.stem for path in output.glob("*.png")
        if SHOT.fullmatch(path.stem) and path.is_file()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="toyrotation-xcresult-") as temp:
        folder = Path(temp)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path",
                        str(args.xcresult), "--output-path", str(folder)], check=True)
        names = export_named(folder, args.output)
    if missing := EXPECTED - names:
        parser.exit(1, "Missing screenshots: " + ", ".join(sorted(missing)) + "\n")
    print(f"Exported {len(EXPECTED)} named screenshots to {args.output}")


if __name__ == "__main__":
    main()
