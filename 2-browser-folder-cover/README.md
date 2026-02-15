<a href="https://www.buymeacoffee.com/chiahsien" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# KOReader Browser Folder Cover

## Overview

This userpatch extends KOReader's file browser (Mosaic view) to display folder covers. A folder cover can be provided via a custom `.cover` file placed inside the folder, or derived from a book cover found inside the folder or its subfolders. This file is derived from sebdelsol/KOReader.patches with additional changes.

## Features

- Support for a custom folder cover file named `.cover` with extensions: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`.
- If no custom cover is present, the patch will try to use the first book in the folder that has a valid cover.
- If no cover is found in the folder, it will recursively search subfolders (default depth: 3) for a book cover.
- Asynchronous cover loading: when book covers are not yet extracted by KOReader, the folder tile will automatically refresh once the cover becomes available.
- Per-directory LRU cache for `FileChooser:getListItem` widgets (max 10 directories) and a cover source cache to avoid repeated directory scans.
- New UI options: crop custom folder image, center folder name, show/hide folder name.
- Respects KOReader's existing cover cache validity checks to avoid using invalid cached covers.

## How It Works

- Cover search order:
  1. Check for a `.cover` file with supported extensions (e.g. `.cover.jpg`). If found, the custom image is used (optionally cropped to fill the slot).
  2. Check the cover source cache — if this folder previously resolved to a specific book's cover, reuse it directly without scanning.
  3. Scan the folder entries and call `BookInfoManager:getBookInfo()` for files; use the first valid book cover that is not marked ignored and that passes cache validity checks.
  4. If no cover is found in the current folder, recursively search subfolders (up to depth 3) for a book cover.
  5. If book covers are still being extracted in the background, register the folder tile for automatic retry via CoverBrowser's polling mechanism.

- Display: builds a mosaic item containing the cover image, folder name, and book count badge. The folder name font size is adjusted to fit available space, and the name can be displayed over a semi-transparent overlay.

- Performance: per-directory LRU widget cache (evicts oldest when exceeding 10 directories), cover source cache to skip expensive directory scans on revisit, and settings version tracking to invalidate caches only when settings change.

## Installation

### Steps

1. Download the patch file `2-browser-folder-cover.lua` from this repository.
2. Locate your KOReader patches directory:
   - Usually: `<koreader_data_dir>/patches/`
   - Common paths:
     - Kobo: `/mnt/onboard/.adds/koreader/patches/`
     - Kindle: `/mnt/us/documents/koreader/patches/`
     - Android: `/sdcard/koreader/patches/` (or app-specific storage)
     - Desktop: `~/.koreader/patches/`

3. Copy the patch file to the patches directory.
4. Restart KOReader — the patch will be loaded automatically on startup.

## Usage

- After installation, folder covers are applied automatically in the Mosaic file browser.
- To use a custom cover, place a file named `.cover` with a supported extension in the folder (e.g. `.cover.jpg`).
- New options appear under KOReader File browser settings → Mosaic and detailed list settings:
  - "Crop folder custom image": crop the custom image to fill the display area (default: enabled).
  - "Folder name centered": center the folder name on the cover (default: enabled).
  - "Show folder name": toggle folder name visibility (default: enabled).

## Related Resources

- [KOReader Documentation](https://github.com/koreader/koreader/wiki)
- [KOReader User Patches](https://github.com/koreader/koreader/wiki/Userpatch)

---

Note: This is a community-derived patch based on [sebdelsol/KOReader.patches](https://github.com/sebdelsol/KOReader.patches). Key differences include recursive subfolder search, custom `.cover` file support, asynchronous cover loading, LRU caching, and various robustness improvements.
