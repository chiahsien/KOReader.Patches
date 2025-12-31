--[[--
User patch to clean up orphaned .sdr (sidecar) folders across all metadata storage modes.

This patch scans for and safely removes sidecar folders that no longer have corresponding
book files.  It supports all three metadata storage modes:
  - "doc"  : sidecar folders are stored alongside book files
  - "dir"  : all sidecars are centralized in ~/.koreader/docsettings/
  - "hash" : sidecars are stored by file hash in ~/.koreader/hashdocsettings/

Execution Priority: 2 (late, after UIManager is ready)

@module CleanOrphanedSDR
]]

local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local util = require("util")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

--[[--
Configuration constants for sidecar cleanup.

@table CONFIG
@field SIDECAR_SUFFIX string suffix used for sidecar directories (.sdr)
@field METADATA_FILENAME string metadata file name (metadata.lua)
]]
local CONFIG = {
    SIDECAR_SUFFIX = ".sdr",
    METADATA_FILENAME = "metadata.lua",
}

--[[--
Display name mappings for metadata storage modes.

@table METADATA_FOLDER_STR
]]
local METADATA_FOLDER_STR = {
    ["doc"]  = _("book folder"),
    ["dir"]  = DocSettings.getSidecarStorage("dir"),
    ["hash"] = DocSettings.getSidecarStorage("hash"),
}

--[[--
Retrieves the home directory for book storage.

Attempts to read the configured home directory from settings, falls back to
device home directory or current directory if not found or invalid.

@treturn string path to the home directory
]]
local function getHomeDirectory()
    local home_dir = G_reader_settings:readSetting("home_dir")
    if not home_dir or lfs.attributes(home_dir, "mode") ~= "directory" then
        home_dir = Device.home_dir or lfs.currentdir()
    end
    return home_dir
end

--[[--
Safely removes a sidecar directory and all its contents.

Recursively deletes all files and subdirectories within the target directory,
then removes the empty directory itself.  Logs all operations for debugging.

@string dir path to the sidecar directory to remove
@treturn bool true if removal succeeded, false otherwise
]]
local function safeRemoveSidecarDir(dir)
    if not dir or lfs.attributes(dir, "mode") ~= "directory" then
        return false
    end

    -- Remove all files and subdirectories
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir .. "/" .. entry
            local mode = lfs.attributes(full_path, "mode")
            if mode == "file" then
                os.remove(full_path)
                logger.dbg("Removed file:", full_path)
            elseif mode == "directory" then
                safeRemoveSidecarDir(full_path) -- Recursive call for subdirectories
            end
        end
    end

    -- Now remove the empty directory
    local success = os.remove(dir)
    if success then
        logger.info("Successfully removed directory:", dir)
    else
        logger.warn("Failed to remove directory:", dir)
    end
    return success
end

--[[--
Checks if a corresponding book file exists for a given sidecar directory (doc mode).

For a sidecar path like `/path/to/book.pdf.sdr`, this function checks if a file
named `book.pdf` (or with any other supported extension) exists in the same directory.

@string sdr_path full path to the sidecar directory (must end with .sdr)
@treturn bool true if a corresponding book file was found, false otherwise
]]
local function hasCorrespondingBook(sdr_path)
    local base_path = sdr_path:gsub(CONFIG.SIDECAR_SUFFIX .. "$", "")
    local dir_path = base_path:match("(.*/)") or "./"
    local sdr_base_name = base_path:match("([^/]+)$")

    -- Build list of all supported file extensions
    local supported_extensions = {}
    local ext_map = DocumentRegistry:getExtensions()
    for ext, _ in pairs(ext_map) do
        table.insert(supported_extensions, "." .. ext)
    end
    -- Add compound extensions (e.g., .kepub.epub)
    table.insert(supported_extensions, ".kepub.epub")

    -- Search for matching book file
    for entry in lfs.dir(dir_path) do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir_path .. entry
            local mode = lfs.attributes(full_path, "mode")

            if mode == "file" then
                -- Check if this file matches the expected book name
                for _, ext in ipairs(supported_extensions) do
                    local expected_book_name = sdr_base_name .. ext
                    if entry == expected_book_name then
                        logger.dbg("Found matching book:", entry, "for SDR:", sdr_base_name)
                        return true
                    end
                end
            end
        end
    end

    logger.dbg("No matching book found for SDR:", sdr_base_name)
    return false
end

--[[--
Creates a file existence checker for "doc" mode (book folder).

Returns a function that checks if a corresponding book file exists alongside
the sidecar directory.

@treturn function checker function (sdr_full_path) -> bool
]]
local function createDocModeChecker()
    return function(sdr_full_path)
        return hasCorrespondingBook(sdr_full_path)
    end
end

--[[--
Creates a file existence checker for "dir" mode (centralized directory).

In dir mode, the directory structure mirrors the original book folder structure.
For example:
  - Book: /home/user/Books/fiction/book.pdf
  - Sidecar: ~/.koreader/docsettings/home/user/Books/fiction/book.pdf.sdr

Returns a function that reconstructs the original file path from the sidecar
path and checks if it still exists.

@treturn function checker function (sdr_full_path) -> bool
]]
local function createDirModeChecker()
    return function(sdr_full_path)
        -- Reconstruct the original file path by removing .sdr suffix
        local original_path = sdr_full_path:gsub(CONFIG.SIDECAR_SUFFIX .. "$", "")

        -- Check if the original book file still exists
        local exists = lfs.attributes(original_path, "mode") == "file"
        if not exists then
            logger.dbg("Original file not found for dir mode SDR:", sdr_full_path)
        end
        return exists
    end
