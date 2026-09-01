-- Regression probe for the one taint vector that cannot be withdrawn.
--
--     lua5.1 tools/render_taint_probe.lua                    (retail, secret values)
--     CHATIFY_STUB_MODE=classic lua5.1 tools/render_taint_probe.lua
--
-- The bug this exists for, reported against 0.11.49:
--
--   attempt to perform string conversion on a secret string value
--   (execution tainted by 'Chatify')
--   ChatFrameUtil.lua:567: in function 'SetLastTellTarget'
--   ChatFrameOverrides.lua:672: in function 'MessageEventHandler'
--
-- Blizzard's MessageEventHandler calls self:AddMessage at line 667 and
-- ChatFrameUtil.SetLastTellTarget at line 672, and SetLastTellTarget does
-- strupper(target) on a whisper sender that is a secret string inside instanced
-- content. Chatify's channel-label / render-time-mention wrapper replaced
-- frame.AddMessage, so reading that field at 667 tainted the execution and the
-- strupper five lines later raised.
--
-- Removing the wrapper afterwards does not help: restoring the original is itself a
-- write from tainted code, so the field stays tainted until /reload. The invariant
-- is therefore about the WRITE, not about the wrapper's behaviour: on a
-- secret-value build the field must never be written at all, unless the user
-- explicitly chose "Maximum features" and accepted the consequence.
--
-- Run against 0.11.49 the "retail default" case below fails.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "retail"
env.install(mode)

-- Blizzard's own AddMessage, recorded before a single line of Chatify is loaded.
-- Every assertion below is "is this still the function the client installed".
local pristine = {}
for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
    local frame = _G["ChatFrame" .. i]
    if frame then
        pristine[i] = frame.AddMessage
    end
end

local ns, addonName = {}, "Chatify"
for line in assert(io.open("Chatify.toc")):lines() do
    line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))(addonName, ns)
    end
end

local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
pcall(addon.OnInitialize, addon)
pcall(addon.OnEnable, addon)
for _, mod in pairs(addon.modules or {}) do
    pcall(mod.OnInitialize, mod)
    pcall(mod.OnEnable, mod)
end

local db = addon.db and addon.db.profile
ns.db = db

local failures = 0
local function check(label, ok, detail)
    print(string.format("%-56s %s%s", label, ok and "PASS" or "FAIL",
        detail and ("  " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
end

-- Which frames Chatify has taken over. Named so a failure says which window.
local function replacedFrames()
    local out = {}
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and pristine[i] and frame.AddMessage ~= pristine[i] then
            out[#out + 1] = "ChatFrame" .. i
        end
    end
    return out
end

local function applyVisuals()
    if type(ns.ApplyVisuals) == "function" then
        pcall(ns.ApplyVisuals)
    end
    if type(ns.RefreshChannelLabelHook) == "function" then
        pcall(ns.RefreshChannelLabelHook)
    end
end

-- The configuration from the report: a Mention Manager rule, plus short channel
-- names. Either one alone is enough to arm the wrapper, so both are on.
local function armEverything()
    db.enableMentionManager = true
    db.shortChannels = true
    db.mentionRules = { {
        text = "Malivil", color = "ffd700", sound = "None",
        channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
        ignoreCase = true, wholeWord = true, enabled = true,
    } }
    if type(ns.RefreshMentionRuntime) == "function" then
        pcall(ns.RefreshMentionRuntime)
    end
    if type(ns.InvalidateChannelLabelCache) == "function" then
        pcall(ns.InvalidateChannelLabelCache)
    end
end

-- Tolerated as missing so the probe can be pointed at an older build and report a
-- failed assertion rather than dying on a nil call.
local function gateAllows()
    if type(ns.CanReplaceChatFrameAddMessage) ~= "function" then
        return true, "gate function does not exist"
    end
    local ok, allowed = pcall(ns.CanReplaceChatFrameAddMessage)
    if not ok then
        return true, "gate function raised"
    end
    return allowed and true or false
end

local retail = ns.IsRetailSecretValueBuild()
print("mode                       :", mode)
print("IsRetailSecretValueBuild   :", retail)

-- 1. Shipped defaults. On 12.x this resolves to "Safest", which is where the
--    reported error came from.
armEverything()
applyVisuals()

print("GetRetailChatFilterMode    :", ns.GetRetailChatFilterMode())
print("CanReplaceAddMessage       :", select(1, gateAllows()), select(2, gateAllows()) or "")

local taken = replacedFrames()
if retail then
    check("default mode: no chat frame AddMessage is replaced",
        #taken == 0, #taken > 0 and table.concat(taken, ", ") or nil)
    local allowed, why = gateAllows()
    check("default mode: the gate itself says no", allowed == false, why)
    check("default mode: render-time mentions stand down",
        ns.ShouldHighlightMentionsOnRender() == false)
else
    check("classic: the wrapper is installed as before",
        #taken > 0, #taken == 0 and "no frame was wrapped" or table.concat(taken, ", "))
    check("classic: the gate allows it", (gateAllows()) == true)
end

-- 2. "Balanced". The mode that withdraws filters inside instances must NOT be read
--    as permission to own AddMessage: a wrapper installed in the open world has
--    already tainted the field by the time the player zones in.
if retail then
    db.retailChatFilterMode = "lockdown"
    db.retailChatFilterModeUserSet = true
    armEverything()
    applyVisuals()

    taken = replacedFrames()
    check("balanced mode: still no AddMessage is replaced",
        #taken == 0, #taken > 0 and table.concat(taken, ", ") or nil)
end

-- 3. "Maximum features". The documented opt-in: the user is told this can break
--    chat in encounters, and this is the shape that breaking takes.
db.retailChatFilterMode = "full"
db.retailChatFilterModeUserSet = true
armEverything()
applyVisuals()

taken = replacedFrames()
check("maximum features: the wrapper is available again",
    #taken > 0, #taken == 0 and "no frame was wrapped" or table.concat(taken, ", "))

print(failures == 0 and "\nrender taint probe: PASS"
    or ("\nrender taint probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
