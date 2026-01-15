-- card.lua: card module for Kanban v 1.03

local retval, script_path = reaper.get_action_context()
local base_path = script_path:match("(.*[/\\])")
local checklist = dofile(base_path .. "checklist.lua")
local json = dofile(base_path .. "dkjson.lua")
local calendar = dofile(base_path .. "calendar.lua")

local M = {}

-- Lua version compatibility for unpack
local unpack = table.unpack or unpack

local priorities = {
    { id = 0, text = "--",           color = nil },
    { id = 1, text = "Not Sure",     color = {0.8, 0.8, 0.8, 1.0} }, -- Lightgrey
    { id = 2, text = "Lowest",       color = {0.7, 0.85, 1.0, 1.0} }, -- Lighyblue
    { id = 3, text = "Low",          color = {0.5, 0.7, 1.0, 1.0} }, -- Darker blue
    { id = 4, text = "Medium",       color = {0.9, 0.9, 0.4, 1.0} }, -- Yellow
    { id = 5, text = "High",         color = {0.9, 0.6, 0.3, 1.0} }, -- Orange
    { id = 6, text = "Highest",      color = {0.9, 0.4, 0.4, 1.0} }, -- Red
}

local function deepcopy(orig)
    return json.decode(json.encode(orig))
end

function M.new(title, description)
    return {
        id = reaper.genGuid(""),
        title = title or "New Card",
        description = description or "",
        labels = {},
        checklists = {},
        priority = 0,
        due_date = nil,
        comments = {},
    }
end

---------------------------------------------------------------------
-- Private functions for drafting the detailed modal
---------------------------------------------------------------------

