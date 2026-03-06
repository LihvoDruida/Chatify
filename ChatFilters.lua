local addonName, ns = ...
local Chatify = ns.Chatify
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local string_find = string.find
local string_gsub = string.gsub
local string_upper = string.upper
local UnitName = UnitName

local PLAYER_NAME = UnitName("player")
local CachedKeywords = {}

local SystemEvents = {
    CHAT_MSG_CHANNEL_JOIN = true,
    CHAT_MSG_CHANNEL_LEAVE = true,
    CHAT_MSG_CHANNEL_NOTICE = true,
    CHAT_MSG_CHANNEL_NOTICE_USER = true,
}

local BaseEvents = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
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
    return db and db.useVirtualChat
end

local function NormalizeText(text)
    local safe = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(text) or text
    if type(safe) ~= "string" then
        return ""
    end

    local ok, normalized = pcall(function()
        local value = safe
        value = string_gsub(value, "|c%x%x%x%x%x%x%x%x", "")
        value = string_gsub(value, "|H.-|h.-|h", "")
        value = string_gsub(value, "|r", "")
        value = string_gsub(value, "[%s%p%c]", "")
        return string_upper(value)
    end)

    if ok and type(normalized) == "string" then
        return normalized
    end

    return ""
end

function ns.UpdateSpamCache()
    local db = DB()
    CachedKeywords = {}

    if not db or not db.spamKeywords then
        return
    end

    for i = 1, #db.spamKeywords do
        local word = db.spamKeywords[i]
        if word and word ~= "" then
            tinsert(CachedKeywords, NormalizeText(word))
        end
    end
end

function ns.IsSpamMessage(normalizedMessage)
    if normalizedMessage == "" then
        return false
    end

    for i = 1, #CachedKeywords do
        local keyword = CachedKeywords[i]
        if keyword ~= "" and string_find(normalizedMessage, keyword, 1, true) then
            return true
        end
    end

    return false
end

local function DecorateLink(url)
    local db = DB()
    if not db then
        return url
    end

    local cleanUrl = url:gsub("[%.,:;!'\"%)%]]+$", "")
    local color = db.urlColor or "0099FF"
    return string.format("|cff%s|Hurl:%s|h[%s]|h|r", color, cleanUrl, cleanUrl)
end

local function IsProtected(text, pos)
    local prefix = text:sub(1, pos)
    local _, openCount = prefix:gsub("|H", "")
    local _, closeCount = prefix:gsub("|h", "")
    return openCount > (closeCount / 2)
end

function ns.FormatMessage(msg)
    local db = DB()
    if type(msg) ~= "string" or not db then
        return msg
    end

    if IsVirtualMode() then
        return msg
    end

    local safeMsg = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(msg) or msg
    if type(safeMsg) ~= "string" then
        return msg
    end

    local ok, result = pcall(function()
        local output = safeMsg

        if db.highlightKeywords then
            for i = 1, #db.highlightKeywords do
                local word = db.highlightKeywords[i]
                if word and word ~= "" then
                    local escaped = word:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
                    output = output:gsub("(" .. escaped .. ")", function(match)
                        local s = output:find(match, 1, true)
                        if s and IsProtected(output, s) then
                            return match
                        end
                        return "|cff" .. (db.myHighlightColor or "ff0000") .. match .. "|r"
                    end)
                end
            end
        end

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

                if isValid and IsProtected(output, s) then
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

        if PLAYER_NAME and PLAYER_NAME ~= "" then
            local escaped = string_gsub(PLAYER_NAME, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
            output = string_gsub(output, "(" .. escaped .. ")", function(match)
                local s = string_find(output, match, 1, true)
                if s and IsProtected(output, s) then
                    return match
                end
                return "|cffffd700" .. match .. "|r"
            end)
        end

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

    if type(msg) ~= "string" then
        return false, msg, author, ...
    end

    if db.enableSpamFilter and ns.IsSpamMessage(NormalizeText(msg)) then
        return true
    end

    return false, ns.FormatMessage(msg), author, ...
end

function Filters:HookCommunities()
    if IsVirtualMode() then
        return
    end

    if CommunitiesChatLineMixin and CommunitiesChatLineMixin.SetMessage then
        self:SecureHook(CommunitiesChatLineMixin, "SetMessage", function(frame, messageInfo)
            if not messageInfo or not messageInfo.text then
                return
            end

            local ok, formatted = pcall(ns.FormatMessage, messageInfo.text)
            frame.Message:SetText(ok and formatted or messageInfo.text)

            if ns.db and ns.Lists and ns.Lists.Fonts then
                local fontId = ns.db.fontID
                local fontPath = fontId and LibStub("LibSharedMedia-3.0"):Fetch("font", fontId)
                if fontPath then
                    local _, size, flags = frame.Message:GetFont()
                    frame.Message:SetFont(fontPath, size, flags)
                end
            end
        end)
    end
end

function Filters:ADDON_LOADED(_, name)
    if name == "Blizzard_Communities" then
        self:HookCommunities()
        self:UnregisterEvent("ADDON_LOADED")
    end
end

function Filters:OnEnable()
    ns.UpdateSpamCache()

    if IsVirtualMode() then
        for eventName in pairs(SystemEvents) do
            ChatFrame_AddMessageEventFilter(eventName, SystemOnlyFilter)
        end
        return
    end

    for i = 1, #BaseEvents do
        ChatFrame_AddMessageEventFilter(BaseEvents[i], LegacyMessageProcessor)
    end

    for eventName in pairs(SystemEvents) do
        ChatFrame_AddMessageEventFilter(eventName, LegacyMessageProcessor)
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
        self:HookCommunities()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
end
