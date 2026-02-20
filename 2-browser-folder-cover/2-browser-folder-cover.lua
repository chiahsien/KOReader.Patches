local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")

local _ = require("gettext")
local Screen = Device.screen

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local function findCover(dir_path)
    local path = dir_path ..  "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function getMenuItem(menu, ...) -- menu text labels to walk
    local function findItem(sub_items, texts)
        local find = {}
        texts = type(texts) == "table" and texts or { texts }
        -- stylua: ignore
        for _, text in ipairs(texts) do find[text] = true end
        for _, item in ipairs(sub_items) do
            local text = item.text
            if not text and item.text_func then
                local ok, result = pcall(item.text_func)
                text = ok and result or nil
            end
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do -- walk path
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in ipairs { ... } do
        if type(key) == "table" then
            local sorted_keys = {}
            for k in pairs(key) do
                table.insert(sorted_keys, k)
            end
            table.sort(sorted_keys, function(a, b) return tostring(a) < tostring(b) end)
            table.insert(keys, "{")
            for _, k in ipairs(sorted_keys) do
                table.insert(keys, tostring(k) .. "=" .. tostring(key[k]))
            end
            table.insert(keys, "}")
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "\0")
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local cached_list = {}       -- cached_list[dirpath][key] = widget
local cached_list_order = {} -- LRU order of dirpaths, most recent last
local cached_list_max = 10   -- max number of directories to keep in cache
local cover_source_cache = {} -- dir_path → book_path that provides the cover

