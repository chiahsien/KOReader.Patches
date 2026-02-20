--[[--
Custom sorting algorithms for KOReader file browser.

Adds four collate entries to BookList.collates, combining two author-name
orderings (first-name-first vs last-name-first) with two fallback fields
(title vs published date). Each collate sorts by:

    Author -> Series -> Series index -> Fallback (title or pubdate) -> Title

Missing metadata fields are normalized to the sentinel "\u{FFFF}" so they
sort after all real values in locale-aware comparisons.

@module 2-sort-by-author-series
]]

local BookList = require("ui/widget/booklist")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

--- Normalizes nil and empty string to nil.
-- Lua treats "" as truthy, so `x or default` won't catch empty strings
-- returned by getDocProps. This helper allows `nilIfEmpty(x) or sentinel`.
local function nilIfEmpty(s) return (s and s ~= "") and s or nil end

--- Locale-aware three-way string comparison.
-- ffiUtil.strcoll(a, b) returns a boolean (a < b), not a three-way value.
-- Two calls are needed to distinguish less-than / greater-than / equal.
-- @treturn true if x < y, false if x > y, nil if equal (enables tie-breaking).
local function strcollCompare(x, y)
    if ffiUtil.strcoll(x, y) then return true end
    if ffiUtil.strcoll(y, x) then return false end
    return nil
end

--- Reorders "First Last" -> "Last, First" for last_first sort mode.
-- Limitations: Assumes the final word is the surname. This fails for
-- compound surnames (e.g., "Gabriel Garcia Marquez"), suffixes ("Jr.", "III"),
-- and name orders where family name comes first (e.g., Chinese, Japanese, Korean).
-- Names already containing a comma are left unchanged.
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

--- BookList.collates item_func callback -- fetches and normalizes metadata.
-- Called once per item before sorting. Attaches doc_props and a precomputed
-- author_sort_key to the item. Uses pcall around getDocProps because the
-- bookinfo module may fail on corrupted files or missing metadata databases.
-- Missing/empty fields are set to "\u{FFFF}" (sorts last in strcoll).
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
    doc_props.authors = nilIfEmpty(doc_props.authors) or "\u{FFFF}"
    doc_props.series = nilIfEmpty(doc_props.series) or "\u{FFFF}"
    doc_props.display_title = nilIfEmpty(doc_props.display_title) or item.text
    doc_props.pubdate = nilIfEmpty(doc_props.pubdate) or "\u{FFFF}"
    item.doc_props = doc_props
    -- Precompute so compareAuthorSeries and formatInfo don't repeat the work
    item.author_sort_key = processAuthorName(doc_props.authors, sort_type)
end

--- BookList.collates mandatory_func callback -- builds the subtitle line.
-- Produces a bullet-separated string of available metadata for display
-- beneath each book title, e.g. "Author . Series #3 . 2020-01-15".
-- Fields set to the sentinel are omitted rather than showing placeholders.
local function formatInfo(item)
    if not item.doc_props then
        return ""
    end

    local parts = {}

    if item.author_sort_key and item.author_sort_key ~= "\u{FFFF}" then
        table.insert(parts, item.author_sort_key)
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

--- Comparison function for author -> series -> series_index.
-- Returns true/false for ordering, or nil when all three levels tie,
-- allowing the caller to continue with fallback comparisons.
-- Series index comparison only applies when both items share the same
-- real series (non-sentinel). Items with an index sort before those without.
local function compareAuthorSeries(a, b)
    local result = strcollCompare(a.author_sort_key, b.author_sort_key)
    if result ~= nil then return result end

    result = strcollCompare(a.doc_props.series, b.doc_props.series)
    if result ~= nil then return result end

    -- Only compare series_index when both items are in a real series
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
            return has_idx_a -- item with index sorts before item without
        end
    end

    return nil
end

--- Factory for BookList.collates entries.
-- Each collate entry requires: text, menu_order, can_collate_mixed,
-- item_func(item, ui), init_sort_func() -> comparator, mandatory_func(item).
-- @string text           Menu label (translatable)
-- @int    menu_order     Position in the sort menu (5-8 for our four modes)
-- @string sort_type      "first_last" or "last_first" -- controls author name rewriting
-- @string fallback_field "title" or "pubdate" -- secondary sort after author/series
local function makeCollate(text, menu_order, sort_type, fallback_field)
    return {
        text = text,
        menu_order = menu_order,
        can_collate_mixed = false, -- item_func only applies to files, not directories

        item_func = function(item, ui)
            prepareItem(item, ui, sort_type)
        end,

        init_sort_func = function()
            return function(a, b)
                local result = compareAuthorSeries(a, b)
                if result ~= nil then
                    return result
                end
                if fallback_field == "pubdate" then
                    result = strcollCompare(a.doc_props.pubdate, b.doc_props.pubdate)
                    if result ~= nil then return result end
                end
                -- Title is always the final tiebreaker
                return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
            end
        end,

        mandatory_func = function(item)
            return formatInfo(item)
        end,
    }
end

-- Register four collate modes (menu_order 5-8, after KOReader's built-in 1-4)
BookList.collates.author_first_last_series_title = makeCollate(
    _("author (first name) - series - title"), 5, "first_last", "title")

BookList.collates.author_last_first_series_title = makeCollate(
    _("author (last name) - series - title"), 6, "last_first", "title")

BookList.collates.author_first_last_series_date = makeCollate(
    _("author (first name) - series - published date"), 7, "first_last", "pubdate")

BookList.collates.author_last_first_series_date = makeCollate(
    _("author (last name) - series - published date"), 8, "last_first", "pubdate")

return BookList.collates