local function parse_date(date_str)
    if not date_str or date_str == "" then return nil end

    -- Try DD-MM-YYYY format
    local d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")
    if d then
        return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    -- Try DD-MM-YY format
    d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d)$")
    if d then
        local year = tonumber(y)
        if year < 100 then year = year + 2000 end
        return os.time({ year = year, month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    -- Try YYYY-MM-DD format (for backwards compatibility)
    y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if y then
        return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    return nil
end

local function get_due_date_status(due_date_str, is_in_done_list)
    if not due_date_str or due_date_str == "" then return "none" end

    local due_timestamp = parse_date(due_date_str)
    if not due_timestamp then return "invalid" end

    if is_in_done_list then return "complete" end

    local now = os.time()
    local one_day = 24 * 60 * 60

    if now > due_timestamp then return "overdue"
    elseif (due_timestamp - now) < one_day then return "due_soon"
    else return "due_later" end
end

local function draw_deadline_popup(ctx, card_obj, save_board_func)
    if reaper.ImGui_BeginPopup(ctx, "edit_deadline_popup") then
        local date_text = card_obj.due_date or ""
        reaper.ImGui_PushItemWidth(ctx, 120)
        local changed, new_date = reaper.ImGui_InputText(ctx, "##due_date_input", date_text)
        reaper.ImGui_PopItemWidth(ctx)
        if changed then card_obj.due_date = new_date; save_board_func() end

        reaper.ImGui_SameLine(ctx)
        local calendar_popup_id = "calendar_popup_" .. card_obj.id
        
        -- Bepaal de positie voor de kalender-popup zodat deze binnen het hoofdvenster past
        local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
        local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
        local cursor_x, cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
        
        -- Geschatte kalenderafmetingen
        local calendar_width = 250
        local calendar_height = 200
        
        -- Bereken beschikbare ruimte
        local available_right = window_x + window_width - cursor_x
        local available_bottom = window_y + window_height - cursor_y
        
        -- Bepaal de popup-positie
        local popup_x = cursor_x
        local popup_y = cursor_y + reaper.ImGui_GetFrameHeight(ctx)
        
        -- Pas positie aan als er niet genoeg ruimte is
        if available_right < calendar_width then
            popup_x = math.max(window_x, cursor_x - calendar_width)
        end
        
        if available_bottom < calendar_height then
            popup_y = math.max(window_y, cursor_y - calendar_height)
        end
        
        -- Stel de popup-positie in VOORDAT we de knop tekenen
        reaper.ImGui_SetNextWindowPos(ctx, popup_x, popup_y)
        
        if reaper.ImGui_Button(ctx, "📅") then
            calendar.set_display_date(card_obj.due_date)
            reaper.ImGui_OpenPopup(ctx, calendar_popup_id)
        end
        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Open Calendar") end

        if reaper.ImGui_BeginPopup(ctx, calendar_popup_id) then
            local new_date = calendar.draw(ctx, card_obj.due_date)
            if new_date then
                card_obj.due_date = new_date
                save_board_func()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        if card_obj.due_date and card_obj.due_date ~= "" then
            if reaper.ImGui_Button(ctx, "Clear") then
                card_obj.due_date = nil
                save_board_func()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

local function draw_priority_popup(ctx, card_obj, save_board_func)
    if reaper.ImGui_BeginPopup(ctx, "edit_priority_popup") then
        for i, priority_def in ipairs(priorities) do
            if reaper.ImGui_Selectable(ctx, priority_def.text, card_obj.priority == priority_def.id) then
                card_obj.priority = priority_def.id
                save_board_func()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

local function draw_labels_popup(ctx, board, card_obj, save_board_func, ui_state)
    local function get_label_def(label_id)
        for _, def in ipairs(board.label_definitions or {}) do
            if def.id == label_id then return def end
        end
        return nil
    end

    if reaper.ImGui_BeginPopup(ctx, "edit_labels_popup") then
        reaper.ImGui_Text(ctx, "Labels")
        reaper.ImGui_TextDisabled(ctx, "Select labels, edit their names, and change their colors.")
        reaper.ImGui_Separator(ctx)

        if reaper.ImGui_BeginChild(ctx, "labels_editor_list", 0, 250) then
            local row_bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.17, 0.24, 0.31, 1.0) -- Darkblue
            local row_height = reaper.ImGui_GetFrameHeight(ctx) + 8

            for i, label_def in ipairs(board.label_definitions or {}) do
                reaper.ImGui_PushID(ctx, label_def.id)

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), row_bg_color)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 4, 4)
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 4.0)

                if reaper.ImGui_BeginChild(ctx, "label_row_"..i, 0, row_height, 0) then
                    local is_on_card = false
                    local on_card_idx = nil
                    for j, existing_id in ipairs(card_obj.labels) do
                        if label_def.id == existing_id then
                            is_on_card = true
                            on_card_idx = j
                            break
                        end
                    end

                    local check_changed, new_checked_state = reaper.ImGui_Checkbox(ctx, "##label_toggle", is_on_card)
                    if check_changed then
                        if new_checked_state then
                            table.insert(card_obj.labels, label_def.id)
                        else
                            table.remove(card_obj.labels, on_card_idx)
                        end
                        save_board_func()
                    end
                    reaper.ImGui_SameLine(ctx)

                    local popup_id = "color_palette_popup_" .. label_def.id
                    local color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(label_def.color))
                    if reaper.ImGui_ColorButton(ctx, "##color_btn" .. label_def.id, color_u32) then
                        reaper.ImGui_OpenPopup(ctx, popup_id)
                    end

                    if reaper.ImGui_BeginPopup(ctx, popup_id) then
                        reaper.ImGui_Text(ctx, "Select a color")
                        reaper.ImGui_Separator(ctx)
                        for j, color_rgba in ipairs(ui_state.color_palette or {}) do
                            if (j - 1) % 6 ~= 0 then reaper.ImGui_SameLine(ctx) end
                            local palette_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(color_rgba))
                            if reaper.ImGui_ColorButton(ctx, "##palette_color_"..j, palette_color_u32) then
                                label_def.color = {unpack(color_rgba)}
                                save_board_func()
                                reaper.ImGui_CloseCurrentPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                    reaper.ImGui_SameLine(ctx)

                    reaper.ImGui_PushItemWidth(ctx, -1)
                    local text_changed, new_text = reaper.ImGui_InputText(ctx, "##label_name_edit", label_def.text)
                    if text_changed then label_def.text = new_text; save_board_func() end
                    reaper.ImGui_PopItemWidth(ctx)
                    reaper.ImGui_EndChild(ctx)
                end

                reaper.ImGui_PopStyleVar(ctx, 2)
                reaper.ImGui_PopStyleColor(ctx)

                reaper.ImGui_PopID(ctx)
            end
            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Button(ctx, "Close", -1, 0) then reaper.ImGui_CloseCurrentPopup(ctx) end

        reaper.ImGui_EndPopup(ctx)
    end
