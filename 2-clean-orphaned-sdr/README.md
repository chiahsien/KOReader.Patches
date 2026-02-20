
<a href="https://www.buymeacoffee.com/chiahsien" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# KOReader Orphaned SDR Cleaner

A KOReader user patch that automatically cleans up orphaned `.sdr` (sidecar) folders for the currently active metadata storage mode.

## Overview

This user patch detects the currently configured metadata storage mode and scans the corresponding directory for `.sdr` folders that no longer have corresponding book files. Orphaned sidecars are safely removed to reclaim storage space.

The cleanup runs on every KOReader startup, deferred by 1 second to avoid blocking the UI.

## Features

* **Multi-mode support** — Works with all three KOReader metadata storage modes
* **Non-blocking** — Deferred execution avoids slowing down startup
* **Safe by default** — Unreadable directories or metadata are skipped, never deleted
* **Detailed logging** — All operations logged to `crash.log` for debugging

## How It Works

### Metadata Storage Modes

KOReader supports three ways to store book metadata. This patch only scans the *active* mode:

| Mode                    | Location                       | How Sidecars are Named                                |
| ----------------------- | ------------------------------ | ----------------------------------------------------- |
| **Book folder** (`doc`) | Alongside book files           | `book.sdr` next to `book.epub`                        |
| **Directory** (`dir`)   | `~/.koreader/docsettings/`     | Mirrors original path: `<prefix>/path/to/book.sdr`    |
| **Hash** (`hash`)       | `~/.koreader/hashdocsettings/` | `XX/<hash>.sdr` based on file content hash            |

> **Note**: KOReader strips the *last* extension to form the sdr name. For example, `book.kepub.epub` becomes `book.kepub.sdr`, not `book.sdr`.

### Cleanup Process

#### For "Book folder" mode (`doc`):

1. Recursively scans your Home directory
2. Finds all `.sdr` folders
3. Checks if a corresponding book file exists (same basename, any supported extension)
4. Removes orphaned folders that have no matching book

#### For "Directory" mode (`dir`):

1. Scans the centralized `~/.koreader/docsettings/` directory
2. Strips the docsettings prefix and `.sdr` suffix to reconstruct the original book path
3. Searches for a file with any supported extension at the original location
4. Removes orphaned sidecars when no matching book is found

#### For "Hash" mode (`hash`):

1. Scans `~/.koreader/hashdocsettings/` with its two-level hash structure
2. Finds the metadata file by pattern (`metadata.<ext>.lua`, e.g., `metadata.epub.lua`)
3. Reads the stored `doc_path` and verifies if the book file still exists
4. Removes sidecars whose books have been deleted or moved
5. Skips sidecars with unreadable metadata (does not delete them)

## Installation

1. **Download** `2-clean-orphaned-sdr.lua` from this repository
2. **Copy** it to your KOReader patches directory:
   - Kobo: `/mnt/onboard/.adds/koreader/patches/`
   - Kindle: `/mnt/us/documents/koreader/patches/`
   - Android: `/sdcard/koreader/patches/` or app-specific directory
   - Desktop: `~/.koreader/patches/`
3. **Restart KOReader** — The patch will automatically execute on startup

## Changing Metadata Storage Mode

This patch cleans orphaned sidecars for the *currently active* mode only. To switch modes in KOReader:

1. Tap the top of the screen to open the **top menu**
2. Tap the **gear icon** (Settings)
3. Tap **Document**
4. Tap **Book metadata location** (shows your current mode)
5. Select one of the three options:
   - **book folder** — Sidecars stored alongside book files (default)
   - **\<docsettings path\>** — All sidecars centralized in one directory
   - **\<hashdocsettings path\>** — Sidecars identified by file content hash

> **Important**: Switching modes does not automatically migrate sidecars. To preserve your reading progress, highlights, and bookmarks, use **Move book metadata** (in the same Document menu) to migrate existing sidecars to the new location *before* restarting KOReader. Any sidecars left behind in the old location will be treated as orphaned and removed by this patch on the next startup.

## Usage

Once installed, the patch runs automatically:

1. **Startup** — Detects your metadata storage mode and schedules cleanup (1s delay)
2. **Scanning** — Recursively searches the appropriate directory for `.sdr` folders
3. **Cleanup** — Removes orphaned `.sdr` folders whose corresponding books are missing
4. **Feedback** --
   - Shows a notification with the count of cleaned folders (if any were found)
   - Runs silently if no orphaned folders are found
   - Logs all operations to `crash.log`

## Troubleshooting

### Patch not running

**Symptoms**: No notification on startup, nothing in logs

**Solutions**:

* Verify the filename is `2-clean-orphaned-sdr.lua` (the `2-` prefix is required)
* Check that it's in the correct `patches` directory
* Ensure KOReader can access the file (check permissions)
* Restart KOReader after installation

### Error: "Unknown metadata storage mode"

**Solutions**:

* Check KOReader Settings → Document to verify your metadata storage mode
* Ensure your KOReader version is up-to-date

### Patch runs but cleans unexpected folders

**Solutions**:

* Review `crash.log` for detailed debugging information
* Check that your metadata storage mode is correctly set
* Verify your Home directory is correctly configured

## Limitations

* Does not handle broken symbolic links
* Hash mode depends on readable `doc_path` in metadata files; unreadable metadata is skipped
* Very large libraries (>10,000 books) may take several seconds
* Sidecar directories with restricted permissions might not be deletable (logged as warnings)

## Related Resources

* [KOReader Documentation](https://github.com/koreader/koreader/wiki)
* [KOReader User Patches](https://github.com/koreader/koreader/wiki/Userpatch)
* [Sidecar File Specification](https://github.com/koreader/koreader/blob/master/frontend/docsettings.lua)

---

## FAQ

### Q: Will this patch delete my book highlights and notes?

**A:** Only if the book file has already been deleted. The patch only removes sidecars where the corresponding book is missing.

### Q: Can I undo a deletion?

**A:** No. Deleted sidecar folders are permanently removed. Always backup your data before using automated cleanup tools.

### Q: How often does the patch run?

**A:** Every time KOReader starts, with a 1-second delay to avoid blocking startup.

### Q: Does it scan all three modes at once?

**A:** No. It only scans the currently active metadata storage mode configured in KOReader settings.

### Q: Can I disable the patch?

**A:** Yes. Remove or rename the file in your patches directory, or use KOReader's patch management interface.

---

**WARNING**: This patch permanently deletes folders. While it has been designed with safety in mind (unreadable directories and metadata are always skipped), always backup important data before using automated cleanup tools. The authors are not responsible for accidental data loss.
