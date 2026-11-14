#!/usr/bin/env python3
"""Type exact values into Petalveil's shader options.

Horizon's shader-pack format has no text fields: every option is a slider with a fixed step. The
values themselves live in a plain file, one `id=value` per line, and the game reads it when the pack
is loaded. This tool edits that file, checking every value against the pack's own manifest.

    tools/options.py list                 # every option, its range and the current value
    tools/options.py get water_glints
    tools/options.py set water_glints 0.62 wave_speed 0.35
    tools/options.py reset water_glints   # back to the pack's default

After writing, reload the pack in the game (pick it again on the Shader Packs page, or save any
.wgsl file of the pack while it runs) — the game loads options with the pack, and it overwrites this
file whenever a slider is touched, so set values while the options screen is closed.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

DEFAULT_MANIFEST = Path(__file__).resolve().parent.parent / "pack" / "horizon-shaders.toml"
DEFAULT_VALUES = (
    Path.home() / ".local/share/horizon/shaderpacks/.horizon-options/petalveil.txt"
)


def load_options(manifest: Path) -> dict[str, dict]:
    with manifest.open("rb") as f:
        data = tomllib.load(f)
    options: dict[str, dict] = {}
    for entry in data.get("options", []):
        options[entry["id"]] = entry
    return options


def load_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep:
            values[key.strip()] = value.strip()
    return values


def save_values(path: Path, values: dict[str, str], defaults: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{k}={v}\n" for k, v in values.items() if v != defaults.get(k)]
    path.write_text("".join(lines))


def default_text(option: dict) -> str:
    if option["type"] == "bool":
        return "1" if option["default"] else "0"
    if option["type"] == "choice":
        return str(option["values"].index(option["default"]))
    return repr(float(option["default"])).rstrip("0").rstrip(".")


def coerce(option: dict, raw: str) -> str:
    kind = option["type"]
    if kind == "bool":
        low = raw.strip().lower()
        if low in {"1", "true", "on", "yes"}:
            return "1"
        if low in {"0", "false", "off", "no"}:
            return "0"
        raise SystemExit(f"{option['id']}: expected on/off, got {raw!r}")
    if kind == "choice":
        choices = option["values"]
        if raw in choices:
            return str(choices.index(raw))
        if raw.isdigit() and int(raw) < len(choices):
            return raw
        raise SystemExit(f"{option['id']}: expected one of {choices}, got {raw!r}")
    value = float(raw)
    low, high = float(option["min"]), float(option["max"])
    if not low <= value <= high:
        raise SystemExit(f"{option['id']}: {value} is outside {low}..{high}")
    return f"{value:g}"


def describe(option: dict, current: str) -> str:
    kind = option["type"]
    if kind == "bool":
        shown = "on" if current not in {"0", ""} else "off"
        return f"{option['id']:<18} {shown:<16} default {'on' if option['default'] else 'off'}"
    if kind == "choice":
        choices = option["values"]
        index = int(current) if current.isdigit() else 0
        name = choices[min(index, len(choices) - 1)]
        return f"{option['id']:<18} {name:<16} default {option['default']}"
    return (
        f"{option['id']:<18} {current:<16} "
        f"{option['min']:g}..{option['max']:g} step {option.get('step', 1):g}, default {option['default']:g}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--file", type=Path, default=DEFAULT_VALUES, help="the .horizon-options/<id>.txt to edit")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="every option with its range and current value")
    get = sub.add_parser("get", help="print one option's value")
    get.add_argument("id")
    set_ = sub.add_parser("set", help="write values, as id value pairs")
    set_.add_argument("pairs", nargs="+", metavar="ID VALUE")
    reset = sub.add_parser("reset", help="drop values, back to the pack's defaults")
    reset.add_argument("ids", nargs="*")

    args = parser.parse_args()
    options = load_options(args.manifest)
    values = load_values(args.file)
    defaults = {key: default_text(opt) for key, opt in options.items()}

    if args.command == "list":
        for key, option in options.items():
            print(describe(option, values.get(key, defaults[key])))
        return 0

    if args.command == "get":
        if args.id not in options:
            raise SystemExit(f"no such option: {args.id}")
        print(values.get(args.id, defaults[args.id]))
        return 0

    if args.command == "set":
        if len(args.pairs) % 2:
            raise SystemExit("set expects id value pairs")
        for key, raw in zip(args.pairs[::2], args.pairs[1::2]):
            if key not in options:
                close = [k for k in options if key.split("_")[0] in k]
                raise SystemExit(f"no such option: {key}" + (f" (did you mean {', '.join(close)}?)" if close else ""))
            values[key] = coerce(options[key], raw)
    else:
        for key in args.ids or list(options):
            values.pop(key, None)
        if not args.ids:
            print("all options reset to the pack's defaults")

    save_values(args.file, values, defaults)
    print(f"wrote {args.file}")
    print("reload the pack in the game to apply it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
