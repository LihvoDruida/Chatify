-- "Reserve Screen Space Next to Chat": Chatify widens the chat frame's clamp
-- insets (never its position) so the game keeps room for the quick button
-- stack, and restores Blizzard's insets exactly when no longer wanted.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
-- The stub's hooksecurefunc is a no-op; model the real post-hook for frame
-- methods so Blizzard rewriting the insets reaches Chatify's hook.
local unpack = unpack or table.unpack
local stubHook = hooksecurefunc
hooksecurefunc = function(target, key, fn)
    if type(target) == "table" and type(key) == "string" and type(fn) == "function"
        and type(target[key]) == "function" then
        local original = target[key]
        target[key] = function(...)
            local results = { original(...) }
            fn(...)
            return unpack(results)
        end
        return
    end
    return stubHook(target, key, fn)
end
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))

local checks = 0
local function check(label, ok)
    checks = checks + 1
    assert(ok, "chat screen reserve probe: " .. label)
end

-- Clamp insets and a real position model: SetPoint stores the x offset and
-- GetLeft/GetRight follow it. Screen is 1920 wide; all scales are 1.
local BLIZZARD = { -35, 35, 38, -50 }
local CHAT_WIDTH = 400
local moves = 0
UIParent.GetLeft = function() return 0 end
UIParent.GetRight = function() return 1920 end
UIParent.GetEffectiveScale = function() return 1 end
for i = 1, 10 do
    local f = _G["ChatFrame" .. i]
    f.__clamp = { unpack(BLIZZARD) }
    f.__x = 600
    f.GetClampRectInsets = function(self) return unpack(self.__clamp) end
    f.SetClampRectInsets = function(self, l, r, t, b) self.__clamp = { l, r, t, b } end
    f.GetEffectiveScale = function() return 1 end
    f.GetNumPoints = function() return 1 end
    f.GetPoint = function(self) return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.__x, 40 end
    f.SetPoint = function(self, _, _, _, x) moves = moves + 1; if not self.__pinned then self.__x = x end end
    f.ClearAllPoints = function() end
    f.GetLeft = function(self) return self.__x end
    f.GetRight = function(self) return self.__x + CHAT_WIDTH end
end
local chat = ChatFrame1
local function insets(frame) return (frame or chat).__clamp end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end

local db = addon.db.profile
local function refresh()
    ns.RefreshQuickChatButtons()
    for _ = 1, 5 do env.runPendingTimers(1e9) end -- follow-up layouts after a shift
end

-- Pure merge: only widens the chosen side, keeps everything else.
local merged = ns.MergeChatClampInsets(BLIZZARD, { side = "LEFT", extent = 48 }, 5)
check("merge widens left by extent + visual delta", same(merged, { -53, 35, 38, -50 }))
check("merge never narrows", same(ns.MergeChatClampInsets(BLIZZARD, { side = "LEFT", extent = 10 }, 0), BLIZZARD))
check("merge right side", same(ns.MergeChatClampInsets(BLIZZARD, { side = "RIGHT", extent = 60 }, 0), { -35, 60, 38, -50 }))
check("merge without reserve", same(ns.MergeChatClampInsets(BLIZZARD, nil, 0), BLIZZARD))
check("AUTO side reserves nothing", ns.ResolveQuickChatPlacement({ side = "AUTO", gap = 18 }).reserve == nil)
local left = ns.ResolveQuickChatPlacement({ side = "LEFT", gap = 18, x = 6, panelWidth = 30 }).reserve
check("left extent = gap - x + width", left.side == "LEFT" and left.extent == 42)
local right = ns.ResolveQuickChatPlacement({ side = "RIGHT", gap = 18, x = 6, panelWidth = 30 }).reserve
check("right extent = gap + x + width", right.side == "RIGHT" and right.extent == 54)

-- Off by default.
check("option is off by default", db.quickChatReserveScreenSpace == false)
db.quickChatButtonSide = "LEFT"
refresh()
check("default leaves Blizzard insets untouched", same(insets(), BLIZZARD))

-- Left: reserve on the left only.
db.quickChatReserveScreenSpace = true
refresh()
local leftInsets = { unpack(insets()) }
check("left reserve widens the left inset (" .. leftInsets[1] .. ")", leftInsets[1] < BLIZZARD[1])
check("left reserve keeps right/top/bottom", leftInsets[2] == 35 and leftInsets[3] == 38 and leftInsets[4] == -50)

-- Right: left restored, right widened.
db.quickChatButtonSide = "RIGHT"
refresh()
check("switching to right restores the left inset", insets()[1] == BLIZZARD[1])
check("right reserve widens the right inset (" .. insets()[2] .. ")", insets()[2] > BLIZZARD[2])

