#!/usr/bin/env python3
"""Copy only LPC sprites reachable from the current Skyval character/editor/items.

Read the appearance option arrays and the inventory catalog directly from the
source scripts. Never copy the whole Universal LPC library. Future items and
color options automatically enter the next full-assets package.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import shutil
import sys

SHAPES = ("male", "female")
ARMOR_TYPES = ("leather", "legion", "plate")


def options(source: str, constant: str) -> list[str]:
    found = re.search(r"^const\s+" + re.escape(constant) + r"\s*:=\s*\[(.*?)\]", source, re.M | re.S)
    if not found:
        raise ValueError(f"Cannot read {constant} from LPC renderer")
    choices = re.findall(r'"([^"]+)"', found.group(1))
    if not choices:
        raise ValueError(f"No available values in {constant}")
    return choices


def inventory_items(source: str) -> list[dict[str, str]]:
    found = re.search(r"^const\s+ITEMS\s*:=\s*\{(.*?)^\}", source, re.M | re.S)
    if not found:
        raise ValueError("Cannot read inventory ITEMS")
    items = []
    for line in found.group(1).splitlines():
        if line.lstrip().startswith("#"):
            continue
        match = re.match(r'^\s*"[^"]+":\s*\{([^}]*)\}', line)
        if match:
            item = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', match.group(1)))
            if "slot" not in item or "style" not in item:
                raise ValueError(f"Unrecognized inventory item: {line.strip()}")
            items.append(item)
    if not items:
        raise ValueError("No equipment items found")
    return items


def defaults(source: str) -> dict[str, str]:
    return dict(re.findall(r'^@export\s+var\s+(\w+):\s+String\s*=\s*"([^"]+)"', source, re.M))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", required=True, type=Path)
    p.add_argument("--destination", required=True, type=Path)
    p.add_argument("--renderer", required=True, type=Path)
    p.add_argument("--inventory", required=True, type=Path)
    args = p.parse_args()
    root = args.source.resolve()
    renderer = args.renderer.read_text(encoding="utf-8")
    inventory = args.inventory.read_text(encoding="utf-8")
    defaults_map = defaults(renderer)
    items = inventory_items(inventory)
    needed: dict[str, str] = {}

    def add(relative: str, category: str) -> None:
        needed.setdefault(relative, category)

    # All body types / skin tones / facial features supported by the creator.
    for gender in SHAPES:
        for skin in options(renderer, "SKINS"):
            add(f"body/bodies/{gender}/{skin}.png", "body")
            add(f"head/heads/human/{gender}/{skin}.png", "head")
            add(f"head/faces/{gender}/neutral/{skin}.png", "face")
    for color in options(renderer, "EYE_COLORS"):
        add(f"eyes/human/adult/default/{color}.png", "eyes")
    for style in options(renderer, "HAIR_STYLES"):
        if style == "none":
            continue  # Baldness needs no image.
        for color in options(renderer, "HAIR_COLORS"):
            add(f"hair/{style}/adult/{color}.png", "hair")

    # The inventory is the authoritative list of currently wearable items.
    for item in items:
        slot = item["slot"]
        style = item["style"]
        variant = item.get("variant", "")
        if slot not in ("shirt", "pants", "footwear"):
            continue
        if not variant:
            raise ValueError(f"Equipment {style} has no color variant")
        for gender in SHAPES:
            if slot == "shirt":
                relative = f"torso/clothes/{style}/{gender}/{variant}.png"
            else:
                shape = "thin" if gender == "female" else "male"
                base = "legs" if slot == "pants" else "feet"
                relative = f"{base}/{style}/{shape}/{variant}.png"
            add(relative, slot)

    # LPC initializes with these before starter gear has been applied.
    # Both body types must be able to render their initial scene.
    for gender in SHAPES:
        shape = "thin" if gender == "female" else "male"
        for slot, style_key, variant_key in (
            ("shirt", "shirt_style", "shirt_variant"),
            ("pants", "pants_style", "pants_variant"),
            ("footwear", "footwear_style", "boots_variant"),
        ):
            style = defaults_map[style_key]
            variant = defaults_map[variant_key]
            if style == "none":
                continue
            if slot == "shirt":
                add(f"torso/clothes/{style}/{gender}/{variant}.png", "starter")
            else:
                base = "legs" if slot == "pants" else "feet"
                add(f"{base}/{style}/{shape}/{variant}.png", "starter")

    # Currently supported armor types: vest, reinforced vest and cuirass.
    # The renderer validates torso visibility at runtime and may fall back to
    # any color in the matching folder; only these three small folders are
    # included, never the whole armor library.
    for gender in SHAPES:
        for armor_type in ARMOR_TYPES:
            directory = root / "torso" / "armour" / armor_type / gender
            for image in sorted(directory.glob("*.png")):
                add(image.relative_to(root).as_posix(), "armor")
        # The optional vest lining is taken from this single garment folder.
        lining = root / "torso" / "clothes" / "sleeveless" / "sleeveless" / gender
        for image in sorted(lining.glob("*.png")):
            add(image.relative_to(root).as_posix(), "vest_lining")

    # A two-layer iron arming sword is used by the new weapon chest.
    # These authentic Universal LPC sheets use the same walk/idle frame
    # positions as the base body; both halves are REQUIRED for equipping.
    for part in ("bg", "fg"):
        add(f"weapon/sword/arming/universal/{part}/iron.png", "weapon")

    missing = []
    copied = Counter()
    copied_bytes = 0
    for relative, category in sorted(needed.items()):
        origin = root / relative
        if not origin.is_file() or origin.stat().st_size == 0:
            missing.append((category, relative))
            continue
        target = args.destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
        copied[category] += 1
        copied_bytes += origin.stat().st_size

    required = [
        f"{base}/{gender}/light.png"
        for gender in SHAPES
        for base in ("body/bodies", "head/heads/human")
    ]
    required += [
        "weapon/sword/arming/universal/bg/iron.png",
        "weapon/sword/arming/universal/fg/iron.png",
    ]
    unavailable = [relative for relative in required if not (args.destination / relative).is_file()]
    if unavailable:
        print("ERROR: essential LPC files unavailable:", file=sys.stderr)
        for relative in unavailable:
            print(f"  {relative}", file=sys.stderr)
        return 1

    # Avoid accidentally packaging an older ~14-sprite test subset.
    count = sum(copied.values())
    if count < 30:
        print(f"ERROR: only {count} current-game LPC PNGs found. Use the full LPC source directory.", file=sys.stderr)
        return 1

    print(f"Selected {count} LPC PNGs ({copied_bytes / (1024 * 1024):.1f} MiB).")
    print("Categories: " + ", ".join(f"{key}={copied[key]}" for key in sorted(copied)))
    if missing:
        counts = Counter(category for category, _ in missing)
        print("Unavailable optional variants: " + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))
        for category, relative in missing:
            print(f"  SKIP [{category}] {relative}")

    # Keep a compact, inspectable inventory within the one-time package.
    manifest = args.destination.parent / "LPC_SELECTED_ASSETS.txt"
    manifest.write_text(
        "Skyval LPC asset selection (source: current appearance options and inventory items)\n"
        + f"Packaged PNGs: {count}\n"
        + f"Total MiB: {copied_bytes / (1024 * 1024):.1f}\n\n"
        + "Included:\n"
        + "".join(f"{rel}\n" for rel in sorted(needed) if (args.destination / rel).is_file())
        + "\nUnavailable in LPC source:\n"
        + "".join(f"{rel}\n" for _, rel in missing),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
