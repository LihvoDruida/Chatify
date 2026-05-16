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
local registeredFilters = {}

local function RegisterMessageFilter(eventName, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return false
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

    if db.enableSpamFilter and ns.IsSpamMessage(msg) then
        return true
    end

    return false, ns.FormatMessage(msg), author, ...
end

local function RetailRestrictedProcessor(self, event, msg, author, ...)
    if type(ns.IsWhisperSensitiveEvent) == "function" and ns.IsWhisperSensitiveEvent(event) then
        return false, msg, author, ...
    end

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

    if db.enableSpamFilter and ns.IsSpamMessage(msg) then
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

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
        self:HookCommunities()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
end


function Filters:OnDisable()
    UnregisterMessageFilters()
    self:UnregisterAllEvents()
    if type(self.UnhookAll) == "function" then
        self:UnhookAll()
    end
end
