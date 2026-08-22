--[[--
User patch to clean up orphaned .sdr (sidecar) folders for the active metadata
storage mode.

On each startup (deferred by 1 second), this patch detects the currently
configured metadata storage mode and scans the corresponding directory for
sidecar folders whose book files no longer exist. Orphaned sidecars are
removed to reclaim storage space.

Supported modes:
  - "doc"  : sidecar folders stored alongside book files
  - "dir"  : sidecars centralized in the docsettings directory
  - "hash" : sidecars stored by file content hash

Execution Priority: 2 (late, after UIManager is ready)

@module CleanOrphanedSDR
]]

local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

--[[--
Configuration constants for sidecar cleanup.

@table CONFIG
@field SIDECAR_SUFFIX string suffix used for sidecar directories (.sdr)
]]
local CONFIG = {
    SIDECAR_SUFFIX = ".sdr",
}

--- Retrieves the home directory for book storage.
-- Attempts to read the configured home directory from settings, falls back to
-- device home directory or current directory if not found or invalid.
-- @treturn string path to the home directory
local function getHomeDirectory()
    local home_dir = G_reader_settings:readSetting("home_dir")
    if not home_dir or lfs.attributes(home_dir, "mode") ~= "directory" then
        home_dir = Device.home_dir or lfs.currentdir()
    end
    logger.dbg("CleanOrphanedSDR: resolved home directory:", home_dir)
    return home_dir
end

--- Creates a file existence checker for "doc" mode (book folder).
-- Builds the supported extension set once, then returns a closure that checks
-- if a corresponding book file exists alongside the sidecar directory.
-- @treturn function checker function (sdr_full_path) → bool
local function createDocModeChecker()
    local supported_extensions = {}
    for ext, _ in pairs(DocumentRegistry:getExtensions()) do
        supported_extensions["." .. ext] = true
    end
    logger.dbg("CleanOrphanedSDR: doc mode checker initialized with supported extensions from DocumentRegistry")

    return function(sdr_full_path)
        local base_path = sdr_full_path:gsub(CONFIG.SIDECAR_SUFFIX .. "$", "")
        local dir_path = base_path:match("(.*/)") or "./"
        local sdr_base_name = base_path:match("([^/]+)$")

        local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
        if not ok then
            logger.warn("Cannot read directory:", dir_path)
            return true
        end
        for entry in iter, dir_obj do
            if entry ~= "." and entry ~= ".." then
                local full_path = dir_path .. entry
                if lfs.attributes(full_path, "mode") == "file" then
                    local ext = entry:match("^" .. sdr_base_name:gsub("([%.%-%+%[%]%(%)%$%^%%])", "%%%1") .. "(%..+)$")
                    if ext and supported_extensions[ext] then
                        logger.dbg("Found matching book:", entry, "for SDR:", sdr_base_name)
                        return true
                    end
                end
            end
        end

        logger.dbg("No matching book found for SDR:", sdr_base_name)
        return false
    end
end