end

local function draw_add_checklist_popup(ctx, card_obj, save_board_func, checklist_templates)
    if reaper.ImGui_BeginPopup(ctx, "add_checklist_popup") then
        if reaper.ImGui_Selectable(ctx, "New Blank Checklist") then
            table.insert(card_obj.checklists, { name = "New Checklist", items = {} })
            save_board_func()
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginMenu(ctx, "Add from Template") then
            if next(checklist_templates) == nil then
                reaper.ImGui_TextDisabled(ctx, "(No templates saved)")
            else
                for name, template in pairs(checklist_templates) do
                    if reaper.ImGui_MenuItem(ctx, name) then
                        local new_checklist = deepcopy(template)
                        table.insert(card_obj.checklists, new_checklist)
                        save_board_func()
                    end
                end
            end
            reaper.ImGui_EndMenu(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

local function draw_card_properties_display(ctx, board, card_obj, list_idx, ui_state)
    local has_labels = card_obj.labels and #card_obj.labels > 0
    local has_priority = card_obj.priority and card_obj.priority > 0
    local has_due_date = card_obj.due_date and card_obj.due_date ~= ""

    if not (has_labels or has_priority or has_due_date) then
        return
    end

    if has_labels then
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.small_font_size)
        reaper.ImGui_TextDisabled(ctx, "LABELS")
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, 0, 2)
        for _, label_id in ipairs(card_obj.labels) do
            local label_def
            for _, def in ipairs(board.label_definitions or {}) do
                if def.id == label_id then label_def = def; break end
            end
            if label_def then
                local color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(label_def.color))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_u32)
                local r, g, b = unpack(label_def.color)
                local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                local text_color = (luminance > 0.5) and reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.0)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
                
                reaper.ImGui_Button(ctx, (label_def.text and label_def.text ~= "") and label_def.text or "     ")
                
                reaper.ImGui_PopStyleColor(ctx, 2)
                reaper.ImGui_SameLine(ctx, 0, 4)
            end
        end
        reaper.ImGui_NewLine(ctx)
        reaper.ImGui_EndGroup(ctx)
    end

    if has_priority then
        if has_labels then reaper.ImGui_SameLine(ctx, 0, 20) end
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.small_font_size)
        reaper.ImGui_TextDisabled(ctx, "PRIORITY")
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, 0, 2)

        local current_priority = priorities[card_obj.priority + 1]
        if current_priority and current_priority.color then
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            
            local text_size_x, text_size_y = reaper.ImGui_CalcTextSize(ctx, current_priority.text)
            local padding_x, padding_y = 5, 1
            local box_width, box_height = text_size_x + (padding_x * 2), text_size_y + (padding_y * 2)
            local x, y = reaper.ImGui_GetCursorScreenPos(ctx)

            local bg_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(current_priority.color))
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_width, y + box_height, bg_color_u32, 4.0)

            local r, g, b = unpack(current_priority.color)
            local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            local text_color_u32 = (luminance > 0.5) and reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.0)
            reaper.ImGui_DrawList_AddText(draw_list, x + padding_x, y + padding_y, text_color_u32, current_priority.text)

            reaper.ImGui_Dummy(ctx, box_width, box_height)
        elseif current_priority then
            reaper.ImGui_Text(ctx, current_priority.text)
        end
        reaper.ImGui_EndGroup(ctx)
    end

    if has_due_date then
        if has_labels or has_priority then reaper.ImGui_SameLine(ctx, 0, 20) end
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.small_font_size)
        reaper.ImGui_TextDisabled(ctx, "DUE DATE")
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_Dummy(ctx, 0, 2)
        reaper.ImGui_Text(ctx, card_obj.due_date)
        reaper.ImGui_EndGroup(ctx)
    end

    reaper.ImGui_Dummy(ctx, 0, 15)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Dummy(ctx, 0, 5)
