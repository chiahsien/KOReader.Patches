<a href="https://www.buymeacoffee.com/chiahsien" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# KOReader Browser Folder Cover

## Overview

This userpatch extends KOReader's file browser (Mosaic view) to display folder covers. A folder cover can be provided via a custom `.cover` file placed inside the folder, or derived from a book cover found inside the folder or its subfolders. This file is derived from sebdelsol/KOReader.patches with additional changes: recursive subfolder search, `.cover` support, and some performance/visual improvements.

## Features

- Support for a custom folder cover file named `.cover` with extensions: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`.
- If no custom cover is present, the patch will try to use the first book in the folder that has a valid cover.
- If no cover is found in the folder, it will recursively search subfolders (default depth: 3) for a book cover.
- Simple caching for `FileChooser:getListItem` to reduce repeated widget creation.
- New UI options: crop custom folder image, center folder name, show/hide folder name.
- Respects KOReader's existing cover cache validity checks to avoid using invalid cached covers.

## How It Works

- Search order and logic:
  1. Check for a `.cover` file plus supported extensions (for example `.cover.jpg`). If found, the custom image is used (optionally cropped to fill the slot).
  2. Scan the folder entries and call `BookInfoManager:getBookInfo()` for files; use the first valid book cover that is not marked ignored and that passes cache validity checks.
  3. If no cover is found in the current folder, perform a recursive search into subfolders (up to a default depth of 3) to find a book cover.

- Display: builds a mosaic item containing the cover image, folder name and number of books. The folder name font size is adjusted to fit available space, and the name can be displayed over a semi-transparent mask.

- Performance: adds a simple cache for `FileChooser:getListItem`, keyed by directory path and other parameters, to avoid rebuilding identical list widgets.

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
  - "Folder name centered": center the folder name on the cover.
  - "Show folder name": toggle folder name visibility.

## Related Resources

- [KOReader Documentation](https://github.com/koreader/koreader/wiki)
- [KOReader User Patches](https://github.com/koreader/koreader/wiki/Userpatch)
- [Sidecar File Specification](https://github.com/koreader/koreader/blob/master/frontend/docsettings.lua)

---

Note: This is a community-derived patch. Key differences from upstream are recursive subfolder search. To revert to the upstream version see: https://github.com/sebdelsol/KOReader.patches