function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    if not cached_list[dirpath] then
        cached_list[dirpath] = {}
        table.insert(cached_list_order, dirpath)
        -- evict oldest directory if over limit
        while #cached_list_order > cached_list_max do
            local oldest = table.remove(cached_list_order, 1)
            cached_list[oldest] = nil
            cover_source_cache[oldest] = nil
        end
    end
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    local dir_cache = cached_list[dirpath]
    dir_cache[key] = dir_cache[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
    return dir_cache[key]
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        local first_byte = word:byte(1)
        if first_byte and first_byte < 0x80 then
            table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
        else
            table.insert(words, word)
        end
    end
    return table.concat(words, " ")
end

local Folder = {
    face = {
        border_size = Size.border.thin,
        alpha = 0.75,
        dir_max_font_size = 25,
    },
    grid = {
        gap = Screen:scaleBySize(2),
    },
}

-- Recursively search subfolders for a book with a valid cover
local function findBookInSubfolders(menu, dir_path, max_depth, BookInfoManager)
    max_depth = max_depth or 3  -- limit search depth to avoid infinite recursion
    if max_depth <= 0 then return nil end

    menu._dummy = true
    local ok, entries = pcall(menu.genItemTableFromPath, menu, dir_path)
    menu._dummy = false
    if not ok or not entries then return nil end

    -- Search for books in the current directory first
    for _, entry in ipairs(entries) do
        if entry.is_file or entry.file then
            local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
            if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched
               and not bookinfo.ignore_cover then
                return entry, bookinfo
            end
        end
    end

    -- No book found in current directory, recurse into subfolders
    for _, entry in ipairs(entries) do
        if not (entry.is_file or entry.file) then
            local book_entry, bookinfo = findBookInSubfolders(menu, entry.path, max_depth - 1, BookInfoManager)
            if book_entry then return book_entry, bookinfo end
        end
    end

    return nil
end

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then return end -- Protect against remnants of project title
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    if not BookInfoManager then return end
    local original_update = MosaicMenuItem.update

    -- setting
    local function BooleanSetting(text, name, default)
        local self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then return not setting end -- false is stored as nil, so we need our own logic for boolean default
            return setting
        end
        self.toggle = function() return BookInfoManager:toggleSetting(name) end
        return self
    end

    local settings_version = 0

    local crop_to_fit = BooleanSetting(_("Crop folder custom image"), "folder_crop_custom_image", true)
    local show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", true)
    local settings = { crop_to_fit, show_folder_name }

    local COVER_MODE = { SINGLE = "single", GRID = "grid" }
    local function getCoverMode()
        return BookInfoManager:getSetting("folder_cover_mode") or COVER_MODE.SINGLE
    end

    -- cover item
    -- Directories skip original_update() to avoid the e-ink flash caused by painting
    -- the default rounded-box tile first, then replacing it with the cover widget.
    -- Instead, we find and set the cover directly, falling back to original_update()
    -- only when no cover is available.
    --
    -- In grid mode, collects up to 4 book covers and dispatches to _setFolderCoverGrid.
    -- A single cover in grid mode falls back to _setFolderCover (full-size display).

    local function hasValidCover(bookinfo, cover_specs)
        return bookinfo
            and bookinfo.cover_bb
            and bookinfo.has_cover
            and bookinfo.cover_fetched
            and not bookinfo.ignore_cover
            and not BookInfoManager.isCachedCoverInvalid(bookinfo, cover_specs)
    end

    local function setCoverFromList(item, covers)
        if #covers == 0 then return false end
        if #covers == 1 or getCoverMode() == COVER_MODE.SINGLE then
            item:_setFolderCover(covers[1])
        else
            item:_setFolderCoverGrid(covers)
        end
        return true
    end

    function MosaicMenuItem:update(...)
        if not self.entry
           or self.entry.is_file or self.entry.file or not self.mandatory
           or self.menu.no_refresh_covers or not self.do_cover_image then
            return original_update(self, ...)
        end

        local dir_path = self.entry.path
        if not dir_path then return original_update(self, ...) end

        if self._foldercover_version == settings_version then return end

        self.is_directory = true
        local border_size = Size.border.thin
        self.menu.cover_specs = {
            max_cover_w = self.width - 2 * border_size,
            max_cover_h = self.height - 2 * border_size,
        }

        -- Custom .cover file always displays as single cover regardless of mode
        local cover_file = findCover(dir_path)
        if cover_file then
            local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
            local success, w, h = pcall(function()
                tmp_img:_render()
                return tmp_img:getOriginalWidth(), tmp_img:getOriginalHeight()
            end)
            tmp_img:free()
            if success then
                self:_setFolderCover { file = cover_file, w = w, h = h, scale_to_fit = crop_to_fit.get() }
                self._foldercover_version = settings_version
                self.bookinfo_found = true
                return
            end
        end

        local cover_mode = getCoverMode()
        local max_covers = cover_mode == COVER_MODE.GRID and 4 or 1

        -- Check cover source cache: skip expensive directory scan on hit.
        -- In grid mode the cache stores an array of book paths.
        local cached = cover_source_cache[dir_path]
        if cached then
            local cached_paths = type(cached) == "table" and cached or { cached }
            local covers = {}
            local cache_valid = true
            for _, book_path in ipairs(cached_paths) do
                local bookinfo = BookInfoManager:getBookInfo(book_path, true)
                if hasValidCover(bookinfo, self.menu.cover_specs) then
                    table.insert(covers, { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                else
                    cache_valid = false
                    break
                end
            end
            if cache_valid and setCoverFromList(self, covers) then
                self._foldercover_version = settings_version
                self.bookinfo_found = true
                return
            end
            cover_source_cache[dir_path] = nil
        end

        self.menu._dummy = true
        local ok, entries = pcall(self.menu.genItemTableFromPath, self.menu, dir_path)
        self.menu._dummy = false
        if not ok or not entries then
            return original_update(self, ...)
        end

        local covers = {}
        local cover_paths = {}
        local has_pending_covers = false
        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                if hasValidCover(bookinfo, self.menu.cover_specs) then
                    table.insert(covers, { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                    table.insert(cover_paths, entry.path)
                    if #covers >= max_covers then break end
                elseif not bookinfo or not bookinfo.cover_fetched then
                    has_pending_covers = true
                end
            end
        end

        -- If we still need more covers, recurse into subfolders
        if #covers < max_covers then
            for _, entry in ipairs(entries) do
                if not (entry.is_file or entry.file) then
                    local book_entry, bookinfo = findBookInSubfolders(self.menu, entry.path, 3, BookInfoManager)
                    if book_entry and bookinfo then
                        if not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                            table.insert(covers, { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                            table.insert(cover_paths, book_entry.path)
                            if #covers >= max_covers then break end
                        end
                    end
                end
            end
        end

        if setCoverFromList(self, covers) then
            -- Cache the source paths (single string for single mode, array for grid)
            cover_source_cache[dir_path] = #cover_paths == 1 and cover_paths[1] or cover_paths
            self._foldercover_version = settings_version
            self.bookinfo_found = true
            self._foldercover_queued = false
        elseif has_pending_covers and self.menu.items_to_update then
            -- No cover yet but extraction is pending; show default tile while waiting
            original_update(self, ...)
            if not self._foldercover_queued then
                self.bookinfo_found = false
                self._foldercover_queued = true
                table.insert(self.menu.items_to_update, self)
            end
        else
            -- No cover available at all; fall back to default directory widget
            original_update(self, ...)
            self._foldercover_version = settings_version
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        if not img.w or not img.h or img.w <= 0 or img.h <= 0 then return end

        local target = {
            w = self.width - 2 * Folder.face.border_size,
            h = self.height - 2 * Folder.face.border_size,
        }

        local img_options = { file = img.file, image = img.data }
        if img.scale_to_fit then
            img_options.scale_factor = math.max(target.w / img.w, target.h / img.h)
            img_options.width = target.w
            img_options.height = target.h
        else
            img_options.scale_factor = math.min(target.w / img.w, target.h / img.h)
        end

        local image = ImageWidget:new(img_options)
        local size = image:getSize()
        local dimen = { w = size.w + 2 * Folder.face.border_size, h = size.h + 2 * Folder.face.border_size }

        local image_widget = FrameContainer:new {
            padding = 0,
            bordersize = Folder.face.border_size,
            image,
            overlap_align = "center",
        }

        local directory = self:_getTextBoxes { w = size.w, h = size.h }

        local folder_name_widget
        if show_folder_name.get() then
            folder_name_widget = BottomContainer:new {
                dimen = dimen,
                FrameContainer:new {
                    padding = Folder.face.border_size,
                    bordersize = 0,
                    AlphaContainer:new { alpha = Folder.face.alpha, directory },
                },
                overlap_align = "center",
            }
        else
            directory:free()
            folder_name_widget = VerticalSpan:new { width = 0 }
        end

        local widget = CenterContainer:new {
            dimen = { w = self.width, h = self.height },
            VerticalGroup:new {
                VerticalSpan:new { width = math.max(0, self.height - dimen.h) },
                OverlapGroup:new {
                    dimen = { w = self.width, h = dimen.h },
                    image_widget,
                    folder_name_widget,
                },
            },
        }
        if self._underline_container and self._underline_container[1] then
            local previous_widget = self._underline_container[1]
            previous_widget:free()
        end

        if self._underline_container then
            self._underline_container[1] = widget
        end
    end

    function MosaicMenuItem:_setFolderCoverGrid(covers)
        local border = Folder.face.border_size
        local gap = Folder.grid.gap
        local target_w = self.width - 2 * border
        local target_h = self.height - 2 * border
        local cell_w = math.floor((target_w - gap) / 2)
        local cell_h = math.floor((target_h - gap) / 2)

        local function makeCell(img)
            local scale = math.max(cell_w / img.w, cell_h / img.h)
            local image = ImageWidget:new {
                image = img.data,
                scale_factor = scale,
                width = cell_w,
                height = cell_h,
            }
            return CenterContainer:new {
                dimen = { w = cell_w, h = cell_h },
                image,
            }
        end

        -- Layout: 2 covers → top row; 3 → top row + bottom-left; 4 → full 2×2
        local top_row = HorizontalGroup:new {}
        top_row[1] = makeCell(covers[1])
        if covers[2] then
            top_row[2] = HorizontalSpan:new { width = gap }
            top_row[3] = makeCell(covers[2])
        end

        local grid = VerticalGroup:new {}
        grid[1] = top_row

        if covers[3] then
            grid[2] = VerticalSpan:new { width = gap }
            local bottom_row = HorizontalGroup:new {}
            bottom_row[1] = makeCell(covers[3])
            if covers[4] then
                bottom_row[2] = HorizontalSpan:new { width = gap }
                bottom_row[3] = makeCell(covers[4])
            end
            grid[3] = bottom_row
        end

        local grid_widget = FrameContainer:new {
            padding = 0,
            bordersize = border,
            grid,
            overlap_align = "center",
        }

        local grid_size = grid_widget:getSize()
        local dimen = { w = grid_size.w, h = grid_size.h }

        local directory = self:_getTextBoxes { w = dimen.w - 2 * border, h = dimen.h - 2 * border }

        local folder_name_widget
        if show_folder_name.get() then
            folder_name_widget = BottomContainer:new {
                dimen = dimen,
                FrameContainer:new {
                    padding = border,
                    bordersize = 0,
                    AlphaContainer:new { alpha = Folder.face.alpha, directory },
                },
                overlap_align = "center",
            }
        else
            directory:free()
            folder_name_widget = VerticalSpan:new { width = 0 }
        end

        local widget = CenterContainer:new {
            dimen = { w = self.width, h = self.height },
            VerticalGroup:new {
                VerticalSpan:new { width = math.max(0, self.height - dimen.h) },
                OverlapGroup:new {
                    dimen = { w = self.width, h = dimen.h },
                    grid_widget,
                    folder_name_widget,
                },
            },
        }

        if self._underline_container and self._underline_container[1] then
            local previous_widget = self._underline_container[1]
            previous_widget:free()
        end

        if self._underline_container then
            self._underline_container[1] = widget
        end
    end

    function MosaicMenuItem:_getTextBoxes(dimen)
        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end -- remove "/"
        text = BD.directory(capitalize(text))
        local available_height = dimen.h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then -- don't go too low
                directory:free(true)
                directory = TextBoxWidget:new {
                    text = text,
                    face = Font:getFace("cfont", 10),
                    width = dimen.w,
                    alignment = "center",
                    bold = true,
                    height = available_height,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }
                break
            end
        end

        return directory
    end

    -- menu
    local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu

    function plugin:addToMainMenu(menu_items)
        orig_CoverBrowser_addToMainMenu(self, menu_items)
        if menu_items.filebrowser_settings == nil then return end

        local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
        if not item then return end

        local function invalidateAndRefresh()
            settings_version = settings_version + 1
            cached_list = {}
            cached_list_order = {}
            cover_source_cache = {}
            self.ui.file_chooser:updateItems()
        end

        item.sub_item_table[#item.sub_item_table].separator = true

        if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), _("Folder cover style")) then
            table.insert(item.sub_item_table, {
                text = _("Folder cover style"),
                sub_item_table = {
                    {
                        text = _("Single cover"),
                        checked_func = function() return getCoverMode() == COVER_MODE.SINGLE end,
                        callback = function()
                            BookInfoManager:saveSetting("folder_cover_mode", COVER_MODE.SINGLE)
                            invalidateAndRefresh()
                        end,
                    },
                    {
                        text = _("Grid (2×2)"),
                        checked_func = function() return getCoverMode() == COVER_MODE.GRID end,
                        callback = function()
                            BookInfoManager:saveSetting("folder_cover_mode", COVER_MODE.GRID)
                            invalidateAndRefresh()
                        end,
                    },
                },
            })
        end

        for __, setting in ipairs(settings) do
            if
                not getMenuItem(
                    menu_items.filebrowser_settings,
                    _("Mosaic and detailed list settings"),
                    setting.text
                )
            then
                table.insert(item.sub_item_table, {
                    text = setting.text,
                    checked_func = function() return setting.get() end,
                    callback = function()
                        setting.toggle()
                        invalidateAndRefresh()
                    end,
                })
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
