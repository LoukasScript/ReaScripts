-- checklist.lua: Modulair checklist component voor ReaImGui

local retval, script_path = reaper.get_action_context()
local base_path = script_path:match("(.*[/\\])")
local calendar = dofile(base_path .. "calendar.lua")

local M = {}
local unpack = table.unpack or unpack

-- Helper om een datumstring te parsen naar een Unix timestamp.
-- Gekopieerd uit card.lua voor modulaire onafhankelijkheid.
local function parse_date(date_str)
    if not date_str or date_str == "" then return nil end

    -- Probeer DD-MM-YYYY formaat
    local d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")
    if d then
        return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    -- Probeer DD-MM-YY formaat
    d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d)$")
    if d then
        local year = tonumber(y)
        if year < 100 then year = year + 2000 end
        return os.time({ year = year, month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    -- Probeer YYYY-MM-DD formaat (voor backwards compatibility)
    y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if y then
        return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
    end

    return nil
end

-- Bepaalt de status van de deadline voor een checklist item.
local function get_due_date_status(due_date_str, is_checked)
    if is_checked then return "complete" end
    if not due_date_str or due_date_str == "" then return "none" end

    local due_timestamp = parse_date(due_date_str)
    if not due_timestamp then return "invalid" end

    local now = os.time()
    local one_day = 24 * 60 * 60

    if now > due_timestamp then return "overdue"
    elseif (due_timestamp - now) < one_day then return "due_soon"
    else return "due_later" end
end

-- Helper to draw a drop zone for reordering checklist items.
local function draw_checklist_item_dropzone(ctx, checklist_id, insert_pos, pending_item_move, dnd_payload_type)
    -- Use a unique ID for the dropzone button.
    reaper.ImGui_InvisibleButton(ctx, "dropzone_"..checklist_id.."_"..insert_pos, -1, 6)
    local hovered = reaper.ImGui_IsItemHovered(ctx)
    local dragging = false

    if reaper.ImGui_BeginDragDropTarget(ctx) then
        dragging = true
        local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, dnd_payload_type)
        if rv then
            local src_idx = tonumber(payload)
            if src_idx then
                -- Store the pending move. It will be executed after the loop.
                pending_item_move.src_idx = src_idx
                pending_item_move.dst_idx = insert_pos
            end
        end
        reaper.ImGui_EndDragDropTarget(ctx)
    end

    -- Visual feedback for the dropzone
    if hovered or dragging then
        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local color = reaper.ImGui_ColorConvertDouble4ToU32(1.0, 1.0, 0.0, 0.30)
        reaper.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, color, 3)
    end
end

