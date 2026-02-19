-- Custom sorting algorithms for KOReader file browser
-- Place this file in koreader/patches/

local BookList = require("ui/widget/booklist")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local function processAuthorName(author_name, sort_type)
    if not author_name or author_name == "\u{FFFF}" then
        return author_name
    end

    if sort_type == "last_first" and not author_name:find(",") then
        local words = {}
        for word in author_name:gmatch("%S+") do
            table.insert(words, word)
        end
        if #words > 1 then
            local last_name = words[#words]
            local first_names = {}
            for i = 1, #words - 1 do
                table.insert(first_names, words[i])
            end
            return last_name .. ", " .. table.concat(first_names, " ")
        end
    end

    return author_name
end

local function prepareItem(item, ui, sort_type)
    if not ui or not ui.bookinfo then
        item.doc_props = {
            authors = "\u{FFFF}",
            series = "\u{FFFF}",
            display_title = item.text,
            pubdate = "\u{FFFF}"
        }
        item.author_sort_key = "\u{FFFF}"
        return
    end

    local ok, doc_props = pcall(ui.bookinfo.getDocProps, ui.bookinfo, item.path or item.file)
    if not ok or not doc_props then
        doc_props = { display_title = item.text }
    end
    doc_props.authors = doc_props.authors or "\u{FFFF}"
    doc_props.series = doc_props.series or "\u{FFFF}"
    doc_props.display_title = doc_props.display_title or item.text
    doc_props.pubdate = doc_props.pubdate or "\u{FFFF}"
    item.doc_props = doc_props
    item.author_sort_key = processAuthorName(doc_props.authors, sort_type)
end

local function formatInfo(item, sort_type)
    if not item.doc_props then
        return ""
    end

    local parts = {}

    if item.doc_props.authors and item.doc_props.authors ~= "\u{FFFF}" then
        table.insert(parts, processAuthorName(item.doc_props.authors, sort_type))
    end

    if item.doc_props.series and item.doc_props.series ~= "\u{FFFF}" then
        if item.doc_props.series_index then
            table.insert(parts, item.doc_props.series .. " #" .. item.doc_props.series_index)
        else
            table.insert(parts, item.doc_props.series)
        end
    end

    if item.doc_props.pubdate and item.doc_props.pubdate ~= "\u{FFFF}" then
        table.insert(parts, item.doc_props.pubdate)
    end

    return table.concat(parts, " \u{2022} ")
end

local function compareAuthorSeries(a, b)
    if a.author_sort_key ~= b.author_sort_key then
        return ffiUtil.strcoll(a.author_sort_key, b.author_sort_key)
    end

    if a.doc_props.series ~= b.doc_props.series then
        return ffiUtil.strcoll(a.doc_props.series, b.doc_props.series)
    end

    if a.doc_props.series ~= "\u{FFFF}" then
        local has_idx_a = a.doc_props.series_index ~= nil
        local has_idx_b = b.doc_props.series_index ~= nil
        if has_idx_a and has_idx_b then
            local idx_a = tonumber(a.doc_props.series_index) or 0
            local idx_b = tonumber(b.doc_props.series_index) or 0
            if idx_a ~= idx_b then
                return idx_a < idx_b
            end
        elseif has_idx_a ~= has_idx_b then
            return has_idx_a
        end
    end

    return nil
end

-- Helper functions defined at module level
local CustomSorting = {
    prepareItem = prepareItem,
    formatInfo = formatInfo,
    compareAuthorSeries = compareAuthorSeries,
}

-- Sorting options
BookList.collates.author_first_last_series_title = {
    text = _("author (first name) - series - title"),
    menu_order = 5,
    can_collate_mixed = false,

    item_func = function(item, ui)
        CustomSorting.prepareItem(item, ui, "first_last")
    end,

    init_sort_func = function(cache)
        local my_cache = cache or {}
        return function(a, b)
            local result = CustomSorting.compareAuthorSeries(a, b)
            if result ~= nil then
                return result
            end
            return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
        end, my_cache
    end,

    mandatory_func = function(item)
        return CustomSorting.formatInfo(item, "first_last")
    end,
}

BookList.collates.author_last_first_series_title = {
    text = _("author (last name) - series - title"),
    menu_order = 6,
    can_collate_mixed = false,

    item_func = function(item, ui)
        CustomSorting.prepareItem(item, ui, "last_first")
    end,

    init_sort_func = function(cache)
        local my_cache = cache or {}
        return function(a, b)
            local result = CustomSorting.compareAuthorSeries(a, b)
            if result ~= nil then
                return result
            end
            return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
        end, my_cache
    end,

    mandatory_func = function(item)
        return CustomSorting.formatInfo(item, "last_first")
    end,
}

BookList.collates.author_first_last_series_date = {
    text = _("author (first name) - series - published date"),
    menu_order = 7,
    can_collate_mixed = false,

    item_func = function(item, ui)
        CustomSorting.prepareItem(item, ui, "first_last")
    end,

    init_sort_func = function(cache)
        local my_cache = cache or {}
        return function(a, b)
            local result = CustomSorting.compareAuthorSeries(a, b)
            if result ~= nil then
                return result
            end
            if a.doc_props.pubdate ~= b.doc_props.pubdate then
                return ffiUtil.strcoll(a.doc_props.pubdate, b.doc_props.pubdate)
            end
            return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
        end, my_cache
    end,

    mandatory_func = function(item)
        return CustomSorting.formatInfo(item, "first_last")
    end,
}

BookList.collates.author_last_first_series_date = {
    text = _("author (last name) - series - published date"),
    menu_order = 8,
    can_collate_mixed = false,

    item_func = function(item, ui)
        CustomSorting.prepareItem(item, ui, "last_first")
    end,

    init_sort_func = function(cache)
        local my_cache = cache or {}
        return function(a, b)
            local result = CustomSorting.compareAuthorSeries(a, b)
            if result ~= nil then
                return result
            end
            if a.doc_props.pubdate ~= b.doc_props.pubdate then
                return ffiUtil.strcoll(a.doc_props.pubdate, b.doc_props.pubdate)
            end
            return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
        end, my_cache
    end,

    mandatory_func = function(item)
        return CustomSorting.formatInfo(item, "last_first")
    end,
}

return BookList.collates
