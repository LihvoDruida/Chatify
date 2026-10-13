-- Models hooksecurefunc *wrapping* the concrete AddMessage method.
-- This model is not proof of WoW secure/taint behavior.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local installed = 0
_G.hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return true end
    if type(target) ~= "table" or type(target[method]) ~= "function" or type(callback) ~= "function" then error("invalid hook") end
    local old = target[method]
    target[method] = function(self, ...)
        local result = { old(self, ...) }
        callback(self, ...)
        return (table.unpack or unpack)(result)
    end
    if method == "AddMessage" then installed = installed + 1 end
    return true
end
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))
assert(pcall(addon.OnEnable, addon))
for _, mod in pairs(addon.modules or {}) do
    if mod.OnInitialize then assert(pcall(mod.OnInitialize, mod)) end
    if mod.OnEnable then assert(pcall(mod.OnEnable, mod)) end
end
local frame = _G.ChatFrame1
local history = assert(addon.modules.History)
local transforms = assert(ns.GetChatTransformStats)
local function count() return #(ns.GetChatifyHistoryEntriesForFrame(frame, 250) or {}) end
local function check(ok, reason) if not ok then error("frame hook lifecycle: " .. reason) end end
local function fire(text)
    frame:AddMessage(text, 1, 1, 1, nil, 0, 0, "CHAT_MSG_GUILD", { text, "tester" })
end
local function refresh()
    history:RefreshFrameCapture()
    ns.RefreshSecureChatTransforms()
end
local preHooks, before = installed, count()
for i = 1, 100 do refresh() end
check(installed == preHooks, "100 refresh cycles duplicated hooks")
fire("first")
check(count() == before + 1, "first line was not captured")
local initialObserved = transforms().observed
local previous = frame.AddMessage
frame.AddMessage = function(self, ...) return previous(self, ...) end
refresh()
local afterRehook = installed
check(afterRehook > preHooks, "replacement wrapping old method not detected")
fire("second")
check(count() == before + 2, "calling previous method duplicated or lost History")
check(transforms().observed == initialObserved + 1, "transforms double callback after wrapper")
local replacement = function(self, text) self.__last = text end
frame.AddMessage = replacement
refresh()
check(installed > afterRehook, "full AddMessage replacement not rehooked")
fire("third")
check(count() == before + 3, "full replacement not captured")
check(transforms().observed == initialObserved + 2, "transforms missed full replacement")
-- Legitimate identical lines must not be collapsed simply because text matches.
local identicalBefore = count()
fire("identical")
fire("identical")
check(count() == identicalBefore + 2, "two real identical lines were incorrectly collapsed")
local finalHooks = installed
for i = 1, 100 do refresh() end
check(installed == finalHooks, "rehook not idempotent")
if history.OnDisable then history:OnDisable() end
fire("disabled")
check(count() == before + 5, "History wrote while disabled")
history:OnEnable()
fire("re-enabled")
check(count() == before + 6, "History not restored after OnEnable")
print("frame hook lifecycle: PASS")
