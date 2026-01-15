-- @description Kanban Board for REAPER
-- @version 1.0.0
-- @author Loukas
-- @about
--   A Kanban-style task board for managing tasks directly inside REAPER.
--   Supports cards, checklists and calendar-based organization.
--                          
-- @requires REAPER v7.45+, ReaImGui v0.10+
-- @changelog
--   + Initial release

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")

dofile(script_path .. "calendar.lua")
dofile(script_path .. "card.lua")
dofile(script_path .. "checklist.lua")
dofile(script_path .. "kanban_stack_utils.lua")
dofile(script_path .. "lib/dkjson.lua")


-- =============================================================================
-- || SCRIPT INITIALIZATION & MODULE LOADING                                  ||
-- =============================================================================

-- 📦 Load stack safety utilities
local retval, script_path = reaper.get_action_context()
script_path = script_path:match("(.*[/\\])")
local stack_utils = dofile(script_path .. "kanban_stack_utils.lua")

-- 🧠 ImGui Context Setup
if ctx then
    reaper.ImGui_DestroyContext(ctx)
end
ctx = reaper.ImGui_CreateContext("Kanban Board")

local json = dofile(script_path .. "dkjson.lua")

-- Lua version compatibility for unpack
local unpack = table.unpack or unpack

local is_windows = reaper.GetOS():find("Win")
local is_macos = reaper.GetOS():find("OSX") or reaper.GetOS():find("macOS")
local is_linux = reaper.GetOS():find("Linux")

-- =============================================================================
-- || CONFIGURATION & CONSTANTS                                               ||
-- =============================================================================

local FONT_NAME = 'Arial' -- Veilige fallback
if is_windows then
    FONT_NAME = 'Segoe UI'
elseif is_macos then
    FONT_NAME = 'Helvetica'
elseif is_linux then
    FONT_NAME = 'DejaVu Sans'
end

local FONT_SIZE = 16
local TITLE_FONT_SIZE = 24
local CHECKLIST_TITLE_FONT_SIZE = 18
local SMALL_FONT_SIZE = 13
local LIST_FONT_SIZE = 18
local main_font = reaper.ImGui_CreateFont(FONT_NAME, FONT_SIZE)
local list_font = reaper.ImGui_CreateFont(FONT_NAME, LIST_FONT_SIZE)

local card = dofile(script_path .. "card.lua")

local function hex_to_rgb(hex)
    hex = hex:gsub("#","")
    return {
        tonumber(hex:sub(1,2), 16) / 255,
        tonumber(hex:sub(3,4), 16) / 255,
        tonumber(hex:sub(5,6), 16) / 255,
        1.0
    }
end

local color_palette = {
    -- Bleu
    hex_to_rgb("#2D3748"), hex_to_rgb("#1A365D"), hex_to_rgb("#4A5568"), 
    hex_to_rgb("#2C5282"), hex_to_rgb("#1E4A7F"),  hex_to_rgb("#153A6E"),
    
    -- Red
    hex_to_rgb("#ff6b6b"), hex_to_rgb("#fa5252"), hex_to_rgb("#e03131"), 
    hex_to_rgb("#c92a2a"), hex_to_rgb("#a61e4d"), hex_to_rgb("#862e9c"),
    
    -- Rich Blue
    hex_to_rgb("#4dabf7"), hex_to_rgb("#339af0"), hex_to_rgb("#228be6"),
    hex_to_rgb("#1c7ed6"), hex_to_rgb("#1971c2"), hex_to_rgb("#1864ab"),
    
    -- Green
    hex_to_rgb("#40c057"), hex_to_rgb("#37b24d"), hex_to_rgb("#2f9e44"),
    hex_to_rgb("#2b8a3e"), hex_to_rgb("#237804"), hex_to_rgb("#1c6b0a"),
    
    -- Purple
    hex_to_rgb("#9c36b5"), hex_to_rgb("#852e9c"), hex_to_rgb("#7048e8"),
    hex_to_rgb("#6741d9"), hex_to_rgb("#5f3dc4"), hex_to_rgb("#5235ab"),
    
    -- Warm
    hex_to_rgb("#ffd43b"), hex_to_rgb("#fcc419"), hex_to_rgb("#fab005"),
    hex_to_rgb("#f59f00"), hex_to_rgb("#e67700"), hex_to_rgb("#d9480f"),
    
    -- Grey
    hex_to_rgb("#f8f9fa"), hex_to_rgb("#e9ecef"), hex_to_rgb("#dee2e6"),
    hex_to_rgb("#ced4da"), hex_to_rgb("#adb5bd"), hex_to_rgb("#868e96"),
    
    -- Dark
    hex_to_rgb("#495057"), hex_to_rgb("#343a40"), hex_to_rgb("#212529"),
    hex_to_rgb("#1a1d21"), hex_to_rgb("#141619"), hex_to_rgb("#0d0f12"),
    
    -- Electric
    hex_to_rgb("#00ffff"), hex_to_rgb("#00ffaa"), hex_to_rgb("#339af0"),
    hex_to_rgb("#ff6b6b"), hex_to_rgb("#ffd43b"), hex_to_rgb("#9c36b5")
}

local priorities = {
    { id = 0, text = "--",           color = nil },
    { id = 1, text = "Not Sure",     color = {0.8, 0.8, 0.8, 1.0} },
    { id = 2, text = "Lowest",       color = {0.7, 0.85, 1.0, 1.0} },
    { id = 3, text = "Low",          color = {0.5, 0.7, 1.0, 1.0} },
    { id = 4, text = "Medium",       color = {0.9, 0.9, 0.4, 1.0} },
    { id = 5, text = "High",         color = {0.9, 0.6, 0.3, 1.0} },
    { id = 6, text = "Highest",      color = {0.9, 0.4, 0.4, 1.0} },
}

local default_list_color = hex_to_rgb("#595D5C")

-- =============================================================================
-- || GLOBAL STATE & FILE MANAGEMENT                                          ||
-- =============================================================================

local function get_project_board_file()
    local proj_path, proj_fn = reaper.GetProjectName(0, "")
    if not proj_fn or proj_fn == "" then return nil end
    local base_name = proj_fn:gsub("%.rpp$", "")
    return proj_path .. "/" .. base_name .. ".kanban.json"
end

local board_file = get_project_board_file()
local checklist_templates_file = script_path .. "kanban_checklist_templates.json"
local card_templates_file = script_path .. "kanban_card_templates.json"
local gradient_templates_file = script_path .. "kanban_gradient_templates.json"
local listing_templates_file = script_path .. "kanban_listing_templates.json"
local board = {}
local checklist_templates = {}
local new_list_focus = false
local list_to_remove = nil
local new_list_timestamp = 0
local show_confirm_dialog = false
local item_to_remove = {type = "", list_idx = 0, card_idx = 0}
local editing_card = nil
local pending_move = nil
local pending_list_move = nil
local archived_card_to_delete_idx = nil
local archived_card_to_restore_idx = nil
local checklist_template_overwrite_confirm_name = nil
local checklist_template_to_delete_confirm_name = nil
local card_templates = {}
local card_template_overwrite_confirm_name = nil
local card_template_to_delete_confirm_name = nil
local gradient_templates = {}
local listing_templates = {}

