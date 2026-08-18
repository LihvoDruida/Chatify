-- Copy window content probe.
--
--     lua5.1 tools/copy_probe.lua
--
-- Drives ns.OpenChatCopyWindow against a chat frame whose buffer holds a mix of
-- lines with and without a visible timestamp, then reads back what the copy window
-- was actually asked to display.
--
-- The case this exists for: lines with no timestamp of their own used to be stamped
-- with date("%H:%M:%S", time()) at the moment the window was opened, so a system
-- line printed at login appeared *after* a chat line sent minutes earlier, and the
-- invented time moved every time the window was reopened.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")

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

-- A chat frame holding exactly what the report described: addon/system lines with
-- no timestamp, followed by one real chat line that carries its own.
local BUFFER = {
    "ChatPreserver: loaded. /cpsvr help - help",
    "Total time played: 141 days, 6 hours, 36 minutes, 41 seconds",
    "[21:32:21] [Malivil] says: test",
}

local frame = _G.ChatFrame1
frame.GetNumMessages = function() return #BUFFER end
frame.GetMessageInfo = function(_, index) return BUFFER[index] end
frame.historyBuffer = nil

local captured
local editBox
local ok, err = pcall(ns.OpenChatCopyWindow, frame, 50)

editBox = _G.ChatifyCopySelectableEditBox
if editBox and type(editBox.GetText) == "function" then
    local okText, text = pcall(editBox.GetText, editBox)
    captured = okText and type(text) == "string" and text or nil
end

local failures = 0
local function check(label, condition, detail)
    print(string.format("%-52s %s%s", label, condition and "PASS" or "FAIL",
        detail and ("  " .. tostring(detail)) or ""))
    if not condition then failures = failures + 1 end
end

check("copy window opens", ok, not ok and err or nil)
check("copy window produced text", type(captured) == "string" and captured ~= "", captured)

if type(captured) == "string" then
    for _, body in ipairs({ "ChatPreserver", "Total time played" }) do
        local found
        for chunk in captured:gmatch("[^\n]+") do
            if chunk:find(body, 1, true) then found = chunk end
        end
        check("no invented timestamp: " .. body,
            found ~= nil and not found:match("^%[%d%d?:%d%d"), found)
    end

    local chatLine
    for chunk in captured:gmatch("[^\n]+") do
        if chunk:find("says: test", 1, true) then chatLine = chunk end
    end
    check("a real timestamp is kept",
        chatLine ~= nil and chatLine:find("21:32:21", 1, true) ~= nil, chatLine)

    check("no placeholder timestamps",
        captured:find("--:--", 1, true) == nil)
end

-- Live capture still stamps with the arrival time; only history reads abstain.
local id = ns.SaveToCache("a message arriving now", "Bob")
check("live capture still records a time", id ~= nil)

print(failures == 0 and "\ncopy probe: PASS"
    or ("\ncopy probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
