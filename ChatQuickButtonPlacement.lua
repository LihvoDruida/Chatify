-- Pure placement helper. No protected Blizzard frames are altered by this code.
-- Kept independent of UI objects so the layout can be regression-tested on all clients.
local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local function finite(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function clamp(value, low, high, fallback)
    return floor(max(low, min(high, finite(value, fallback))) + 0.5)
end

-- rects share one coordinate space (GetLeft/GetRight/GetTop/GetBottom).
-- Only consider the native sidebar if it is outside and vertically adjacent
-- to this chat frame. An above-chat or unrelated sidebar must not push the bar.
local function nativeGap(side, rect, sidebar, tolerance)
    if not rect or not sidebar then return 0 end
    local left, right = rect.left, rect.right
    local sLeft, sRight = sidebar.left, sidebar.right
    if type(left) ~= "number" or type(right) ~= "number"
        or type(sLeft) ~= "number" or type(sRight) ~= "number" then
        return 0
    end
    if type(sidebar.top) == "number" and type(sidebar.bottom) == "number"
        and type(rect.top) == "number" and type(rect.bottom) == "number"
        and (sidebar.bottom >= rect.top or sidebar.top <= rect.bottom) then
        return 0
    end
    tolerance = type(tolerance) == "number" and tolerance or 12
    if side == "LEFT" and sLeft < left and sRight >= left - tolerance then
        return max(0, left - sLeft + 4)
    elseif side == "RIGHT" and sRight > right and sLeft <= right + tolerance then
        return max(0, sRight - right + 4)
    end
    return 0
end

-- side RIGHT/LEFT means outside the chat; AUTO chooses the larger safe margin.
-- Alignment TOP/CENTER/BOTTOM follows the frame without saving screen coords.
function ns.ResolveQuickChatPlacement(opts)
    opts = type(opts) == "table" and opts or {}
    local requested = opts.side
    if requested ~= "LEFT" and requested ~= "AUTO" then requested = "RIGHT" end
    local vertical = opts.align
    if vertical ~= "TOP" and vertical ~= "CENTER" then vertical = "BOTTOM" end
    local baseGap = clamp(opts.gap, 0, 100, 18)
    local y = clamp(opts.y, -100, 100, -4)
    local rect, sidebar, root = opts.chat, opts.sidebar, opts.screen
    local avoid = opts.avoidNative ~= false
    local function gapFor(side)
        local reserve = 0
        if avoid then
            reserve = nativeGap(side, rect, sidebar)
            if type(opts.extraObstacles) == "table" then
                for _, obstacle in ipairs(opts.extraObstacles) do
                    reserve = max(reserve, nativeGap(side, rect, obstacle, 160))
                end
            end
        end
        return max(baseGap, reserve)
    end
    local side = requested
    if requested == "AUTO" then
        side = "RIGHT"
        if rect and root and type(root.left) == "number" and type(root.right) == "number"
            and type(rect.left) == "number" and type(rect.right) == "number" then
            local panelWidth = max(1, finite(opts.panelWidth, 30))
            local freeLeft = rect.left - root.left - gapFor("LEFT") - panelWidth
            local freeRight = root.right - rect.right - gapFor("RIGHT") - panelWidth
            -- Prefer right when both sides fit equally, preserving legacy visuals.
            if freeLeft > freeRight then side = "LEFT" end
        end
    end
    return { side = side, align = vertical, gap = gapFor(side), y = y }
end