local ui_state = {
    show_archive_dialog = false,
    show_save_checklist_template_dialog = false,
    show_save_card_template_dialog = false,
    checklist_to_save_as_template = nil,
    new_checklist_template_name = "",
    main_font = main_font,
    list_font = list_font, 
    title_font_size = TITLE_FONT_SIZE,
    checklist_title_font_size = CHECKLIST_TITLE_FONT_SIZE,
    small_font_size = SMALL_FONT_SIZE,
    list_font_size = LIST_FONT_SIZE, 
    show_deadlines_view = false,
    color_palette = color_palette,
    search_query = "",
    show_save_gradient_preset_dialog = false,
    new_gradient_preset_name = "",
    card_to_save_as_template = nil,
    new_card_template_name = "",
    filters = {
        label_id = nil,
        priority_id = nil,
        active = false,
    },
    editing_list_color = nil,
    show_save_list_preset_dialog = false,
    current_list_colors = {},
    new_list_preset_name = "",
    is_exporting = false,
    export_started = false,
    board_options_pos = { x = 0, y = 0 },
}

-- =============================================================================
-- || CORE DATA MANIPULATION FUNCTIONS                                        ||
-- =============================================================================

local function deepcopy(orig)
    return json.decode(json.encode(orig))
end

local function save_board()
    if board_file then
        local f = io.open(board_file, "w")
        if f then f:write(json.encode(board)); f:close() end
    else
        reaper.SetProjExtState(0, "LVC_Kanban", "untitled_board", json.encode(board))
    end
end

-- Safe function to load JSON files
local function safe_load_json(file_path)
    local success, data_or_err = pcall(function()
        local f = io.open(file_path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if content == "" then return {} end
        return json.decode(content)
    end)
    if success then return data_or_err, nil end
    return nil, data_or_err
end

-- =============================================================================
-- || DATA LOADING & MIGRATION                                                ||
-- =============================================================================

local loaded_data, err
loaded_data, err = safe_load_json(checklist_templates_file)
if err then reaper.ShowConsoleMsg("Kanban: WARNING - Could not load checklist templates: " .. tostring(err) .. "\n") end
checklist_templates = loaded_data or {}

loaded_data, err = safe_load_json(card_templates_file)
if err then reaper.ShowConsoleMsg("Kanban: WARNING - Could not load card templates: " .. tostring(err) .. "\n") end
card_templates = loaded_data or {}

-- Gradient templates load
loaded_data, err = safe_load_json(gradient_templates_file)
if err then reaper.ShowConsoleMsg("Kanban: WARNING - Could not load gradient templates: " .. tostring(err) .. "\n") end
if loaded_data then
    gradient_templates = loaded_data
else
    gradient_templates = {
        Professional = {0x2D3748FF, 0x4A5568FF, 0x718096FF, 0x4A5568FF},
        Creative = {0x553C9AFF, 0x6B46C1FF, 0x9F7AEADF, 0x6B46C1FF},
        Sunset = {0xFF6A6AFF, 0xFF9966FF, 0xFFCC66FF, 0xFF6699FF},
        Ocean = {0x3366CCFF, 0x33CCCCFF, 0x66FFCCFF, 0x006699FF}
    }
    local f = io.open(gradient_templates_file, "w")
    if f then f:write(json.encode(gradient_templates)); f:close() end
end

-- Listing templates load
loaded_data, err = safe_load_json(listing_templates_file)
if err then reaper.ShowConsoleMsg("Kanban: WARNING - Could not load list color templates: " .. tostring(err) .. "\n") end
if loaded_data then
    listing_templates = loaded_data
else
    listing_templates = {
        ["Basic Colors"] = {
            ["To Do"] = {0.8, 0.2, 0.2, 1.0},
            ["In Progress"] = {0.9, 0.6, 0.2, 1.0},
            ["Done"] = {0.2, 0.7, 0.2, 1.0}
        },
        ["Pastel Colors"] = {
            ["To Do"] = {0.95, 0.6, 0.6, 1.0},
            ["In Progress"] = {0.7, 0.8, 0.9, 1.0},
            ["Done"] = {0.6, 0.9, 0.7, 1.0}
        },
        ["Dark Theme"] = {
            ["To Do"] = {0.35, 0.2, 0.2, 1.0},
            ["In Progress"] = {0.2, 0.3, 0.2, 1.0},
            ["Done"] = {0.2, 0.2, 0.35, 1.0}
        }
    }
    local f = io.open(listing_templates_file, "w")
    if f then f:write(json.encode(listing_templates)); f:close() end
end

local board_loaded = false
if board_file then
    local loaded_board, load_err = safe_load_json(board_file)
    if loaded_board then
        board = loaded_board
        board_loaded = true
    elseif load_err then
        reaper.ShowConsoleMsg("Kanban: WARNING - Project board file is corrupt. A new board will be created.\n")
        local backup_file = board_file:gsub("%.json$", ".corrupt.bak")
        os.rename(board_file, backup_file)
        reaper.ShowConsoleMsg("Kanban: Your corrupt board file was backed up to: " .. backup_file .. "\n")
        board = {}
    end
end

if not board_loaded then
    local _, temp_board_str = reaper.GetProjExtState(0, "LVC_Kanban", "untitled_board")
    if temp_board_str and temp_board_str ~= "" then
        board = json.decode(temp_board_str) or {}
        board_loaded = true
        if board_file then
            save_board()
            reaper.SetProjExtState(0, "LVC_Kanban", "untitled_board", "")
        end
    end
end

board.lists = board.lists or {}
board.archived_cards = board.archived_cards or {}

if not board.gradient then
    board.gradient = {
        enabled = true,
        stops = gradient_templates["Professional"] or {0x2D3748FF, 0x4A5568FF, 0x718096FF, 0x4A5568FF},
        currentPreset = "Professional"
    }
end

-- Remove old board data (migration)
if board.gradient and board.gradient.presets then
    board.gradient.presets = nil
    save_board()
end

local function migrate_board_data(board_obj)
    local was_modified = false
    board_obj.lists = board_obj.lists or {}
    board_obj.archived_cards = board_obj.archived_cards or {}

    if not board_obj.gradient then
        board_obj.gradient = {
            enabled = true,
            stops = gradient_templates["Professional"] or {0x2D3748FF, 0x4A5568FF, 0x718096FF, 0x4A5568FF},
            currentPreset = "Professional"
        }
        was_modified = true
    end

    if board_obj.gradient and board_obj.gradient.presets then
        board_obj.gradient.presets = nil
        was_modified = true
    end

    for _, list in ipairs(board_obj.lists) do
        list.cards = list.cards or {}
        if list.collapsed == nil then
            list.collapsed = false
            was_modified = true
        end
        for _, card_obj in ipairs(list.cards) do
            if not card_obj.id then
                card_obj.id = reaper.genGuid("")
                was_modified = true
            end
        end
    end

    if not board_obj.label_definitions then
        if #board_obj.lists > 0 then
            reaper.ShowConsoleMsg("Kanban: Board data is being migrated with default labels.\n")
        end
        board_obj.label_definitions = {
            { id = reaper.genGuid(""), text = "", color = {0.8, 0.2, 0.2, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.8, 0.5, 0.2, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.8, 0.8, 0.2, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.2, 0.7, 0.2, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.2, 0.7, 0.7, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.2, 0.2, 0.8, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.5, 0.2, 0.8, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.8, 0.2, 0.8, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.6, 0.6, 0.6, 1.0} },
            { id = reaper.genGuid(""), text = "", color = {0.4, 0.3, 0.2, 1.0} },
        }
        was_modified = true
        
        for _, list_item in ipairs(board_obj.lists) do
            if list_item.cards then
                for _, card_obj in ipairs(list_item.cards) do
                    if card_obj.labels and #card_obj.labels > 0 and type(card_obj.labels[1]) == 'number' then
                        local new_label_ids = {}
                        for _, label_idx in ipairs(card_obj.labels) do
                            if board_obj.label_definitions[label_idx] then table.insert(new_label_ids, board_obj.label_definitions[label_idx].id) end
                        end
                        card_obj.labels = new_label_ids
                    end
                end
            end
        end
    end

    if was_modified then save_board() end
end

migrate_board_data(board)

local function create_default_board()
    board.lists = {
        {
            name = "To Do", 
            cards = {
                card.new("Card example 1", "Apply compression and EQ to vocals"),
                card.new("Card example 2", "Quantize MIDI and audio"),
                card.new("Card example 3", "Rhythm and lead parts")
            }
        },
        {
            name = "In Progress", 
            cards = {
                card.new("Master example", "Final mastering and export")
            }
        },
        {
            name = "Done", 
            cards = {}
        }
    }

    board.label_definitions = {
        { id = reaper.genGuid(""), text = "", color = {0.8, 0.2, 0.2, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.8, 0.5, 0.2, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.8, 0.8, 0.2, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.2, 0.7, 0.2, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.2, 0.7, 0.7, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.2, 0.2, 0.8, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.5, 0.2, 0.8, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.8, 0.2, 0.8, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.6, 0.6, 0.6, 1.0} },
        { id = reaper.genGuid(""), text = "", color = {0.4, 0.3, 0.2, 1.0} },
    }
    save_board()
end

if not board_loaded then create_default_board() end

local function add_new_list()
    table.insert(board.lists, {name = "", cards = {}, color = default_list_color, height = 400})
    new_list_focus = true
    new_list_timestamp = reaper.time_precise()
    save_board()
end

local function add_card(list_idx, template)
    if not board.lists[list_idx] then return end
    local new_card_obj = template and deepcopy(template) or card.new("New Card", "Click to edit description")
    table.insert(board.lists[list_idx].cards, new_card_obj)
    save_board()
end

local function remove_list(list_idx)
    table.remove(board.lists, list_idx)
    save_board()
end

local function archive_card(list_idx, card_idx)
    local card_to_archive = table.remove(board.lists[list_idx].cards, card_idx)
    if card_to_archive then
        card_to_archive.archived_from_list_idx = list_idx
        table.insert(board.archived_cards, card_to_archive)
        save_board()
    end
end

local function restore_archived_card(archive_idx)
    local card_to_restore = table.remove(board.archived_cards, archive_idx)
    if card_to_restore then
        local target_list_idx = card_to_restore.archived_from_list_idx or 1
        if not board.lists[target_list_idx] then target_list_idx = 1 end
        card_to_restore.archived_from_list_idx = nil
        table.insert(board.lists[target_list_idx].cards, card_to_restore)
        save_board()
    end
end

local function delete_archived_card(archive_idx)
    table.remove(board.archived_cards, archive_idx)
    save_board()
end

local function move_list_left(list_idx)
    pending_list_move = { from = list_idx, to = list_idx - 1 }
end

local function move_list_right(list_idx)
    pending_list_move = { from = list_idx, to = list_idx + 1 }
end

local function insert_card_at(list_idx, pos, moved_card)
    table.insert(board.lists[list_idx].cards, pos, moved_card)
    save_board()
end

-- =============================================================================
-- || FILTERING & SEARCH LOGIC (UPDATED FOR CHECKLISTS)                       ||
-- =============================================================================

local function checklist_item_matches_filter(checklist_item, ui_state)
    if ui_state.search_query and ui_state.search_query ~= "" then
        local term = ui_state.search_query:lower()
        if checklist_item.text and checklist_item.text:lower():find(term, 1, true) then
            return true
        end
        if checklist_item.due_date and checklist_item.due_date:find(term, 1, true) then
            return true
        end
        return false
    end
    return true
end

local function card_matches_filter(card_obj, ui_state, force_show)
    -- If card is being edited, always show it
    if force_show then return true end
    
    if ui_state.search_query and ui_state.search_query ~= "" then
        local term = ui_state.search_query:lower()
        local text_match = false
        
        -- Check card properties
        if (card_obj.title and card_obj.title:lower():find(term, 1, true)) or
           (card_obj.description and card_obj.description:lower():find(term, 1, true)) or
           (card_obj.due_date and card_obj.due_date:find(term, 1, true)) then
            text_match = true
        end
        
        -- Check checklist items
        if not text_match and card_obj.checklists then
            for _, cl in ipairs(card_obj.checklists) do
                for _, item in ipairs(cl.items) do
                    if checklist_item_matches_filter(item, ui_state) then
                        text_match = true
                        break
                    end
                end
                if text_match then break end
            end
        end
        
        if not text_match then return false end
    end

    if ui_state.filters.label_id then
        local has_label = false
        for _, label_id in ipairs(card_obj.labels or {}) do
            if label_id == ui_state.filters.label_id then has_label = true; break end
        end
        if not has_label then return false end
    end

    if ui_state.filters.priority_id then
        if ui_state.filters.priority_id == 0 then
            if card_obj.priority ~= 0 then return false end
        elseif card_obj.priority ~= ui_state.filters.priority_id then
            return false
        end
    end

    return true
end

-- =============================================================================
-- || DEADLINE & AGENDA VIEW LOGIC                                            ||
-- =============================================================================

local function parse_date(date_str)
    if not date_str or date_str == "" then return nil end
    local d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")
    if d then return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 }) end
    d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d)$")
    if d then local year = tonumber(y); if year < 100 then year = year + 2000 end; return os.time({ year = year, month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 }) end
    y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if y then return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 }) end
    return nil
