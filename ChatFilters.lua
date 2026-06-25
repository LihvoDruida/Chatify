local addonName, ns = ...
local Chatify = ns.Chatify
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local string_find = string.find
local string_gsub = string.gsub
local string_upper = string.upper
local strlower = string.lower
local table_concat = table.concat
local unpackValues = unpack or table.unpack
local UnitName = UnitName

local PLAYER_NAME = UnitName("player")
local CachedKeywords = {}
local NormalizeCache = {}
local NormalizeCacheOrder = {}
local NORMALIZE_CACHE_LIMIT = 256
local FriendCache = {}
local friendCacheLastClear = 0
local repeatCacheLastPrune = 0

local function IsSecretValue(value)
    return type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value)
end

local SystemEvents = {
    CHAT_MSG_CHANNEL_JOIN = true,
    CHAT_MSG_CHANNEL_LEAVE = true,
    CHAT_MSG_CHANNEL_NOTICE = true,
    CHAT_MSG_CHANNEL_NOTICE_USER = true,
}

local filtersInstalled = false
local registeredFilters = {}
local communitiesHooked = false

local function RegisterMessageFilter(eventName, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return false
    end

    if registeredFilters[eventName] and registeredFilters[eventName][callback] then
        return true
    end

    local ok = false
    if type(ns.AddMessageEventFilterIfSupported) == "function" then
        ok = ns.AddMessageEventFilterIfSupported(eventName, callback)
    elseif type(ChatFrame_AddMessageEventFilter) == "function" then
        ok = pcall(ChatFrame_AddMessageEventFilter, eventName, callback) and true or false
    end

    if ok then
        registeredFilters[eventName] = registeredFilters[eventName] or {}
        registeredFilters[eventName][callback] = true
    end

    return ok
end

local function UnregisterMessageFilters()
    for eventName, callbacks in pairs(registeredFilters) do
        for callback in pairs(callbacks) do
            if type(ns.RemoveMessageEventFilterIfSupported) == "function" then
                ns.RemoveMessageEventFilterIfSupported(eventName, callback)
            elseif type(ChatFrame_RemoveMessageEventFilter) == "function" then
                pcall(ChatFrame_RemoveMessageEventFilter, eventName, callback)
            end
        end
    end

    registeredFilters = {}
    filtersInstalled = false
end

local BaseEvents = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_BN_CONVERSATION",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_AFK",
    "CHAT_MSG_DND",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_LOOT",
}

-- Modern Retail: use Blizzard's secure message-event filter path only.
-- These callbacks are wrapped by ChatFrameUtil's secure registry and will only
-- run when the event payload is accessible via canaccessvalue(...).
local RetailRestrictedEvents = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    -- Do not register message mutating filters for whispers on modern Retail.
    -- Blizzard routes whispers to General, temporary tabs and BNet conversations through
    -- sensitive chat payloads; changing the payload here can create blank whisper tabs.
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_LOOT",
}

