-- Regression probe for the AddMessage taint and the guard that contains it.
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
-- Blizzard's MessageEventHandler reads self.AddMessage at line 667 and calls
-- ChatFrameUtil.SetLastTellTarget at 672. Reading a tainted table field taints the
-- execution, so Chatify's channel-label wrapper made the strupper(target) inside
-- SetLastTellTarget raise on a whisper sender that is a secret string.
--
-- 0.11.50 answered that by refusing the wrapper, which cost mention highlighting and
-- short channel names on every 12.x client and drew the report that reverting to
-- 0.11.49 restored them. 0.11.51 answers it at the victim instead: everything
-- downstream of line 667 is SetLastTellTarget, PlaySound, FlashClientIcon and
-- FlashTabIfNotShown, and only the first touches a secret.
--
-- So the invariant is no longer "the field is never written". It is: wherever
-- Chatify owns AddMessage on a secret-value client, SetLastTellTarget must already
-- be guarded, and the guard must swallow a secret target without reaching Blizzard's
-- comparison.
--
-- CAVEAT on what a PASS here means. The stub raises on a secret target
-- unconditionally, because Lua 5.1 cannot model taint (see the note on
-- SetLastTellTarget in tools/stub/wow_env.lua). These assertions prove the guard
-- intercepts the call. They do not prove the in-game taint analysis behind it.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "retail"
env.install(mode)

-- Blizzard's own AddMessage, recorded before a single line of Chatify is loaded.
-- Every assertion below is "is this still the function the client installed".
-- rawget throughout, not a plain index. The stub's frame metatable answers unknown
-- capitalised keys with a fresh closure each time, so identity comparison silently
-- means nothing for any method it does not define. AddMessage happens to be a real
-- stub method today, which is the only reason the plain-index version of this probe
-- was measuring anything; that is too fragile to leave in place.
local function frameOwnsAddMessage(frame)
    return rawget(frame, "AddMessage") ~= nil
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

local db = addon.db and addon.db.profile
ns.db = db

-- Case 2's profile has to be in place before anything enables, because the shipped
-- defaults arm the wrapper on their own (short channel names are on out of the box)
-- and the guard is a once-per-session install. Clearing the settings after OnEnable
-- would be measuring a session that had already armed and disarmed.
local idleCase = os.getenv("CHATIFY_PROBE_CASE") == "guard-scope"
if idleCase and db then
    db.enableMentionManager = false
    db.shortChannels = false
    db.mentionRules = {}
    db.channelModes, db.channelLabels, db.channelLabelsNamed = {}, {}, {}
end

pcall(addon.OnEnable, addon)
for _, mod in pairs(addon.modules or {}) do
    pcall(mod.OnInitialize, mod)
    pcall(mod.OnEnable, mod)
end

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
        if frame and frameOwnsAddMessage(frame) then
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

local function guardInstalled()
    if type(ns.IsLastTellTargetGuarded) ~= "function" then
        return false, "guard function does not exist"
    end
    local ok, guarded = pcall(ns.IsLastTellTargetGuarded)
    if not ok then
        return false, "guard query raised"
    end
    return guarded and true or false
end

local retail = ns.IsRetailSecretValueBuild()
print("mode                       :", mode)
print("IsRetailSecretValueBuild   :", retail)