end

local function draw_card_actions_row(ctx, board, card_obj, save_board_func, checklist_templates, ui_state)
    local command = nil
    if reaper.ImGui_Button(ctx, "Labels") then reaper.ImGui_OpenPopup(ctx, "edit_labels_popup") end
    draw_labels_popup(ctx, board, card_obj, save_board_func, ui_state)
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Priority") then reaper.ImGui_OpenPopup(ctx, "edit_priority_popup") end
    draw_priority_popup(ctx, card_obj, save_board_func)
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Due Date") then reaper.ImGui_OpenPopup(ctx, "edit_deadline_popup") end
    draw_deadline_popup(ctx, card_obj, save_board_func)
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Add Checklist") then reaper.ImGui_OpenPopup(ctx, "add_checklist_popup") end
    draw_add_checklist_popup(ctx, card_obj, save_board_func, checklist_templates)
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Comments") then
        card_obj.ui_show_comments = not card_obj.ui_show_comments
    end

    return command
end

local function draw_checklists_section(ctx, card_obj, save_board_func, checklist_templates, ui_state)
    local checklist_to_remove = nil
    local returned_command = nil
    for i, cl_obj in ipairs(card_obj.checklists) do
        local cmd = checklist.draw(ctx, cl_obj, "checklist" .. i .. card_obj.id, save_board_func, ui_state)
        if cmd then
            if cmd.action == 'remove' then checklist_to_remove = i
            elseif cmd.action == 'convert_to_card' then
                local item_to_convert = table.remove(cl_obj.items, cmd.item_index)
                if item_to_convert then
                    save_board_func()
                    returned_command = { action = 'create_card_from_text', text = item_to_convert.text }
                end
            else 
                returned_command = cmd end
        end
    end
    if checklist_to_remove then table.remove(card_obj.checklists, checklist_to_remove); save_board_func() end
    return returned_command
end

local function draw_comments_section(ctx, card_obj, save_board_func, content_width, ui_state)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Comments")
    local new_comment_text = card_obj.new_comment_buffer or ""

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), ui_state.input_bg_color)
    local button_width = 120
    reaper.ImGui_PushItemWidth(ctx, (content_width or reaper.ImGui_GetContentRegionAvail(ctx)) - button_width)
    local changed, entered_text = reaper.ImGui_InputText(ctx, "##new_comment", new_comment_text)
    reaper.ImGui_PopItemWidth(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    if changed then card_obj.new_comment_buffer = entered_text end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.2))
    if reaper.ImGui_Button(ctx, "Add Comment") and card_obj.new_comment_buffer and card_obj.new_comment_buffer ~= "" then
        table.insert(card_obj.comments, 1, { text = card_obj.new_comment_buffer, timestamp = os.time() })
        card_obj.new_comment_buffer = ""
        save_board_func()
    end
    reaper.ImGui_PopStyleColor(ctx, 3)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildBorderSize(), 1.0)
    if reaper.ImGui_BeginChild(ctx, "comments_list", 0, 100, 0) then
        for _, comment in ipairs(card_obj.comments) do
            local time_str = os.date("%Y-%m-%d %H:%M", comment.timestamp)
            reaper.ImGui_TextWrapped(ctx, comment.text)
            reaper.ImGui_TextDisabled(ctx, time_str)
            reaper.ImGui_Separator(ctx)
        end
        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)
