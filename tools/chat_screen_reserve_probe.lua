-- Side = Left makes room next to the chat automatically:
--   * the chat frame's clamp insets are widened on the left by the room the
--     quick button stack needs (Blizzard's values restored exactly later);
--   * a chat too close to the left screen edge is moved just far enough,
--     out of combat only;
--   * choosing another side (or hiding the buttons) restores the insets and
--     puts the chat back where it was, unless the player moved it since.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local unpack = unpack or table.unpack

-- The stub's hooksecurefunc is a no-op; model the real post-hook for frame
-- methods so Blizzard rewriting the insets reaches Chatify's hook.
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
    assert(ok, "chat room probe: " .. label)
end

-- Clamp insets and a real position model: SetPoint stores the x offset and
-- GetLeft/GetRight follow it. Screen is 1920 wide; all scales are 1.
local BLIZZARD = { -35, 35, 38, -50 }
local CHAT_WIDTH = 400
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
    f.SetPoint = function(self, _, _, _, x) self.__x = x end
    f.ClearAllPoints = function() end
    f.GetLeft = function(self) return self.__x end
    f.GetRight = function(self) return self.__x + CHAT_WIDTH end
end
local chat = ChatFrame1
local function insets() return chat.__clamp end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end
local db = addon.db.profile
local function settle()
    for _ = 1, 5 do env.runPendingTimers(1e9) end -- follow-up layouts after a move
end
local function refresh() ns.RefreshQuickChatButtons(); settle() end
local function side(value) db.quickChatButtonSide = value; refresh() end

-- Pure maths.
local merged = ns.MergeChatClampInsets(BLIZZARD, { side = "LEFT", extent = 48 }, 5)
check("merge widens left by extent + visual delta", same(merged, { -53, 35, 38, -50 }))
check("merge never narrows", same(ns.MergeChatClampInsets(BLIZZARD, { side = "LEFT", extent = 10 }, 0), BLIZZARD))
check("merge without reserve", same(ns.MergeChatClampInsets(BLIZZARD, nil, 0), BLIZZARD))
check("AUTO side reserves nothing", ns.ResolveQuickChatPlacement({ side = "AUTO", gap = 18 }).reserve == nil)
local left = ns.ResolveQuickChatPlacement({ side = "LEFT", gap = 18, x = 6, panelWidth = 30 }).reserve
check("left extent = gap - x + width", left.side == "LEFT" and left.extent == 42)
local shift = ns.ResolveChatShift
check("shift right by the missing room", shift({ side = "LEFT", extent = 60 }, { left = 5, right = 405 }, { left = 0, right = 1920 }) == 55)
check("no shift when it fits", shift({ side = "LEFT", extent = 60 }, { left = 80, right = 480 }, { left = 0, right = 1920 }) == 0)
check("never pushes the chat off the other edge", shift({ side = "LEFT", extent = 60 }, { left = 0, right = 1900 }, { left = 0, right = 1920 }) == 20)
check("the separate option is gone", ns.defaults.profile.quickChatReserveScreenSpace == nil)

-- Right (default): nothing touched.
check("default side is not Left", (db.quickChatButtonSide or "RIGHT") ~= "LEFT")
refresh()
check("Right leaves Blizzard's insets alone", same(insets(), BLIZZARD))
check("Right leaves the chat where it is", chat.__x == 600)

-- Left with enough room: insets widened, chat not moved.
side("LEFT")
check("Left widens the left clamp inset (" .. insets()[1] .. ")", insets()[1] < BLIZZARD[1])
check("Left keeps the other insets", insets()[2] == 35 and insets()[3] == 38 and insets()[4] == -50)
check("Left with room does not move the chat", chat.__x == 600)

-- Blizzard rewrites the insets itself: adopted as base and re-applied.
chat:SetClampRectInsets(-40, 30, 38, -50)
refresh()
check("game's rewrite becomes the base", insets()[1] < -40 and insets()[2] == 30)
side("RIGHT")
check("Right restores the game's latest insets exactly", same(insets(), { -40, 30, 38, -50 }))

-- Chat at the left edge: Left moves it just far enough; Right puts it back.
chat.__x = 5
side("LEFT")
local extent = -insets()[1]
check("Left moves the chat right (left=" .. chat.__x .. ")", chat.__x > 5)
check("stack fits exactly at the screen edge", chat.__x - extent >= 0 and chat.__x - extent <= 1)
local moved = chat.__x
refresh()
check("no further moves once it fits", chat.__x == moved)
check("the original position is kept per character", type(addon.db.char.quickChatShift) == "table")
side("RIGHT")
check("Right puts the chat back where it was (left=" .. chat.__x .. ")", chat.__x == 5)
check("Right restores Blizzard's insets", same(insets(), { -40, 30, 38, -50 }))
check("the saved position is cleared", addon.db.char.quickChatShift == nil)
side("AUTO")
check("Automatic does not move the chat", chat.__x == 5)

-- Persistence: the record lives in db.char, so another side can still put
-- the chat back after a reload.
side("LEFT")
local record = addon.db.char.quickChatShift
check("record names the frame and both positions", record and record.frame == "ChatFrame1" and record.from and record.to)
side("RIGHT")
check("restored from the saved record", chat.__x == 5)

-- The player moves the chat after Chatify did: their position wins.
side("LEFT")
chat.__x = 300
refresh()
side("RIGHT")
check("a chat the player moved is not pulled back (left=" .. chat.__x .. ")", chat.__x == 300)

-- Combat: wait to move and wait to restore.
local inCombat = true
local savedLockdown = InCombatLockdown
InCombatLockdown = function() return inCombat end
chat.__x = 5
side("LEFT")
check("no move during combat", chat.__x == 5)
inCombat = false
env.fireEvent("PLAYER_REGEN_ENABLED"); settle()
check("moved after combat ends", chat.__x > 5)
inCombat = true
side("RIGHT")
check("no restore during combat", chat.__x > 5)
inCombat = false
env.fireEvent("PLAYER_REGEN_ENABLED"); settle()
check("restored after combat ends (left=" .. chat.__x .. ")", chat.__x == 5)
InCombatLockdown = savedLockdown

-- Hiding the quick buttons also puts everything back.
side("LEFT")
check("moved again for Left", chat.__x > 5)
db.quickChatButtons = false
refresh()
check("hiding the buttons puts the chat back", chat.__x == 5)
check("hiding the buttons restores the insets", same(insets(), { -40, 30, 38, -50 }))
db.quickChatButtons = true

-- A layout manager (e.g. Edit Mode) that puts the chat back after every move
-- is not fought forever: at most a few attempts.
side("RIGHT")
db.quickChatButtonSide = "LEFT"
local function movedCount()
    return (ns.Runtime and ns.Runtime.counters and ns.Runtime.counters["quickbuttons:chat-moved"]) or 0
end
local before = movedCount()
for _ = 1, 8 do
    chat.__x = 5 -- restored by "someone else"
    ns.RefreshQuickChatButtons()
    env.runPendingTimers(1e9)
end
local attempts = movedCount() - before
check("gives up after 3 attempts against a restoring layout (" .. attempts .. ")", attempts >= 1 and attempts <= 3)
chat.__x = 12
refresh()
check("a chat dragged to a new spot is handled again (left=" .. chat.__x .. ")", chat.__x > 12)

print(string.format("chat room probe: PASS (%d checks)", checks))
