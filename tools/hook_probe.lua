-- Regression probe for Chatify's hooks on public Blizzard chat functions.
--
--     lua5.1 tools/hook_probe.lua
--
-- Any addon can call FCF_* directly, so a hook that trusts its arguments will be
-- handed whatever that addon passed. This drives the hooks with the argument shapes
-- real callers use and asserts none of them raises.
--
-- The case that shipped broken in 0.11.39 and earlier:
--   FCF_SetChatWindowFontSize(self, chatFrame, fontSize)
-- was hooked as function(chatFrame), so Prat's Font module object arrived where a
-- chat frame was expected and ns.GetEditBox died on it.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")

local namedHooks = {}
_G.hooksecurefunc = function(a, b)
    if type(a) == "string" and type(b) == "function" then
        namedHooks[a] = namedHooks[a] or {}
        table.insert(namedHooks[a], b)
    end
    return true
end

_G.FCF_SetChatWindowFontSize = function() end

local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end

local addon = LibStub("AceAddon-3.0"):GetAddon("Chatify")
pcall(addon.OnInitialize, addon)
pcall(addon.OnEnable, addon)
for _, mod in pairs(addon.modules or {}) do
    pcall(mod.OnInitialize, mod)
    pcall(mod.OnEnable, mod)
end

local failures = 0
local function check(label, ok, detail)
    print(string.format("%-52s %s%s", label, ok and "PASS" or "FAIL",
        detail and ("  " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
end

local chatFrame = _G.ChatFrame1
-- Not a frame: this is the shape of an Ace3 module object, which is what Prat
-- passes as `self`.
local foreignModule = { moduleName = "Font", name = "Prat_Font", db = {}, hooks = {} }

check("ns.IsChatFrame rejects a non-frame table",
    ns.IsChatFrame(foreignModule) == false)
check("ns.IsChatFrame accepts a real chat frame",
    ns.IsChatFrame(chatFrame) == true)
check("ns.GetEditBox survives a non-frame table",
    pcall(ns.GetEditBox, foreignModule))

local fontHooks = namedHooks["FCF_SetChatWindowFontSize"] or {}
check("FCF_SetChatWindowFontSize is hooked", #fontHooks > 0, #fontHooks)

for i = 1, #fontHooks do
    local fn = fontHooks[i]

    -- Prat: FCF_SetChatWindowFontSize(module, chatFrame, size)
    local ok, err = pcall(fn, foreignModule, chatFrame, 14)
    check("hook survives (foreign module, chatFrame, size)", ok, not ok and err or nil)

    -- Blizzard's own dropdown: FCF_SetChatWindowFontSize(button, chatFrame, size)
    local ok2, err2 = pcall(fn, env.newFrame("Button"), chatFrame, 16)
    check("hook survives (dropdown button, chatFrame, size)", ok2, not ok2 and err2 or nil)

    -- Defensive: a caller that passes nothing useful at all.
    local ok3, err3 = pcall(fn, nil, nil, nil)
    check("hook survives (nil, nil, nil)", ok3, not ok3 and err3 or nil)
end

print(failures == 0 and "\nhook probe: PASS"
    or ("\nhook probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
