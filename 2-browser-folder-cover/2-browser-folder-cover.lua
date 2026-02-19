local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
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
    edge = {
        thick = Screen: scaleBySize(2.5),
        margin = Size.line.medium,
        color = Blitbuffer.COLOR_GRAY_4,
        width = 0.97,
    },
    face = {
        border_size = Size.border.thick,
        alpha = 0.75,
        dir_max_font_size = 25,
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

    -- cover item
    function MosaicMenuItem:update(...)
        original_update(self, ...)
        if self.menu.no_refresh_covers or not self.do_cover_image then return end
        if self._foldercover_version == settings_version then return end

        if not self.entry then return end
        if self.entry.is_file or self.entry.file or not self.mandatory then return end -- it's a file
        local dir_path = self.entry.path
        if not dir_path then return end

        local cover_file = findCover(dir_path) -- custom .cover file
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

        -- check cover source cache: skip expensive directory scan on hit
        local cached_book_path = cover_source_cache[dir_path]
        if cached_book_path then
            local bookinfo = BookInfoManager:getBookInfo(cached_book_path, true)
            if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched
               and not bookinfo.ignore_cover
               and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                self._foldercover_version = settings_version
                self.bookinfo_found = true
                return
            end
            cover_source_cache[dir_path] = nil
        end

        self.menu._dummy = true
        local ok, entries = pcall(self.menu.genItemTableFromPath, self.menu, dir_path)
        self.menu._dummy = false
        if not ok or not entries then return end

        local found_book = false
        local has_pending_covers = false
        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                if
                    bookinfo
                    and bookinfo.cover_bb
                    and bookinfo.has_cover
                    and bookinfo.cover_fetched
                    and not bookinfo.ignore_cover
                    and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs)
                then
                    self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                    cover_source_cache[dir_path] = entry.path
                    found_book = true
                    break
                elseif not bookinfo or not bookinfo.cover_fetched then
                    has_pending_covers = true
                end
            end
        end

        if not found_book then
            for _, entry in ipairs(entries) do
                if not (entry.is_file or entry.file) then
                    local book_entry, bookinfo = findBookInSubfolders(self.menu, entry.path, 3, BookInfoManager)
                    if book_entry and bookinfo then
                        if not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                            self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                            cover_source_cache[dir_path] = book_entry.path
                            found_book = true
                            break
                        end
                    end
                end
            end
        end

        if found_book then
            self._foldercover_version = settings_version
            self.bookinfo_found = true
            self._foldercover_queued = false
        elseif has_pending_covers and self.menu.items_to_update then
            if not self._foldercover_queued then
                self.bookinfo_found = false
                self._foldercover_queued = true
                table.insert(self.menu.items_to_update, self)
            end
        else
            self._foldercover_version = settings_version
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        if not img.w or not img.h or img.w <= 0 or img.h <= 0 then return end

        local top_h = 2 * (Folder.edge.thick + Folder.edge.margin)
        local target = {
            w = self.width - 2 * Folder.face.border_size,
            h = self.height - 2 * Folder.face.border_size - top_h,
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
                    padding = 0,
                    bordersize = Folder.face.border_size,
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
                VerticalSpan:new { width = math.max(0, self.height - (top_h + dimen.h)) },
                LineWidget:new {
                    background = Folder.edge.color,
                    dimen = { w = math.floor(dimen.w * (Folder.edge.width ^ 2)), h = Folder.edge.thick },
                },
                VerticalSpan:new { width = Folder.edge.margin },
                LineWidget:new {
                    background = Folder.edge.color,
                    dimen = { w = math.floor(dimen.w * Folder.edge.width), h = Folder.edge.thick },
                },
                VerticalSpan:new { width = Folder.edge.margin },
                OverlapGroup:new {
                    dimen = { w = self.width, h = self.height - top_h },
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
        if item then
            item.sub_item_table[#item.sub_item_table].separator = true
            for __, setting in ipairs(settings) do
                if
                    not getMenuItem( -- already exists ?
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
                            settings_version = settings_version + 1
                            cached_list = {}
                            cached_list_order = {}
                            cover_source_cache = {}
                            self.ui.file_chooser:updateItems()
                        end,
                    })
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