end

local function get_date_boundaries()
    local now = os.time()
    local today_t = os.date("*t", now)
    local today_start = os.time({year=today_t.year, month=today_t.month, day=today_t.day, hour=0, min=0, sec=0})
    local today_end = today_start + 86400 - 1
    local tomorrow_end = today_end + 86400

    local wday = today_t.wday
    local day_of_week_monday_first = (wday == 1) and 7 or (wday - 1)
    local this_week_start = today_start - (day_of_week_monday_first - 1) * 86400
    local this_week_end = this_week_start + 7 * 86400 - 1
    local next_week_end = this_week_end + 7 * 86400

    local this_month_end
    if today_t.month == 12 then this_month_end = os.time({year=today_t.year + 1, month=1, day=1, hour=0, min=0, sec=0}) - 1
    else this_month_end = os.time({year=today_t.year, month=today_t.month + 1, day=1, hour=0, min=0, sec=0}) - 1 end

    local next_month_year = today_t.year
    local next_month_month = today_t.month + 1
    if next_month_month > 12 then next_month_month = 1; next_month_year = next_month_year + 1 end
    local next_month_start = os.time({year=next_month_year, month=next_month_month, day=1, hour=0, min=0, sec=0})
    local next_month_end = os.time({year=next_month_year, month=next_month_month + 1, day=1, hour=0, min=0, sec=0}) - 1

    return { now = now, today_start = today_start, today_end = today_end, tomorrow_end = tomorrow_end, this_week_end = this_week_end, next_week_end = next_week_end, this_month_end = this_month_end, next_month_end = next_month_end }
end