local LinkRegexRules = {
    { exp = "^(%a[%w+.-]+://%S+)", verifyDomain = false },
    { exp = "%f[%S](%a[%w+.-]+://%S+)", verifyDomain = false },
    { exp = '^(%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = '%f[%S](%"[^%"]+%"@[%w_.-%%]+%.(%a%a+))', verifyDomain = true },
    { exp = "(%S+@[%w_.-%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d[:/]%S+)", verifyDomain = false },
    { exp = "^([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },
    { exp = "%f[%S]([0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d%.[0-2]?%d?%d)%f[%D]", verifyDomain = false },
    { exp = "^(www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S](www%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([%w_.-%%]+[%w_-%%]%.(%a%a+):%d+)", verifyDomain = true },
    { exp = "%f[%S]([%w_.-%%]+[%w_-%%]%.(%a%a+):%d+)", verifyDomain = true },
    { exp = "^([%w_.-%%]+[%w_-%%]%.(%a%a+)/%S+)", verifyDomain = true },
    { exp = "%f[%S]([%w_.-%%]+[%w_-%%]%.(%a%a+)/%S+)", verifyDomain = true },
    { exp = "^([-%w_%%]+%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S]([-%w_%%]+%.[-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "^([-%w_%%]+%.(%a%a+))", verifyDomain = true },
    { exp = "%f[%S]([-%w_%%]+%.(%a%a+))", verifyDomain = true },
}

local ValidTopLevelDomains = {}
local TLD_STRING = [[
ONION COM NET ORG EDU GOV MIL UA RU UK DE FR PL US CA IO CO ME EU TV INFO BIZ
AC AD AE AERO AF AG AI AL AM AR AS ASIA AT AU AW AX AZ BA BB BE BG BH BI BJ BM BN
BO BR BS BT BY BZ CC CD CH CI CL CN CR CU CX CY CZ DK DM DO DZ EC EE EG ES ET FI
FJ FM FO GA GD GE GF GG GH GI GL GM GN GR GS GT GU HK HN HR HT HU ID IE IL IM IN
INT IQ IR IS IT JE JM JO JP KG KH KR KW KZ LA LB LI LK LT LU LV LY MA MC MD MG MK
ML MM MN MO MOBI MP MQ MR MS MT MU MV MW MX MY MZ NA NAME NC NE NG NI NL NO NP NR NU
NZ OM PA PE PF PG PH PK PM PN PR PRO PS PT PW PY QA RE RO RS RW SA SB SC SD SE SG
SH SI SJ SK SL SM SN SO SR ST SU SV SY SZ TC TD TEL TG TH TJ TK TL TM TN TO TR TRAVEL
TT TW TZ UG UY UZ VA VC VE VG VI VN VU WS ZA ZM ZW PP KR JP CN ID
]]
for tld in TLD_STRING:gmatch("%S+") do
    ValidTopLevelDomains[tld] = true
end

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns.db
end

local function IsVirtualMode()
    local db = DB()
    if not db or not db.useVirtualChat then
        return false
    end

    if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        return false
    end

    return true
end

local function IsRetailRestricted()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
end

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end

    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EscapePattern(value)
    return (value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function StripWoWMarkup(text)
    local value = text

    -- Keep the visible text of hyperlinks. The previous spam normalizer removed the
    -- whole |H...|hvisible|h block, so ads that linked words like VIP/CARRY could
    -- slip through even when the keyword existed in the blocklist.
    local guard = 0
    while guard < 8 do
        local changed
        value, changed = string_gsub(value, "|H.-|h(.-)|h", "%1")
        if changed == 0 then
            break
        end
        guard = guard + 1
    end

    value = string_gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string_gsub(value, "|r", "")
    value = string_gsub(value, "|T.-|t", " ")
    value = string_gsub(value, "|A.-|a", " ")
    value = string_gsub(value, "{.-}", " ")

    return value
end

function ns.NormalizeSpamText(text)
    if IsSecretValue(text) then
        return { compact = "", tokens = " ", clean = "" }
    end

    local safe = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(text) or text
    if type(safe) == "number" then
        safe = tostring(safe)
    end
    if type(safe) ~= "string" then
        return { compact = "", tokens = " ", clean = "" }
    end

    -- Chattynator/Prat-style hot path: repeat spam checks should not rebuild the
    -- same normalized forms over and over. Keep the cache small and only for
    -- reasonably short normal strings; protected values are never stored.
    if #safe <= 512 then
        local cached = NormalizeCache[safe]
        if cached then
            return cached
        end
    end

    local ok, forms = pcall(function()
        local clean = string_upper(StripWoWMarkup(safe))
        local tokens = string_gsub(clean, "[^%w]+", " ")
        tokens = " " .. Trim(tokens) .. " "
        local compact = string_gsub(tokens, "%s+", "")

        return {
            compact = compact,
            tokens = tokens,
            clean = clean,
        }
    end)

    if ok and type(forms) == "table" then
        if #safe <= 512 then
            NormalizeCache[safe] = forms
            NormalizeCacheOrder[#NormalizeCacheOrder + 1] = safe
            if #NormalizeCacheOrder > NORMALIZE_CACHE_LIMIT then
                local oldKey = table.remove(NormalizeCacheOrder, 1)
                if oldKey then
                    NormalizeCache[oldKey] = nil
                end
            end
        end
        return forms
    end

    return { compact = "", tokens = " ", clean = "" }
end

local function NormalizeText(text)
    local forms = ns.NormalizeSpamText(text)
    return forms.compact or ""
end

local function BuildFuzzyWordPattern(compactKeyword)
    if type(compactKeyword) ~= "string" or compactKeyword == "" then
        return nil
    end
    if not compactKeyword:match("^[%w]+$") then
        return nil
    end

    local parts = {}
    for index = 1, #compactKeyword do
        parts[#parts + 1] = EscapePattern(compactKeyword:sub(index, index))
    end

    -- Letter-frontier boundaries keep short keywords like VIP from matching VIPER,
    -- but still catch VIP 9/9, VIP9/9 and obfuscated forms such as V.I.P or V-I-P.
    local startBoundary = compactKeyword:match("^[%a]+$") and "%f[%a]" or "%f[%w]"
    local endBoundary = compactKeyword:match("^[%a]+$") and "%f[%A]" or "%f[%W]"
    return startBoundary .. table_concat(parts, "[%s%p%c]*") .. endBoundary
end

function ns.UpdateSpamCache()
    local db = DB()
    CachedKeywords = {}
    NormalizeCache = {}
    NormalizeCacheOrder = {}

    if not db or type(db.spamKeywords) ~= "table" then
        return
    end

    local seen = {}
    for i = 1, #db.spamKeywords do
        local raw = Trim(tostring(db.spamKeywords[i] or ""))
        if raw ~= "" then
            local forms = ns.NormalizeSpamText(raw)
            local compact = forms.compact or ""
            if compact ~= "" and not seen[compact] then
                seen[compact] = true
                tinsert(CachedKeywords, {
                    raw = raw,
                    compact = compact,
                    token = " " .. compact .. " ",
                    fuzzyPattern = BuildFuzzyWordPattern(compact),
                    allowCompactSubstring = #compact >= 4,
                })
            end
        end
    end
end

function ns.GetSpamMatch(messageText)
    local forms
    if type(messageText) == "table" then
        forms = messageText
    else
        forms = ns.NormalizeSpamText(messageText)
    end

    local compactMessage = forms.compact or ""
    local tokenMessage = forms.tokens or " "
    local cleanMessage = forms.clean or ""

    if compactMessage == "" then
        return nil
    end

    for i = 1, #CachedKeywords do
        local keyword = CachedKeywords[i]
        if keyword and keyword.compact and keyword.compact ~= "" then
            if keyword.token and string_find(tokenMessage, keyword.token, 1, true) then
                return keyword.raw or keyword.compact
            end

            if keyword.fuzzyPattern and string_find(cleanMessage, keyword.fuzzyPattern) then
                return keyword.raw or keyword.compact
            end

            if keyword.allowCompactSubstring and string_find(compactMessage, keyword.compact, 1, true) then
                return keyword.raw or keyword.compact
            end
        end
    end

    return nil
end

function ns.IsSpamMessage(messageText)
    return ns.GetSpamMatch(messageText) ~= nil
end


local function GetSafeString(value)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(value)
    end
    if type(value) == "number" then
        return tostring(value)
    end
    if type(value) == "string" then
        return value
    end
    return nil
end

local function Upper(value)
    local safe = GetSafeString(value)
    if type(safe) ~= "string" then
        return ""
    end
    return string_upper(safe)
end

local function ContainsAny(value, ...)
    local upper = Upper(value)
    if upper == "" then
        return false
    end

    for i = 1, select("#", ...) do
        local needle = select(i, ...)
        if type(needle) == "string" and needle ~= "" and string_find(upper, needle, 1, true) then
            return true
        end
    end
    return false
end

local function GetEventCategory(eventName, ...)
    if eventName == "CHAT_MSG_GUILD" then return "GUILD", "GUILD" end
    if eventName == "CHAT_MSG_OFFICER" then return "GUILD", "OFFICER" end
    if eventName == "CHAT_MSG_PARTY" or eventName == "CHAT_MSG_PARTY_LEADER" then return "PARTY", "PARTY" end
    if eventName == "CHAT_MSG_RAID" or eventName == "CHAT_MSG_RAID_LEADER" or eventName == "CHAT_MSG_RAID_WARNING" then return "RAID", "RAID" end
    if eventName == "CHAT_MSG_INSTANCE_CHAT" or eventName == "CHAT_MSG_INSTANCE_CHAT_LEADER" then return "RAID", "INSTANCE" end
    if eventName == "CHAT_MSG_WHISPER" or eventName == "CHAT_MSG_WHISPER_INFORM" or eventName == "CHAT_MSG_BN_WHISPER" or eventName == "CHAT_MSG_BN_WHISPER_INFORM" or eventName == "CHAT_MSG_BN_CONVERSATION" then return "WHISPER", "WHISPER" end
    if eventName == "CHAT_MSG_COMMUNITIES_CHANNEL" then return "COMMUNITY", "COMMUNITY" end
    if eventName == "CHAT_MSG_SAY" then return "SAY", "SAY" end
    if eventName == "CHAT_MSG_YELL" then return "YELL", "YELL" end
    if eventName == "CHAT_MSG_LOOT" then return "LOOT", "LOOT" end
    if eventName == "CHAT_MSG_CHANNEL" then
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if ContainsAny(value, "SERVICES") then return "CHANNEL", "SERVICES" end
            if ContainsAny(value, "TRADE") then return "CHANNEL", "TRADE" end
            if ContainsAny(value, "GENERAL") then return "CHANNEL", "GENERAL" end
            if ContainsAny(value, "LOOKINGFORGROUP", "LOOKING FOR GROUP", "LFG") then return "CHANNEL", "LFG" end
        end
        return "CHANNEL", "CHANNEL"
    end

    return "OTHER", "OTHER"
end

ns.GetChatifyEventCategory = GetEventCategory

local function IsSelfAuthorForMention(author)
    local safeAuthor = GetSafeString(author)
    if type(safeAuthor) ~= "string" or safeAuthor == "" or type(PLAYER_NAME) ~= "string" or PLAYER_NAME == "" then
        return false
    end

    local shortName = safeAuthor
    if type(Ambiguate) == "function" then
        local ok, result = pcall(Ambiguate, safeAuthor, "none")
        if ok and type(result) == "string" and result ~= "" then
            shortName = result
        end
    end
    shortName = shortName:match("([^%-]+)") or shortName

    return strlower(shortName) == strlower(PLAYER_NAME)
end

local function QueueMentionRuleSound(rule, index, eventName, author, ...)
    if not rule or eventName == "CHAT_MSG_WHISPER_INFORM" or eventName == "CHAT_MSG_BN_WHISPER_INFORM" then
        return
    end

    if IsSelfAuthorForMention(author) then
        return
    end

    local soundName = rule.sound
    if type(soundName) ~= "string" or soundName == "" or soundName == "None" then
        return
    end

    if type(ns.CanPlayMentionRuleSound) == "function" then
        local ok, canPlay = pcall(ns.CanPlayMentionRuleSound, rule, index)
        if not ok or not canPlay then
            return
        end
    end

    local function play()
        if type(ns.PlayMentionSound) == "function" then
            ns.PlayMentionSound(soundName)
        end
    end

    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(0, play)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, play)
    else
        play()
    end
end

local function ClearFriendCache()
    FriendCache = {}
    friendCacheLastClear = GetTime and GetTime() or 0
end

function Filters:FRIENDLIST_UPDATE()
    ClearFriendCache()
end

function Filters:BN_FRIEND_LIST_SIZE_CHANGED()
    ClearFriendCache()
end

local function IsLegacyFriendByName(shortName)
    if type(shortName) ~= "string" or shortName == "" then
        return false
    end

    if type(GetNumFriends) ~= "function" or type(GetFriendInfo) ~= "function" then
        return false
    end

    local okCount, count = pcall(GetNumFriends)
    count = okCount and tonumber(count) or 0
    if not count or count <= 0 then
        return false
    end

    for i = 1, count do
        local okInfo, name = pcall(GetFriendInfo, i)
        if okInfo and type(name) == "string" and name ~= "" then
            local candidate = name
            if type(Ambiguate) == "function" then
                local okAmb, value = pcall(Ambiguate, name, "none")
                if okAmb and type(value) == "string" and value ~= "" then candidate = value end
            end
            candidate = candidate:match("([^%-]+)") or candidate
            if candidate == shortName or name == shortName then
                return true
            end
        end
    end

    return false
end

local function IsFriendAuthor(author)
    local safeAuthor = GetSafeString(author)
    if type(safeAuthor) ~= "string" or safeAuthor == "" then
        return false
    end

    local shortName = safeAuthor
    if type(Ambiguate) == "function" then
        local ok, result = pcall(Ambiguate, safeAuthor, "none")
        if ok and type(result) == "string" and result ~= "" then
            shortName = result
        end
    end
    shortName = shortName:match("([^%-]+)") or shortName
    if shortName == "" then
        return false
    end

    local now = GetTime and GetTime() or 0
    local cached = FriendCache[shortName]
    if cached and (now - cached.time) < 30 then
        return cached.value
    end

    local result = false
    if C_FriendList and type(C_FriendList.GetFriendInfoByName) == "function" then
        local ok, info = pcall(C_FriendList.GetFriendInfoByName, shortName)
        if ok and type(info) == "table" and info.name then
            result = true
        end
    end

    if not result and C_FriendList and type(C_FriendList.GetFriendInfo) == "function" then
        local ok, info = pcall(C_FriendList.GetFriendInfo, shortName)
        if ok and type(info) == "table" and info.name then
            result = true
        end
    end

    if not result and type(GetFriendInfo) == "function" then
        local ok, name = pcall(GetFriendInfo, shortName)
        if ok and type(name) == "string" and name ~= "" then
            result = true
        elseif IsLegacyFriendByName(shortName) then
            result = true
        end
    end

    FriendCache[shortName] = { value = result, time = now }
    return result
end


local function GetSpamWhitelist(db)
    db.spamWhitelist = db.spamWhitelist or {}
    return db.spamWhitelist
end

local function IsSpamWhitelisted(db, category, author)
    local whitelist = GetSpamWhitelist(db)
    if category == "GUILD" and whitelist.guild then return true end
    if category == "PARTY" and whitelist.party then return true end
    if category == "RAID" and whitelist.raid then return true end
    if whitelist.friends and IsFriendAuthor(author) then return true end
    return false
end

local function GetSpamChannelRules(db)
    db.spamChannelRules = db.spamChannelRules or {}
    return db.spamChannelRules
end

local function IsSpamChannelEnabled(db, category, channelKey)
    local rules = GetSpamChannelRules(db)
    if rules[channelKey] ~= nil then
        return rules[channelKey] and true or false
    end
    if rules[category] ~= nil then
        return rules[category] and true or false
    end
    if category == "CHANNEL" then
        return rules.CHANNEL ~= false
    end
    if category == "GUILD" or category == "PARTY" or category == "RAID" or category == "LOOT" or category == "WHISPER" then
        return false
    end
    return true
end

local SpamRuntime = ns.SpamRuntime or { blocked = 0, logged = 0, log = {} }
ns.SpamRuntime = SpamRuntime
local RepeatCache = {}

local function PruneRepeatCache(now, maxAge)
    for key, entry in pairs(RepeatCache) do
        if type(entry) ~= "table" or not entry.time or (now - entry.time) > maxAge then
            RepeatCache[key] = nil
        end
    end
end

local function Shorten(value, limit)
    value = GetSafeString(value) or ""
    limit = tonumber(limit) or 160
    if #value > limit then
        return value:sub(1, limit - 3) .. "..."
    end
    return value
end

local function AddSpamDebugLog(action, eventName, author, reason, messageText, channelKey)
    local limit = 20
    local db = DB()
    if db and tonumber(db.spamLogLimit) then
        limit = math.max(1, math.min(50, tonumber(db.spamLogLimit)))
    end

    local entry = {
        time = date and date("%H:%M:%S") or tostring(math.floor(GetTime and GetTime() or 0)),
        action = action or "block",
        event = eventName or "?",
        channel = channelKey or "?",
        author = Shorten(author, 64),
        reason = Shorten(reason, 80),
        text = Shorten(messageText, 180),
    }

    table.insert(SpamRuntime.log, 1, entry)
    while #SpamRuntime.log > limit do
        table.remove(SpamRuntime.log)
    end

    if action == "log" then
        SpamRuntime.logged = (SpamRuntime.logged or 0) + 1
    else
        SpamRuntime.blocked = (SpamRuntime.blocked or 0) + 1
    end
end

function ns.GetSpamFilterStats()
    return SpamRuntime
end

function ns.ResetSpamFilterStats()
    SpamRuntime.blocked = 0
    SpamRuntime.logged = 0
    SpamRuntime.log = {}
    RepeatCache = {}
    repeatCacheLastPrune = 0
    NormalizeCache = {}
    NormalizeCacheOrder = {}
    ClearFriendCache()
end

function ns.GetSpamDebugText()
    local stats = ns.GetSpamFilterStats and ns.GetSpamFilterStats() or SpamRuntime
    local lines = {}
    lines[#lines + 1] = string.format("Blocked: %d   Logged: %d", tonumber(stats.blocked) or 0, tonumber(stats.logged) or 0)
    if not stats.log or #stats.log == 0 then
        lines[#lines + 1] = "|cff888888No spam events logged this session.|r"
        return table_concat(lines, "\n")
    end

    for i = 1, math.min(#stats.log, 20) do
        local entry = stats.log[i]
        lines[#lines + 1] = string.format("%02d. [%s] %s %s/%s: %s — %s", i, entry.time or "?", entry.action or "?", entry.event or "?", entry.channel or "?", entry.reason or "?", entry.text or "")
    end
    return table_concat(lines, "\n")
end

local function GetRepeatReason(db, forms, author, eventName, channelKey)
    if not db.enableThrottle then
        return nil
    end

    local compact = forms and forms.compact or ""
    local minLength = tonumber(db.throttleMinLength) or 20
    if compact == "" or #compact < minLength then
        return nil
    end

    local timeout = tonumber(db.throttleTime) or 60
    if timeout <= 0 then
        return nil
    end

    local now = GetTime and GetTime() or 0
    if (now - repeatCacheLastPrune) > 5 then
        PruneRepeatCache(now, timeout * 2)
        repeatCacheLastPrune = now
    end

    local authorKey = NormalizeText(author or "unknown")
    if authorKey == "" then authorKey = "unknown" end
    local key = tostring(eventName or "?") .. "|" .. tostring(channelKey or "?") .. "|" .. authorKey .. "|" .. compact
    local previous = RepeatCache[key]
    RepeatCache[key] = { time = now }

    if previous and previous.time and (now - previous.time) <= timeout then
        return string.format("repeat within %ds", timeout)
    end

    return nil
end

function ns.ProcessSpamMessage(eventName, msg, author, ...)
    local db = DB()
    if not db then
        return false
    end

    if not db.enableSpamFilter and not db.enableThrottle then
        return false
    end

    local category, channelKey = GetEventCategory(eventName, ...)
    if IsSpamWhitelisted(db, category, author) then
        return false
    end

    if not IsSpamChannelEnabled(db, category, channelKey) then
        return false
    end

    local forms = ns.NormalizeSpamText(msg)
    local reason = nil

    if db.enableSpamFilter then
        local matched = ns.GetSpamMatch(forms)
        if matched then
            reason = "keyword: " .. tostring(matched)
        end
    end

    if not reason then
        reason = GetRepeatReason(db, forms, author, eventName, channelKey)
    end

    if not reason then
        return false
    end

    local action = db.spamFilterMode == "log" and "log" or "block"
    AddSpamDebugLog(action, eventName, author, reason, msg, channelKey)
    return action ~= "log"
end

local function DecorateLink(url)
    if IsSecretValue(url) then
        return url
    end

    local db = DB()
    if not db then
        return url
    end

    local cleanUrl, trailing = url:match("^(.-)([%.,:;!'\"%)%]]*)$")
    cleanUrl = cleanUrl or url
    trailing = trailing or ""

    if cleanUrl == "" then
        return url
    end

    local color = db.urlColor or "0099FF"
    return string.format("|cff%s|Hurl:%s|h[%s]|h|r%s", color, cleanUrl, cleanUrl, trailing)
end

local function TransformPlainTextSegments(text, transformer)
    if type(text) ~= "string" then
        return text
    end
    if type(transformer) ~= "function" then
        return text
    end
    if not text:find("|H", 1, true) then
        return transformer(text)
    end

    local out = {}
    local index = 1
    local length = #text

    while index <= length do
        local hs = text:find("|H", index, true)
        if not hs then
            out[#out + 1] = transformer(text:sub(index))
            break
        end

        if hs > index then
            out[#out + 1] = transformer(text:sub(index, hs - 1))
        end

        local firstClose = text:find("|h", hs + 2, true)
        if not firstClose then
            out[#out + 1] = transformer(text:sub(hs))
            break
        end

        local secondClose = text:find("|h", firstClose + 2, true)
        if not secondClose then
            out[#out + 1] = transformer(text:sub(hs))
            break
        end

        out[#out + 1] = text:sub(hs, secondClose + 1)
        index = secondClose + 2
    end

    return table_concat(out)
end

local function DecorateLinksInSegment(segment)
    if type(segment) ~= "string" or segment == "" then
        return segment
    end

    local output = segment
    for i = 1, #LinkRegexRules do
        local rule = LinkRegexRules[i]
        local startIdx = 1

        while true do
            local s, e, cap1, cap2 = output:find(rule.exp, startIdx)
            if not s then
                break
            end

            local url = cap1
            local tld = cap2
            local isValid = true

            if rule.verifyDomain and tld and not ValidTopLevelDomains[tld:upper()] then
                isValid = false
            end

            if isValid then
                local newLink = DecorateLink(url)
                output = output:sub(1, s - 1) .. newLink .. output:sub(e + 1)
                startIdx = s + #newLink
            else
                startIdx = e + 1
            end
        end
    end

    return output
end

local function DecorateLinksInText(text)
    if type(text) ~= "string" or IsSecretValue(text) then
        return text
    end

    if text:find("|Hurl:", 1, true) then
        return text
    end

    if not text:find("://", 1, true) and not text:find("www.", 1, true) and not text:find("@", 1, true) and not text:find("%.") then
        return text
    end

    return TransformPlainTextSegments(text, DecorateLinksInSegment)
end

local MentionCooldowns = {}

local function NormalizeColor(value, fallback)
    value = type(value) == "string" and value:gsub("#", "") or ""
    if value:match("^%x%x%x%x%x%x$") then
        return value
    end
    if value:match("^%x%x%x%x%x%x%x%x$") then
        return value:sub(3)
    end
    return fallback or "ffd700"
end

local function ParseChannelSet(value)
    if type(value) == "table" then
        return value
    end

    local set = {}
    if type(value) ~= "string" or value == "" then
        set.ALL = true
        return set
    end

    for token in value:gmatch("[^,%s]+") do
        token = string_upper(token)
        if token ~= "" then
            set[token] = true
        end
    end

    if next(set) == nil then
        set.ALL = true
    end
    return set
end

local function MentionRuleAppliesToEvent(rule, eventName, ...)
    local channels = ParseChannelSet(rule.channels)
    if channels.ALL then
        return true
    end

    local category, channelKey = GetEventCategory(eventName, ...)
    return channels[category] or channels[channelKey] or false
end

local function GetMentionRules(db)
    if not db or db.enableMentionManager == false or type(db.mentionRules) ~= "table" then
        return nil
    end
    return db.mentionRules
end

local function RuleText(rule)
    local text = rule and (rule.text or rule.word or rule.keyword)
    if type(text) ~= "string" then
        return nil
    end
    text = Trim(text)
    if text == "" then
        return nil
    end
    return text
end

local function SegmentContainsRule(segment, rule)
    local text = RuleText(rule)
    if not text or type(segment) ~= "string" or segment == "" then
        return false
    end

    local haystack = segment
    local needle = text
    if rule.ignoreCase ~= false then
        haystack = strlower(haystack)
        needle = strlower(needle)
    end

    local escaped = EscapePattern(needle)
    if rule.wholeWord and needle:match("^[%w_]+$") then
        return string_find(haystack, "%f[%w]" .. escaped .. "%f[%W]") ~= nil
    end

    return string_find(haystack, escaped) ~= nil
end

local function HighlightMentionRuleInSegment(segment, rule)
    local text = RuleText(rule)
    if not text or type(segment) ~= "string" or segment == "" then
        return segment
    end

    local color = NormalizeColor(rule.color, "ffd700")
    local escaped = EscapePattern(text)
    local pattern = "(" .. escaped .. ")"

    -- Lua patterns in WoW are not Unicode-aware. Whole-word matching is kept for
    -- ASCII identifiers such as RL/Sebas; Cyrillic phrases fall back to safe phrase matching.
    if rule.wholeWord and text:match("^[%w_]+$") then
        pattern = "(%f[%w]" .. escaped .. "%f[%W])"
    end

    local ok, output = pcall(function()
        if rule.ignoreCase ~= false then
            local lowerSegment = strlower(segment)
            local lowerNeedle = strlower(text)
            local lowerEscaped = EscapePattern(lowerNeedle)
            local lowerPattern = "(" .. lowerEscaped .. ")"
            if rule.wholeWord and lowerNeedle:match("^[%w_]+$") then
                lowerPattern = "(%f[%w]" .. lowerEscaped .. "%f[%W])"
            end

            local result = {}
            local index = 1
            while index <= #segment do
                local s, e = string_find(lowerSegment, lowerPattern, index)
                if not s then
                    result[#result + 1] = segment:sub(index)
                    break
                end
                if s > index then
                    result[#result + 1] = segment:sub(index, s - 1)
                end
                result[#result + 1] = "|cff" .. color .. segment:sub(s, e) .. "|r"
                index = e + 1
            end
            return table_concat(result)
        end

        return segment:gsub(pattern, "|cff" .. color .. "%1|r")
    end)

    if ok and type(output) == "string" then
        return output
    end
    return segment
end

function ns.GetMentionRuleMatch(messageText, eventName, ...)
    local db = DB()
    local rules = GetMentionRules(db)
    if not rules or type(messageText) ~= "string" or IsSecretValue(messageText) then
        return nil
    end

    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and rule.enabled ~= false and RuleText(rule) and MentionRuleAppliesToEvent(rule, eventName, ...) then
            local matched = false
            TransformPlainTextSegments(messageText, function(segment)
                if not matched and SegmentContainsRule(segment, rule) then
                    matched = true
                end
                return segment
            end)
            if matched then
                return rule, i
            end
        end
    end
    return nil
end

function ns.CanPlayMentionRuleSound(rule, index)
    if not rule then
        return false
    end
    local sound = rule.sound
    if type(sound) ~= "string" or sound == "" or sound == "None" then
        return false
    end

    local cooldown = tonumber(rule.cooldown) or 2
    if cooldown < 0 then cooldown = 0 end
    local now = GetTime and GetTime() or 0
    local key = tostring(index or RuleText(rule) or "mention")
    local last = MentionCooldowns[key]
    if last and cooldown > 0 and (now - last) < cooldown then
        return false
    end
    MentionCooldowns[key] = now
    return true
end

function ns.ApplyMentionRules(text, eventName, author, ...)
    local db = DB()
    local rules = GetMentionRules(db)
    if not rules or type(text) ~= "string" or IsSecretValue(text) then
        return text
    end

    local output = text
    local soundQueued = false
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and rule.enabled ~= false and RuleText(rule) and MentionRuleAppliesToEvent(rule, eventName, ...) then
            local matchedRule = false
            output = TransformPlainTextSegments(output, function(segment)
                if not matchedRule and SegmentContainsRule(segment, rule) then
                    matchedRule = true
                end
                return HighlightMentionRuleInSegment(segment, rule)
            end)

            if matchedRule and not soundQueued then
                QueueMentionRuleSound(rule, i, eventName, author, ...)
                soundQueued = true
            end
        end
    end
    return output
end

function ns.FormatLinksOnly(msg)
    if type(msg) ~= "string" then
        return msg
    end

    local safeMsg = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(msg) or msg
    if type(safeMsg) ~= "string" then
        return msg
    end

    local ok, result = pcall(function()
        return DecorateLinksInText(safeMsg)
    end)

    if ok and type(result) == "string" then
        return result
    end

    return msg
end

function ns.FormatMessage(msg, eventName, author, ...)
    local db = DB()
    if type(msg) ~= "string" or not db then
        return msg
    end

    local argCount = select("#", ...)
    local args = { ... }

    local safeMsg = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(msg) or msg
    if type(safeMsg) ~= "string" then
        return msg
    end

    local ok, result = pcall(function()
        local output = safeMsg

        if type(ns.ApplyMentionRules) == "function" then
            output = ns.ApplyMentionRules(output, eventName, author, unpackValues(args, 1, argCount))
        end

        output = DecorateLinksInText(output)

        return output
    end)

    if ok and type(result) == "string" then
        return result
    end

    return msg
end

local function SystemOnlyFilter(self, event, msg, author, ...)
    local db = DB()
    if db and db.hideSystemSpam and SystemEvents[event] then
        return true
    end

    return false, msg, author, ...
end

local function LegacyMessageProcessor(self, event, msg, author, ...)
    local db = DB()
    if not db then
        return false, msg, author, ...
    end

    if db.hideSystemSpam and SystemEvents[event] then
        return true
    end

    if type(ns.CanMutateChatPayload) == "function" then
        if not ns.CanMutateChatPayload(event, msg, author, ...) then
            return false, msg, author, ...
        end
    else
        if IsSecretValue(msg) or IsSecretValue(author) then
            return false, msg, author, ...
        end

        if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
            return false, msg, author, ...
        end

        if type(msg) ~= "string" then
            return false, msg, author, ...
        end
    end

    if type(ns.ProcessSpamMessage) == "function" and ns.ProcessSpamMessage(event, msg, author, ...) then
        return true
    end

    return false, ns.FormatMessage(msg, event, author, ...), author, ...
end

local function RetailRestrictedProcessor(self, event, msg, author, ...)
    if type(ns.IsWhisperSensitiveEvent) == "function" and ns.IsWhisperSensitiveEvent(event) then
        return false, msg, author, ...
    end

    local db = DB()
    if not db then
        return false, msg, author, ...
    end

    if db.hideSystemSpam and SystemEvents[event] then
        return true
    end

    if type(ns.CanMutateChatPayload) == "function" then
        if not ns.CanMutateChatPayload(event, msg, author, ...) then
            return false, msg, author, ...
        end
    else
        if IsSecretValue(msg) or IsSecretValue(author) then
            return false, msg, author, ...
        end

        if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
            return false, msg, author, ...
        end

        if type(msg) ~= "string" then
            return false, msg, author, ...
        end
    end

    if type(ns.ProcessSpamMessage) == "function" and ns.ProcessSpamMessage(event, msg, author, ...) then
        return true
    end

    return false, ns.FormatMessage(msg, event, author, ...), author, ...
end

function Filters:HookCommunities()
    if communitiesHooked or IsVirtualMode() then
        return
    end

    if CommunitiesChatLineMixin and CommunitiesChatLineMixin.SetMessage then
        local function callback(frame, messageInfo)
            if not messageInfo or not messageInfo.text or not frame or not frame.Message then
                return
            end

            local sourceText = messageInfo.text
            if IsSecretValue(sourceText) then
                return
            end
            if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(sourceText) then
                return
            end

            local formatter = ns.FormatMessage
            local ok, formatted = pcall(formatter, sourceText, "CHAT_MSG_COMMUNITIES_CHANNEL", messageInfo.author or messageInfo.sender or messageInfo.displayName)
            local finalText = ok and formatted or sourceText
            if finalText then
                frame.Message:SetText(finalText)
            end

            if ns.db and ns.Lists and ns.Lists.Fonts then
                local fontId = ns.db.fontID
                local fontPath = nil
                if type(ns.ResolveFontPath) == "function" then
                    fontPath = ns.ResolveFontPath(fontId)
                elseif fontId then
                    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
                    fontPath = LSM and LSM.Fetch and LSM:Fetch("font", fontId, true) or nil
                end
                if fontPath then
                    local _, size, flags = frame.Message:GetFont()
                    if type(ns.SafeSetFont) == "function" then
                        ns.SafeSetFont(frame.Message, fontPath, size, flags)
                    else
                        pcall(frame.Message.SetFont, frame.Message, fontPath, size, flags)
                    end
                end
            end
        end

        local hooked = false
        if type(ns.SafeSecureHook) == "function" then
            hooked = ns.SafeSecureHook(self, CommunitiesChatLineMixin, "SetMessage", callback)
        elseif type(self.SecureHook) == "function" then
            hooked = pcall(self.SecureHook, self, CommunitiesChatLineMixin, "SetMessage", callback) and true or false
        end
        communitiesHooked = hooked or communitiesHooked
    end
end

function Filters:ADDON_LOADED(_, name)
    if name == "Blizzard_Communities" then
        self:HookCommunities()
        if type(self.UnregisterEvent) == "function" then
            pcall(self.UnregisterEvent, self, "ADDON_LOADED")
        end
    end
end

function Filters:OnEnable()
    ns.UpdateSpamCache()

    if Chatify and Chatify.db and Chatify.db.profile then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
    end

    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "FRIENDLIST_UPDATE", "FRIENDLIST_UPDATE")
        ns.RegisterEventIfSupported(self, "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED")
    else
        pcall(self.RegisterEvent, self, "FRIENDLIST_UPDATE", "FRIENDLIST_UPDATE")
        pcall(self.RegisterEvent, self, "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED")
    end

    if not filtersInstalled then
        if IsRetailRestricted() then
            for i = 1, #RetailRestrictedEvents do
                RegisterMessageFilter(RetailRestrictedEvents[i], RetailRestrictedProcessor)
            end

            for eventName in pairs(SystemEvents) do
                RegisterMessageFilter(eventName, RetailRestrictedProcessor)
            end
        elseif IsVirtualMode() then
            for eventName in pairs(SystemEvents) do
                RegisterMessageFilter(eventName, SystemOnlyFilter)
            end
        else
            for i = 1, #BaseEvents do
                RegisterMessageFilter(BaseEvents[i], LegacyMessageProcessor)
            end

            for eventName in pairs(SystemEvents) do
                RegisterMessageFilter(eventName, LegacyMessageProcessor)
            end
        end

        filtersInstalled = true
    end

    if type(ns.IsAddOnLoadedCompat) == "function" and ns.IsAddOnLoadedCompat("Blizzard_Communities") then
        self:HookCommunities()
    elseif C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_Communities")
        if ok and loaded then
            self:HookCommunities()
        elseif type(ns.RegisterEventIfSupported) == "function" then
            ns.RegisterEventIfSupported(self, "ADDON_LOADED", "ADDON_LOADED")
        else
            pcall(self.RegisterEvent, self, "ADDON_LOADED")
        end
    elseif type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "ADDON_LOADED", "ADDON_LOADED")
    else
        pcall(self.RegisterEvent, self, "ADDON_LOADED")
    end
end


function Filters:OnDisable()
    UnregisterMessageFilters()
    self:UnregisterAllEvents()
    if type(self.UnhookAll) == "function" then
        self:UnhookAll()
    end
    communitiesHooked = false
end