-- Sub-run entry point for case 2 below. The guard is a once-per-session install, so
-- "was it installed on a profile that never armed the wrapper" cannot be asked in a
-- process that has already armed it. A fresh interpreter is the only honest answer.
if idleCase then
    applyVisuals()

    local wrapped = replacedFrames()
    local guarded = guardInstalled()
    if #wrapped == 0 and guarded == false then
        print("idle-case OK")
        os.exit(0)
    end
    print("idle-case FAIL  wrapped=" .. #wrapped .. " guarded=" .. tostring(guarded))
    os.exit(1)
end

-- 1. Shipped defaults. On 12.x this is "Safest", which is where 0.11.49 crashed and
--    where 0.11.50 silently dropped both features.
armEverything()
applyVisuals()

print("GetRetailChatFilterMode    :", ns.GetRetailChatFilterMode())
print("CanReplaceAddMessage       :", select(1, gateAllows()), select(2, gateAllows()) or "")

local taken = replacedFrames()
check("default mode: the wrapper is installed",
    #taken > 0, #taken == 0 and "no frame was wrapped" or table.concat(taken, ", "))
-- On Classic the filters are installed and they own the highlight, so the render
-- path standing down there is correct rather than a fault. What must hold on both is
-- that exactly one of the two routes is live.
if retail then
    check("default mode: mentions reach the screen via the render path",
        ns.ShouldHighlightMentionsOnRender() == true)
else
    check("classic: mentions reach the screen via the filters",
        ns.ShouldHighlightMentionsOnRender() == false)
end

if retail then
    -- The whole point of 0.11.51: the wrapper is allowed back only because the one
    -- thing its taint could break is already neutralised by the time it is written.
    local guarded, guardWhy = guardInstalled()
    check("default mode: SetLastTellTarget is guarded first", guarded == true, guardWhy)

    -- A secret sender must be swallowed. Unguarded, the stub raises exactly as
    -- ChatFrameUtil.lua:567 does.
    env.secretString = env.secretString or "\1CHATIFY_SECRET_PAYLOAD\1"
    env.lastTellTarget = nil
    local ok, err = pcall(ChatFrameUtil.SetLastTellTarget, env.secretString, "WHISPER")
    check("secret whisper sender does not raise", ok, not ok and tostring(err) or nil)
    check("secret sender never reaches Blizzard's comparison",
        env.lastTellTarget == nil,
        env.lastTellTarget and "it was recorded anyway" or nil)

    -- ...and an ordinary sender must still be recorded, or /r breaks everywhere
    -- instead of only inside instanced content.
    env.lastTellTarget = nil
    local ok2 = pcall(ChatFrameUtil.SetLastTellTarget, "Svampollon-ArgentDawn", "WHISPER")
    check("ordinary whisper sender is passed through", ok2
        and env.lastTellTarget ~= nil
        and env.lastTellTarget.target == "Svampollon-ArgentDawn"
        and env.lastTellTarget.chatType == "WHISPER")
else
    -- Installing it here would take away a working /r to prevent an error that
    -- cannot occur on a client without secret values.
    check("classic: no SetLastTellTarget guard is installed",
        (guardInstalled()) == false)
end

-- 2. The guard is installed only alongside a wrapper. On a profile with nothing to
--    render there is no taint, Blizzard reaches line 672 clean and records the
--    secret target itself; guarding unconditionally would be a straight loss.
if retail then
    local fresh = "guard-scope"
    local cmd = ("CHATIFY_STUB_MODE=retail CHATIFY_PROBE_CASE=%s lua5.1 tools/render_taint_probe.lua"):format(fresh)
    if os.getenv("CHATIFY_PROBE_CASE") ~= fresh then
        local pipe = io.popen(cmd .. " 2>&1")
        local out = pipe:read("*a")
        local okRun = pipe:close()
        check("idle profile: guard is not installed without a wrapper",
            okRun and out:find("idle-case OK", 1, true) ~= nil,
            not okRun and "sub-run failed" or nil)
    end
end

-- 2b. The combat log window is left alone. It carries no player chat, so wrapping it
--     taints a frame for no feature at all. The stub reports ChatFrame2 as the combat
--     log, matching the client default.
local combatLogID
if type(FCF_IsWindowIDCombatLog) == "function" then
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        if FCF_IsWindowIDCombatLog(i) then combatLogID = i end
    end
end

if combatLogID then
    armEverything()
    applyVisuals()
    local logFrame = _G["ChatFrame" .. combatLogID]
    check("the combat log window is not wrapped",
        logFrame ~= nil and rawget(logFrame, "AddMessage") == nil,
        "ChatFrame" .. combatLogID)

    -- Guards against the skip being too eager: every other frame must still be taken.
    local others = 0
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        if i ~= combatLogID and _G["ChatFrame" .. i]
            and rawget(_G["ChatFrame" .. i], "AddMessage") ~= nil then
            others = others + 1
        end
    end
    check("every other window is still wrapped", others > 0, others .. " wrapped")
else
    check("stub reports a combat log window", false, "none found")
end

-- 3. "Maximum features" keeps working as before.
db.retailChatFilterMode = "full"
db.retailChatFilterModeUserSet = true
armEverything()
applyVisuals()

taken = replacedFrames()
check("maximum features: the wrapper is available",
    #taken > 0, #taken == 0 and "no frame was wrapped" or table.concat(taken, ", "))

print(failures == 0 and "\nrender taint probe: PASS"
    or ("\nrender taint probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
