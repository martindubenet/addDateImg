# Add Date to Image File Name —  macOS Automator Quick Action <img width="48px" src="https://static.wikia.nocookie.net/ipod/images/a/ab/Automator.png/revision/latest?cb=20160908152407" alt="Otto the Automator" />

Renames the selected images **in place**, adding the date the photo was taken to their file name, straight from the Finder. No copy is made.

<img width="100%" src="img_addDateImg.avif" alt="Screenshot">

> Part of `aiScripts/`. Steps shared by all the scripts (Python libraries, `~/aiScripts` symbolic link, Xcode Command Line Tools) are detailed in [`watermarkImg/README.md`](../watermarkImg/README.md#1-install-the-dependencies-once).

## How it works

- `add_date.py` — the Python script called by the Quick Action. It reads the dates and renames the files.
- `AddDate.app` — a small native macOS app (source in `AddDateApp/`, built on your Mac with `build_app.sh`) that only shows the window and posts the end-of-task notification.

If `AddDate.app` is missing or fails, the script automatically falls back to a native list dialog with the same 4 combinations (see [Fallback](#fallback)).

## 1. Requirements (once)

- Pillow and pillow-heif for `/opt/homebrew/bin/python3` (to read the EXIF date, including iPhone HEIC photos): `/opt/homebrew/bin/python3 -m pip install -U Pillow pillow-heif`
- The `~/aiScripts` symbolic link (see the watermark README, step 2).
- Xcode Command Line Tools, to build the app (`xcode-select -p` to check).

## 2. Build the app (once, and after any change to `AddDateApp/`)

In your Terminal app:

```bash
~/aiScripts/addDateImg/build_app.sh
```

It ends with `Built: …/AddDate.app`.

## 3. Create the Quick Action in Automator

1. Open **Automator**, **File > New**, choose `Quick Action`.
2. At the top of the document, set:
   - **Workflow receives current** → `image files`
   - **in** → `Finder`
   - **Image** (*optional*) → an icon of your choice
3. Add the **Run Shell Script** action, with **Shell** → `/bin/zsh` and **Pass input** → `as arguments`.
4. Replace the content of the script box with:

   ```bash
   /opt/homebrew/bin/python3 "$HOME/aiScripts/addDateImg/add_date.py" "$@"
   ```

5. **File > Save**, e.g. **Add Date to Image File Name**.

## 4. Usage

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

If the window ever becomes unstable, delete or rename `AddDate.app` in the Finder: the script then shows a native list dialog with the 4 combinations (before/after × with/without time). To force it for a test, in your Terminal app:

```bash
AI_FORCE_DIALOG=1 /opt/homebrew/bin/python3 ~/aiScripts/addDateImg/add_date.py ~/Desktop/a-photo.jpg
```

## Troubleshooting

- **The list dialog shows up instead of the window** → `AddDate.app` is missing or failed: rebuild it. Running the script from the Terminal (command above, without `AI_FORCE_DIALOG=1`) prints the reason (`AddDate.app gave no answer…`).
- **No notification at the end** → the first time, macOS asks whether the app may send notifications: click **Allow**. Check **System Settings › Notifications** and Focus modes. If notifications are refused, a dialog that closes itself after 3 seconds is shown instead.
- **Permission alert "… wants access to control Finder"** → click **Allow** (dialogs are shown by the Finder so they get the focus).
- **Wrong date** → the camera clock was probably off: check the EXIF with `exiftool -a -G1 "photo.jpg"` (after `brew install exiftool`).