--- Tekent een volledige checklist en beheert de interactie.
-- @param ctx ImGui context.
-- @param checklist_obj De checklist tabel.
-- @param checklist_id Een unieke ID voor deze checklist in de UI.
-- @param save_board_func Functie om het board op te slaan.
-- @return boolean True als de checklist verwijderd moet worden.
function M.draw(ctx, checklist_obj, checklist_id, save_board_func, ui_state)
    local command = nil
    local pending_item_move = {} -- Use a table to pass by reference.

    -- Create a shorter, but still unique, payload type for drag-and-drop.
    -- The full checklist_id (which includes a GUID) is too long for ImGui's payload type limit of 32 chars.
    -- We use a prefix and the end of the unique ID, which is unique enough for this purpose.
    local dnd_payload_type = "CLI_" .. string.sub(checklist_id, -27)

    reaper.ImGui_PushID(ctx, checklist_id)

    -- Sectie: Titel en actieknoppen
    reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.checklist_title_font_size or 18)
        reaper.ImGui_Text(ctx, "📋")  -- Clipboard symbool
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PopFont(ctx)

        -- API-wijziging: ImGui_GetContentRegionAvailWidth is niet beschikbaar in deze versie.
        -- We gebruiken ImGui_GetContentRegionAvail, die breedte en hoogte retourneert.
        local content_w = ui_state.current_content_width or reaper.ImGui_GetContentRegionAvail(ctx)
        local buttons_width = 190 -- Geschatte breedte voor "Save as Template" + "X" + spacing
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), ui_state.input_bg_color)
        reaper.ImGui_PushItemWidth(ctx, content_w - buttons_width)
        local changed, new_name = reaper.ImGui_InputText(ctx, "##name", checklist_obj.name)
        if changed then checklist_obj.name = new_name; save_board_func() end
        reaper.ImGui_PopItemWidth(ctx)
        reaper.ImGui_PopStyleColor(ctx)

        reaper.ImGui_SameLine(ctx)
        -- Maak de knoppen visueel zachter met een transparante achtergrond.
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.2))
        if reaper.ImGui_Button(ctx, "Save as Template") then command = { action = 'save_as_template', data = checklist_obj } end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "X") then command = { action = 'remove' } end
        reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_EndGroup(ctx)

    -- Voortgangsbalk
    local total, checked = #checklist_obj.items, 0
    for _, item in ipairs(checklist_obj.items) do if item.checked then checked = checked + 1 end end
    local progress = total > 0 and (checked / total) or 0
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local pos_x, pos_y = reaper.ImGui_GetCursorScreenPos(ctx)
    -- API-wijziging: ImGui_GetContentRegionAvailWidth is niet beschikbaar in deze versie.
    -- We gebruiken ImGui_GetContentRegionAvail, die breedte en hoogte retourneert.
    local bar_width = ui_state.current_content_width or reaper.ImGui_GetContentRegionAvail(ctx)
    local progress_bar_height = 8
    local rounding = 4.0
    local bar_bg_color = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1.0)
    local bar_fg_color = progress == 1.0 and reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.8, 0.4, 1.0) or reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.6, 1.0, 1.0)
    
    reaper.ImGui_DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + bar_width, pos_y + progress_bar_height, bar_bg_color, rounding)
    if progress > 0 then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + bar_width * progress, pos_y + progress_bar_height, bar_fg_color, rounding)
    end
    reaper.ImGui_Dummy(ctx, 0, progress_bar_height + 2)

    reaper.ImGui_PushFont(ctx, ui_state.main_font, ui_state.small_font_size or 13)
    local percent_text = string.format("%d%%", math.floor(progress * 100))
    reaper.ImGui_Text(ctx, percent_text)
    
    -- Collapse/Expand knop toevoegen
    reaper.ImGui_SameLine(ctx)
    local collapse_button_text = checklist_obj.collapsed and "▶ Expand" or "▼ Collapse"
    if reaper.ImGui_Button(ctx, collapse_button_text) then
        checklist_obj.collapsed = not checklist_obj.collapsed
        save_board_func()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Toggle visibility of checklist items")
    end
    
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_Dummy(ctx, 0, 6) -- Extra ruimte voor de items
    
    -- Checklist items - alleen tonen als niet gecollapsed
    local item_to_remove = nil

    if not checklist_obj.collapsed then
        -- Dropzone at the very top of the list
        draw_checklist_item_dropzone(ctx, checklist_id, 1, pending_item_move, dnd_payload_type)

        for j, item in ipairs(checklist_obj.items) do
            reaper.ImGui_PushID(ctx, "item" .. j)

            -- Drag handle
            -- Use a Selectable as the drag source. It's an interactive item, which is required
            -- by BeginDragDropSource and fixes the assertion failure. We make it small to act as a handle.
            reaper.ImGui_Selectable(ctx, "⠿", false, reaper.ImGui_SelectableFlags_None(), 15, 0)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Drag to reorder")
            end

            if reaper.ImGui_BeginDragDropSource(ctx) then
                local payload = tostring(j)
                reaper.ImGui_SetDragDropPayload(ctx, dnd_payload_type, payload)
                reaper.ImGui_Text(ctx, item.text) -- Preview
                reaper.ImGui_EndDragDropSource(ctx)
            end
            reaper.ImGui_SameLine(ctx)

            local check_changed, new_checked = reaper.ImGui_Checkbox(ctx, "##checked", item.checked)
            if check_changed then item.checked = new_checked; save_board_func() end
            reaper.ImGui_SameLine(ctx)

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), ui_state.input_bg_color)
            -- Laat het tekstveld de beschikbare ruimte opvullen tussen de checkbox en de deadline-input.
            -- De breedte van de elementen op de lijn wordt hier geschat om de breedte van het tekstveld te bepalen.
            -- De vorige methode, waarbij we de breedte van het tekstveld handmatig berekenden, was niet robuust.
            -- We gebruiken nu een superieure techniek: PushItemWidth met een negatieve waarde.
            -- Dit vertelt ImGui om alle beschikbare ruimte te gebruiken, MINUS de ruimte voor de knoppen aan de rechterkant.
            -- Dit is de meest betrouwbare manier om te zorgen dat alle knoppen zichtbaar blijven.
            local deadline_width = 100
            local to_card_width = 70  -- Geschatte breedte voor "To Card" knop
            local remove_width = 35   -- Geschatte breedte voor "-" knop
            local spacing = 15        -- Geschatte ruimte voor de 'SameLine' aanroepen
            local right_side_total_width = deadline_width + to_card_width + remove_width + spacing

            reaper.ImGui_PushItemWidth(ctx, -right_side_total_width)
            local text_changed, new_text = reaper.ImGui_InputText(ctx, "##text", item.text)
            reaper.ImGui_PopItemWidth(ctx)
            reaper.ImGui_PopStyleColor(ctx)
            if text_changed then item.text = new_text; save_board_func() end
            reaper.ImGui_SameLine(ctx)

            -- Deadline input met statuskleur
            item.due_date = item.due_date or nil -- Zorg dat het veld bestaat voor oude data.
            local status = get_due_date_status(item.due_date, item.checked)
            local status_color
            if status == "overdue" then status_color = {1.0, 0.3, 0.3, 1.0} -- Rood
            elseif status == "due_soon" then status_color = {1.0, 0.8, 0.3, 1.0} -- Geel
            elseif status == "complete" then status_color = {0.4, 0.8, 0.4, 1.0} -- Groen
            end

            if status_color then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(unpack(status_color)))
            end

           reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), ui_state.input_bg_color)
