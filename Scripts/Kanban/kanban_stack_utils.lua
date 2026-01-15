-- kanban_stack_utils.lua v1
local M = {}

-- Configuration
local ENABLE_DEBUG_OUTPUT = false

-- Stack counters (encapsulated)
local debug_style_stack_counter = 0
local debug_style_var_stack_counter = 0

function M.PushStyleColor(ctx, idx, col)
    if not ctx then return end
    if type(col) == "number" then
        reaper.ImGui_PushStyleColor(ctx, idx, col)
    else
        local fallback = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1.0)
        reaper.ImGui_PushStyleColor(ctx, idx, fallback)
    end
    debug_style_stack_counter = debug_style_stack_counter + 1
end

function M.PopStyleColor(ctx, count)
    count = count or 1
    if not ctx or count <= 0 then return end
    
    if debug_style_stack_counter >= count then
        reaper.ImGui_PopStyleColor(ctx, count)
        debug_style_stack_counter = debug_style_stack_counter - count
    elseif debug_style_stack_counter > 0 then
        reaper.ImGui_PopStyleColor(ctx, debug_style_stack_counter)
        reaper.ShowConsoleMsg("⚠️ PopStyleColor mismatch: popped " .. debug_style_stack_counter .. ", expected " .. count .. "\n")
        debug_style_stack_counter = 0
    end
end

function M.PushStyleVar(ctx, idx, val1, val2)
    if not ctx then return end
    if val2 ~= nil then
        reaper.ImGui_PushStyleVar(ctx, idx, val1, val2)
    else
        reaper.ImGui_PushStyleVar(ctx, idx, val1)
    end
    debug_style_var_stack_counter = debug_style_var_stack_counter + 1
end

function M.PopStyleVar(ctx, count)
    count = count or 1
    if not ctx or count <= 0 then return end
    
    if debug_style_var_stack_counter >= count then
        reaper.ImGui_PopStyleVar(ctx, count)
        debug_style_var_stack_counter = debug_style_var_stack_counter - count
    elseif debug_style_var_stack_counter > 0 then
        reaper.ImGui_PopStyleVar(ctx, debug_style_var_stack_counter)
        reaper.ShowConsoleMsg("⚠️ PopStyleVar mismatch: popped " .. debug_style_var_stack_counter .. ", expected " .. count .. "\n")
        debug_style_var_stack_counter = 0
    end
end

function M.Cleanup(ctx)
    if not ctx then return end
    if debug_style_stack_counter > 0 then
        reaper.ShowConsoleMsg("⚠️ Cleaning up StyleColor stack: " .. debug_style_stack_counter .. "\n")
        reaper.ImGui_PopStyleColor(ctx, debug_style_stack_counter)
        debug_style_stack_counter = 0
    end
    if debug_style_var_stack_counter > 0 then
        reaper.ShowConsoleMsg("⚠️ Cleaning up StyleVar stack: " .. debug_style_var_stack_counter .. "\n")
        reaper.ImGui_PopStyleVar(ctx, debug_style_var_stack_counter)
        debug_style_var_stack_counter = 0
    end
end

function M.PrintStackStatus(label)
    if ENABLE_DEBUG_OUTPUT then
        reaper.ShowConsoleMsg("[" .. label .. "] StyleColor: " .. debug_style_stack_counter .. ", StyleVar: " .. debug_style_var_stack_counter .. "\n")
    end
end

function M.GetStackCounts()
    return debug_style_stack_counter, debug_style_var_stack_counter
end

return M