end

function M.draw(ctx, board, list_idx, card_idx, editing_card, save_board_func, checklist_templates, ui_state)
    local card_obj = board.lists[list_idx].cards[card_idx]

    if not card_obj.id then
        card_obj.id = reaper.genGuid("")
        save_board_func()
    end

    if not card_obj.labels then card_obj.labels = {} end
    if not card_obj.description then card_obj.description = "" end
    if not card_obj.checklists then card_obj.checklists = {} end
    if not card_obj.comments then card_obj.comments = {} end
    if not card_obj.priority then card_obj.priority = 0 end
    if not card_obj.due_date then card_obj.due_date = nil end

    local card_id = "card_child_" .. card_obj.id


    local function draw_card_content(is_drawing_pass, board, list_idx)
        reaper.ImGui_BeginGroup(ctx)
            reaper.ImGui_TextWrapped(ctx, card_obj.title)

            if #card_obj.labels > 0 then
                reaper.ImGui_Dummy(ctx, 0, 4)
                for _, label_id in ipairs(card_obj.labels) do
                    local label_def = nil
                    for _, def in ipairs(board.label_definitions or {}) do
                        if def.id == label_id then
                            label_def = def
                            break
                        end
                    end

                    if label_def and is_drawing_pass then
                        local color = reaper.ImGui_ColorConvertDouble4ToU32(unpack(label_def.color))
                        local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
                        reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx), x, y, x + 30, y + 6, color, 3)
                    end
                    reaper.ImGui_Dummy(ctx, 32, 6)
                    reaper.ImGui_SameLine(ctx, 0, 4)
                end
                reaper.ImGui_NewLine(ctx)
            end
            
            local has_icons = #card_obj.description > 0 or #card_obj.checklists > 0 or (card_obj.due_date and card_obj.due_date ~= "") or (card_obj.priority and card_obj.priority > 0)
            if has_icons then reaper.ImGui_Dummy(ctx, 0, 4) end

            if #card_obj.description > 0 then
                reaper.ImGui_TextDisabled(ctx, "≡"); reaper.ImGui_SameLine(ctx)
            end

            if #card_obj.checklists > 0 then
                local total, checked = 0, 0
                for _, cl in ipairs(card_obj.checklists) do
                    total = total + #cl.items
                    for _, item in ipairs(cl.items) do if item.checked then checked = checked + 1 end end
                end
                if total > 0 then
                    local is_complete = (checked == total)
                    if is_complete then
                        local green_color = reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.8, 0.4, 1.0)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), green_color)
                        reaper.ImGui_Text(ctx, ("☑ %d/%d"):format(checked, total))
                        reaper.ImGui_PopStyleColor(ctx)
                    else
                        local default_color = reaper.ImGui_ColorConvertDouble4ToU32(0.9, 0.9, 0.9, 0.85) -- Lightgrey light transparant
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), default_color)
                        reaper.ImGui_Text(ctx, ("☑ %d/%d"):format(checked, total))
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                    reaper.ImGui_SameLine(ctx)
                end
            end

            if card_obj.due_date and card_obj.due_date ~= "" then
                local list_name = board.lists[list_idx].name or ""
                local is_done = list_name:lower():find("done") or list_name:lower():find("completed")
                
                local status = get_due_date_status(card_obj.due_date, is_done)
                
                local status_color
                if status == "overdue" then status_color = {1.0, 0.3, 0.3, 1.0} -- Red
                elseif status == "due_soon" then status_color = {1.0, 0.8, 0.3, 1.0} -- Yellow
                elseif status == "complete" then status_color = {0.4, 0.8, 0.4, 1.0} -- Green
                else status_color = {0.7, 0.7, 0.7, 1.0} end -- Grey (standard)

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(unpack(status_color)))
                reaper.ImGui_Text(ctx, "⏱ " .. card_obj.due_date)
                reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_SameLine(ctx)
            end

            local current_priority = priorities[card_obj.priority + 1]
            if current_priority and current_priority.color then
                local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

                reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.small_font_size)
                
                local text_size_x, text_size_y = reaper.ImGui_CalcTextSize(ctx, current_priority.text)
                local padding_x = 5
                local padding_y = 1
                local box_width = text_size_x + (padding_x * 2)
                local box_height = text_size_y + (padding_y * 2)

                local x, y = reaper.ImGui_GetCursorScreenPos(ctx)

                local bg_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(unpack(current_priority.color))
                reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_width, y + box_height, bg_color_u32, 4.0)

                local r, g, b = unpack(current_priority.color)
                local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                local text_color_u32
                if luminance > 0.5 then
                    text_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0) -- Dark text
                else
                    text_color_u32 = reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.0) -- Light text
                end
                reaper.ImGui_DrawList_AddText(draw_list, x + padding_x, y + padding_y, text_color_u32, current_priority.text)

                reaper.ImGui_Dummy(ctx, box_width, box_height)
                reaper.ImGui_SameLine(ctx)

                reaper.ImGui_PopFont(ctx)
            end
        reaper.ImGui_EndGroup(ctx)
    end

    local start_x, start_y = reaper.ImGui_GetCursorScreenPos(ctx)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.0)
    draw_card_content(false, board, list_idx)
    reaper.ImGui_PopStyleVar(ctx)
    local _, content_max_y = reaper.ImGui_GetItemRectMax(ctx)
    local content_height = content_max_y - start_y

    local card_padding = 8
    local card_height = content_height + (card_padding * 2)
    local rounding = 4.0

    reaper.ImGui_SetCursorScreenPos(ctx, start_x, start_y)

    local horizontal_margin = 5

    local available_width, _ = reaper.ImGui_GetContentRegionAvail(ctx)

    local current_cursor_x = reaper.ImGui_GetCursorPosX(ctx)
    reaper.ImGui_SetCursorPosX(ctx, current_cursor_x + horizontal_margin)

    local button_width = available_width - (2 * horizontal_margin)
    if button_width < 1 then button_width = 1 end

    reaper.ImGui_InvisibleButton(ctx, "card_interaction_"..card_obj.id, button_width, card_height)
    local is_hovered = reaper.ImGui_IsItemHovered(ctx)

    if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 1) then
        editing_card = { list = list_idx, card = card_idx }
    end

    if reaper.ImGui_BeginDragDropSource(ctx) then
        local payload = ("%d,%d"):format(list_idx, card_idx)
        reaper.ImGui_SetDragDropPayload(ctx, 'CARD', payload)
        reaper.ImGui_Text(ctx, card_obj.title)
        reaper.ImGui_EndDragDropSource(ctx)
    end

    local min_card_x, min_card_y = reaper.ImGui_GetItemRectMin(ctx)
    local max_card_x, max_card_y = reaper.ImGui_GetItemRectMax(ctx)

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

    local glow_steps = 3
    local glow_max_alpha = 0.08
    for i = glow_steps, 1, -1 do
        local expansion = i
        local alpha = glow_max_alpha * (1 - (i-1)/glow_steps)
        local glow_color = reaper.ImGui_ColorConvertDouble4ToU32(1.0, 1.0, 1.0, alpha)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, min_card_x - expansion, min_card_y - expansion, max_card_x + expansion, max_card_y + expansion, glow_color, rounding + expansion)
    end

    local bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.27, 1.0) -- Darkgrey
    reaper.ImGui_DrawList_AddRectFilled(draw_list, min_card_x, min_card_y, max_card_x, max_card_y, bg_color, rounding)

    local border_color_u32 = is_hovered and reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 1.0)
    reaper.ImGui_DrawList_AddRect(draw_list, min_card_x, min_card_y, max_card_x, max_card_y, border_color_u32, rounding, 0, 1.0)

    reaper.ImGui_SetCursorScreenPos(ctx, min_card_x + card_padding, min_card_y + card_padding)
    draw_card_content(true, board, list_idx)

    local this_card_is_editing = editing_card and editing_card.list == list_idx and editing_card.card == card_idx
    local popup_id = "Card Details##" .. card_obj.id
    local command = nil

    if this_card_is_editing then reaper.ImGui_OpenPopup(ctx, popup_id) end
    
    card_obj.ui_show_comments = card_obj.ui_show_comments or false

    reaper.ImGui_SetNextWindowSize(ctx, 500, 600, reaper.ImGui_Cond_FirstUseEver())

        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
        local window_flags = reaper.ImGui_WindowFlags_None()
        if reaper.ImGui_BeginPopupModal(ctx, popup_id, true, window_flags) then
            
            -- NIEUW: Click outside to close en Escape key
            if reaper.ImGui_IsMouseClicked(ctx, 0) then -- Links klik
                local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
                local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
                local window_w, window_h = reaper.ImGui_GetWindowSize(ctx)
                
                -- Check of klik buiten het venster is
                if mouse_x < window_x or mouse_x > window_x + window_w or
                   mouse_y < window_y or mouse_y > window_y + window_h then
                    editing_card = nil
                    card_obj.ui_show_comments = nil
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
            end
            
            -- NIEUW: Escape key to close
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                editing_card = nil
                card_obj.ui_show_comments = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            
            -- Behoud bestaande close button tooltip
            if reaper.ImGui_IsWindowHovered(ctx) then
                local window_pos_x, window_pos_y = reaper.ImGui_GetWindowPos(ctx)
                local window_size_x, window_size_y = reaper.ImGui_GetWindowSize(ctx)
    
                -- Create a small rectangle in the top-right corner for the close button
                local close_button_min_x = window_pos_x + window_size_x - 30
                local close_button_min_y = window_pos_y + 8
                local close_button_max_x = window_pos_x + window_size_x - 8
                local close_button_max_y = window_pos_y + 30
    
                local mouse_pos_x, mouse_pos_y = reaper.ImGui_GetMousePos(ctx)
    
                -- Check if mouse is within the close button area
                if mouse_pos_x >= close_button_min_x and mouse_pos_x <= close_button_max_x and
                   mouse_pos_y >= close_button_min_y and mouse_pos_y <= close_button_max_y then
                    reaper.ImGui_SetTooltip(ctx, "Close")
                end
            end


        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
        local popup_bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.20, 1.0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), popup_bg_color)
        
        ui_state.input_bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.22, 1.0)

        -- Header row with title and options menu
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.title_font_size)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), popup_bg_color)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 4, 8)
        
        -- Title input (takes most of the width)
        reaper.ImGui_PushItemWidth(ctx, -40) -- Reserve space for options button
        local changed, new_title = reaper.ImGui_InputText(ctx, "##Title", card_obj.title)
        if changed then card_obj.title = new_title; save_board_func() end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopFont(ctx)
        
       -- Options button aligned to the right
