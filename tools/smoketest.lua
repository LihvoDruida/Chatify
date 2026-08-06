--[[
Loads every Lua file in Chatify.toc order under a stub WoW environment, then
calls the entry points that run at login and when settings change.

This exists because of the ChatVisuals.lua "attempt to call a nil value" crash:
a slice-and-replace edit removed a block of hook management functions while
leaving their call sites in place. Every file still compiled - `luac -p` only
checks syntax - and nothing caught it until users hit it on login.

    lua5.1 tools/smoketest.lua

Exit code 0 means everything loaded and the entry points ran. The stub is
deliberately shallow: it is not a WoW emulator, and it will not catch logic
bugs. What it does catch is the class of error that actually shipped - calling
something that does not exist.
]]

local FILES = {
    "Compatibility.lua",
    "Locales.lua",
    "locale/enUS.lua",
    "locale/ukUA.lua",
    "Config.lua",
    "Settings.lua",
    "ChatCopy.lua",
    "ChatRouter.lua",
    "ChatVisuals.lua",
    "ChatQuickButtons.lua",
    "ChatFilters.lua",
    "ChatHistory.lua",
    "ChatSounds.lua",
    "ChatAutoReply.lua",
}

-- ---------------------------------------------------------------- stub frames

local function makeFrame()
    local f = {}
    local scripts, events = {}, {}
    local noop = function() end

    -- Any widget member we have not modelled resolves to something that is both
    -- callable and indexable, so `frame:Foo()` and `frame.EditBox:Bar()` both work
    -- without listing the whole widget API.
    local stubMember = setmetatable({}, {
        __call = function() return f end,
        __index = function(t) return t end,
    })

    setmetatable(f, { __index = function() return stubMember end })

    f.SetScript = function(_, name, fn) scripts[name] = fn; return f end
    f.GetScript = function(_, name) return scripts[name] end
    f.HookScript = function(_, name, fn) return f end
    f.RegisterEvent = function(_, e) events[e] = true; return f end
    f.UnregisterEvent = function(_, e) events[e] = nil; return f end
    f.UnregisterAllEvents = function() events = {}; return f end
    f.IsShown = function() return false end
    f.IsVisible = function() return false end
    f.GetID = function() return 1 end
    f.GetName = function() return "ChatifyStubFrame" end
    f.AddMessage = function() end
    f.GetMaxLines = function() return 128 end
    f.AtBottom = function() return true end
    f.GetScrollOffset = function() return 0 end
    f.GetNumMessages = function() return 0 end
    f.GetText = function() return "" end
    f.GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
    f.GetWidth = function() return 400 end
    f.GetHeight = function() return 200 end
    f.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
    f.CreateTexture = function() return makeFrame() end
    f.CreateFontString = function() return makeFrame() end
    f.GetRegions = function() return end
    f.GetChildren = function() return end
    return f
end

-- --------------------------------------------------------------- stub globals

_G.UIParent = makeFrame()
_G.WorldFrame = makeFrame()
_G.NUM_CHAT_WINDOWS = 10
for i = 1, 10 do
    _G["ChatFrame" .. i] = makeFrame()
    _G["ChatFrame" .. i .. "Tab"] = makeFrame()
    _G["ChatFrame" .. i .. "EditBox"] = makeFrame()
end
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
_G.SELECTED_CHAT_FRAME = _G.ChatFrame1
_G.GENERAL_CHAT_DOCK = makeFrame()
_G.ChatFrameMenuButton = makeFrame()
_G.QuickJoinToastButton = makeFrame()