-- Blizzard rewrites the insets itself: adopt them as the new base.
chat:SetClampRectInsets(-40, 30, 38, -50)
refresh()
check("Blizzard's rewrite becomes the base and the reserve is re-applied",
    insets()[1] == -40 and insets()[2] > 30)

-- Automatic side: nothing reserved, base restored exactly.
db.quickChatButtonSide = "AUTO"
refresh()
check("Automatic side restores Blizzard's insets", same(insets(), { -40, 30, 38, -50 }))

-- Option off restores; quick buttons off restores.
db.quickChatButtonSide = "LEFT"
refresh()
check("reserve back on for left", insets()[1] < -40)
db.quickChatReserveScreenSpace = false
refresh()
check("turning the option off restores Blizzard's insets", same(insets(), { -40, 30, 38, -50 }))
db.quickChatReserveScreenSpace = true
refresh()
db.quickChatButtons = false
refresh()
check("hiding the quick buttons restores Blizzard's insets", same(insets(), { -40, 30, 38, -50 }))
db.quickChatButtons = true
refresh()

check("no move while the stack already fits (" .. moves .. " moves)", moves == 0)

-- Pure shift maths.
local shift = ns.ResolveChatShift
check("shift right by the missing room", shift({ side = "LEFT", extent = 60 }, { left = 5, right = 405 }, { left = 0, right = 1920 }) == 55)
check("no shift when it fits", shift({ side = "LEFT", extent = 60 }, { left = 80, right = 480 }, { left = 0, right = 1920 }) == 0)
check("shift left for the right side", shift({ side = "RIGHT", extent = 60 }, { left = 1500, right = 1900 }, { left = 0, right = 1920 }) == -40)
check("never pushes the chat off the other edge", shift({ side = "LEFT", extent = 60 }, { left = 0, right = 1900 }, { left = 0, right = 1920 }) == 20)

-- Chat at the left screen edge: Chatify moves it just far enough.
db.quickChatButtonSide = "LEFT"
db.quickChatReserveScreenSpace = true
chat.__x = 5
moves = 0
refresh()
local extent = -insets()[1]
check("chat moved right (left=" .. chat.__x .. ")", chat.__x > 5)
local stackLeft = chat.__x - extent
check("stack now fits exactly at the screen edge (stack left=" .. stackLeft .. ")", stackLeft >= 0 and stackLeft <= 1)
local after = chat.__x
refresh()
check("no further moves once it fits", chat.__x == after)

-- Option off: never moves.
db.quickChatReserveScreenSpace = false
chat.__x = 5
refresh()
check("option off leaves the chat where it is", chat.__x == 5)

-- In combat: wait, then move when combat ends.
db.quickChatReserveScreenSpace = true
local inCombat = true
local savedLockdown = InCombatLockdown
InCombatLockdown = function() return inCombat end
refresh()
check("no move during combat", chat.__x == 5)
inCombat = false
env.fireEvent("PLAYER_REGEN_ENABLED")
for _ = 1, 5 do env.runPendingTimers(1e9) end
check("moved after combat ends (left=" .. chat.__x .. ")", chat.__x > 5)
InCombatLockdown = savedLockdown

-- Right side at the right screen edge: moves left.
db.quickChatButtonSide = "RIGHT"
chat.__x = 1920 - CHAT_WIDTH - 3
refresh()
check("right side moves the chat left (right=" .. (chat.__x + CHAT_WIDTH) .. ")", chat.__x + CHAT_WIDTH < 1917)
check("right stack fits", chat.__x + CHAT_WIDTH + insets()[2] <= 1921)

-- A layout manager (e.g. Edit Mode) that puts the chat back after every move
-- is not fought forever: at most a few attempts.
db.quickChatButtonSide = "LEFT"
local function moved()
    return (ns.Runtime and ns.Runtime.counters and ns.Runtime.counters["quickbuttons:chat-moved"]) or 0
end
local before = moved()
for _ = 1, 8 do
    chat.__x = 5 -- restored by "someone else"
    ns.RefreshQuickChatButtons()
    env.runPendingTimers(1e9)
end
local attempts = moved() - before
check("gives up after 3 attempts against a restoring layout (" .. attempts .. ")", attempts >= 1 and attempts <= 3)
-- The player dragging the chat to a new spot is honoured again.
chat.__x = 12
ns.RefreshQuickChatButtons()
for _ = 1, 5 do env.runPendingTimers(1e9) end
check("a chat dragged to a new spot is moved again (left=" .. chat.__x .. ")", chat.__x > 12)

print(string.format("chat screen reserve probe: PASS (%d checks)", checks))
