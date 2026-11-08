#!/usr/bin/env python3
from __future__ import annotations

"""
add_date.py

Renames the Finder-selected images in place, adding their capture date to the
file name. Meant to be called from an Automator "Run Shell Script" Quick Action
that passes the selected files as command-line arguments.

Workflow:
    1. Receive image file paths as CLI arguments (from the Finder selection).
    2. Ask where the date goes (before / after the name) and whether hours and
       minutes are included, in the "Add Date to Image File Name" window (AddDate.app,
       built from AddDateApp/ with build_app.sh; last choices remembered), or in
       a native list dialog if the app is missing. Cancel exits silently.
    3. For each image, read the capture date (EXIF DateTimeOriginal, then
       DateTimeDigitized, then DateTime, then the file's creation date) and
       rename the file itself -- no copy is made:
           photo.jpg -> "260925-14h32 photo.jpg"   (before, with time)
           photo.jpg -> "photo 260925.jpg"         (after, day only)
       A file that already carries a date stamp at that position is skipped,
       so running the action twice doesn't stack dates.

Requires on the Mac running this:
    - Python 3.9+ with Pillow   (pip3 install -U Pillow)
    - pillow-heif, to read the date of HEIC/HEIF/AVIF photos (pip3 install pillow-heif)
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Optional

try:
    from PIL import Image
except ImportError:  # still works without Pillow: falls back to the file creation date
    Image = None

try:
    import pillow_heif  # HEIC/HEIF (and AVIF) read support for Pillow

    pillow_heif.register_heif_opener()
    try:
        pillow_heif.register_avif_opener()
    except Exception:
        pass
except ImportError:
    pillow_heif = None

# --- Tunables -------------------------------------------------------------
# Native window (AddDateApp/, built with build_app.sh). When the app is missing,
# fails, or AI_FORCE_DIALOG=1 is set, the list dialog (CHOICES) is used instead.
SCRIPT_DIR = Path(__file__).resolve().parent
APP_PATH = SCRIPT_DIR / "AddDate.app"
LAST_CHOICE_FILE = SCRIPT_DIR / ".last_choice.json"

DATE_FORMAT_FULL = "%y%m%d-%Hh%M"  # YYMMDD-HHhMM (lowercase "h" = "heure")
DATE_FORMAT_DAY = "%y%m%d"         # YYMMDD
DATE_SEPARATOR = " "               # between the file name and the date stamp

# Matches a stamp written by this script (with or without time), used to skip already-dated files.
STAMP_RE = r"\d{6}(?:-\d{2}h\d{2})?"

SUPPORTED_EXT = {
    ".jpg", ".jpeg", ".png", ".webp",
    ".heic", ".heif", ".avif",
    ".tif", ".tiff", ".bmp", ".dng",
}

# EXIF tags used to find when the photo was taken (first one found wins)
EXIF_IFD_POINTER = 0x8769
EXIF_DATETIME_ORIGINAL = 36867   # DateTimeOriginal: when the shutter fired
EXIF_DATETIME_DIGITIZED = 36868  # DateTimeDigitized
EXIF_DATETIME = 306              # DateTime (IFD0)

# Choices of the list dialog: label -> (position, include_time)
CHOICES = {
    "Before the name, with time   (YYMMDD-HHhMM photo.jpg)": ("before", True),
    "Before the name, day only   (YYMMDD photo.jpg)": ("before", False),
    "After the name, with time   (photo YYMMDD-HHhMM.jpg)": ("after", True),
    "After the name, day only   (photo YYMMDD.jpg)": ("after", False),
}


def _as_literal(text: str) -> str:
    """Escape a Python string for safe interpolation into an AppleScript string literal."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run_dialog(body: str) -> tuple[Optional[str], bool]:
    """Run an AppleScript dialog owned by the frontmost app (Finder, for a Quick Action).

    A dialog shown by a background osascript process may not get the keyboard/mouse
    focus when launched from the Finder (lost clicks since macOS 27.2). Asking the
    frontmost app to show it avoids that. If macOS refuses the Apple Event (Automation
    permission denied), the dialog is shown by osascript itself as a fallback.

    Returns (stdout, cancelled).
    """
    wrapped = ("tell application (path to frontmost application as text)\n"
               "activate\n" + body + "\nend tell")
    for script in (wrapped, body):
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip(), False
        if "-128" in result.stderr:  # user clicked Cancel
            return None, True
        print(f"Dialog failed: {result.stderr.strip()}", file=sys.stderr)
    return None, True


def notify(message: str, title: str = "Add Date to Image File Name") -> None:
    """Show a native macOS alert dialog (visible even though this runs headless from Automator)."""
    script = (f"display dialog {_as_literal(message)} with title {_as_literal(title)} "
              "buttons {\"OK\"} default button \"OK\"")
    run_dialog(script)

def announce(message: str, title: str) -> None:
    """Success summary as a macOS notification posted by this script's own app.

    (An AppleScript "display notification" would come from Script Editor, and
    clicking it would open Script Editor.) If the app can't post it (missing,
    or notifications refused), a dialog that closes itself after a few seconds
    is shown instead. Errors still get a regular dialog (notify).
    """
    data = run_app(["--notify-title", title, "--notify-body", message])
    if data is not None and data.get("posted"):
        return
    run_dialog(f"display dialog {_as_literal(message)} with title {_as_literal(title)} "
               "buttons {\"OK\"} default button \"OK\" giving up after 3")