_G.CreateFrame = function() return makeFrame() end
_G.GetTime = function() return 1000 end
_G.time = os.time
_G.date = os.date
_G.GetServerTime = os.time
_G.InCombatLockdown = function() return false end
_G.IsInInstance = function() return false, "none" end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.UnitName = function() return "Tester" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitGUID = function() return "Player-1-00000001" end
_G.UnitIsGroupLeader = function() return false end
_G.IsInGuild = function() return true end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.GetGuildInfo = function() return "Guild" end
_G.GetChannelList = function() return 1, "General - Elwynn Forest", false, 2, "Trade - City", false end
_G.GetChannelName = function() return 1, "General" end
_G.Ambiguate = function(name) return name end
_G.PlaySoundFile = function() end
_G.PlaySound = function() end
_G.SendChatMessage = function() end
_G.GetLocale = function() return "enUS" end
_G.GetBuildInfo = function() return "12.0.7", "68256", "Jul 2026", 120007 end
_G.GetCVar = function() return "none" end
_G.SetCVar = function() return true end
_G.hooksecurefunc = function() end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strsplit = function(sep, str) return str end
_G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.format = string.format
_G.tinsert = table.insert
_G.tremove = table.remove
_G.sort = table.sort
_G.max = math.max
_G.min = math.min
_G.floor = math.floor
_G.abs = math.abs
_G.RAID_CLASS_COLORS = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end
_G.C_Timer = { After = function(_, fn) end, NewTimer = function() return makeFrame() end }
_G.C_CVar = { GetCVar = function() return "none" end, SetCVar = function() return true end }
_G.C_ChatInfo = {}
_G.C_FriendList = { IsFriend = function() return false end }
_G.C_BattleNet = {}
_G.C_AddOns = {
    GetAddOnMetadata = function() return "0.0.0" end,
    IsAddOnLoaded = function() return false end,
}
_G.ChatFrameUtil = nil

-- Chat GlobalStrings the label engine derives its patterns from.
_G.GUILD, _G.OFFICER, _G.PARTY, _G.RAID = "Guild", "Officer", "Party", "Raid"
_G.PARTY_LEADER, _G.RAID_LEADER, _G.RAID_WARNING = "Party Leader", "Raid Leader", "Raid Warning"
_G.INSTANCE_CHAT, _G.INSTANCE_CHAT_LEADER = "Instance", "Instance Leader"
_G.CHAT_SAY_GET, _G.CHAT_YELL_GET = "%s says: ", "%s yells: "
_G.CHAT_WHISPER_GET, _G.CHAT_WHISPER_INFORM_GET = "%s whispers: ", "To %s: "
_G.CHAT_BN_WHISPER_GET, _G.CHAT_BN_WHISPER_INFORM_GET = "%s whispers: ", "To %s: "
_G.CHAT_GUILD_GET = "|Hchannel:GUILD|h[%s]|h %s: "
_G.CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[%s]|h %s: "
_G.CHAT_PARTY_GET = "|Hchannel:party|h[%s]|h %s: "
_G.CHAT_PARTY_LEADER_GET = "|Hchannel:party|h[%s]|h %s: "
_G.CHAT_RAID_GET = "|Hchannel:raid|h[%s]|h %s: "
_G.CHAT_RAID_LEADER_GET = "|Hchannel:raid|h[%s]|h %s: "
_G.CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[%s]|h %s: "
_G.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[%s]|h %s: "
_G.CHAT_RAID_WARNING_GET = "|Hchannel:RAID_WARNING|h[%s]|h %s: "

-- ------------------------------------------------------------------ stub Ace3

local addonObject
local moduleMixin = {
    NewModule = function(self, name)
        local m = setmetatable({ moduleName = name }, { __index = self })
        self.modules = self.modules or {}
        self.modules[name] = m
        return m
    end,
    GetModule = function(self, name) return (self.modules or {})[name] end,
    RegisterEvent = function() end,
    UnregisterEvent = function() end,
    UnregisterAllEvents = function() end,
    RegisterChatCommand = function() end,
    RawHook = function() end,
    Hook = function() end,
    UnhookAll = function() end,
    SecureHook = function() end,
    Print = function() end,
    ScheduleTimer = function() end,
    CancelAllTimers = function() end,
    IterateModules = function(self) return pairs(self.modules or {}) end,
}