local function get_task_category(ts, boundaries)
    if ts < boundaries.today_start then return "Overdue" end
    if ts <= boundaries.today_end then return "Today" end
    if ts <= boundaries.tomorrow_end then return "Tomorrow" end
    if ts <= boundaries.this_week_end then return "This Week" end
    if ts <= boundaries.next_week_end then return "Next Week" end
    if ts <= boundaries.this_month_end then return "This Month" end
    if ts <= boundaries.next_month_end then return "Next Month" end
    return "Later"
end

local function get_all_tasks_with_deadlines()
    local tasks = {}
    for list_idx, list in ipairs(board.lists) do
        for card_idx, card in ipairs(list.cards) do
            if card.due_date and not card.archived then
                local ts = parse_date(card.due_date)
                if ts then
                    table.insert(tasks, {
                        text = card.title, due_date_ts = ts, due_date_str = card.due_date, is_card = true,
                        card_title = card.title, list_idx = list_idx, card_idx = card_idx, card_id = card.id
                    })
                end
            end
            
            if card.checklists then
                for _, cl in ipairs(card.checklists) do
                    for _, item in ipairs(cl.items) do
                        if item.due_date and not item.checked then
                            local ts = parse_date(item.due_date)
                            if ts then
                                table.insert(tasks, {
                                    text = item.text, due_date_ts = ts, due_date_str = item.due_date, is_card = false,
                                    card_title = card.title, list_idx = list_idx, card_idx = card_idx, card_id = card.id
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(tasks, function(a, b) return a.due_date_ts < b.due_date_ts end)
    return tasks
end

local function perform_actual_export(file_path, project_name)
    local export_data = {
        project_name = project_name, 
        export_time = os.date("%Y-%m-%d %H:%M:%S"),
        deadlines = {}, 
        label_definitions = board.label_definitions or {}
    }
    
    for list_idx, list in ipairs(board.lists) do
        for card_idx, card_obj in ipairs(list.cards) do
            if card_obj.due_date and card_obj.due_date ~= "" then
                table.insert(export_data.deadlines, {
                    title = card_obj.title or "Untitled", 
                    due_date = card_obj.due_date, 
                    is_card = true,
                    card_title = card_obj.title or "Untitled", 
                    project = project_name, 
                    card_id = card_obj.id,
                    list_idx = list_idx, 
                    card_idx = card_idx, 
                    labels = card_obj.labels or {}, 
                    priority = card_obj.priority or 0
                })
            end
            
            if card_obj.checklists then
                for _, checklist in ipairs(card_obj.checklists) do
                    for item_idx, item in ipairs(checklist.items) do
                        if item.due_date and item.due_date ~= "" and not item.checked then
                            table.insert(export_data.deadlines, {
                                title = item.text or "Checklist Item", 
                                due_date = item.due_date, 
                                is_card = false,
                                card_title = card_obj.title or "Untitled", 
                                project = project_name, 
                                card_id = card_obj.id,
                                list_idx = list_idx, 
                                card_idx = card_idx, 
                                labels = card_obj.labels or {}, 
                                priority = card_obj.priority or 0
                            })
                        end
                    end
                end
            end
        end
    end
    
    local file = io.open(file_path, "w")
    if file then
        file:write(json.encode(export_data, { indent = true }))
        file:close()
        reaper.ShowMessageBox("Deadlines exported to:\n" .. file_path, "Export Successful", 0)
    else
        reaper.ShowConsoleMsg("Kanban: ERROR - Could not write to file: " .. file_path .. "\n")
        reaper.ShowMessageBox("Could not write to file. Check file permissions.", "Export Error", 0)
    end
end

local function export_deadlines_for_global_overview()
    local project_name = reaper.GetProjectName(0, ""):gsub("%.rpp$", "")
    if project_name == "" then project_name = "Untitled" end
    
    -- Try to get last used folder
    local initial_folder = reaper.GetExtState("Kanban", "LastExportDir")
    
    if not initial_folder or initial_folder == "" then
        if is_windows then
            initial_folder = os.getenv("USERPROFILE") .. "\\Desktop"
        else
            local home = os.getenv("HOME")
            if home then
                initial_folder = home .. "/Desktop"
            else
                initial_folder = "."
            end
        end
    end
    
    if reaper.JS_Dialog_BrowseForSaveFile then
        local retval, file = reaper.JS_Dialog_BrowseForSaveFile("Export Deadlines", initial_folder, project_name .. "_deadlines.json", "JSON files (.json)\0*.json\0All files (*.*)\0*.*\0")
        if retval and file and file ~= "" then
            if not file:lower():match("%.json$") then file = file .. ".json" end
            
            -- Save the directory for next time
            local dir = file:match("(.*[/\\])")
            if dir then
                reaper.SetExtState("Kanban", "LastExportDir", dir, true)
            end
            
            perform_actual_export(file, project_name)
        end
    else
        reaper.ShowMessageBox("Please install the JS_ReaScriptAPI extension via ReaPack to use the native file browser.", "Missing Extension", 0)
    end
end

-- =============================================================================
-- || UI HELPER FUNCTIONS                                                     ||
-- =============================================================================

local function draw_dropzone(id, width, height, list_idx, insert_pos)
    reaper.ImGui_InvisibleButton(ctx, id, width, height, reaper.ImGui_ButtonFlags_MouseButtonLeft())
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    local dragging = false

    if reaper.ImGui_BeginDragDropTarget(ctx) then
        dragging = true
        local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, 'CARD')
        if rv then
            local src_list, src_card = payload:match("(%d+),(%d+)")
            src_list, src_card = tonumber(src_list), tonumber(src_card)
            if src_list and src_card then pending_move = { src_list=src_list, src_card=src_card, dst_list=list_idx, dst_pos=insert_pos } end
        end
        reaper.ImGui_EndDragDropTarget(ctx)
    end

    if hovered or dragging then
        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local color = reaper.ImGui_ColorConvertDouble4ToU32(1.0, 1.0, 0.0, 0.30)
        reaper.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, color, 3)
    end
end

local function draw_vertical_text(text)
    local char_spacing = reaper.ImGui_GetFontSize(ctx) * 0.85
    for i = 1, #text do
        local char = text:sub(i, i)
        local char_width = reaper.ImGui_CalcTextSize(ctx, char)
        reaper.ImGui_SetCursorPosX(ctx, (reaper.ImGui_GetWindowWidth(ctx) - char_width) / 2)
        reaper.ImGui_Text(ctx, char)
        if i < #text then
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - (reaper.ImGui_GetTextLineHeight(ctx) - char_spacing))
        end
    end
end

local function draw_spinner(label, radius, thickness, color)
    local p = {reaper.ImGui_GetCursorScreenPos(ctx)}
    local x, y = p[1], p[2]
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local num_segments = 30
    local a = reaper.time_precise() * 6
    local start_angle = a
    local end_angle = a + math.pi * 1.5
    for i = 0, num_segments do
        local angle = start_angle + (i / num_segments) * (end_angle - start_angle)
        reaper.ImGui_DrawList_PathLineTo(draw_list, x + math.cos(angle) * radius, y + math.sin(angle) * radius)
    end
    reaper.ImGui_DrawList_PathStroke(draw_list, color, 0, thickness)
end