def read_last_choice() -> dict:
    """Choices made last time in the window (per machine, git-ignored)."""
    try:
        data = json.loads(LAST_CHOICE_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_last_choice(data: dict) -> None:
    try:
        LAST_CHOICE_FILE.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass  # not critical: the defaults are used next time


def run_app(extra_args: list[str]) -> Optional[dict]:
    """Show the native window and return its JSON answer; None if it could not run.

    "open -W" launches it as a regular app (so it gets the focus) and waits until it quits.
    """
    if not APP_PATH.is_dir() or os.environ.get("AI_FORCE_DIALOG") == "1":
        return None
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "result.json"
        cmd = ["open", "-W", "-n", str(APP_PATH), "--args", *extra_args, "--out", str(out)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        try:
            data = json.loads(out.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            print(f"{APP_PATH.name} gave no answer (exit {result.returncode}): "
                  f"{result.stderr.strip()}", file=sys.stderr)
            return None
    return data if isinstance(data, dict) else None


def ask_choice(count: int) -> Optional[tuple[str, bool]]:
    """Return (position, include_time), or None if cancelled: native window, else the list."""
    last = read_last_choice()
    data = run_app(["--count", str(count),
                    "--after", "1" if last.get("after", False) else "0",
                    "--time", "1" if last.get("time", True) else "0"])
    if data is not None:
        if data.get("cancelled"):
            return None
        after, with_time = bool(data.get("after", False)), bool(data.get("time", True))
        save_last_choice({"after": after, "time": with_time})
        return ("after" if after else "before"), with_time
    return ask_choice_list(count)


def ask_choice_list(count: int) -> Optional[tuple[str, bool]]:
    """Fallback: one native list dialog; return (position, include_time), or None if cancelled."""
    labels = list(CHOICES)
    items = "{" + ", ".join(_as_literal(label) for label in labels) + "}"
    script = (
        f"set picked to choose from list {items} "
        f"with title \"Add Date to Image File Name\" "
        f"with prompt {_as_literal(f'Add the capture date to {count} file name(s):')} "
        f"default items {{{_as_literal(labels[0])}}} OK button name \"Rename\"\n"
        "if picked is false then return \"\"\n"
        "return item 1 of picked"
    )
    picked, cancelled = run_dialog(script)
    if cancelled or not picked:
        return None
    return CHOICES.get(picked)


def get_date_created(path: Path) -> datetime:
    """Return when the photo was taken: EXIF dates first, then the file's creation date."""
    if Image is not None:
        try:
            with Image.open(path) as img:
                exif = img.getexif()
                sub_ifd = exif.get_ifd(EXIF_IFD_POINTER)
                for raw in (sub_ifd.get(EXIF_DATETIME_ORIGINAL),
                            sub_ifd.get(EXIF_DATETIME_DIGITIZED),
                            exif.get(EXIF_DATETIME)):
                    if not raw:
                        continue
                    if isinstance(raw, bytes):
                        raw = raw.decode("ascii", errors="ignore")
                    try:
                        return datetime.strptime(raw.strip("\x00 ")[:19], "%Y:%m:%d %H:%M:%S")
                    except ValueError:
                        continue  # e.g. "0000:00:00 00:00:00" -- try the next tag
        except Exception:  # noqa: BLE001 -- unreadable image or EXIF: use the file date
            pass
    stat = path.stat()
    return datetime.fromtimestamp(getattr(stat, "st_birthtime", stat.st_mtime))


def already_dated(stem: str, position: str) -> bool:
    """True if the stem already starts (before) or ends (after) with a date stamp."""
    if position == "before":
        return re.match(STAMP_RE + re.escape(DATE_SEPARATOR), stem) is not None
    return re.search(re.escape(DATE_SEPARATOR) + STAMP_RE + "$", stem) is not None


def unique_target(src: Path, target: Path) -> Path:
    """Return target, or 'name (1).ext', 'name (2).ext'... if another file already uses it."""
    candidate, index = target, 1
    while candidate.exists() and not os.path.samefile(candidate, src):
        candidate = target.with_name(f"{target.stem} ({index}){target.suffix}")
        index += 1
    return candidate


def main() -> int:
    paths = [Path(p) for p in sys.argv[1:] if Path(p).suffix.lower() in SUPPORTED_EXT]
    if not paths:
        notify("No valid image was received.")
        return 0

    choice = ask_choice(len(paths))
    if choice is None:
        return 0  # Cancel: exit quietly
    position, include_time = choice
    fmt = DATE_FORMAT_FULL if include_time else DATE_FORMAT_DAY

    renamed, skipped, errors = 0, [], []
    for path in paths:
        try:
            if already_dated(path.stem, position):
                skipped.append(path.name)
                continue
            stamp = get_date_created(path).strftime(fmt)
            if position == "before":
                new_name = f"{stamp}{DATE_SEPARATOR}{path.stem}{path.suffix}"
            else:
                new_name = f"{path.stem}{DATE_SEPARATOR}{stamp}{path.suffix}"
            path.rename(unique_target(path, path.with_name(new_name)))
            renamed += 1
        except Exception as exc:  # noqa: BLE001 -- listed in the summary dialog
            errors.append(f"{path.name}: {exc}")

    summary = f"{renamed} file(s) renamed."
    if not errors:
        if skipped:
            summary += f" {len(skipped)} already dated, left as is."
        announce(summary, "Add Date to Image File Name")
        return 0
    if skipped:
        summary += f"\n\nAlready dated, left as is ({len(skipped)}):\n" + "\n".join(skipped[:15])
        if len(skipped) > 15:
            summary += "\n…"
    if errors:
        summary += "\n\nErrors:\n" + "\n".join(errors)
    notify(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