local libs = {
    ["AceAddon-3.0"] = {
        NewAddon = function(_, name)
            addonObject = setmetatable({ name = name }, { __index = moduleMixin })
            return addonObject
        end,
        GetAddon = function() return addonObject end,
    },
    ["AceDB-3.0"] = {
        New = function(_, _, defaults)
            local profile = {}
            if defaults and defaults.profile then
                local function deepcopy(src, dst)
                    for k, v in pairs(src) do
                        if type(v) == "table" then
                            dst[k] = {}
                            deepcopy(v, dst[k])
                        else
                            dst[k] = v
                        end
                    end
                end
                deepcopy(defaults.profile, profile)
            end
            return {
                profile = profile,
                RegisterCallback = function() end,
                RegisterDefaults = function() end,
                ResetProfile = function() end,
            }
        end,
    },
    ["AceConfig-3.0"] = { RegisterOptionsTable = function(_, _, tbl) libs.__optionsTable = tbl end },
    ["AceConfigDialog-3.0"] = {
        AddToBlizOptions = function() return makeFrame() end,
        Open = function() end,
        SetDefaultSize = function() end,
    },
    ["AceConfigRegistry-3.0"] = { NotifyChange = function() end },
    ["AceDBOptions-3.0"] = { GetOptionsTable = function() return { name = "Profiles", type = "group", args = {} } end },
    ["AceLocale-3.0"] = {
        NewLocale = function() return setmetatable({}, { __newindex = function() end }) end,
        GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
    },
    ["LibSharedMedia-3.0"] = {
        Register = function() end,
        Fetch = function() return "Fonts\\FRIZQT__.TTF" end,
        List = function() return { "Friz Quadrata TT" } end,
        HashTable = function() return { ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF" } end,
        RegisterCallback = function() end,
    },
    ["LibStub"] = true,
}

_G.LibStub = setmetatable({
    GetLibrary = function(_, name, silent) return libs[name] end,
    NewLibrary = function(_, name) return libs[name] end,
}, {
    __call = function(_, name, silent)
        local lib = libs[name]
        if not lib and not silent then
            error("LibStub: missing library " .. tostring(name), 2)
        end
        return lib
    end,
})

-- ------------------------------------------------------------------- run them

local ns = {}
local failures = 0

for _, file in ipairs(FILES) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("LOAD FAIL  " .. file .. ": " .. tostring(err))
        failures = failures + 1
    else
        local ok, runErr = pcall(chunk, "Chatify", ns)
        if ok then
            print("ok         " .. file)
        else
            print("RUN FAIL   " .. file .. ": " .. tostring(runErr))
            failures = failures + 1
        end
    end
end

-- Entry points. ApplyVisuals is the one that crashed on login; the rest are the
-- other paths a fresh session and a settings change go through.
local function try(label, fn, ...)
    if type(fn) ~= "function" then
        print("MISSING    " .. label)
        failures = failures + 1
        return
    end
    local ok, err = pcall(fn, ...)
    if ok then
        print("ok         " .. label)
    else
        print("CALL FAIL  " .. label .. ": " .. tostring(err))
        failures = failures + 1
    end
end

if addonObject then
    addonObject.db = libs["AceDB-3.0"].New(nil, nil, { profile = ns.Defaults or {} })
end

try("ns.ApplyVisuals", ns.ApplyVisuals)
try("ns.RefreshChannelLabelHook", ns.RefreshChannelLabelHook)
try("ns.RemoveChannelLabelHook", ns.RemoveChannelLabelHook)
try("ns.InvalidateChannelLabelCache", ns.InvalidateChannelLabelCache)
try("ns.InvalidateChannelListCache", ns.InvalidateChannelListCache)
try("ns.GetJoinedChannels", ns.GetJoinedChannels)
try("ns.ApplyChannelLabels", ns.ApplyChannelLabels,
    "|Hchannel:PARTY|h[Party]|h |Hplayer:Bob|h[Bob]|h: go")

-- Regressions worth pinning: the link token a channel really uses is not always
-- the token we call it internally, and leader variants share their base
-- channel's token.
if type(ns.GetChannelLinkToken) == "function" and type(ns.Lists) == "table" then
    for _, entry in ipairs(ns.Lists.ChannelLabels or {}) do
        if entry.kind == "link" then
            local token = ns.GetChannelLinkToken(entry)
            local expected = {
                INSTANCE = "INSTANCE_CHAT",
                INSTANCE_LEADER = "INSTANCE_CHAT",
                PARTY_LEADER = "PARTY",
                RAID_LEADER = "RAID",
            }
            local want = expected[entry.token]
            if want and token ~= want then
                print("CALL FAIL  link token for " .. entry.token ..
                      ": got " .. tostring(token) .. ", expected " .. want)
                failures = failures + 1
            end
        end
    end
    print("ok         channel link tokens")
end
try("ns.ApplyNativeTimestamps", ns.ApplyNativeTimestamps)
try("ns.RefreshTimestampFilterState", ns.RefreshTimestampFilterState)

print(("-"):rep(52))
if failures == 0 then
    print("smoketest: all good")
    os.exit(0)
end
print("smoketest: " .. failures .. " failure(s)")
os.exit(1)
