local addonName, ns = ...
local Chatify = ns.Chatify
local Filters = Chatify:NewModule("Filters", "AceEvent-3.0", "AceHook-3.0")

local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local string_find = string.find
local string_gsub = string.gsub
local string_upper = string.upper
local table_concat = table.concat
local UnitName = UnitName

local PLAYER_NAME = UnitName("player")
local CachedKeywords = {}

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

-- Retail 12.x: use Blizzard's secure message-event filter path only.
-- These callbacks are wrapped by ChatFrameUtil's secure registry and will only
-- run when the event payload is accessible via canaccessvalue(...).
local RetailRestrictedEvents = {
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
    return db and db.useVirtualChat
end

local function IsRetailRestricted()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
end

local function NormalizeText(text)
    if IsSecretValue(text) then
        return ""
    end

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

    return TransformPlainTextSegments(text, DecorateLinksInSegment)
end

local function HighlightWordList(text, words, color)
    if type(text) ~= "string" or IsSecretValue(text) or type(words) ~= "table" or #words == 0 then
        return text
    end

    local function apply(segment)
        local output = segment
        for i = 1, #words do
            local word = words[i]
            if word and word ~= "" then
                local escaped = word:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
                output = output:gsub("(" .. escaped .. ")", "|cff" .. color .. "%1|r")
            end
        end
        return output
    end

    return TransformPlainTextSegments(text, apply)
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

function ns.FormatMessage(msg)
    local db = DB()
    if type(msg) ~= "string" or not db then
        return msg
    end


    local safeMsg = type(ns.TryMakeSafeText) == "function" and ns.TryMakeSafeText(msg) or msg
    if type(safeMsg) ~= "string" then
        return msg
    end

    local ok, result = pcall(function()
        local output = safeMsg

        if db.highlightKeywords then
            output = HighlightWordList(output, db.highlightKeywords, db.myHighlightColor or "ff0000")
        end

        output = DecorateLinksInText(output)

        if PLAYER_NAME and PLAYER_NAME ~= "" then
            output = HighlightWordList(output, { PLAYER_NAME }, "ffd700")
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

    if IsSecretValue(msg) or IsSecretValue(author) then
        return false, msg, author, ...
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
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

local function RetailRestrictedProcessor(self, event, msg, author, ...)
    local db = DB()
    if not db then
        return false, msg, author, ...
    end

    if IsSecretValue(msg) or IsSecretValue(author) then
        return false, msg, author, ...
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
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
            local ok, formatted = pcall(formatter, sourceText)
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
                    fontPath = LibStub("LibSharedMedia-3.0"):Fetch("font", fontId, true)
                end
                if fontPath then
                    local _, size, flags = frame.Message:GetFont()
                    pcall(frame.Message.SetFont, frame.Message, fontPath, size, flags)
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

    if Chatify and Chatify.db and Chatify.db.profile then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
    end

    if not filtersInstalled then
        if IsRetailRestricted() then
            for i = 1, #RetailRestrictedEvents do
                if type(ns.AddMessageEventFilterIfSupported) == "function" then
                    ns.AddMessageEventFilterIfSupported(RetailRestrictedEvents[i], RetailRestrictedProcessor)
                else
                    ChatFrame_AddMessageEventFilter(RetailRestrictedEvents[i], RetailRestrictedProcessor)
                end
            end

            for eventName in pairs(SystemEvents) do
                if type(ns.AddMessageEventFilterIfSupported) == "function" then
                    ns.AddMessageEventFilterIfSupported(eventName, RetailRestrictedProcessor)
                else
                    ChatFrame_AddMessageEventFilter(eventName, RetailRestrictedProcessor)
                end
            end
        elseif IsVirtualMode() then
            for eventName in pairs(SystemEvents) do
                if type(ns.AddMessageEventFilterIfSupported) == "function" then
                    ns.AddMessageEventFilterIfSupported(eventName, SystemOnlyFilter)
                else
                    ChatFrame_AddMessageEventFilter(eventName, SystemOnlyFilter)
                end
            end
        else
            for i = 1, #BaseEvents do
                if type(ns.AddMessageEventFilterIfSupported) == "function" then
                    ns.AddMessageEventFilterIfSupported(BaseEvents[i], LegacyMessageProcessor)
                else
                    ChatFrame_AddMessageEventFilter(BaseEvents[i], LegacyMessageProcessor)
                end
            end

            for eventName in pairs(SystemEvents) do
                if type(ns.AddMessageEventFilterIfSupported) == "function" then
                    ns.AddMessageEventFilterIfSupported(eventName, LegacyMessageProcessor)
                else
                    ChatFrame_AddMessageEventFilter(eventName, LegacyMessageProcessor)
                end
            end
        end

        filtersInstalled = true
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
        self:HookCommunities()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
end
