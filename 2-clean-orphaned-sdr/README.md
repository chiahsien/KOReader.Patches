# KOReader Orphaned SDR Cleaner

A KOReader user patch that automatically cleans up orphaned `.sdr` (sidecar) folders across all metadata storage modes.

## Overview

This user patch scans your KOReader data directories for `.sdr` folders that no longer have corresponding book files and safely removes them.  This helps reclaim storage space when books are deleted or moved outside of KOReader.

## Features

* **🔄 Multi-mode support** :  Works with all three KOReader metadata storage modes
* **📁 Automatic cleanup** : Runs on every KOReader startup
* **🎯 Precise detection** : Uses mode-specific logic to accurately identify orphaned folders
* **📝 Detailed logging** : Comprehensive logging for debugging and verification

## How It Works

### Metadata Storage Modes

KOReader supports three ways to store book metadata:

| Mode                    | Location                       | How Sidecars are Named                   | Supported |
| ----------------------- | ------------------------------ | ---------------------------------------- | --------- |
| **Book folder** (`doc`) | Alongside book files            | Mirrors filename:`book.pdf` → `book.sdr`  | ✅ Yes    |
| **Directory** (`dir`)   | `~/.koreader/docsettings/`     | Mirrors folder structure                 | ✅ Yes    |
| **Hash** (`hash`)       | `~/.koreader/hashdocsettings/` | Based on file content hash                | ✅ Yes    |

### Cleanup Process

#### For "Book folder" mode:

1. Recursively scans your Home directory
2. Finds all `.sdr` folders
3. Checks if a corresponding book file exists (same basename, any supported extension)
4. Removes orphaned folders that have no matching book

#### For "Directory" mode:

1. Scans the centralized `~/.koreader/docsettings/` directory
2. Reconstructs original file paths from directory structure
3. Checks if the original book file still exists
4. Removes orphaned sidecars when original books are gone

#### For "Hash" mode:

1. Scans `~/.koreader/hashdocsettings/` with its two-level hash structure
2. Reads the stored `doc_path` from each sidecar's `metadata.lua`
3. Verifies if the book file still exists at that path
4. Removes sidecars whose books have been deleted or moved

## Installation

### Steps

1. **Download the patch file** `2-clean-orphaned-sdr.lua` from this repository
2. **Locate your KOReader patches directory** :

* Usually found at `<koreader_data_dir>/patches/`
* Common paths:
  - Kobo: `/mnt/onboard/.adds/koreader/patches/`
  - Kindle: `/mnt/us/documents/koreader/patches/`
  - Android: `/sdcard/koreader/patches/` or app-specific directory
  - Desktop: `~/.koreader/patches/`

3. **Copy the patch file** to the patches directory
4. **Restart KOReader** - The patch will automatically execute on startup

## Usage

Once installed, the patch runs automatically:

1. **On startup** : Automatically detects your metadata storage mode
2. **Validation** : Confirms the mode is valid (handles any future modes gracefully)
3. **Scanning** : Recursively searches the appropriate directory
4. **Cleanup** : Removes all orphaned `.sdr` folders
5. **Feedback** :
   * Shows a notification with the count of cleaned folders
   * If no orphaned folders found, runs silently
   * Logs all operations to `crash.log`

### Troubleshooting

### Patch not running

**Symptoms** : No notification on startup, nothing in logs

**Solutions** :

* Verify the filename is `2-clean-orphaned-sdr.lua` (the `2-` prefix is required for priority)
* Check that it's in the correct `patches` directory
* Ensure KOReader can access the file (check permissions)
* Restart KOReader after installation

### Error: "Unknown metadata storage mode"

**Symptoms** : Notification shows unknown storage mode

**Solutions** :

* Check KOReader Settings → Document to verify your metadata storage mode
* Ensure your KOReader version is up-to-date

### Patch runs but cleans unexpected folders

**Solutions** :

* Review `crash.log` for detailed debugging information
* Check that your metadata storage mode is correctly set
* Verify your Home directory is correctly configured

## Limitations & Known Issues

* Does not handle broken symbolic links (rare case)
* Hash mode depends on accurate `doc_path` in metadata files
* Very large libraries (>10,000 books) may take several seconds
* Sidecar directories with unusual permissions might not be deletable

## Contributing

Contributions are welcome! Please:

1. Test your changes across different platforms and storage modes
2. Add appropriate logging statements for debugging
3. Update documentation if adding features
4. Follow the existing code style (LuaDoc comments, consistent formatting)

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

**A:** Every time KOReader starts. This is by design to keep your metadata directory clean.

### Q: Can I disable the patch?

**A:** Yes. Remove or rename the file in your patches directory, or use KOReader's patch management interface.

---

**⚠️ Important Disclaimer** : This patch permanently deletes folders. While it has been designed with safety in mind, always backup important data before using automated cleanup tools. The authors are not responsible for accidental data loss.

For issues or questions, please open an issue on GitHub or consult KOReader's documentation.