reaper.ImGui_SameLine(ctx)
local card_options_popup_id = "card_options_popup##" .. card_obj.id

-- Sla de knop positie op voor later gebruik
local button_min_x, button_min_y = reaper.ImGui_GetCursorScreenPos(ctx)

if reaper.ImGui_Button(ctx, "...") then 
    reaper.ImGui_OpenPopup(ctx, card_options_popup_id)
end

-- Sla de actuele knop positie op nadat de knop is getekend
local actual_button_min_x, actual_button_min_y = reaper.ImGui_GetItemRectMin(ctx)
local actual_button_max_x, actual_button_max_y = reaper.ImGui_GetItemRectMax(ctx)
local button_height = actual_button_max_y - actual_button_min_y

if reaper.ImGui_IsItemHovered(ctx) then 
    reaper.ImGui_SetTooltip(ctx, "Card options") 
end
        
-- Card options popup
if reaper.ImGui_BeginPopup(ctx, card_options_popup_id) then
    -- Gebruik de opgeslagen knop positie om de popup te positioneren
    local dropdown_width = 150
    local dropdown_height = 60
    
    -- Positioneer de popup links van de knop
    local popup_x = actual_button_min_x - dropdown_width
    local popup_y = actual_button_min_y + button_height
    
    reaper.ImGui_SetWindowPos(ctx, popup_x, popup_y)
    
    if reaper.ImGui_MenuItem(ctx, "Save as Template") then
        command = { action = 'save_card_as_template', data = deepcopy(card_obj) }
        editing_card = nil 
        reaper.ImGui_CloseCurrentPopup(ctx)
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    if reaper.ImGui_MenuItem(ctx, "Archive") then
        editing_card.archive = true
    end
    reaper.ImGui_EndPopup(ctx)