local function draw_collapsed_list(list, list_idx)
    local card_count = #(list.cards or {})
    local original_name = (list.name ~= "" and list.name or "Unnamed list"):upper()
    local max_chars = 15
    local display_name = original_name
    if #original_name > max_chars then display_name = original_name:sub(1, max_chars - 3) .. "..." end
    
    local width = 50
    local height = 0
    local color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(list.color[1], list.color[2], list.color[3], list.color[4])
    
    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), color_u32)
    stack_utils.PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 8.0)
    
    local child_visible = reaper.ImGui_BeginChild(ctx, "collapsed_list_container" .. list_idx, width, height)
    if child_visible then
        local r, g, b = unpack(list.color)
        local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        local text_color_u32 = (luminance > 0.6) and reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.0)
        
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color_u32)
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x10606060)
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x40606060)
        
        if reaper.ImGui_Button(ctx, "«»", -1, 25) then
            list.collapsed = not list.collapsed
            save_board()
        end
        stack_utils.PopStyleColor(ctx, 3)

        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Expand list") end

        reaper.ImGui_Dummy(ctx, 0, 10)
        draw_vertical_text(display_name)
        reaper.ImGui_Dummy(ctx, 0, 10)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 5)

        local card_count_str = tostring(card_count)
        local text_width = reaper.ImGui_CalcTextSize(ctx, card_count_str)
        reaper.ImGui_SetCursorPosX(ctx, (width - text_width) * 0.5)
        reaper.ImGui_Text(ctx, card_count_str)

        stack_utils.PopStyleColor(ctx)

        if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then
            reaper.ImGui_OpenPopup(ctx, "CollapsedListContext"..list_idx)
        end

        if reaper.ImGui_BeginPopup(ctx, "CollapsedListContext"..list_idx) then
            if list_idx > 1 then if reaper.ImGui_MenuItem(ctx, "← Move Left") then move_list_left(list_idx); reaper.ImGui_CloseCurrentPopup(ctx) end end
            if list_idx < #board.lists then if reaper.ImGui_MenuItem(ctx, "→ Move Right") then move_list_right(list_idx); reaper.ImGui_CloseCurrentPopup(ctx) end end
            if list_idx > 1 or list_idx < #board.lists then reaper.ImGui_Separator(ctx) end
            if reaper.ImGui_MenuItem(ctx, "Delete List") then item_to_remove = {type = "list", list_idx = list_idx, card_idx = 0}; show_confirm_dialog = true; reaper.ImGui_CloseCurrentPopup(ctx) end
            reaper.ImGui_EndPopup(ctx)
        end
        reaper.ImGui_EndChild(ctx)
    end
    stack_utils.PopStyleVar(ctx)
    stack_utils.PopStyleColor(ctx)
    return child_visible
end

-- =============================================================================
-- || MAIN APPLICATION LOOP                                                   ||
-- =============================================================================