--- Creates a file existence checker for "dir" mode (centralized directory).
-- In dir mode, the sdr path mirrors the original book path with the last extension
-- stripped. For example:
--   - Book: /mnt/onboard/Books/novel.epub
--   - Sidecar: ~/.koreader/docsettings/mnt/onboard/Books/novel.sdr
-- To check if the original book still exists, we strip the docsettings prefix and
-- the .sdr suffix to recover the base path, then look for a file with any supported
-- extension at that location.
-- @treturn function checker function (sdr_full_path) → bool
local function createDirModeChecker()
    local doc_settings_dir = DataStorage:getDocSettingsDir()

    -- Build supported extension set for O(1) lookup
    local supported_extensions = {}
    for ext, _ in pairs(DocumentRegistry:getExtensions()) do
        supported_extensions["." .. ext] = true
    end
    logger.dbg("CleanOrphanedSDR: dir mode checker initialized with supported extensions from DocumentRegistry")

    return function(sdr_full_path)
        -- Strip the docsettings prefix and .sdr suffix to recover the original base path
        -- e.g. "~/.koreader/docsettings/mnt/onboard/Books/novel.sdr"
        --    -> "/mnt/onboard/Books/novel"
        local base_path = sdr_full_path:gsub(CONFIG.SIDECAR_SUFFIX .. "$", "")
        base_path = "/" .. base_path:sub(#doc_settings_dir + 2) -- +2 to skip the trailing /
        logger.dbg("CleanOrphanedSDR: dir mode reconstructed base_path:", base_path)

        -- Extract directory and basename for scanning
        local dir_path = base_path:match("(.*/)") or "./"
        local base_name = base_path:match("([^/]+)$")
        if not base_name then
            logger.warn("CleanOrphanedSDR: could not extract base name from dir mode SDR:", sdr_full_path)
            return false
        end

        -- Check if directory exists before scanning
        if lfs.attributes(dir_path, "mode") ~= "directory" then
            logger.dbg("Original directory not found for dir mode SDR:", dir_path)
            return false
        end

        -- Search for a matching book file with any supported extension
        local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
        if not ok then
            logger.warn("Cannot read directory:", dir_path)
            return true
        end
        for entry in iter, dir_obj do
            if entry ~= "." and entry ~= ".." then
                local ext = entry:match("^" .. base_name:gsub("([%.%-%+%[%]%(%)%$%^%%])", "%%%1") .. "(%..+)$")
                if ext and supported_extensions[ext] then
                    logger.dbg("Found matching book:", entry, "for dir mode SDR:", sdr_full_path)
                    return true
                end
            end
        end

        logger.dbg("Original file not found for dir mode SDR:", sdr_full_path)
        return false
    end
end

--- Creates a file existence checker for "hash" mode (hash-based storage).
-- In hash mode, sidecars are stored by file content hash. The metadata filename
-- is `metadata.<ext>.lua` (e.g., `metadata.epub.lua`), not a fixed name.
-- The checker scans the sdr directory for any matching metadata file, reads the
-- stored doc_path, and verifies the original book still exists.
-- @treturn function checker function (sdr_full_path) → bool
local function createHashModeChecker()
    return function(sdr_full_path)
        -- Find the metadata file by pattern (metadata.<ext>.lua)
        local metadata_file = nil
        local ok, iter, dir_obj = pcall(lfs.dir, sdr_full_path)
        if not ok then
            logger.warn("Cannot read hash mode SDR directory:", sdr_full_path)
            return true
        end
        for entry in iter, dir_obj do
            if entry:match("^metadata%..+%.lua$") then
                metadata_file = sdr_full_path .. "/" .. entry
                break
            end
        end

        if not metadata_file then
            logger.warn("No metadata file found in hash mode SDR:", sdr_full_path)
            return false
        end

        local ok, doc_settings = pcall(DocSettings.openSettingsFile, metadata_file)
        if not ok or not doc_settings or not doc_settings.data then
            -- Unreadable metadata -- skip deletion to be safe
            logger.warn("Failed to read metadata from hash mode SDR:", metadata_file)
            return true
        end

        local doc_path = doc_settings:readSetting("doc_path")

        -- Check if the document file still exists
        local exists = doc_path and lfs.attributes(doc_path, "mode") == "file"
        if exists then
            logger.dbg("CleanOrphanedSDR: hash mode book found at:", doc_path)
        else
            logger.dbg("Document file not found for hash mode SDR. doc_path:", doc_path)
        end
        return exists
    end
end

--- Unified scanner for orphaned .sdr folders with mode-specific existence checking.
-- Uses a Strategy Pattern approach: the same recursive scanning logic works for all
-- modes, but delegates file existence checks to a mode-specific checker function.
-- @string dir current directory being scanned
-- @function existence_checker function(sdr_full_path) → bool that determines if file exists
-- @int cleaned_count running count of cleaned folders (default: 0)
-- @treturn int total number of folders cleaned
local function scanAndCleanOrphanedSdrs(dir, existence_checker, cleaned_count)
    cleaned_count = cleaned_count or 0

    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then
        logger.warn("Cannot read directory, skipping:", dir)
        return cleaned_count
    end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir .. "/" .. entry
            local mode = lfs.attributes(full_path, "mode")

            if mode == "directory" then
                if entry:match(CONFIG.SIDECAR_SUFFIX .. "$") then
                    -- Found a .sdr folder, check if it's orphaned
                    if not existence_checker(full_path) then
                        logger.info("Cleaning orphaned SDR folder:", full_path)
                        local purge_ok, purge_err = pcall(ffiUtil.purgeDir, full_path)
                        if purge_ok then
                            cleaned_count = cleaned_count + 1
                        else
                            logger.warn("Failed to remove orphaned SDR folder:", full_path, purge_err)
                        end
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
        name = _("settings folder"),
        getDir = function()
            return DataStorage:getDocSettingsDir()
        end,
        checker = createDirModeChecker,
    },
    hash = {
        name = _("hash folder"),
        getDir = function()
            return DataStorage:getDocSettingsHashDir()
        end,
        checker = createHashModeChecker,
    },
}

--- Main cleanup function with automatic mode detection and handling.
-- Reads the current metadata storage mode setting from G_reader_settings and
-- dispatches to the appropriate scanner with the corresponding existence checker.
-- Displays user-friendly messages about the cleanup results.
local function cleanupOrphanedSdrFolders()
    -- Determine the current metadata storage mode
    local preferred_location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    logger.info("CleanOrphanedSDR: detected metadata storage mode:", preferred_location)

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

-- Defer cleanup to avoid blocking startup
UIManager:scheduleIn(1, cleanupOrphanedSdrFolders)
logger.info("CleanOrphanedSDR patch loaded, cleanup scheduled in 1 second")