local popup_id = "calendar_popup_item_" .. j
local deadline_text = item.due_date or "Set Date"

-- Slimme popup positionering
local function calculate_best_popup_position(ctx, button_x, button_y)
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
    
    -- Kalender afmetingen
    local calendar_width = 250
    local calendar_height = 200
    
    -- Bereken beschikbare ruimte in alle richtingen
    local available_right = window_x + window_width - button_x
    local available_bottom = window_y + window_height - button_y
    local available_left = button_x - window_x
    local available_top = button_y - window_y
    
    local popup_x, popup_y = button_x, button_y + reaper.ImGui_GetFrameHeight(ctx)
    
    -- Optimaliseer horizontale positie
    if available_right < calendar_width then
        if available_left >= calendar_width then
            popup_x = button_x - calendar_width  -- Plaats links van de knop
        else
            popup_x = window_x + (window_width - calendar_width) / 2  -- Centreer
        end
    end
    
    -- Optimaliseer verticale positie  
    if available_bottom < calendar_height then
        if available_top >= calendar_height then
            popup_y = button_y - calendar_height  -- Plaats boven de knop
        else
            popup_y = window_y + (window_height - calendar_height) / 2  -- Centreer
        end
    end
    
    return popup_x, popup_y
end

local button_x, button_y = reaper.ImGui_GetItemRectMin(ctx)
local popup_x, popup_y = calculate_best_popup_position(ctx, button_x, button_y)

-- Stel de popup-positie in
reaper.ImGui_SetNextWindowPos(ctx, popup_x, popup_y)

if reaper.ImGui_Button(ctx, deadline_text, 100, 0) then
    calendar.set_display_date(item.due_date)
    reaper.ImGui_OpenPopup(ctx, popup_id)
end

if reaper.ImGui_BeginPopup(ctx, popup_id) then
    local new_date = calendar.draw(ctx, item.due_date)
    if new_date then
        item.due_date = new_date
        save_board_func()
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Clear Date") then
        item.due_date = nil
        save_board_func()
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
end
reaper.ImGui_PopStyleColor(ctx)

            if status_color then reaper.ImGui_PopStyleColor(ctx) end

            reaper.ImGui_SameLine(ctx)
            -- Maak de knop visueel zachter met een transparante achtergrond.
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.1))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.2))
            if reaper.ImGui_Button(ctx, "As Card") then
                command = { action = 'convert_to_card', item_index = j }
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Convert this item to a new card")
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "-") then item_to_remove = j end
            reaper.ImGui_PopStyleColor(ctx, 3)
            reaper.ImGui_PopID(ctx)

            -- Dropzone after each item
            draw_checklist_item_dropzone(ctx, checklist_id, j + 1, pending_item_move, dnd_payload_type)
        end
        if item_to_remove then table.remove(checklist_obj.items, item_to_remove); save_board_func() end

        -- Execute the move after the loop has finished rendering.
        if pending_item_move.src_idx then
            local src_idx = pending_item_move.src_idx
            local dst_idx = pending_item_move.dst_idx

            -- Adjust destination index if moving an item downwards in the same list.
            if src_idx < dst_idx then
                dst_idx = dst_idx - 1
            end

            local moved_item = table.remove(checklist_obj.items, src_idx)
            if moved_item then
                table.insert(checklist_obj.items, dst_idx, moved_item)
                save_board_func()
            end
        end

        -- Maak de knop visueel zachter met een transparante achtergrond.
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.1))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.2))
        if reaper.ImGui_Button(ctx, "Add Item") then
            table.insert(checklist_obj.items, { text = "New item", checked = false, due_date = nil })
            save_board_func()
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
    else
        -- Toon samenvatting wanneer gecollapsed
        reaper.ImGui_Text(ctx, string.format("(%d items, %d%% completed)", total, math.floor(progress * 100)))
        if total > 0 then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Add Item") then
                table.insert(checklist_obj.items, { text = "New item", checked = false, due_date = nil })
                save_board_func()
            end
        end
    end

    reaper.ImGui_Dummy(ctx, 0, 15)
    reaper.ImGui_PopID(ctx)

    return command
end

return M