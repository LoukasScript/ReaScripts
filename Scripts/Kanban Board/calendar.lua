-- Kanban helper: Calendar
-- Author: Loukas
-- Internal module (loaded by Kanban.lua)


local M = {}
local unpack = table.unpack or unpack

-- State for the calendar widget. We keep it local to this module.
local calendar_state = {
    -- The month and year currently being displayed by the calendar.
    -- 1 = Jan, 12 = Dec.
    display_month = os.date("*t").month,
    display_year = os.date("*t").year,
}

-- Helper to get the number of days in a given month and year.
local function get_days_in_month(year, month)
    local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
        return 29 -- Leap year
    end
    return days_in_month[month]
end

-- Helper to get the day of the week for the first day of the month.
-- 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
local function get_first_day_of_week(year, month)
    local t = os.time({ year = year, month = month, day = 1 })
    return os.date("*t", t).wday
end

--- Draws an interactive calendar widget.
-- @param ctx ImGui context.
-- @param current_date_str The currently selected date in "DD-MM-YYYY" format, or nil.
-- @return string|nil The newly selected date in "DD-MM-YYYY" format if a day was clicked, otherwise nil.
function M.draw(ctx, current_date_str)
    local new_date_selected = nil

    -- Parse the current date to highlight it
    local selected_d, selected_m, selected_y
    if current_date_str then
        local d, m, y = current_date_str:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")
        if d then selected_d, selected_m, selected_y = tonumber(d), tonumber(m), tonumber(y) end
        d, m, y = current_date_str:match("^(%d%d)-(%d%d)-(%d%d)$")
        if d then selected_d, selected_m, selected_y = tonumber(d), tonumber(m), tonumber(y) + 2000 end
    end

    -- Header: Month/Year navigation
    reaper.ImGui_BeginGroup(ctx)
    if reaper.ImGui_ArrowButton(ctx, "##prev_month", reaper.ImGui_Dir_Left()) then
        calendar_state.display_month = calendar_state.display_month - 1
        if calendar_state.display_month < 1 then
            calendar_state.display_month = 12
            calendar_state.display_year = calendar_state.display_year - 1
        end
    end
    reaper.ImGui_SameLine(ctx)

    local month_name = os.date("%B", os.time({ year = calendar_state.display_year, month = calendar_state.display_month, day = 1 }))
    reaper.ImGui_Text(ctx, ("%s %d"):format(month_name, calendar_state.display_year))

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_ArrowButton(ctx, "##next_month", reaper.ImGui_Dir_Right()) then
        calendar_state.display_month = calendar_state.display_month + 1
        if calendar_state.display_month > 12 then
            calendar_state.display_month = 1
            calendar_state.display_year = calendar_state.display_year + 1
        end
    end
    reaper.ImGui_EndGroup(ctx)
    reaper.ImGui_Separator(ctx)

    -- Days of the week header
    local days_of_week = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
    for i, day_name in ipairs(days_of_week) do
        reaper.ImGui_Text(ctx, day_name)
        if i < 7 then 
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Dummy(ctx, 2, 0)
            reaper.ImGui_SameLine(ctx)
        end
    end

    -- Days grid
    local first_day_wday = get_first_day_of_week(calendar_state.display_year, calendar_state.display_month)
    -- Convert to Monday-first: Monday=1, Sunday=7
    local start_offset
    if first_day_wday == 1 then -- Sunday
        start_offset = 6
    else -- Monday=2, Tuesday=3, ..., Saturday=7
        start_offset = first_day_wday - 2
    end

    local days_in_month = get_days_in_month(calendar_state.display_year, calendar_state.display_month)
    
    -- Add leading empty spaces
    for i = 1, start_offset do
        reaper.ImGui_Dummy(ctx, 28, 28)
        reaper.ImGui_SameLine(ctx)
    end

    for day = 1, days_in_month do
        local is_selected = (selected_d == day and selected_m == calendar_state.display_month and selected_y == calendar_state.display_year)

        if is_selected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.6, 1.0, 1.0))
        end

        if reaper.ImGui_Button(ctx, tostring(day), 28, 28) then
            new_date_selected = string.format("%02d-%02d-%04d", day, calendar_state.display_month, calendar_state.display_year)
        end

        if is_selected then
            reaper.ImGui_PopStyleColor(ctx)
        end

        -- Calculate current day of week (1=Monday, 7=Sunday)
        local current_day_of_week = (start_offset + day) % 7
        if current_day_of_week == 0 then current_day_of_week = 7 end
        
        if current_day_of_week ~= 7 and day < days_in_month then
            reaper.ImGui_SameLine(ctx)
        end
    end

    return new_date_selected
end

-- Function to reset the calendar display to a specific date, or today if nil.
function M.set_display_date(date_str)
    local d, m, y
    if date_str then
        d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d%d%d)$")
        if not d then
            d, m, y = date_str:match("^(%d%d)-(%d%d)-(%d%d)$")
            if y then y = tonumber(y) + 2000 end
        end
    end

    if m and y then
        calendar_state.display_month = tonumber(m)
        calendar_state.display_year = tonumber(y)
    else
        local today = os.date("*t")
        calendar_state.display_month = today.month
        calendar_state.display_year = today.year
    end
end

return M