end
        
        reaper.ImGui_EndGroup(ctx)
        
        reaper.ImGui_Dummy(ctx, 0, 10)

        draw_card_actions_row(ctx, board, card_obj, save_board_func, checklist_templates, ui_state)
        reaper.ImGui_Dummy(ctx, 0, 10)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Dummy(ctx, 0, 5)

        draw_card_properties_display(ctx, board, card_obj, list_idx, ui_state)

        if reaper.ImGui_BeginChild(ctx, "main_content_scroller", 0, 0, 0) then
            local left_padding = 15
            local right_padding = 15

            local total_available_width, _ = reaper.ImGui_GetContentRegionAvail(ctx)

            reaper.ImGui_Indent(ctx, left_padding)

            local content_width = total_available_width - left_padding - right_padding
            if content_width < 1 then content_width = 1 end

            reaper.ImGui_Dummy(ctx, 0, 5)

            reaper.ImGui_Text(ctx, "Description")
            reaper.ImGui_Dummy(ctx, 0, 5)

            local input_height = 80
            local container_height = input_height + 5 

            if reaper.ImGui_BeginChild(ctx, "desc_wrapper", content_width, container_height, 0, reaper.ImGui_WindowFlags_NoScrollbar()) then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), ui_state.input_bg_color)
                reaper.ImGui_PushItemWidth(ctx, -1)
                local changed, new_desc = reaper.ImGui_InputTextMultiline(ctx, "##Description", card_obj.description, -1, input_height)
                reaper.ImGui_PopItemWidth(ctx)
                if changed then card_obj.description = new_desc; save_board_func() end
                reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_EndChild(ctx)
            end
            reaper.ImGui_Dummy(ctx, 0, 10)

            ui_state.current_content_width = content_width
            local checklist_command = draw_checklists_section(ctx, card_obj, save_board_func, checklist_templates, ui_state)
            ui_state.current_content_width = nil
            if checklist_command then
                if checklist_command.action == 'create_card_from_text' then
                    checklist_command.list_idx = list_idx
                    command = checklist_command
                    reaper.ImGui_CloseCurrentPopup(ctx); editing_card = nil
                elseif checklist_command.action == 'save_as_template' then
                    command = { action = 'save_checklist_as_template', data = checklist_command.data }
                    reaper.ImGui_CloseCurrentPopup(ctx); editing_card = nil
                end
            end

            if card_obj.ui_show_comments then
                draw_comments_section(ctx, card_obj, save_board_func, content_width, ui_state)
            end

            reaper.ImGui_Unindent(ctx, left_padding)
        end
        reaper.ImGui_EndChild(ctx)

        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx) -- Pop PopupBg (pushed inside modal)
        reaper.ImGui_EndPopup(ctx)
    else
        if this_card_is_editing then
            editing_card = nil
            card_obj.ui_show_comments = nil
        end
    end
    reaper.ImGui_PopStyleVar(ctx) -- Pop WindowRounding (pushed before modal)
    return editing_card, command
end

return M