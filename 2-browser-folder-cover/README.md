<a href="https://www.buymeacoffee.com/chiahsien" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# KOReader Browser Folder Cover

## Overview

This userpatch extends KOReader's file browser (Mosaic view) to display folder covers. A folder cover can be provided via a custom `.cover` file placed inside the folder, or derived from a book cover found inside the folder or its subfolders. This file is derived from sebdelsol/KOReader.patches with additional changes.

## Features

- Support for a custom folder cover file named `.cover` with extensions: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`.
- **Two folder cover styles**: "Single cover" (one book cover per folder) and "Grid (2×2)" (up to 4 book covers in a 2×2 grid layout).
- If no custom cover is present, the patch will try to use books in the folder that have valid covers.
- If no cover is found in the folder, it will recursively search subfolders (default depth: 3) for book covers.
- Asynchronous cover loading: when book covers are not yet extracted by KOReader, the folder tile will automatically refresh once the cover becomes available.
- Per-directory LRU cache for `FileChooser:getListItem` widgets (max 10 directories) and a cover source cache to avoid repeated directory scans.
- Directories skip `original_update()` to eliminate e-ink cover flash when paging through the file browser.
- Respects KOReader's existing cover cache validity checks to avoid using invalid cached covers.

## How It Works

- Cover search order:
  1. Check for a `.cover` file with supported extensions (e.g. `.cover.jpg`). If found, the custom image is always displayed as a single cover (optionally cropped to fill the slot), regardless of the selected cover style.
  2. Check the cover source cache — if this folder previously resolved to book cover(s), reuse directly without scanning.
  3. Scan the folder entries and call `BookInfoManager:getBookInfo()` for files; collect valid book covers (up to 4 in grid mode, 1 in single mode).
  4. If more covers are needed, recursively search subfolders (up to depth 3) for additional book covers.
  5. If book covers are still being extracted in the background, register the folder tile for automatic retry via CoverBrowser's polling mechanism.

- Display:
  - **Single cover mode**: one book cover per folder tile, bottom-aligned. The folder name is displayed over a semi-transparent overlay at the bottom.
  - **Grid (2×2) mode**: up to 4 book covers arranged in a 2×2 grid with a fine gap between cells and a single shared border. Each cell uses aspect fill scaling (crops overflow to fill the cell). Partial grids are supported: 2 covers fill the top row; 3 covers fill the top row and bottom-left. If only 1 cover is found, it falls back to single cover display. The folder name overlay works the same as in single mode.

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
  - **"Folder cover style"**: submenu with two options — "Single cover" (default) and "Grid (2×2)".
  - "Crop folder custom image": crop the custom `.cover` image to fill the display area (default: enabled).
  - "Show folder name": toggle folder name visibility (default: enabled).

## Related Resources

- [KOReader Documentation](https://github.com/koreader/koreader/wiki)
- [KOReader User Patches](https://github.com/koreader/koreader/wiki/Userpatch)

---

Note: This is a community-derived patch based on [sebdelsol/KOReader.patches](https://github.com/sebdelsol/KOReader.patches). Key differences include grid (2×2) cover mode, recursive subfolder search, custom `.cover` file support, e-ink flash elimination, asynchronous cover loading, LRU caching, and various robustness improvements.
