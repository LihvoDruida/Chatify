-- Cross-client boot and API-contract regression checks.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local fixtures = require("client_fixtures")
local name = os.getenv("CHATIFY_COMPAT_CLIENT") or "retail"
local fixture = fixtures.install(env, name)
local checks = 0
local function check(label, condition)
    checks = checks + 1
    assert(condition, "compatibility probe: " .. label)
end

-- Model an unsupported event as an actual registration error, rather than
-- allowing the permissive frame stub to pretend every event exists.
local createFrame = CreateFrame
_G.CreateFrame = function(...)
    local frame = createFrame(...)
    local register = frame.RegisterEvent
    frame.RegisterEvent = function(self, event)
        if event == "CHATIFY_UNSUPPORTED_EVENT" then error("unknown event") end
        return register(self, event)
    end
    if name == "minimal-classic" then frame.SetBackdrop = false end
    return frame
end
local ns = {}
for line in io.lines(fixture[4]) do
    if line:match("%.lua$") then assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns) end
end
local addon = ns.Chatify
addon:OnInitialize()
if addon.OnEnable then addon:OnEnable() end
for _, module in pairs(addon.modules) do
    if module.OnInitialize then module:OnInitialize() end
    if module.OnEnable then module:OnEnable() end
end
check("client identity", ns.GetProjectKey() == fixture[3])
check("Classic family excludes other game types", ns.IsClassicClient() ==
    (fixture[3] == "vanilla" or fixture[3] == "tbc" or fixture[3] == "wrath"
    or fixture[3] == "titan" or fixture[3] == "cata" or fixture[3] == "mists"))
