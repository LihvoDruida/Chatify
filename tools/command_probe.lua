-- Every registered slash command is actually run.
--
--     lua5.1 tools/command_probe.lua                    (retail, secret values)
--     CHATIFY_STUB_MODE=classic lua5.1 tools/command_probe.lua
--
-- The bug this exists for, reported against 0.11.53:
--
--   Interface/AddOns/Chatify/Settings.lua:2207: attempt to call a nil value
--   (*temporary)="Chat taint report:"
--
-- Settings.lua declares its translator as `local T`. Four diagnostic printers called
-- `L(...)` instead, which is a global, which is nil. The oldest of them shipped in
-- 0.11.49 and had never once produced output; /chatifytrace has been dead since it
-- was written, including on both occasions it was recommended as the way to find out
-- who owns frame.AddMessage.
--
-- Nothing in CI touched it. The symbol check tracks ns.* references and L is not one.
-- The static audit checks profile defaults. Both load tests import every file, which
-- proves the chunks compile and their top-level code runs, and a typo inside a
-- function body survives that untouched. No probe had ever CALLED a command handler.
--
-- So the assertion here is deliberately shallow and broad rather than deep: invoke
-- every registered command with plausible input and require that it does not raise.
-- A wrong upvalue, a renamed helper, a nil method - the whole family fails the same
-- way and this catches all of it. Checking what the commands print is a different job
-- and belongs in the probes for the features themselves.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "retail"
env.install(mode)

local ns, addonName = {}, "Chatify"
for line in assert(io.open("Chatify.toc")):lines() do
    line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))(addonName, ns)
    end
end

local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)

-- RegisterChatCommand is AceConsole's. Recording the handler names as they are
-- registered means the probe follows the addon rather than a list that has to be kept
-- in step with it: a command added later is covered without touching this file.
local registered = {}
addon.RegisterChatCommand = function(self, command, handler)
    registered[#registered + 1] = { command = command, handler = handler }
end

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

print("mode                       :", mode)
check("commands were registered", #registered > 0, #registered .. " found")

-- Arguments a user might type. Every command is run with each: a bare invocation is
-- the common case, and the others catch handlers that assume an argument is present.
local INPUTS = { "", "status", "1 2" }

for i = 1, #registered do
    local entry = registered[i]
    local handler = entry.handler
    local fn = handler

    if type(handler) == "string" then
        fn = addon[handler]
    end

    if type(fn) ~= "function" then
        check("/" .. entry.command .. " has a handler", false,
            "handler " .. tostring(handler) .. " is " .. type(fn))
    else
        local worstErr
        for j = 1, #INPUTS do
            local ok, err = pcall(fn, addon, INPUTS[j])
            if not ok then
                worstErr = worstErr or err
            end
        end
        check("/" .. entry.command .. " runs without raising", worstErr == nil, worstErr)
    end
end

-- The specific shape of the 0.11.53 report: a printer whose first statement calls the
-- translator. If the translator is bound to the wrong name the command dies before
-- printing anything, so "did any output reach the frame" is the sharper question than
-- "did it not raise".
local frame = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
if frame then
    for _, name in ipairs({ "PrintChatTaintReport", "PrintChatEntryTrace",
                            "PrintSavedVariablesReport" }) do
        local fn = addon[name]
        if type(fn) == "function" then
            frame.__last = nil
            local ok, err = pcall(fn, addon, "")
            local produced = ok and frame.__last ~= nil
            check(name .. " produces output", produced,
                (not produced) and (ok and "printed nothing" or tostring(err)) or nil)
        else
            check(name .. " exists", false, "missing")
        end
    end
end

print(failures == 0 and "\ncommand probe: PASS"
    or ("\ncommand probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