end

--[[--
Creates a file existence checker for "hash" mode (hash-based storage).

In hash mode, sidecars are stored by file content hash.  The checker attempts to
read the stored doc_path from the sidecar's metadata file to determine if the
original book still exists.

@treturn function checker function (sdr_full_path) -> bool
]]
local function createHashModeChecker()
    return function(sdr_full_path)
        -- Try to read doc_path from the metadata file
        local metadata_file = sdr_full_path ..  "/" .. CONFIG.METADATA_FILENAME
        local doc_path = nil

        if lfs.attributes(metadata_file, "mode") == "file" then
            local doc_settings = DocSettings.openSettingsFile(metadata_file)
            if doc_settings and doc_settings.data then
                doc_path = doc_settings:readSetting("doc_path")
            else
                logger.warn("Failed to read metadata from hash mode SDR:", metadata_file)
                return false
            end
        else
            logger.warn("Metadata file not found in hash mode SDR:", sdr_full_path)
            return false
        end

        -- Check if the document file still exists
        local exists = doc_path and lfs.attributes(doc_path, "mode") == "file"
        if not exists then
            logger.dbg("Document file not found for hash mode SDR.  doc_path:", doc_path)
        end
        return exists
    end
end

--[[--
Unified scanner for orphaned .sdr folders with mode-specific existence checking.

Uses a Strategy Pattern approach: the same recursive scanning logic works for all
modes, but delegates file existence checks to a mode-specific checker function.

@string dir current directory being scanned
@function existence_checker function(sdr_full_path) -> bool that determines if file exists
@int cleaned_count running count of cleaned folders (default: 0)
@treturn int total number of folders cleaned
]]
local function scanAndCleanOrphanedSdrs(dir, existence_checker, cleaned_count)
    cleaned_count = cleaned_count or 0

    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir .. "/" .. entry
            local mode = lfs.attributes(full_path, "mode")

            if mode == "directory" then
                if entry:match(CONFIG.SIDECAR_SUFFIX .. "$") then
                    -- Found a .sdr folder, check if it's orphaned
                    if not existence_checker(full_path) then
                        logger.info("Cleaning orphaned SDR folder:", full_path)
                        safeRemoveSidecarDir(full_path)
                        cleaned_count = cleaned_count + 1
                    end
                else
                    -- Recurse into subdirectories
                    cleaned_count = scanAndCleanOrphanedSdrs(full_path, existence_checker, cleaned_count)
                end
            end
        end
    end

    return cleaned_count
end

--[[--
Mode registry table for extensible mode configuration.

Each mode entry contains:
  - name: display name for user messages
  - getDir: function that returns the directory to scan
  - checker: function that returns a file existence checker

Design allows easy addition of new modes without modifying main function.

@table MODES
]]
local MODES = {
    doc = {
        name = _("book folder"),
        getDir = getHomeDirectory,
        checker = createDocModeChecker,
    },
    dir = {
        name = METADATA_FOLDER_STR["dir"],
        getDir = function()
            return DataStorage:getDocSettingsDir()
        end,
        checker = createDirModeChecker,
    },
    hash = {
        name = METADATA_FOLDER_STR["hash"],
        getDir = function()
            return DataStorage:getDocSettingsHashDir()
        end,
        checker = createHashModeChecker,
    },
}

--[[--
Main cleanup function with automatic mode detection and handling.

Reads the current metadata storage mode setting from G_reader_settings and
dispatches to the appropriate scanner with the corresponding existence checker.
Displays user-friendly messages about the cleanup results.

@treturn nil
]]
local function cleanupOrphanedSdrFolders()
    -- Determine the current metadata storage mode
    local preferred_location = G_reader_settings:readSetting("document_metadata_folder", "doc")

    -- Look up mode configuration
    local mode_config = MODES[preferred_location]

    if not mode_config then
        -- Handle unknown/unexpected mode
        UIManager:show(InfoMessage:new{
            text = T(_("Unknown metadata storage mode: %1"), preferred_location),
            timeout = 5
        })
        logger.warn("SDR cleanup patch skipped: unknown storage mode:", preferred_location)
        return
    end

    -- Get the scan directory and checker function
    local scan_dir = mode_config.getDir()
    local mode_name = mode_config.name

    -- Verify scan directory exists
    if not scan_dir or lfs.attributes(scan_dir, "mode") ~= "directory" then
        logger.warn("Scan directory does not exist or is inaccessible:", scan_dir)
        UIManager:show(InfoMessage:new{
            text = T(_("Cannot scan %1: directory not found or not accessible."), mode_name),
            timeout = 5
        })
        return
    end

    logger.info("Starting cleanup of orphaned .sdr folders in", mode_name)
    logger.info("Scanning directory:", scan_dir)

    -- Create the mode-specific file existence checker
    local existence_checker = mode_config.checker()

    -- Execute the unified scan with the mode-specific checker
    local cleaned_count = scanAndCleanOrphanedSdrs(scan_dir, existence_checker)

    -- Display results and log
    if cleaned_count > 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("Cleaned up %1 orphaned .sdr folder(s) in %2."), cleaned_count, mode_name),
            timeout = 3
        })
        logger.info("Cleanup completed: removed", cleaned_count, "orphaned .sdr folders from", mode_name)
    else
        logger.info("No orphaned .sdr folders found in", mode_name)
    end
end

-- Execute the cleanup on patch load
cleanupOrphanedSdrFolders()