local function loop()
    stack_utils.Cleanup(ctx)
    stack_utils.PrintStackStatus("Loop Start")
   
    if ui_state and ui_state.main_font then
        reaper.ImGui_PushFont(ctx, ui_state.main_font, FONT_SIZE)
    end

    -- Basic styling
    if board.gradient and board.gradient.enabled then
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x00000000)
    else
        local bg_color = hex_to_rgb("#202020")
        local bg_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(bg_color[1], bg_color[2], bg_color[3], bg_color[4])
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), bg_color_u32)
    end

    -- Titlebar Color
    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(),          0x4A5568FF)
    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(),    0x4A5568FF)
    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), 0x4A5568FF)

    stack_utils.PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)

    local window_open = true
    local main_visible, window_open = reaper.ImGui_Begin(ctx, " Kanban Board", window_open, reaper.ImGui_WindowFlags_NoCollapse())
    
    -- TOOLTIP X button
    if reaper.ImGui_IsWindowHovered(ctx) then
        local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
        local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
        local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
        local close_button_size = 20
        local close_button_x = window_x + window_width - close_button_size - 8
        local close_button_y = window_y + 8
        if mouse_x >= close_button_x and mouse_x <= close_button_x + close_button_size and
           mouse_y >= close_button_y and mouse_y <= close_button_y + close_button_size then
            reaper.ImGui_SetTooltip(ctx, "Close")
        end
    end

    if not window_open then
        reaper.ImGui_End(ctx)
        stack_utils.PopStyleVar(ctx)
        stack_utils.PopStyleColor(ctx, 4)
        if ui_state and ui_state.main_font then reaper.ImGui_PopFont(ctx) end
        return
    end

    if main_visible then
        -- Draw background gradient if enabled
        if board.gradient and board.gradient.enabled then
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local x, y = reaper.ImGui_GetWindowPos(ctx)
            local w, h = reaper.ImGui_GetWindowSize(ctx)
            reaper.ImGui_DrawList_AddRectFilledMultiColor(dl, x, y, x + w, y + h,
                board.gradient.stops[1], board.gradient.stops[2],
                board.gradient.stops[3], board.gradient.stops[4])
        end

        if reaper.ImGui_Button(ctx, "+ Add List") then add_new_list() end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Board Options") then reaper.ImGui_OpenPopup(ctx, "BoardOptionsMenu") end
        ui_state.board_options_pos.x, ui_state.board_options_pos.y = reaper.ImGui_GetItemRectMin(ctx)

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "🎨 Background") then reaper.ImGui_OpenPopup(ctx, "BackgroundOptions") end
        local background_button_pos_x, background_button_pos_y = reaper.ImGui_GetItemRectMin(ctx)
        local _, background_button_height = reaper.ImGui_GetItemRectSize(ctx)

        -- Background Options Popup
        reaper.ImGui_SetNextWindowPos(ctx, background_button_pos_x, background_button_pos_y + background_button_height)
        if reaper.ImGui_BeginPopup(ctx, "BackgroundOptions") then
            local enabled_changed; enabled_changed, board.gradient.enabled = reaper.ImGui_Checkbox(ctx, "Enable Gradient", board.gradient.enabled)
            if enabled_changed then save_board() end

            if board.gradient.enabled then
                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_BeginMenu(ctx, "🎨 Presets") then
                    for name, colors in pairs(gradient_templates) do  
                        if reaper.ImGui_MenuItem(ctx, name, nil, name == board.gradient.currentPreset) then
                            board.gradient.stops = {table.unpack(colors)}
                            board.gradient.currentPreset = name
                            save_board()
                        end
                    end
                    reaper.ImGui_EndMenu(ctx)
                end

                if reaper.ImGui_BeginMenu(ctx, "Edit Colors...") then
                    local any_stop_changed = false
                    local temp_stops = {table.unpack(board.gradient.stops)}
                    local changed
                    changed, temp_stops[1] = reaper.ImGui_ColorEdit4(ctx, "Top-Left", temp_stops[1]); if changed then any_stop_changed = true end
                    changed, temp_stops[2] = reaper.ImGui_ColorEdit4(ctx, "Top-Right", temp_stops[2]); if changed then any_stop_changed = true end
                    changed, temp_stops[3] = reaper.ImGui_ColorEdit4(ctx, "Bottom-Right", temp_stops[3]); if changed then any_stop_changed = true end
                    changed, temp_stops[4] = reaper.ImGui_ColorEdit4(ctx, "Bottom-Left", temp_stops[4]); if changed then any_stop_changed = true end
                    if any_stop_changed then
                        board.gradient.stops = temp_stops
                        board.gradient.currentPreset = "Custom"
                        save_board()
                    end
                    reaper.ImGui_EndMenu(ctx)
                end

                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_MenuItem(ctx, "Save as New Preset...") then
                    ui_state.show_save_gradient_preset_dialog = true
                    ui_state.new_gradient_preset_name = "My Custom Preset"
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
            end
            reaper.ImGui_EndPopup(ctx)
        end

        -- Board Options Menu with Deadlines
        reaper.ImGui_SetNextWindowPos(ctx, ui_state.board_options_pos.x, ui_state.board_options_pos.y + 30)
        if reaper.ImGui_BeginPopup(ctx, "BoardOptionsMenu") then
            if reaper.ImGui_MenuItem(ctx, "View Archive...") then ui_state.show_archive_dialog = true end
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "View Deadlines...") then ui_state.show_deadlines_view = true end
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "Export Deadlines") then
                export_deadlines_for_global_overview()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Separator(ctx)

        -- Search and Filtering section
        local input_bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.22, 1.0)
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), input_bg_color)
        stack_utils.PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)

        -- Search box
        local filter_button_width = 80
        reaper.ImGui_PushItemWidth(ctx, -filter_button_width)
        local search_changed, new_query = reaper.ImGui_InputText(ctx, "##Search", ui_state.search_query)
        if search_changed then ui_state.search_query = new_query end
        if reaper.ImGui_IsItemHovered(ctx) and not reaper.ImGui_IsItemActive(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Search by title, description, checklist items, or deadline (e.g., '25-12')")
        end
        reaper.ImGui_PopItemWidth(ctx)

        -- Filters button with active indicator
        local filter_active = ui_state.filters.label_id or ui_state.filters.priority_id
        reaper.ImGui_SameLine(ctx)
        if filter_active then 
            stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.6, 0.2, 1.0))
        end
        if reaper.ImGui_Button(ctx, "Filters") then reaper.ImGui_OpenPopup(ctx, "FilterPopup") end
        if filter_active then stack_utils.PopStyleColor(ctx) end

        local filter_button_pos_x, filter_button_pos_y = reaper.ImGui_GetItemRectMin(ctx)
        local _, filter_button_height = reaper.ImGui_GetItemRectSize(ctx)
        reaper.ImGui_SetNextWindowPos(ctx, filter_button_pos_x - 50, filter_button_pos_y + filter_button_height)

        -- Filter Popup
        if reaper.ImGui_BeginPopup(ctx, "FilterPopup") then
            reaper.ImGui_Text(ctx, "Filter by Label")
            reaper.ImGui_Separator(ctx)
            for _, label_def in ipairs(board.label_definitions or {}) do
                if label_def.text and label_def.text ~= "" then
                    if reaper.ImGui_Selectable(ctx, label_def.text, ui_state.filters.label_id == label_def.id) then
                        ui_state.filters.label_id = (ui_state.filters.label_id == label_def.id) and nil or label_def.id
                    end
                end
            end

            reaper.ImGui_Dummy(ctx, 0, 10)
            reaper.ImGui_Text(ctx, "Filter by Priority")
            reaper.ImGui_Separator(ctx)
            for _, priority_def in ipairs(priorities) do
                if reaper.ImGui_Selectable(ctx, priority_def.text, ui_state.filters.priority_id == priority_def.id) then
                    ui_state.filters.priority_id = (ui_state.filters.priority_id == priority_def.id) and nil or priority_def.id
                end
            end

            reaper.ImGui_Dummy(ctx, 0, 10)
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_Button(ctx, "Clear All Filters", -1, 0) then
                ui_state.search_query = ""
                ui_state.filters.label_id = nil
                ui_state.filters.priority_id = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        -- Pop search styling
        stack_utils.PopStyleVar(ctx)
        stack_utils.PopStyleColor(ctx)
        reaper.ImGui_Separator(ctx)

        -- Active filters display
        local any_filter_active = ui_state.search_query ~= "" or ui_state.filters.label_id or ui_state.filters.priority_id
        if any_filter_active then
            reaper.ImGui_TextDisabled(ctx, "Active filters: ")
            reaper.ImGui_SameLine(ctx)
            
            if ui_state.search_query ~= "" then
                reaper.ImGui_Text(ctx, "Search: '" .. ui_state.search_query .. "'")
                reaper.ImGui_SameLine(ctx)
            end
            
            if ui_state.filters.label_id then
                local label_def
                for _, def in ipairs(board.label_definitions or {}) do
                    if def.id == ui_state.filters.label_id then label_def = def; break end
                end
                if label_def then
                    local color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(label_def.color))
                    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_u32)
                    reaper.ImGui_Button(ctx, label_def.text)
                    stack_utils.PopStyleColor(ctx)
                    reaper.ImGui_SameLine(ctx)
                end
            end
            
            if ui_state.filters.priority_id then
                local priority_def = priorities[ui_state.filters.priority_id + 1]
                if priority_def then
                    reaper.ImGui_Text(ctx, "Priority: " .. priority_def.text)
                    reaper.ImGui_SameLine(ctx)
                end
            end
            
            if reaper.ImGui_Button(ctx, "Clear All") then
                ui_state.search_query = ""
                ui_state.filters.label_id = nil
                ui_state.filters.priority_id = nil
            end
            reaper.ImGui_Separator(ctx)
        end

        -- Child window for horizontal scrolling of lists
        local list_area_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), 0x00000000)
        if reaper.ImGui_BeginChild(ctx, "lists_scrolling_region", 0, 0, 0, list_area_flags) then
            local list_spacing = 15
            for i = 1, #board.lists do
                local list = board.lists[i]
                list.color = list.color or default_list_color
                if i > 1 then reaper.ImGui_SameLine(ctx, 0, list_spacing) end
                
                if list.collapsed then
                    draw_collapsed_list(list, i)
                else
                    -- Height calculation
                    local total_cards_height = 0
                    list.cards = list.cards or {}
                    local function calculate_card_height(card_obj)
                        local height = 90
                        if card_obj.labels and type(card_obj.labels) == "table" then
                            local label_count = #card_obj.labels
                            if label_count > 0 and label_count < 100 then height = height + 20 end
                        end
                        if card_obj.checklists and type(card_obj.checklists) == "table" then
                            for _, checklist in ipairs(card_obj.checklists) do
                                if checklist.expanded and checklist.items and type(checklist.items) == "table" then
                                    local item_count = #checklist.items
                                    if item_count > 0 and item_count < 50 then height = height + (20 * item_count) + 10 end
                                end
                            end
                        end
                        return math.max(50, math.min(1000, height))
                    end

                    for j = 1, #list.cards do
                        local card_obj = list.cards[j]
                        local is_editing = editing_card and editing_card.list == i and editing_card.card == j
                        if card_matches_filter(card_obj, ui_state, is_editing) then
                            local card_height = calculate_card_height(card_obj)
                            total_cards_height = total_cards_height + card_height
                            if total_cards_height > 100000 then total_cards_height = 100000; break end
                        end
                    end
                    local base_height = 120
                    local dynamic_height = total_cards_height + base_height
                    local function safe_height_calculation(height)
                        if type(height) ~= "number" or height ~= height then return 400 end
                        if math.abs(height) == math.huge then return 400 end
                        return math.max(200, math.min(1200, height))
                    end
                    list.height = safe_height_calculation(dynamic_height)

                    -- List container
                    local color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(list.color[1], list.color[2], list.color[3], list.color[4])
                    stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), color_u32)
                    stack_utils.PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 8.0)
            
                    if reaper.ImGui_BeginChild(ctx, "list_container" .. i, 300, list.height) then
                        reaper.ImGui_Dummy(ctx, 0, 4)
                        reaper.ImGui_BeginGroup(ctx)
                            reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 8)
                            reaper.ImGui_PushItemWidth(ctx, 200)
                            local r, g, b = unpack(list.color)
                            local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                            local text_color_u32 = (luminance > 0.6) and reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.0)
                            
                            stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x00000000)
                            stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color_u32)
                            local display_name = (list.name ~= "" and list.name or "Unnamed List"):upper()
                            local changed, new_name = reaper.ImGui_InputText(ctx, "##listname"..i, display_name)
                            if changed and new_name ~= "" then list.name = new_name; save_board() end
                            stack_utils.PopStyleColor(ctx, 2)
                            reaper.ImGui_PopItemWidth(ctx)
                        reaper.ImGui_EndGroup(ctx)
            
                        reaper.ImGui_SameLine(ctx)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x10606060)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x40606060)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color_u32)
            
                        if reaper.ImGui_Button(ctx, "⋯##menu"..i, 25, 0) then reaper.ImGui_OpenPopup(ctx, "ListContext"..i) end
                        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "List options") end

                        reaper.ImGui_SameLine(ctx, 0, 5)
                        if reaper.ImGui_Button(ctx, "»«##collapse"..i, 25, 0) then list.collapsed = true; save_board() end
                        stack_utils.PopStyleColor(ctx, 4)
                        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Collapse list") end

                        reaper.ImGui_Separator(ctx)

                        -- List popup menu
                        if reaper.ImGui_BeginPopup(ctx, "ListContext"..i) then
                            if i > 1 then if reaper.ImGui_MenuItem(ctx, "← Move Left") then move_list_left(i); reaper.ImGui_CloseCurrentPopup(ctx) end end
                            if i < #board.lists then if reaper.ImGui_MenuItem(ctx, "→ Move Right") then move_list_right(i); reaper.ImGui_CloseCurrentPopup(ctx) end end
                            if i > 1 or i < #board.lists then reaper.ImGui_Separator(ctx) end
                            if reaper.ImGui_MenuItem(ctx, "Delete List") then item_to_remove = {type = "list", list_idx = i}; show_confirm_dialog = true; reaper.ImGui_CloseCurrentPopup(ctx) end
                            reaper.ImGui_Separator(ctx)
                            if reaper.ImGui_BeginMenu(ctx, "🎨 List Color") then
                                if reaper.ImGui_BeginMenu(ctx, "Presets") then
                                    for preset_name, colors in pairs(listing_templates) do
                                        if reaper.ImGui_MenuItem(ctx, preset_name) then
                                            for list_name, color in pairs(colors) do
                                                if list.name:lower():find(list_name:lower(), 1, true) then list.color = color; break end
                                            end
                                            save_board()
                                        end
                                    end
                                    reaper.ImGui_EndMenu(ctx)
                                end
                                reaper.ImGui_Separator(ctx)
                                reaper.ImGui_Text(ctx, "Custom Color:")
                                local color_u32_picker = reaper.ImGui_ColorConvertDouble4ToU32(unpack(list.color))
                                local color_changed, new_color_u32 = reaper.ImGui_ColorEdit4(ctx, "##listcolorpicker", color_u32_picker)
                                if color_changed then list.color = {reaper.ImGui_ColorConvertU32ToDouble4(new_color_u32)}; save_board() end
                                reaper.ImGui_Separator(ctx)
                                if reaper.ImGui_MenuItem(ctx, "Save Colors as Preset...") then
                                    ui_state.show_save_list_preset_dialog = true
                                    ui_state.current_list_colors = {}
                                    for _, list_obj in ipairs(board.lists) do ui_state.current_list_colors[list_obj.name] = list_obj.color end
                                    ui_state.new_list_preset_name = "My List Colors"
                                    reaper.ImGui_CloseCurrentPopup(ctx)
                                end
                                reaper.ImGui_EndMenu(ctx)
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
            
                        -- Cards
                        list.cards = list.cards or {}
                        local j = 1
                        while j <= #list.cards do
                            local card_obj = list.cards[j]
                            local deleted = false
                            local is_editing = editing_card and editing_card.list == i and editing_card.card == j
                            if card_matches_filter(card_obj, ui_state, is_editing) then
                                draw_dropzone("dropzone"..i.."-"..j, -1, 6, i, j)
                                reaper.ImGui_PushID(ctx, "card"..i.."-"..j)
                                editing_card, command = card.draw(ctx, board, i, j, editing_card, save_board, checklist_templates, ui_state)
                                if command then
                                    if command.action == 'save_checklist_as_template' then
                                        ui_state.show_save_checklist_template_dialog = true
                                        ui_state.checklist_to_save_as_template = command.data
                                        ui_state.new_checklist_template_name = command.data.name or "New Checklist Template"
                                    elseif command.action == 'save_card_as_template' then
                                        ui_state.show_save_card_template_dialog = true
                                        ui_state.card_to_save_as_template = command.data
                                        ui_state.new_card_template_name = command.data.title or "New Card Template"
                                    elseif command.action == 'create_card_from_text' then
                                        local new_card = card.new(command.text, "")
                                        table.insert(board.lists[command.list_idx].cards, new_card)
                                        save_board()
                                    end
                                end
                                if editing_card and editing_card.archive then archive_card(i, j); editing_card = nil; deleted = true end
                                reaper.ImGui_PopID(ctx)
                                reaper.ImGui_Dummy(ctx, 0, 4)
                            end
                            if not deleted then j = j + 1 end
                        end
                        draw_dropzone("dropzone"..i.."-end", -1, 10, i, #list.cards+1)
            
                        -- Add card button
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x10606060)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x40606060)
                        stack_utils.PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color_u32)
                        if reaper.ImGui_Button(ctx, "+ Add card##"..i, 120, 0) then reaper.ImGui_OpenPopup(ctx, "add_card_popup_"..i) end
                        stack_utils.PopStyleColor(ctx, 4)
            
                        if reaper.ImGui_BeginPopup(ctx, "add_card_popup_"..i) then
                            if reaper.ImGui_MenuItem(ctx, "New Blank Card") then add_card(i, nil) end
                            reaper.ImGui_Separator(ctx)
                            if next(card_templates) then
                                reaper.ImGui_TextDisabled(ctx, "Card Templates:")
                                for name, template in pairs(card_templates) do
                                    if reaper.ImGui_MenuItem(ctx, name) then add_card(i, template) end
                                end
                            else
                                reaper.ImGui_TextDisabled(ctx, "(No card templates saved)")
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                        reaper.ImGui_EndChild(ctx)
                    end
                    stack_utils.PopStyleVar(ctx)
                    stack_utils.PopStyleColor(ctx)
                end
            end
            reaper.ImGui_EndChild(ctx)
            stack_utils.PopStyleColor(ctx)
        end
    end
    reaper.ImGui_End(ctx)

    -- Pop basic styling
    stack_utils.PopStyleVar(ctx)
    stack_utils.PopStyleColor(ctx, 4)

    -- === MODALS & POPUPS ===

    -- Deadlines
    if ui_state.show_deadlines_view then reaper.ImGui_OpenPopup(ctx, "Deadlines") end
    local is_still_open_deadlines = reaper.ImGui_BeginPopupModal(ctx, "Deadlines", true, reaper.ImGui_WindowFlags_None())
    if is_still_open_deadlines then
        reaper.ImGui_SetNextWindowSize(ctx, 500, 600, reaper.ImGui_Cond_FirstUseEver())
        reaper.ImGui_Text(ctx, "Upcoming Deadlines")
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginChild(ctx, "deadlines_list", 0, 0) then
            local tasks = get_all_tasks_with_deadlines()
            local boundaries = get_date_boundaries()
            local last_category = nil
            if #tasks == 0 then reaper.ImGui_TextDisabled(ctx, "No items with a deadline found.") end
            for i, task in ipairs(tasks) do
                local category = get_task_category(task.due_date_ts, boundaries)
                if category ~= last_category then
                    reaper.ImGui_Separator(ctx)
                    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1,1,0.6,1), category)
                    reaper.ImGui_Separator(ctx)
                    last_category = category
                end
                if task.is_card then
                    reaper.ImGui_Bullet(ctx); reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, task.text)
                else
                    reaper.ImGui_Dummy(ctx, 20, 0); reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, task.text)
                end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextDisabled(ctx, "(" .. task.due_date_str .. ")")
                reaper.ImGui_TextDisabled(ctx, "  in card: ")
                reaper.ImGui_SameLine(ctx)
                local link_color = reaper.ImGui_ColorConvertDouble4ToU32(0.6, 0.8, 1.0, 1.0)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), link_color)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 0)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0)
                if reaper.ImGui_Button(ctx, task.card_title .. "##jump" .. i) then
                    editing_card = { list = task.list_idx, card = task.card_idx }
                    ui_state.show_deadlines_view = false
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                reaper.ImGui_PopStyleColor(ctx, 2)
                reaper.ImGui_PopStyleVar(ctx)
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
    if not is_still_open_deadlines then ui_state.show_deadlines_view = false end

    -- Archive
    if ui_state.show_archive_dialog then reaper.ImGui_OpenPopup(ctx, "Archived Cards") end
    local is_still_open_archive = reaper.ImGui_BeginPopupModal(ctx, "Archived Cards", true, reaper.ImGui_WindowFlags_None())
    if is_still_open_archive then
        reaper.ImGui_SetNextWindowSize(ctx, 400, 500, reaper.ImGui_Cond_FirstUseEver())
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginChild(ctx, "ArchiveList", 0, -40) then
            for i = #board.archived_cards, 1, -1 do
                local card = board.archived_cards[i]
                if card.confirm_delete then
                    reaper.ImGui_TextColored(ctx, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.7, 0.7, 1.0), "Delete '" .. (card.title or "") .. "'?")
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "Yes##del" .. i) then archived_card_to_delete_idx = i end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "No##del" .. i) then card.confirm_delete = false end
                else
                    reaper.ImGui_TextWrapped(ctx, card.title or "Untitled Card")
                    if reaper.ImGui_Button(ctx, "Restore##" .. i) then archived_card_to_restore_idx = i end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "Delete##" .. i) then card.confirm_delete = true end
                end
                reaper.ImGui_Separator(ctx)
            end
        end
        reaper.ImGui_EndChild(ctx)
        reaper.ImGui_EndPopup(ctx)
    end
    if not is_still_open_archive then ui_state.show_archive_dialog = false end

    -- Confirm Deletion
    if show_confirm_dialog then reaper.ImGui_OpenPopup(ctx, "Confirm Deletion") end
    if reaper.ImGui_BeginPopupModal(ctx, "Confirm Deletion", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        if item_to_remove.type == "list" then
            local list_name = board.lists[item_to_remove.list_idx].name or "this list"
            reaper.ImGui_Text(ctx, "Delete '" .. list_name .. "'?")
            reaper.ImGui_Text(ctx, "All cards in this list will be lost!")
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Button(ctx, "Yes, Delete") then
            if item_to_remove.type == "list" then remove_list(item_to_remove.list_idx) end
            show_confirm_dialog = false
            item_to_remove = {type = "", list_idx = 0, card_idx = 0}
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel") then
            show_confirm_dialog = false
            item_to_remove = {type = "", list_idx = 0, card_idx = 0}
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    -- Save Gradient Preset
    if ui_state.show_save_gradient_preset_dialog then reaper.ImGui_OpenPopup(ctx, "Save Gradient Preset") end
    if reaper.ImGui_BeginPopupModal(ctx, "Save Gradient Preset", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_Text(ctx, "Name:")
        local changed, new_name = reaper.ImGui_InputText(ctx, "##PresetName", ui_state.new_gradient_preset_name)
        if changed then ui_state.new_gradient_preset_name = new_name end
        if reaper.ImGui_Button(ctx, "Save") then
            if ui_state.new_gradient_preset_name ~= "" then
                gradient_templates[ui_state.new_gradient_preset_name] = {table.unpack(board.gradient.stops)}
                board.gradient.currentPreset = ui_state.new_gradient_preset_name
                local f = io.open(gradient_templates_file, "w"); if f then f:write(json.encode(gradient_templates)); f:close() end
                save_board()
                ui_state.show_save_gradient_preset_dialog = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    else
        if ui_state.show_save_gradient_preset_dialog then ui_state.show_save_gradient_preset_dialog = false end
    end

    -- Save List Preset
    if ui_state.show_save_list_preset_dialog then reaper.ImGui_OpenPopup(ctx, "Save List Color Preset") end
    if reaper.ImGui_BeginPopupModal(ctx, "Save List Color Preset", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_Text(ctx, "Name:")
        local changed, new_name = reaper.ImGui_InputText(ctx, "##ListPresetName", ui_state.new_list_preset_name)
        if changed then ui_state.new_list_preset_name = new_name end
        if reaper.ImGui_Button(ctx, "Save") then
            if ui_state.new_list_preset_name ~= "" then
                listing_templates[ui_state.new_list_preset_name] = deepcopy(ui_state.current_list_colors)
                local f = io.open(listing_templates_file, "w"); if f then f:write(json.encode(listing_templates)); f:close() end
                ui_state.show_save_list_preset_dialog = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if ui_state and ui_state.main_font then reaper.ImGui_PopFont(ctx) end

    -- Post-frame logic
    if archived_card_to_delete_idx then delete_archived_card(archived_card_to_delete_idx); archived_card_to_delete_idx = nil end
    if archived_card_to_restore_idx then restore_archived_card(archived_card_to_restore_idx); archived_card_to_restore_idx = nil end

    if pending_move then
        if pending_move.src_list == pending_move.dst_list and pending_move.src_card < pending_move.dst_pos then
            pending_move.dst_pos = pending_move.dst_pos - 1
        end
        local moved_card = table.remove(board.lists[pending_move.src_list].cards, pending_move.src_card)
        if moved_card then insert_card_at(pending_move.dst_list, pending_move.dst_pos, moved_card) end
        pending_move = nil
    end

    if pending_list_move then
        local from, to = pending_list_move.from, pending_list_move.to
        if from and to and from >= 1 and from <= #board.lists and to >= 1 and to <= #board.lists then
            local list_to_move = table.remove(board.lists, from)
            table.insert(board.lists, to, list_to_move)
            if editing_card then
                if editing_card.list == from then editing_card.list = to
                elseif editing_card.list >= to and editing_card.list < from then editing_card.list = editing_card.list + 1
                elseif editing_card.list <= to and editing_card.list > from then editing_card.list = editing_card.list - 1 end
            end
            save_board()
        end
        pending_list_move = nil
    end

    stack_utils.PrintStackStatus("Loop End")
    if window_open then reaper.defer(loop) end
end

-- Start loop
reaper.defer(loop)
