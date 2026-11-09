# Add Date to Image File Name —  macOS Automator Quick Action <img width="48px" src="https://static.wikia.nocookie.net/ipod/images/a/ab/Automator.png/revision/latest?cb=20160908152407" alt="Otto the Automator" />

Renames the selected images **in place**, adding the date the photo was taken to their file name, straight from the Finder. No copy is made.

<img width="100%" src="img_addDateImg.avif" alt="Screenshot">

> Related scripts: [`watermarkImg`](https://github.com/martindubenet/watermarkImg) and [`renameForServer`](https://github.com/martindubenet/renameForServer).
>
> Generic macOS setup (Python libraries for Automator, Xcode Command Line Tools, creating a Quick Action, permissions, notifications): see my [wiki › macOS Automator](https://github.com/martindubenet/wed-dev-design/wiki/app-%E2%80%A2-macOS-Automator).

## How it works

- `add_date.py` — the Python script called by the Quick Action. It reads the dates and renames the files.
- `AddDate.app` — a small native macOS app (source in `AddDateApp/`, built locally with `build_app.sh`) that only shows the window and posts the end-of-task notification.

If `AddDate.app` is missing or fails, the script automatically falls back to a native list dialog with the same 4 combinations (see [Fallback](#fallback)).

## Requirements

- Pillow and pillow-heif, installed for the `python3` used by the Quick Action, to read the EXIF date (including iPhone HEIC photos).
- Xcode Command Line Tools, to build the app.

## Setup

1. **Build the app** (once, and after any change to `AddDateApp/`), from this folder: `./build_app.sh` — it ends with `Built: …/AddDate.app` (git-ignored).
2. **Create the Quick Action** in Automator with:
   - **Workflow receives current** → `image files` in `Finder`
   - **Run Shell Script** action, **Shell** → `/bin/zsh`, **Pass input** → `as arguments`, script (adjust the path to this folder):

     ```bash
     /opt/homebrew/bin/python3 "$HOME/aiScripts/addDateImg/add_date.py" "$@"
     ```

   - Saved as e.g. **Add Date to Image File Name**.

## Usage

> ⚠ The selected files are renamed directly. Try it on copies first.

1. In the Finder, select one or more images (jpg, jpeg, png, webp, heic, heif, avif, tif, tiff, bmp, dng).
2. Right-click → **Quick Actions** → your Quick Action (e.g. **Add Date to Image File Name**).
3. In the **Add Date to Image File Name** window:

   | Option | Off | On |
   | --- | --- | --- |
   | **Add hours and minutes** (`YYMMDD-HHhMM`) | `260925 photo.jpg` (day only) | `260925-14h32 photo.jpg` |
   | **Position the information after the file name** | `260925-14h32 photo.jpg` (before the name) | `photo 260925-14h32.jpg` (after the name) |

   The **Preview** field shows the resulting name pattern, e.g. `[YYMMDD-HHhMM] [FileName] [.extension]`. Both switches remember their last state. **Rename N file(s)** (or **Return**) renames; **Cancel** (or **Esc**, or the red button) stops without any message. With keyboard navigation on, **Tab** goes Rename → Add hours and minutes → Position… → Cancel.
4. A **notification** confirms the result (e.g. "12 file(s) renamed."). If some files failed, a dialog lists the errors instead.

### Naming rules

- Format `YYMMDD-HHhMM` (the lowercase "h" separates hours from minutes) or `YYMMDD`, separated from the name by a space. Change them at the top of the script: `DATE_FORMAT_FULL`, `DATE_FORMAT_DAY`, `DATE_SEPARATOR`.
- The date comes from the photo's EXIF metadata: `DateTimeOriginal` (when the shot was taken), then `DateTimeDigitized`, then `DateTime`. Without EXIF (screenshot, web export…), the file's creation date is used.
- **Already dated files are skipped:** a file that already starts (before) or ends (after) with a date stamp is left as is, so running the action twice doesn't stack dates. The notification tells how many were skipped.
- If the new name is already taken, ` (1)`, ` (2)`… is added.

## Fallback

If the window ever becomes unstable, delete or rename `AddDate.app`: the script then shows a native list dialog with the 4 combinations (before/after × with/without time). To force it for a test, from this folder:

```bash
AI_FORCE_DIALOG=1 /opt/homebrew/bin/python3 add_date.py ~/Desktop/a-photo.jpg
```

## Troubleshooting

- **The list dialog shows up instead of the window** → `AddDate.app` is missing or failed: rebuild it. Running the script from the Terminal (command above, without `AI_FORCE_DIALOG=1`) prints the reason (`AddDate.app gave no answer…`).
- **No notification at the end** → allow notifications for **Add date to image file** (the app name) the first time macOS asks. If macOS refuses them, a dialog that closes itself after 3 seconds is shown instead.
- **Wrong date** → the camera clock was probably off: check the EXIF with `exiftool -a -G1 "photo.jpg"` (after `brew install exiftool`).