check("secret build detection", ns.IsModernSecretValueBuild() == fixture[5])
check("unsupported event rejected", not ns.RegisterEventIfSupported(CreateFrame("Frame"), "CHATIFY_UNSUPPORTED_EVENT"))
check("normal event accepted", ns.RegisterEventIfSupported(CreateFrame("Frame"), "PLAYER_LOGIN"))
check("options build", type(addon:GetOptions()) == "table")
check("compatibility report has feature states", #ns.GetClientCompatibilityReport() >= 25)
DEFAULT_CHAT_FRAME.__last = nil
addon:PrintClientCompatibilityReport()
check("live diagnostic prints", DEFAULT_CHAT_FRAME.__last ~= nil)
check("no guarded errors during initialization", #ns.Runtime.errors == 0)
env.fireEvent("PLAYER_LOGIN")
env.fireEvent("PLAYER_ENTERING_WORLD")
env.fireEvent("UPDATE_CHAT_WINDOWS")
check("lifecycle events do not raise", #(env.eventErrors or {}) == 0)
if ns.IsFeatureAvailable("quickButtons") then
    ChatFrame1.ButtonFrame = function() end
    check("invalid sidebar field ignored", pcall(ns.RefreshQuickChatButtons))
    ChatFrame1.ButtonFrame = env.newFrame("Frame", "FixtureSidebar")
    check("frame-owned sidebar supported", pcall(ns.RefreshQuickChatButtons))
    ChatFrame1.ButtonFrame = nil
end
addon:OpenConfig()
check("native window opens", ns.SettingsWindow.window:IsShown())
if name == "plunderstorm" then
    for _, feature in ipairs({ "composer", "autoReply", "channels", "quickButtons", "communities" }) do
        check("missing capability: " .. feature, not ns.IsFeatureAvailable(feature))
    end
end

-- Both LoadAddOn generations return (loaded, failureReason), not one union.
local legacyLoads = 0
LoadAddOn = function() legacyLoads = legacyLoads + 1; return true end
C_AddOns = { LoadAddOn = function() return nil, "MISSING" end }
local ok, reason = ns.LoadAddOnCompat("missing")
check("nil load is failure and reason preserved", not ok and reason == "MISSING" and legacyLoads == 0)
C_AddOns.LoadAddOn = function() return false, "DISABLED" end
ok, reason = ns.LoadAddOnCompat("disabled")
check("false load is failure", not ok and reason == "DISABLED")
C_AddOns.LoadAddOn = function() error("load failed") end
ok, reason = ns.LoadAddOnCompat("throws")
check("load exception stays a failure", not ok and type(reason) == "string" and legacyLoads == 0)
C_AddOns = nil
LoadAddOn = function() return nil, "INCOMPATIBLE" end
ok, reason = ns.LoadAddOnCompat("legacy")
check("legacy load reason", not ok and reason == "INCOMPATIBLE")
LoadAddOn = function() return true end
check("successful legacy load", ns.LoadAddOnCompat("legacy"))

-- Name-based, indexed namespace and indexed tuple friend-list generations.
C_FriendList = { GetFriendInfo = function(wanted) return wanted == "Modern" and {name="Modern"} or nil end }
check("modern friend lookup", ns.IsFriendCompat("Modern"))
C_FriendList = {
    GetNumFriends = function() return 2 end,
    GetFriendInfoByIndex = function(index) return { name = index == 1 and "Friend-Realm" or "Local" } end,
}
check("indexed namespace friend lookup", ns.IsFriendCompat("Friend-Realm"))
check("different realm is not whitelisted", not ns.IsFriendCompat("Friend-Other"))
check("same-realm short record", ns.IsFriendCompat("Local-Realm"))
C_FriendList = nil
GetNumFriends = function() return 1 end
GetFriendInfo = function() return "Legacy-Realm", 80, "Warrior", "City", true end
check("legacy tuple friend lookup", ns.GetFriendInfoByNameCompat("Legacy-Realm").connected)
check("legacy realm mismatch", not ns.IsFriendCompat("Legacy-Other"))

-- Presence selects one send API. Errors must never trigger duplicate sends.
local modernCalls, legacyCalls, bnetCalls = 0, 0, 0
C_ChatInfo = { SendChatMessage = function(message, kind, language, target)
    modernCalls = modernCalls + 1
    if kind == "CHANNEL" then assert(target == "4", "namespace target must be cstring") end
end }
SendChatMessage = function() legacyCalls = legacyCalls + 1 end
ns.InvalidateLockdownCache()
check("modern channel target", ns.SendChatMessageCompat("hello", "CHANNEL", nil, 4))
check("exactly one modern send", modernCalls == 1 and legacyCalls == 0)
check("invalid channel rejected", not ns.SendChatMessageCompat("hello", "CHANNEL", nil, "bad") and modernCalls == 1)
C_ChatInfo.SendChatMessage = function() modernCalls = modernCalls + 1; error("blocked") end
check("modern send error has no legacy retry", not ns.SendChatMessageCompat("hello", "GUILD") and legacyCalls == 0)
C_ChatInfo = nil
check("legacy send", ns.SendChatMessageCompat("hello", "GUILD") and legacyCalls == 1)
check("empty AFK can clear state", ns.SendChatMessageCompat("", "AFK") and legacyCalls == 2)
check("empty regular message rejected", not ns.SendChatMessageCompat("", "GUILD") and legacyCalls == 2)
C_BattleNet = { SendWhisper = function() bnetCalls = bnetCalls + 1; error("blocked") end }
BNSendWhisper = function() legacyCalls = legacyCalls + 1 end
check("Battle.net error has no legacy retry", not ns.SendBNetWhisperCompat(12, "hello") and bnetCalls == 1 and legacyCalls == 2)
C_BattleNet = nil
check("legacy Battle.net send", ns.SendBNetWhisperCompat(12, "hello") and legacyCalls == 3)
check("invalid account rejected", not ns.SendBNetWhisperCompat(0, "hello") and legacyCalls == 3)

if fixture[5] then
    local secret = env.secretString
    local before = legacyCalls
    check("secret message rejected", not ns.SendChatMessageCompat(secret, "GUILD"))
    check("secret target rejected", not ns.SendChatMessageCompat("hello", "WHISPER", nil, secret))
    check("secret chat type rejected", not ns.SendChatMessageCompat("hello", secret))
    check("secret Battle.net payload rejected", not ns.SendBNetWhisperCompat(12, secret))
    check("no protected send reached API", legacyCalls == before)
    C_ChatInfo = { InChatMessagingLockdown = function() error("temporarily unavailable") end }
    ns.InvalidateLockdownCache()
    check("failed lockdown query blocks sending", not ns.CanSendAddonChat())
    C_ChatInfo.InChatMessagingLockdown = function() return false end
    check("failed query was not cached", ns.CanSendAddonChat())
end

-- No C_Timer: delays and zero-delay recursion must survive unchanged.
C_Timer = nil
local ticks, fired = 0, 0
check("fallback scheduler accepted", ns.SafeAfter(0.5, function() fired = fired + 1 end))
local timerFrame = ChatifyFallbackTimerFrame
check("fallback does not run immediately", fired == 0 and timerFrame ~= nil)
timerFrame:GetScript("OnUpdate")(timerFrame, 0.25)
check("fallback respects delay", fired == 0)
timerFrame:GetScript("OnUpdate")(timerFrame, 0.25)
check("fallback executes due work", fired == 1)
local function recursive()
    ticks = ticks + 1
    if ticks < 3 then ns.SafeAfter(0, recursive) end
end
ns.SafeAfter(0, recursive)
timerFrame:GetScript("OnUpdate")(timerFrame, 0)
check("new work waits until next update", ticks == 1)
timerFrame:GetScript("OnUpdate")(timerFrame, 0)
timerFrame:GetScript("OnUpdate")(timerFrame, 0)
check("recursive queue terminates", ticks == 3)
ns.ScheduleUnique("compat", 0, function() fired = fired + 100 end)
ns.ScheduleUnique("compat", 0, function() fired = fired + 1 end)
timerFrame:GetScript("OnUpdate")(timerFrame, 0)
check("unique scheduler drops stale work", fired == 2)

-- Modern Settings can be broken while legacy registration remains available.
local integration = ns.SettingsIntegration
local registrations = 0
Settings = { RegisterCanvasLayoutCategory = function() error("missing canvas implementation") end,
    RegisterAddOnCategory = function() error("must not receive missing category") end }
InterfaceOptions_AddCategory = function() registrations = registrations + 1 end
check("legacy settings fallback", integration:Register() and integration.api == "interface-options")
check("fallback registration once", integration:Register() and registrations == 1)

-- Fresh namespace to reproduce early missing build/security APIs in isolation.
local late = {}
GetBuildInfo = nil
WOW_PROJECT_ID = 999
issecretvalue, canaccessvalue, hasanysecretvalues, canaccessallvalues, C_Secrets = nil, nil, nil, nil, nil
assert(loadfile("Config.lua"))("Chatify", late)
check("missing build is unknown", late.GetProjectKey() == "unknown")
check("negative secret probe", not late.HasSecretValueAPI() and not late.IsModernSecretValueBuild())
GetBuildInfo = function() error("not ready") end
check("failed build query stays retryable", late.GetBuildInterface() == 0)
GetBuildInfo = function() return "fixture", "test", "fixture", 11509 end
C_Secrets = { HasSecretRestrictions = function() return false end }
check("Classic restriction false remains retryable", not late.IsModernSecretValueBuild())
-- Interface is session-constant after a valid query, so use project identity
-- to model APIs appearing late on the same Classic runtime.
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
GetBuildInfo = function() return "fixture", "test", "fixture", 16001 end
C_Secrets = { HasSecretRestrictions = function() return true end }
check("late project API recognized", late.GetProjectKey() == "forever")
check("late security API recognized", late.HasSecretValueAPI() and late.IsModernSecretValueBuild())
check("client notice available", type(late.GetClientCompatibilityNotice()) == "string")

print(string.format("compatibility probe: PASS (%s; %d checks)", name, checks))
