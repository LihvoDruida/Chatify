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
    local x = clamp(opts.x, -100, 100, 0)
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
    -- x is a screen-direction nudge (positive = right) applied after the
    -- outward gap and native clearance.
    local result = { side = side, align = vertical, gap = gapFor(side), x = x, y = y, mode = "exterior" }
    if opts.keepOnScreen == false then return result end
    return ns.KeepQuickChatPlacementOnScreen(result, opts, gapFor)
end

local function isRect(r)
    return type(r) == "table" and type(r.left) == "number" and type(r.right) == "number"
        and type(r.top) == "number" and type(r.bottom) == "number"
end

-- Highest vertical gap of at least `required` units inside one column span.
-- `blocks` are rectangles (native buttons, Chatify's own toolbar) to avoid.
local function findColumnGap(top, bottom, left, right, rects, required, padding)
    if top - bottom < required + padding * 2 then return nil end
    local blocks = {}
    for _, rect in ipairs(type(rects) == "table" and rects or {}) do
        if isRect(rect) and rect.top > rect.bottom
            and rect.left < right and rect.right > left
            and rect.bottom < top and rect.top > bottom then
            blocks[#blocks + 1] = { top = min(rect.top, top), bottom = max(rect.bottom, bottom) }
        end
    end
    table.sort(blocks, function(a, b)
        if a.top == b.top then return a.bottom > b.bottom end
        return a.top > b.top
    end)
    local cursor = top
    for _, block in ipairs(blocks) do
        if cursor - block.top >= required + padding * 2 then return cursor - padding end
        cursor = min(cursor, block.bottom)
    end
    if cursor - bottom >= required + padding * 2 then return cursor - padding end
    return nil
end

-- Horizontal span of an exterior dock for a given side/gap/x.
local function exteriorSpan(side, rect, gap, x, width)
    if side == "LEFT" then
        local right = rect.left - gap + x
        return right - width, right
    end
    local left = rect.right + gap + x
    return left, left + width
end

-- A dock that leaves the screen is invisible and useless. When the requested
-- side does not fit, fall back in this order, never moving native controls:
--   1. a free vertical gap inside Blizzard's chat-button column on that side;
--   2. the opposite chat edge, when it fits there;
--   3. the requested side, nudged back just inside the screen edge.
function ns.KeepQuickChatPlacementOnScreen(result, opts, gapFor)
    local rect, root = opts.chat, opts.screen
    if not isRect(rect) or type(root) ~= "table"
        or type(root.left) ~= "number" or type(root.right) ~= "number" then
        return result
    end
    local width = max(1, finite(opts.panelWidth, 30))
    local function fits(side, gap, x)
        local left, right = exteriorSpan(side, rect, gap, x, width)
        return left >= root.left - 0.5 and right <= root.right + 0.5
    end
    if fits(result.side, result.gap, result.x) then return result end

    local sidebar = opts.sidebar
    local height = finite(opts.panelHeight, 0)
    if isRect(sidebar) and height > 0 and sidebar.right > sidebar.left then
        local centerX = (sidebar.left + sidebar.right) / 2
        local chatCenter = (rect.left + rect.right) / 2
        local onSide = (result.side == "LEFT" and centerX < chatCenter)
            or (result.side == "RIGHT" and centerX > chatCenter)
        local colLeft, colRight = centerX - width / 2, centerX + width / 2
        if onSide and colLeft >= root.left - 0.5 and colRight <= root.right + 0.5 then
            local top = findColumnGap(min(rect.top, sidebar.top), rect.bottom, colLeft, colRight,
                opts.columnObstacles, height, 3)
            if top then
                result.mode = "native-column"
                result.slot = { x = centerX, top = top, width = width, height = height }
                return result
            end
        end
    end

    local other = result.side == "LEFT" and "RIGHT" or "LEFT"
    local otherGap = gapFor and gapFor(other) or result.gap
    if fits(other, otherGap, 0) then
        result.requestedSide = result.side
        result.side, result.gap, result.x = other, otherGap, 0
        result.mode = "flipped"
        return result
    end

    local left, right = exteriorSpan(result.side, rect, result.gap, result.x, width)
    if left < root.left then
        result.x = result.x + (root.left - left)
    elseif right > root.right then
        result.x = result.x - (right - root.right)
    end
    result.x = floor(result.x + 0.5)
    result.mode = "clamped"
    return result
end

-- Find an empty vertical section in Blizzard's existing chat-button column.
-- Native buttons are represented only by their screen rectangles: they are
-- never moved, hidden, resized, reparented, or used as parents for our buttons.
-- Coordinates are UI units in the same space (not physical screen pixels).
function ns.ResolveNativeSidebarSlot(opts)
    opts = type(opts) == "table" and opts or {}
    local sidebar, chat = opts.sidebar, opts.chat
    if type(sidebar) ~= "table" or type(chat) ~= "table" then return nil end
    if type(sidebar.left) ~= "number" or type(sidebar.right) ~= "number"
        or type(sidebar.top) ~= "number" or type(chat.top) ~= "number"
        or type(chat.bottom) ~= "number" or sidebar.right <= sidebar.left
        or chat.top <= chat.bottom then
        return nil
    end

    local width = clamp(opts.width, 16, 40, 26)
    local height = clamp(opts.height, 18, 50, 28)
    local count = clamp(opts.count, 1, 8, 3)
    local spacing = clamp(opts.spacing, 1, 10, 2)
    local padding = clamp(opts.padding, 1, 12, 3)
    local required = count * height + (count - 1) * spacing
    local centerX = (sidebar.left + sidebar.right) / 2
    local left, right = centerX - width / 2, centerX + width / 2
    -- ChatFrame.ButtonFrame may cover only part of the chat. Use the actual
    -- chat height, so native controls at the very bottom are still considered.
    local top, bottom = min(chat.top, sidebar.top), chat.bottom
    if top - bottom < required + (padding * 2) then return nil end

    local blocks = {}
    for _, rect in ipairs(type(opts.buttons) == "table" and opts.buttons or {}) do
        if type(rect) == "table" and type(rect.left) == "number"
            and type(rect.right) == "number" and type(rect.top) == "number"
            and type(rect.bottom) == "number" and rect.top > rect.bottom
            and rect.left < right and rect.right > left
            and rect.bottom < top and rect.top > bottom then
            blocks[#blocks + 1] = {
                top = min(rect.top, top),
                bottom = max(rect.bottom, bottom),
            }
        end
    end
    table.sort(blocks, function(a, b)
        if a.top == b.top then return a.bottom > b.bottom end
        return a.top > b.top
    end)

    -- Prefer the highest gap large enough for the entire column. In a stock
    -- UI this usually lies below the chat/voice buttons and above scroll-down.
    local cursor = top
    local function tryGap(nextTop)
        if cursor - nextTop >= required + padding * 2 then
            return {
                x = centerX,
                top = cursor - padding,
                width = width,
                height = required,
                placement = "inline-native-column",
            }
        end
        return nil
    end
    for _, block in ipairs(blocks) do
        local slot = tryGap(block.top)
        if slot then return slot end
        cursor = min(cursor, block.bottom)
    end
    return tryGap(bottom)
end
