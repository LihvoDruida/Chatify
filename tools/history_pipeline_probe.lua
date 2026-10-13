-- R1-04: buffered post-render History, removal, metadata and per-frame fallback.
-- This is a model, NOT a test of Blizzard's taint/secret restrictions.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local hooks = 0
_G.hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return true end
    if method ~= "AddMessage" or type(target[method]) ~= "function" then error("bad hook") end
    local old = target[method]
    target[method] = function(self, ...)
        local results = { old(self, ...) }
        callback(self, ...)
        return (unpack or table.unpack)(results)
    end
    hooks = hooks + 1
end
local frames = { _G.ChatFrame1, _G.ChatFrame3, _G.ChatFrame4 }
for _, frame in ipairs(frames) do
    frame.buffer = {}
    frame.AddMessage = function(self, text, r, g, b, ...)
        self.buffer[#self.buffer + 1] = { text = text, meta = { ... } }
    end
    frame.RemoveMessagesByPredicate = function(self, pred)
        local removed = 0
        for i = #self.buffer, 1, -1 do
            local entry = self.buffer[i]
            if pred(entry.text, 1, 1, 1, (unpack or table.unpack)(entry.meta)) then
                table.remove(self.buffer, i)
                removed = removed + 1
            end
        end
        return removed > 0
    end
    frame.TransformMessages = function(self, pred, fn)
        for _, entry in ipairs(self.buffer) do
            if pred(entry.text, 1, 1, 1, (unpack or table.unpack)(entry.meta)) then
                entry.text = fn(entry.text, 1, 1, 1, (unpack or table.unpack)(entry.meta))
            end
        end
        return true
    end
end
-- Frame4 has no hookable AddMessage; only it needs event fallback.
_G.ChatFrame4.AddMessage = false
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))
local db = assert(addon.db.profile)
db.enableHistory = true
-- Eliminate external filters from this dedicated post-render model.
ns.AreMessageFiltersInstalled = function() return false end
ns.ProcessSpamMessage = function(_, message) return message == "block-me" end
ns.ApplyChannelLabels = function(text) return "PRESENTED:" .. text end
assert(pcall(addon.OnEnable, addon))
for _, module in pairs(addon.modules or {}) do
    if module.OnInitialize then assert(pcall(module.OnInitialize, module)) end
    if module.OnEnable then assert(pcall(module.OnEnable, module)) end
end
local history = assert(addon.modules.History)
local f1, f3, f4 = (unpack or table.unpack)(frames)
local function entries(frame) return ns.GetChatifyHistoryEntriesForFrame(frame, 1000) or {} end
local function check(ok, reason) if not ok then error("history pipeline: " .. reason) end end
local function fire(frame, message, shifted)
    local args = { message, "Seller-Realm", nil, "General" }
    if shifted then
        frame:AddMessage(message, 1,1,1, nil, 0, 0, "padding", 12, "CHAT_MSG_CHANNEL", args)
    else
        frame:AddMessage(message, 1,1,1, nil, 0, 0, "CHAT_MSG_CHANNEL", args)
    end
end
local base1, base3, base4 = #entries(f1), #entries(f3), #entries(f4)
fire(f1, "hello", true)
check(#entries(f1) == base1 + 1, "shifted metadata not captured")
check(entries(f1)[#entries(f1)] == "PRESENTED:hello", "history did not save final presentation")
check(f1.buffer[1].text == "PRESENTED:hello", "buffer not transformed")
check(#entries(f3) == base3, "frame3 received frame1 rendered line")
fire(f1, "block-me")
check(#f1.buffer == 1 and #entries(f1) == base1 + 1, "removed spam remained in buffer/history")
fire(f3, "block-me")
check(#f3.buffer == 0 and #entries(f3) == base3, "frame3 spam not removed")
-- If the removal operation fails, history must match the visible buffer.
f1.RemoveMessagesByPredicate = function() return false end
fire(f1, "block-me")
check(#f1.buffer == 2 and #entries(f1) == base1 + 2, "failed removal silently discarded history")
-- Log-only/no-block: retain a final presented line in both places.
ns.ProcessSpamMessage = function() return false end
fire(f1, "log-only")
check(#entries(f1) == base1 + 3 and entries(f1)[#entries(f1)] == "PRESENTED:log-only", "allowed line mismatch")
check(f1.buffer[#f1.buffer].text == "PRESENTED:log-only", "allowed buffer mismatch")
-- A failed hook on frame4 must not cause the event path to duplicate frame1.
local before1, before3 = #entries(f1), #entries(f3)
f4:RegisterEvent("CHAT_MSG_GUILD")
history:RefreshFrameCapture()
history:OnChatEvent("CHAT_MSG_GUILD", "fallback", "Fallback")
check(#entries(f1) == before1 and #entries(f3) == before3, "per-frame fallback duplicated hooked frames")
check(#entries(f4) == base4 + 1, "fallback missed unhookable frame")
local currentHooks = hooks
history:RefreshFrameCapture()
check(hooks == currentHooks, "refresh stacked existing hooks")
fire(f1, "identical")
fire(f1, "identical")
check(#entries(f1) == before1 + 2, "two legitimate identical messages collapsed")
print("history pipeline: PASS")
