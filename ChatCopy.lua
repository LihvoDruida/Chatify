local addonName, ns = ...
local Chatify = ns.Chatify
local CopyModule = Chatify:NewModule("Copy", "AceHook-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

-- =========================================================
-- 1. КЕШУВАННЯ ДЛЯ КОПІЮВАННЯ
-- =========================================================
local msgCache = {}
local msgIndex = 0
local fullChatCache = {}
local fullChatIndex = 0
local CACHE_SIZE = 500
local COPY_WINDOW_MAX_LINES = 250
local HISTORY_WINDOW_MAX_LINES = 500
local COPY_WINDOW_MAX_CHARS = 60000
local CHAT_CAPTURE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_ACHIEVEMENT",
}

-- Modern Retail-safe capture list. We still keep copy cache useful for normal
-- public/group chat, but avoid registering sensitive whisper/BN/emote/achievement
-- payloads. Protected lines remain available through Blizzard native selection.
local RETAIL_CHAT_CAPTURE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
}
local captureFrame
local captureRegisteredCount = 0
local lastEntrySignature
local lastEntryTime = 0

local PLAYER_COLORS = {
    "ff7ad7ff", "ffffd36b", "ff9dff7a", "ffff9a9a", "ffc79cff",
    "ff7affb2", "ffffb86b", "ff9ab7ff", "ffff7adf", "ffb7ffea",
}

local function IsProtectedChatValue(value)
    if type(ns.IsProtectedChatValue) == "function" then
        local ok, protected = pcall(ns.IsProtectedChatValue, value)
        if ok then
            return protected and true or false
        end
        return true
    end

    if type(ns.IsSecretValue) == "function" then
        local ok, secret = pcall(ns.IsSecretValue, value)
        if ok and secret then
            return true
        end
    end

    if type(ns.CanAccessChatValue) == "function" then
        local ok, accessible = pcall(ns.CanAccessChatValue, value)
        if ok and not accessible then
            return true
        elseif not ok then
            return true
        end
    end

    return false
end

local function SafeChatText(value)
    if IsProtectedChatValue(value) then
        return nil
    end

    if type(ns.TryMakeSafeText) == "function" then
        local ok, safe = pcall(ns.TryMakeSafeText, value)
        if ok and type(safe) == "string" then
            return safe
        elseif not ok then
            return nil
        end
    end

    if type(value) == "number" then
        return tostring(value)
    end

    if type(value) == "string" then
        return value
    end

    return nil
end

local function IsNonEmptyString(value)
    if type(value) ~= "string" then
        return false
    end

    local ok, length = pcall(string.len, value)
    return ok and length > 0
end

local function GetMessagePayload(value)
    if type(value) ~= "table" then
        return value
    end

    return value.message or value.text or value[1]
end

local function GetMessageAuthor(value)
    if type(value) ~= "table" then
        return nil
    end

    return value.author or value.sender or value.playerName or value[2]
end

local function StripChatMarkup(text)
    local safe = SafeChatText(text)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, clean = pcall(function()
        local value = safe
        -- Prat-style safety: replace protected/K hyperlinks with a visible marker,
        -- then strip normal color/texture/hyperlink markup without touching secret payloads.
        value = value:gsub("|K.-|k", "<protected>")
        value = value:gsub("|W.-|w", "<protected>")

        -- Colour openers come in two forms and BOTH have to go before |r does.
        --
        --   |cffa335ee            classic, eight hex digits
        --   |cnITEM_QUALITY4_COLOR:   named, added in 11.x
        --
        -- Only the classic form was handled, so a named opener survived while its
        -- |r was stripped - which is why every character after an item link or a
        -- URL stayed purple or blue to the end of the line.
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|c[nN][%w_]+:", "")
        value = value:gsub("|r", "")

        value = value:gsub("|H.-|h(.-)|h", "%1")
        value = value:gsub("|A:Professions%-ChatIcon%-Quality%-Tier(%d):.-|a", "%1*")
        value = value:gsub("|A.-|a", "")
        value = value:gsub("|T.-|t", "")
        -- |4singular:plural; pluralisation, e.g. "2 |4hour:hours;". The game
        -- resolves this at render time; copied text kept the raw markup, so
        -- "1 |4day:days;, 2 |4hour:hours;" was what landed on the clipboard.
        -- The number immediately before it picks the form.
        value = value:gsub("(%d+)%s*|4([^:;]*):([^;]*);", function(count, one, many)
            return count .. " " .. ((tonumber(count) == 1) and one or many)
        end)
        -- Any left over with no number in front: take the plural, which is what
        -- Blizzard falls back to.
        value = value:gsub("|4([^:;]*):([^;]*);", "%2")

        value = value:gsub("||", "|")
        return value
    end)

    if ok and not IsProtectedChatValue(clean) and IsNonEmptyString(clean) then
        return clean
    end

    return nil
end

local function NormalizeName(author)
    local safe = SafeChatText(author)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, name = pcall(function()
        local value = safe
        value = value:gsub("|K.-|k", "")
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|H.-|h%[?(.-)%]?|h", "%1")
        value = value:gsub("^%[", ""):gsub("%]$", "")
        value = value:gsub("%-.+$", "")
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        return value
    end)

    if ok and not IsProtectedChatValue(name) and IsNonEmptyString(name) then
        return name
    end

    return nil
end

local function ExtractAuthorFromText(text)
    local safe = SafeChatText(text)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, author = pcall(function()
        local _, linkName = safe:match("|Hplayer:([^|:]+)[^|]*|h%[?([^%]|]+)%]?|h")
        if linkName then
            return NormalizeName(linkName)
        end

        -- Any other player-ish hyperlink type.
        --
        -- 12.1 relays Discord messages into guild chat, and those senders are not
        -- |Hplayer: links - they carry their own link type with no guarantee about
        -- its name. Rather than hardcoding a tag that may be renamed before the
        -- patch ships, this takes the visible text of the FIRST hyperlink on the
        -- line, which is where the sender sits in every chat format the game uses.
        --
        -- Channel links are excluded explicitly: on a line like
        -- "|Hchannel:GUILD|h[Guild]|h |Hplayer:Bob|h[Bob]|h: hi" the channel tag
        -- comes first and is emphatically not the author.
        -- gmatch rather than match: the channel tag is the leftmost link on most
        -- lines, so a single match would find it, get rejected, and give up.
        for linkType, visible in safe:gmatch("|H([%a]+):[^|]*|h%[?([^%]|]+)%]?|h") do
            if linkType:lower() ~= "channel" then
                local normalized = NormalizeName(visible)
                if normalized and #normalized <= 32 then
                    return normalized
                end
            end
        end

        local bracketName = safe:match("^%s*%[([^%]]+)%]%s*:")
        if bracketName then
            return NormalizeName(bracketName)
        end

        -- Last resort: "Name: message" with no markup at all.
        --
        -- This used to accept anything before the first colon, which swallowed
        -- system lines: "Total time played: 1 day..." made "Total time played"
        -- the author, and since the payload was never trimmed the line came out
        -- as "Total time played: Total time played: 1 day...".
        --
        -- A character name is a single token - no spaces, no punctuation beyond
        -- the realm separator - so requiring that rules system text out while
        -- still catching a genuinely unlinked sender.
        local plainName = safe:match("^%s*([^%s:%[%]]+)%s*:")
        if plainName and #plainName <= 32 and not plainName:find("%d%d") then
            return NormalizeName(plainName)
        end

        return nil
    end)

    if ok and IsNonEmptyString(author) then
        return author
    end

    return nil
end

local function GetNameColor(name)
    name = NormalizeName(name)
    if not name then
        return "ffffffff"
    end

    local hash = 0
    for i = 1, #name do
        hash = (hash + name:byte(i) * i) % #PLAYER_COLORS
    end
    return PLAYER_COLORS[hash + 1]
end

local function ColorName(name)
    name = NormalizeName(name)
    if not name then
        return ""
    end
    return "|c" .. GetNameColor(name) .. name .. "|r"
end

-- Leading-timestamp extraction.
--
-- ReadMessageHistory pulls fully rendered lines out of the chat frame via
-- GetMessageInfo, so whatever timestamp is visible in chat is already part of the
-- text. BuildEntry then prefixed its own [HH:MM:SS], which is where the doubled
-- timestamps in the copy window came from. It became visible to everyone on 12.0+
-- because Chatify now drives Blizzard's own showTimestamps CVar there, so a
-- timestamp is present even when Chatify's filter never ran.
--
-- The leading stamp is therefore parsed off and reused as the entry's time, which
-- also fixes a quieter bug: with no timestamp argument the entry fell back to
-- time(), stamping every copied line with the moment the window was opened rather
-- than when the message arrived.
--
-- Patterns are anchored and deliberately narrow. Anything that does not look like
-- a clock is left alone - mangling a real message is far worse than showing one
-- redundant timestamp.
local timestampStripPatterns = {
    -- Chatify's own: [12:30], [12:30:45], [12:30 PM], [08.02 12:30]
    "^%[%s*%d%d?%.%d%d?%s+%d%d?:%d%d%s*%]%s*",
    "^%[%s*%d%d?:%d%d:%d%d%s*[AaPp]?%.?[Mm]?%.?%s*%]%s*",
    "^%[%s*%d%d?:%d%d%s*[AaPp]?%.?[Mm]?%.?%s*%]%s*",
    -- Blizzard's showTimestamps CVar renders without brackets.
    "^%d%d?:%d%d:%d%d%s+[AaPp]%.?[Mm]%.?%s+",
    "^%d%d?:%d%d%s+[AaPp]%.?[Mm]%.?%s+",
    "^%d%d?:%d%d:%d%d%s+",
    "^%d%d?:%d%d%s+",
}

-- Returns the text with any leading timestamp removed, plus the stamp itself.
local function SplitLeadingTimestamp(text)
    if type(text) ~= "string" or text == "" then
        return text, nil
    end

    for i = 1, #timestampStripPatterns do
        local ok, stamp = pcall(string.match, text, timestampStripPatterns[i])
        if ok and stamp then
            local okRest, rest = pcall(string.gsub, text, timestampStripPatterns[i], "", 1)
            if okRest and type(rest) == "string" and rest ~= "" then
                -- Normalise to the copy window's own HH:MM:SS column width by
                -- keeping the stamp as written; padding it out would invent
                -- seconds the original line never had.
                stamp = stamp:gsub("^%s*%[?%s*", ""):gsub("%s*%]?%s*$", "")
                return rest, (stamp ~= "" and stamp or nil)
            end
        end
    end

    return text, nil
end

local function BuildProtectedEntry(label, timestamp)
    local fallback = L("Protected chat line omitted.")
    local safeLabel = StripChatMarkup(label) or fallback
    return {
        text = safeLabel,
        raw = safeLabel,
        author = nil,
        time = date("%H:%M:%S", tonumber(timestamp) or time()),
        protected = true,
    }
end

local function BuildEntry(text, author, timestamp)
    local rawPayload = GetMessagePayload(text)
    local rawAuthor = author or GetMessageAuthor(text)
    local cleanText = StripChatMarkup(rawPayload)
    if not IsNonEmptyString(cleanText) then
        return nil
    end

    -- Strip before the author is derived, so a leading stamp cannot be mistaken
    -- for the sender by ExtractAuthorFromText.
    local embeddedTime
    cleanText, embeddedTime = SplitLeadingTimestamp(cleanText)
    if not IsNonEmptyString(cleanText) then
        return nil
    end

    local cleanAuthor = NormalizeName(rawAuthor) or ExtractAuthorFromText(rawPayload) or ExtractAuthorFromText(cleanText)

    -- Precedence: an explicit timestamp argument (the live filter path knows
    -- exactly when the message arrived), then the stamp already in the line, then
    -- the clock as a last resort.
    local timeText
    if tonumber(timestamp) then
        timeText = date("%H:%M:%S", tonumber(timestamp))
    elseif embeddedTime then
        timeText = embeddedTime
    else
        timeText = date("%H:%M:%S", time())
    end

    return {
        text = cleanText,
        raw = cleanText,
        author = cleanAuthor,
        time = timeText,
    }
end

-- Removes a leading "Author: " / "Author says: " from the payload when the entry
-- already carries that author separately. Anchored and exact: if the text does
-- not literally start with this author, it is left completely alone.
local function StripLeadingAuthor(text, author)
    if not IsNonEmptyString(text) or not IsNonEmptyString(author) then
        return text
    end

    local ok, result = pcall(function()
        local escaped = author:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        -- Optional realm suffix, then the separator the game uses.
        local stripped = text:gsub("^%s*" .. escaped .. "%-?[^%s:]*%s*:%s*", "", 1)
        if stripped ~= text and stripped ~= "" then
            return stripped
        end
        return text
    end)

    if ok and IsNonEmptyString(result) then
        return result
    end
    return text
end

local function BuildPlainLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry)
    end
    if type(entry) ~= "table" then
        return nil
    end

    local text = StripChatMarkup(entry.text)
    if not IsNonEmptyString(text) then
        return nil
    end

    local author = NormalizeName(entry.author)
    if IsNonEmptyString(author) then
        -- The rendered payload usually still begins with the sender, because it
        -- is the same string the author was derived from. Emitting both is what
        -- produced doubled prefixes; drop the one already in the text.
        text = StripLeadingAuthor(text, author)
        return string.format("[%s] %s: %s", entry.time or "--:--:--", author, text)
    end

    return string.format("[%s] %s", entry.time or "--:--:--", text)
end

local function BuildColoredLine(entry)
    if type(entry) == "string" then
        return StripChatMarkup(entry) or ""
    end
    if type(entry) ~= "table" then
        return ""
    end

    local text = StripChatMarkup(entry.text)
    if not IsNonEmptyString(text) then
        return ""
    end

    local timeText = string.format("|cff888888[%s]|r", entry.time or "--:--:--")
    local author = NormalizeName(entry.author)
    if IsNonEmptyString(author) then
        text = StripLeadingAuthor(text, author)
        return string.format("%s %s: %s", timeText, ColorName(author), text)
    end

    return string.format("%s %s", timeText, text)
end

local function AddFullChatEntry(entry)
    if type(entry) ~= "table" then
        return
    end

    fullChatIndex = fullChatIndex + 1
    fullChatCache[fullChatIndex] = entry

    local pruneBefore = fullChatIndex - CACHE_SIZE
    if pruneBefore > 0 then
        fullChatCache[pruneBefore] = nil
    end
end

function ns.SaveToCache(text, author, timestamp)
    local safeText = SafeChatText(text)
    if not IsNonEmptyString(safeText) then
        return nil
    end

    local safeAuthor = SafeChatText(author)
    local entry = BuildEntry(safeText, safeAuthor, timestamp)
    if not entry then
        return nil
    end

    local now = time()
    local signature = (entry.author or "") .. "\31" .. (entry.text or "")
    if signature == lastEntrySignature and (now - lastEntryTime) <= 1 then
        return msgIndex > 0 and msgIndex or nil
    end
    lastEntrySignature = signature
    lastEntryTime = now

    msgIndex = msgIndex + 1
    msgCache[msgIndex] = entry
    AddFullChatEntry(entry)

    if msgIndex > CACHE_SIZE + 50 then
        for i = msgIndex - CACHE_SIZE - 50, msgIndex - CACHE_SIZE do
            msgCache[i] = nil
        end
    end

    return msgIndex
end

-- =========================================================
-- 2. ВІКНО КОПІЮВАННЯ
-- =========================================================
local copyFrame
local copyEditBox
local copyTitle
local copyScroll
local copyContent
local copyHint
local copyButton
local copyPreviewBg
local copyTabs
local copyTabPrevButton
local copyTabNextButton
local copyTabButtons = {}
local copyTabOffset = 1
local copyAvailableTabs = {}
local copyCurrentFrame
local copyCurrentMaxLines = COPY_WINDOW_MAX_LINES
local copyWindowMode = "copy"
local copyTextValue = ""
local copySettingText = false
local nativeCopySessions = setmetatable({}, { __mode = "k" })
local nativeCopySessionId = 0
local nativeCopyActiveSessionId
local nativeCopyGuardFrame
local nativeCopyLastBlockedWarning = 0
local GetPreferredChatFrame
local GetCopyDB

local function IsInCombatLockdown()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function SafeFrameCall(frame, methodName, ...)
    if not frame or type(methodName) ~= "string" then
        return false
    end

    local method = frame[methodName]
    if type(method) ~= "function" then
        return false
    end

    -- securecallfunction reduces taint propagation for Blizzard frame methods.
    -- It does not make protected calls legal in combat, so callers still avoid
    -- combat lockdown before toggling native chat selection.
    if type(securecallfunction) == "function" then
        local ok = pcall(securecallfunction, method, frame, ...)
        if ok then
            return true
        end
    end

    local ok = pcall(method, frame, ...)
    return ok and true or false
end

local function StartCopyFrameMoving(frame)
    if not frame or not frame.StartMoving then
        return
    end

    frame:StartMoving()
end

local function StopCopyFrameMoving(frame)
    if not frame or not frame.StopMovingOrSizing then
        return
    end

    frame:StopMovingOrSizing()
end

local function ScrollCopyWindow(delta)
    if not copyScroll or not copyScroll.GetVerticalScroll or not copyScroll.SetVerticalScroll then
        return
    end

    local step = 28
    local current = copyScroll:GetVerticalScroll() or 0
    local maxScroll = 0
    local scrollbar = _G["ChatifyCopyPreviewScrollScrollBar"]
    if scrollbar and scrollbar.GetMinMaxValues then
        local _, maxValue = scrollbar:GetMinMaxValues()
        maxScroll = tonumber(maxValue) or 0
    end

    local nextValue = current - ((tonumber(delta) or 0) * step)
    if nextValue < 0 then
        nextValue = 0
    elseif maxScroll > 0 and nextValue > maxScroll then
        nextValue = maxScroll
    end

    copyScroll:SetVerticalScroll(nextValue)
    if scrollbar and scrollbar.SetValue then
        scrollbar:SetValue(nextValue)
    end
end

local function CreateMoveHandle(parent, name, anchorFunc)
    local handle = CreateFrame("Frame", name, parent)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    anchorFunc(handle)
    handle:SetScript("OnDragStart", function()
        StartCopyFrameMoving(parent)
    end)
    handle:SetScript("OnDragStop", function()
        StopCopyFrameMoving(parent)
    end)
    handle:SetScript("OnMouseUp", function()
        StopCopyFrameMoving(parent)
    end)
    return handle
end


GetCopyDB = function()
    return Chatify and Chatify.db and Chatify.db.profile or nil
end

local function GetMaxCopyChatWindows()
    local total = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    if type(ns.GetMaxChatWindows) == "function" then
        local ok, value = pcall(ns.GetMaxChatWindows)
        if ok and type(value) == "number" and value > 0 then
            total = value
        end
    end

    return math.max(1, math.min(tonumber(total) or 10, 20))
end

local function GetChatFrameID(frame, fallbackIndex)
    local index = tonumber(fallbackIndex)
    if not index and frame and type(frame.GetID) == "function" then
        local ok, value = pcall(frame.GetID, frame)
        if ok and tonumber(value) then
            index = tonumber(value)
        end
    end

    return index
end

local function GetChatFrameDisplayName(frame, index)
    local fallback = string.format(L("Chat %d"), tonumber(index) or 1)
    if not frame then
        return fallback
    end

    local name
    local frameName
    if type(frame.GetName) == "function" then
        local ok, value = pcall(frame.GetName, frame)
        if ok and IsNonEmptyString(value) then
            frameName = value
        end
    end

    local frameID = GetChatFrameID(frame, index)
    if frameID and type(ns.CallChatAPI) == "function" then
        local ok, value = ns.CallChatAPI("FCF_GetChatWindowInfo", "GetChatWindowInfo", frameID)
        if ok and IsNonEmptyString(value) then
            name = value
        end
    end

    local tab = frameName and _G[frameName .. "Tab"]
    if not IsNonEmptyString(name) and tab and type(tab.GetText) == "function" then
        local ok, value = pcall(tab.GetText, tab)
        if ok and IsNonEmptyString(value) then
            name = value
        end
    end

    if not IsNonEmptyString(name) and frame.nameText and type(frame.nameText.GetText) == "function" then
        local ok, value = pcall(frame.nameText.GetText, frame.nameText)
        if ok and IsNonEmptyString(value) then
            name = value
        end
    end

    if not IsNonEmptyString(name) and frame.name and IsNonEmptyString(frame.name) then
        name = frame.name
    end

    if not IsNonEmptyString(name) then
        name = frameName
    end

    name = StripChatMarkup(name) or fallback
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name:match("^ChatFrame%d+$") then
        return fallback
    end
    return name
end


local function NormalizeCopyFrameNameForMatch(value)
    local safe = StripChatMarkup(value)
    if not IsNonEmptyString(safe) then
        return nil
    end

    local ok, normalized = pcall(function()
        local text = safe:gsub("^%s+", ""):gsub("%s+$", "")
        text = text:gsub("%s+", " ")
        return string.lower(text)
    end)

    if ok and IsNonEmptyString(normalized) then
        return normalized
    end

    return safe
end

local function CopyFrameNameMatchesGlobal(name, ...)
    local normalized = NormalizeCopyFrameNameForMatch(name)
    if not normalized then
        return false
    end

    for i = 1, select("#", ...) do
        local globalName = select(i, ...)
        local value = type(globalName) == "string" and _G[globalName] or nil
        local globalNormalized = NormalizeCopyFrameNameForMatch(value)
        if globalNormalized and normalized == globalNormalized then
            return true
        end
    end

    return false
end

local function IsExcludedCopyFrameName(name)
    local normalized = NormalizeCopyFrameNameForMatch(name)
    if not normalized then
        return false
    end

    if CopyFrameNameMatchesGlobal(name, "COMBAT_LOG", "COMBATLOG", "COMBAT_LOG_TAB", "COMBAT_TEXT_LABEL") then
        return true
    end

    if CopyFrameNameMatchesGlobal(name, "VOICE", "VOICE_CHAT", "VOICE_CHAT_CHANNEL", "VOICE_CHAT_CHANNELS") then
        return true
    end

    if normalized == "combat log" or normalized == "combatlog" then
        return true
    end
    if normalized:find("combat", 1, true) and normalized:find("log", 1, true) then
        return true
    end
    if normalized == "журнал боя" or normalized == "журнал бою" or normalized == "бойовий журнал" then
        return true
    end
    if normalized == "voice" or normalized == "voice chat" or normalized == "голос" or normalized == "голосовий чат" or normalized == "голосовой чат" then
        return true
    end

    return false
end

local function ChatFrameHasCopyBlockedMessages(frameID)
    if not frameID or type(_G.GetChatWindowMessages) ~= "function" then
        return false
    end

    local ok, messages = pcall(function()
        return { _G.GetChatWindowMessages(frameID) }
    end)
    if not ok or type(messages) ~= "table" then
        return false
    end

    for i = 1, #messages do
        local msgType = type(messages[i]) == "string" and messages[i] or ""
        -- Do not block generic COMBAT_* message groups here: normal General
        -- chat can contain XP/honor/faction combat notifications. Combat Log is
        -- handled by ChatFrame2 / FCF_IsWindowIDCombatLog / tab name checks.
        if msgType == "VOICE" or msgType == "VOICE_TEXT" or msgType == "VOICE_CHAT" or msgType:find("^VOICE_") then
            return true
        end
    end

    return false
end

local function IsCopyBlockedChatFrame(frame, index)
    local frameID = GetChatFrameID(frame, index)

    -- Blizzard reserves ChatFrame2 for the Combat Log on default layouts. Never
    -- expose it in ChatCopy even if it is docked, hidden, renamed, or manually selected.
    if frameID == 2 then
        return true
    end

    if frameID and type(ns.CallChatAPI) == "function" then
        local ok, isCombatLog = ns.CallChatAPI("FCF_IsWindowIDCombatLog", "IsWindowIDCombatLog", frameID)
        if ok and isCombatLog then
            return true
        end
    end

    if frameID and ChatFrameHasCopyBlockedMessages(frameID) then
        return true
    end

    if IsExcludedCopyFrameName(GetChatFrameDisplayName(frame, frameID or index)) then
        return true
    end

    return false
end

local function IsChatFrameVisibleForCopy(frame)
    if not frame then
        return false
    end

    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and shown then
            return true
        end
    end

    if type(frame.GetName) == "function" then
        local okName, frameName = pcall(frame.GetName, frame)
        local tab = okName and frameName and _G[frameName .. "Tab"]
        if tab and type(tab.IsShown) == "function" then
            local okTab, shown = pcall(tab.IsShown, tab)
            if okTab and shown then
                return true
            end
        end
    end

    return false
end

local function GetChatFrameMessageCount(chatFrame)
    if not chatFrame or type(chatFrame.GetNumMessages) ~= "function" then
        return nil
    end

    local ok, value = pcall(chatFrame.GetNumMessages, chatFrame)
    if ok and type(value) == "number" then
        return math.max(0, value)
    end

    return nil
end

local function GetCopyFrameKey(frame, index)
    local frameID = GetChatFrameID(frame, index)
    if frameID and frameID > 0 then
        return "frame:" .. frameID
    end

    if frame and type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and IsNonEmptyString(name) then
            return "name:" .. name
        end
    end

    return "frame:" .. tostring(frame or index or "unknown")
end

local function AddCopyFrameCandidate(list, seen, frame, index)
    if not frame or seen[frame] then
        return
    end

    if type(frame.GetNumMessages) ~= "function" and type(frame.GetRegions) ~= "function" then
        return
    end

    seen[frame] = true
    local frameID = GetChatFrameID(frame, index)
    list[#list + 1] = {
        frame = frame,
        index = frameID or index,
        key = GetCopyFrameKey(frame, frameID or index),
        visible = IsChatFrameVisibleForCopy(frame),
    }
end

local function CollectCopyFrameCandidates(preferred)
    local list, seen = {}, {}
    AddCopyFrameCandidate(list, seen, preferred, GetChatFrameID(preferred))
    AddCopyFrameCandidate(list, seen, GetPreferredChatFrame and GetPreferredChatFrame(preferred), nil)
    AddCopyFrameCandidate(list, seen, SELECTED_CHAT_FRAME, nil)
    AddCopyFrameCandidate(list, seen, DEFAULT_CHAT_FRAME, nil)

    local dock = _G.GeneralDockManager
    if type(dock) == "table" then
        AddCopyFrameCandidate(list, seen, dock.primary, nil)
        AddCopyFrameCandidate(list, seen, dock.selected, nil)
        if type(dock.DOCKED_CHAT_FRAMES) == "table" then
            for _, frame in pairs(dock.DOCKED_CHAT_FRAMES) do
                AddCopyFrameCandidate(list, seen, frame, nil)
            end
        end
        if type(dock.DOCKED_CHAT_FRAME_ORDER) == "table" then
            for _, frame in ipairs(dock.DOCKED_CHAT_FRAME_ORDER) do
                AddCopyFrameCandidate(list, seen, frame, nil)
            end
        end
    end

    local total = GetMaxCopyChatWindows()
    for i = 1, total do
        AddCopyFrameCandidate(list, seen, _G["ChatFrame" .. i], i)
    end

    table.sort(list, function(a, b)
        local ai = tonumber(a.index) or 999
        local bi = tonumber(b.index) or 999
        if ai == bi then
            return tostring(a.key) < tostring(b.key)
        end
        return ai < bi
    end)

    return list
end

local function GetCopyTabMode()
    local db = GetCopyDB and GetCopyDB()
    local mode = db and db.copyTabMode
    if mode == "ALL" or mode == "VISIBLE" or mode == "PINNED" or mode == "SELECTED" then
        return mode
    end
    return "VISIBLE"
end

local function IsCopyFrameAllowedForTabs(info, preferred)
    if type(info) ~= "table" or not info.frame then
        return false
    end

    if IsCopyBlockedChatFrame(info.frame, info.index) then
        return false
    end

    local mode = GetCopyTabMode()
    if mode == "SELECTED" and info.frame ~= preferred then
        return false
    end
    if mode == "VISIBLE" and not info.visible then
        return false
    end

    local db = GetCopyDB and GetCopyDB()
    local overrides = db and db.copyTabFrames
    if type(overrides) == "table" and overrides[info.key] ~= nil then
        return overrides[info.key] == true
    end

    -- Hidden chat windows are noisy and often include internal/system tabs.
    -- Keep them disabled by default; users can explicitly enable a normal hidden
    -- tab through the checklist. Combat Log and Voice remain blocked above.
    if not info.visible then
        return false
    end

    return mode ~= "PINNED"
end

local function BuildUniqueCopyLabels(list)
    local nameCounts = {}
    for i = 1, #list do
        local info = list[i]
        local baseName = GetChatFrameDisplayName(info.frame, info.index)
        local count = (nameCounts[baseName] or 0) + 1
        nameCounts[baseName] = count
        info.label = count > 1 and string.format("%s #%d", baseName, count) or baseName
        if not info.visible then
            info.optionLabel = string.format("%s |cff888888(%s)|r", info.label, L("hidden"))
        else
            info.optionLabel = info.label
        end
    end
end

local function BuildCopyFrameList(preferred)
    preferred = preferred or (GetPreferredChatFrame and GetPreferredChatFrame(nil))
    local candidates = CollectCopyFrameCandidates(preferred)
    local list = {}

    BuildUniqueCopyLabels(candidates)
    for i = 1, #candidates do
        local info = candidates[i]
        if IsCopyFrameAllowedForTabs(info, preferred) then
            list[#list + 1] = info
        end
    end

    BuildUniqueCopyLabels(list)
    return list
end

function ns.GetCopyChatFrameOptionValues()
    local preferred = GetPreferredChatFrame and GetPreferredChatFrame(nil)
    local candidates = CollectCopyFrameCandidates(preferred)
    local values = {}

    BuildUniqueCopyLabels(candidates)
    for i = 1, #candidates do
        local info = candidates[i]
        if not IsCopyBlockedChatFrame(info.frame, info.index) then
            values[info.key] = info.optionLabel or info.label or info.key
        end
    end

    if next(values) == nil then
        values.__none = L("No chat windows detected.")
    end

    return values
end

local function GetCopyFrameCandidateByKey(key)
    if not IsNonEmptyString(key) then
        return nil
    end

    local candidates = CollectCopyFrameCandidates(GetPreferredChatFrame and GetPreferredChatFrame(nil))
    for i = 1, #candidates do
        local info = candidates[i]
        if info.key == key then
            return info
        end
    end

    return nil
end

local function IsCopyFrameKeyBlocked(key)
    local info = GetCopyFrameCandidateByKey(key)
    if not info then
        return true
    end
    return IsCopyBlockedChatFrame(info.frame, info.index)
end

local function IsCopyFrameKeyVisible(key)
    local info = GetCopyFrameCandidateByKey(key)
    return info and info.visible == true or false
end

function ns.GetCopyChatFrameIncluded(key)
    if key == "__none" or IsCopyFrameKeyBlocked(key) then
        return false
    end

    local db = GetCopyDB and GetCopyDB()
    local overrides = db and db.copyTabFrames
    if type(overrides) == "table" and overrides[key] ~= nil then
        return overrides[key] == true
    end

    if not IsCopyFrameKeyVisible(key) then
        return false
    end

    return GetCopyTabMode() ~= "PINNED"
end

function ns.SetCopyChatFrameIncluded(key, enabled)
    if key == "__none" or IsCopyFrameKeyBlocked(key) then
        return
    end

    local db = GetCopyDB and GetCopyDB()
    if not db then
        return
    end

    db.copyTabFrames = db.copyTabFrames or {}
    db.copyTabFrames[key] = enabled and true or false

    if type(ns.RefreshCopyChatTabs) == "function" then
        ns.RefreshCopyChatTabs()
    end
end

function ns.ResetCopyChatFrameFilter()
    local db = GetCopyDB and GetCopyDB()
    if db then
        db.copyTabFrames = {}
    end
    if type(ns.RefreshCopyChatTabs) == "function" then
        ns.RefreshCopyChatTabs()
    end
end

local function StyleCopyTab(button, active)
    if not button then
        return
    end
    if button.bg and button.bg.SetColorTexture then
        if active then
            button.bg:SetColorTexture(0.42, 0.28, 0.06, 0.95)
        else
            button.bg:SetColorTexture(0.08, 0.07, 0.05, 0.92)
        end
    end
    if button.border and button.border.SetBackdropBorderColor then
        if active then
            button.border:SetBackdropBorderColor(0.95, 0.72, 0.18, 1)
        else
            button.border:SetBackdropBorderColor(0.35, 0.28, 0.14, 0.85)
        end
    end
    if button.text then
        button.text:SetTextColor(active and 1 or 0.78, active and 0.86 or 0.68, active and 0.22 or 0.42, 1)
    end
end

local function SetCopyTabNavState(button, enabled)
    if not button then
        return
    end
    if type(button.SetEnabled) == "function" then
        button:SetEnabled(enabled and true or false)
    end
    if type(button.SetAlpha) == "function" then
        button:SetAlpha(enabled and 1 or 0.35)
    end
end

local function MeasureCopyTabWidth(label)
    local text = StripChatMarkup(label) or tostring(label or "")
    return math.max(76, math.min(152, (#text * 7) + 28))
end

local function FindCopyTabIndex(tabs, frame)
    if type(tabs) ~= "table" or not frame then
        return nil
    end

    for i = 1, #tabs do
        if tabs[i].frame == frame then
            return i
        end
    end

    return nil
end

local function DoesCopyTabFitFromOffset(tabs, offset, targetIndex, maxWidth)
    if type(tabs) ~= "table" or not targetIndex then
        return false
    end

    offset = math.max(1, tonumber(offset) or 1)
    maxWidth = math.max(160, tonumber(maxWidth) or 500)
    local usedWidth = 0

    for sourceIndex = offset, #tabs do
        local width = MeasureCopyTabWidth(tabs[sourceIndex].label)
        local gap = sourceIndex > offset and 4 or 0
        if sourceIndex > offset and (usedWidth + gap + width) > maxWidth then
            return false
        end

        usedWidth = usedWidth + gap + width
        if sourceIndex == targetIndex then
            return true
        end
    end

    return false
end

local function ResolveCopyTabOffset(tabs, currentFrame, maxWidth, keepOffset)
    local count = type(tabs) == "table" and #tabs or 0
    if count == 0 then
        return 1
    end

    local currentOffset = math.max(1, math.min(tonumber(copyTabOffset) or 1, count))
    if keepOffset then
        return currentOffset
    end

    local activeIndex = FindCopyTabIndex(tabs, currentFrame)
    if not activeIndex then
        return currentOffset
    end

    -- Do not jump the tab strip just because the user clicked another visible
    -- tab. Keeping General/previous tabs on screen is a better UX and avoids the
    -- confusing "General disappeared" effect. Only move when the active tab is
    -- genuinely outside the current visible slice.
    if DoesCopyTabFitFromOffset(tabs, currentOffset, activeIndex, maxWidth) then
        return currentOffset
    end

    if DoesCopyTabFitFromOffset(tabs, 1, activeIndex, maxWidth) then
        return 1
    end

    return math.max(1, activeIndex - 2)
end

local function RefreshCopyTabs(keepOffset)
    if not copyTabs then
        return
    end

    local tabs = BuildCopyFrameList(copyCurrentFrame)
    copyAvailableTabs = tabs

    for i = 1, #copyTabButtons do
        copyTabButtons[i]:Hide()
        copyTabButtons[i].chatFrame = nil
    end

    if #tabs == 0 then
        copyTabOffset = 1
        SetCopyTabNavState(copyTabPrevButton, false)
        SetCopyTabNavState(copyTabNextButton, false)
        return
    end

    local maxWidth = 500
    if copyTabs.GetWidth then
        maxWidth = math.max(220, math.floor(copyTabs:GetWidth() or 500))
    end

    copyTabOffset = ResolveCopyTabOffset(tabs, copyCurrentFrame, maxWidth, keepOffset)
    if copyTabOffset < 1 then
        copyTabOffset = 1
    elseif copyTabOffset > #tabs then
        copyTabOffset = #tabs
    end

    local usedWidth = 0
    local visibleIndex = 0
    local lastButton
    local lastSourceIndex = copyTabOffset - 1

    for sourceIndex = copyTabOffset, #tabs do
        local info = tabs[sourceIndex]
        visibleIndex = visibleIndex + 1
        local tab = copyTabButtons[visibleIndex]
        if not tab then
            tab = CreateFrame("Button", nil, copyTabs, BackdropTemplateMixin and "BackdropTemplate" or nil)
            tab:SetHeight(24)
            tab:SetScript("OnClick", function(self)
                if not self.chatFrame then
                    return
                end
                if copyWindowMode == "history" and type(ns.OpenChatHistoryWindow) == "function" then
                    ns.OpenChatHistoryWindow(self.chatFrame, copyCurrentMaxLines)
                elseif type(ns.OpenChatCopyWindow) == "function" then
                    ns.OpenChatCopyWindow(self.chatFrame, copyCurrentMaxLines)
                end
            end)
            tab:SetScript("OnEnter", function(self)
                if self.text then self.text:SetTextColor(1, 0.92, 0.38, 1) end
            end)
            tab:SetScript("OnLeave", function(self)
                StyleCopyTab(self, self.chatFrame == copyCurrentFrame)
            end)
            tab.bg = tab:CreateTexture(nil, "BACKGROUND")
            tab.bg:SetAllPoints()
            tab.border = CreateFrame("Frame", nil, tab, BackdropTemplateMixin and "BackdropTemplate" or nil)
            tab.border:SetAllPoints()
            if tab.border.SetBackdrop then
                tab.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            end
            tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tab.text:SetPoint("LEFT", 9, 0)
            tab.text:SetPoint("RIGHT", -9, 0)
            tab.text:SetJustifyH("CENTER")
            copyTabButtons[visibleIndex] = tab
        end

        tab.chatFrame = info.frame
        tab.text:SetText(info.label)
        local width = MeasureCopyTabWidth(info.label)
        if tab.text and type(tab.text.GetStringWidth) == "function" then
            width = math.max(76, math.min(152, (tab.text:GetStringWidth() or width) + 24))
        end
        local gap = lastButton and 4 or 0
        if visibleIndex > 1 and (usedWidth + gap + width) > maxWidth then
            tab:Hide()
            break
        end

        tab:SetWidth(width)
        tab:ClearAllPoints()
        if lastButton then
            tab:SetPoint("LEFT", lastButton, "RIGHT", 4, 0)
        else
            tab:SetPoint("LEFT", copyTabs, "LEFT", 0, 0)
        end
        tab:Show()
        StyleCopyTab(tab, info.frame == copyCurrentFrame)
        usedWidth = usedWidth + gap + width
        lastButton = tab
        lastSourceIndex = sourceIndex
    end

    for i = visibleIndex + 1, #copyTabButtons do
        copyTabButtons[i]:Hide()
        copyTabButtons[i].chatFrame = nil
    end

    SetCopyTabNavState(copyTabPrevButton, copyTabOffset > 1)
    SetCopyTabNavState(copyTabNextButton, lastSourceIndex < #tabs)
end

function ns.RefreshCopyChatTabs()
    if copyFrame and (type(copyFrame.IsShown) ~= "function" or copyFrame:IsShown()) then
        RefreshCopyTabs(true)
    end
end

local function ShiftCopyTabOffset(delta)
    local count = type(copyAvailableTabs) == "table" and #copyAvailableTabs or 0
    if count <= 1 then
        return
    end

    copyTabOffset = copyTabOffset + (tonumber(delta) or 0)
    if copyTabOffset < 1 then
        copyTabOffset = 1
    elseif copyTabOffset > count then
        copyTabOffset = count
    end
    RefreshCopyTabs(true)
end

local function CreateCopyWindow()
    if copyFrame then return end

    local f = CreateFrame("Frame", "ChatifyCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.98)
        f:SetBackdropBorderColor(0.95, 0.72, 0.18, 1)
    end
    f:SetSize(660, 486)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()

    local titleBar = CreateMoveHandle(f, "ChatifyCopyFrameMoveTitle", function(handle)
        handle:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
        handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -6)
        handle:SetHeight(32)
    end)

    CreateMoveHandle(f, "ChatifyCopyFrameMoveLeft", function(handle)
        handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        handle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        handle:SetWidth(14)
    end)
    CreateMoveHandle(f, "ChatifyCopyFrameMoveRight", function(handle)
        handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        handle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        handle:SetWidth(14)
    end)
    CreateMoveHandle(f, "ChatifyCopyFrameMoveBottom", function(handle)
        handle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        handle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        handle:SetHeight(14)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -13)
    title:SetPoint("TOPRIGHT", -42, -13)
    title:SetJustifyH("LEFT")
    title:SetText(L("Chatify Copy"))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local prevTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prevTab:SetSize(24, 22)
    prevTab:SetPoint("TOPLEFT", 18, -49)
    prevTab:SetText("<")
    prevTab:SetScript("OnClick", function() ShiftCopyTabOffset(-1) end)

    local nextTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextTab:SetSize(24, 22)
    nextTab:SetPoint("TOPRIGHT", -42, -49)
    nextTab:SetText(">")
    nextTab:SetScript("OnClick", function() ShiftCopyTabOffset(1) end)

    local tabs = CreateFrame("Frame", "ChatifyCopyTabs", f)
    tabs:SetPoint("LEFT", prevTab, "RIGHT", 5, 0)
    tabs:SetPoint("RIGHT", nextTab, "LEFT", -5, 0)
    tabs:SetPoint("TOP", f, "TOP", 0, -48)
    tabs:SetHeight(24)
    tabs:EnableMouseWheel(true)
    tabs:SetScript("OnMouseWheel", function(_, delta)
        ShiftCopyTabOffset(delta and delta > 0 and -1 or 1)
    end)

    local previewBg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    previewBg:SetPoint("TOPLEFT", 16, -78)
    previewBg:SetPoint("BOTTOMRIGHT", -34, 58)
    previewBg:EnableMouse(false)
    if previewBg.SetBackdrop then
        previewBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        previewBg:SetBackdropColor(0.02, 0.02, 0.025, 0.92)
        previewBg:SetBackdropBorderColor(0.42, 0.32, 0.12, 0.95)
    end

    local scrollArea = CreateFrame("ScrollFrame", "ChatifyCopyPreviewScroll", f, "UIPanelScrollFrameTemplate")
    scrollArea:SetPoint("TOPLEFT", previewBg, "TOPLEFT", 10, -10)
    scrollArea:SetPoint("BOTTOMRIGHT", previewBg, "BOTTOMRIGHT", -28, 10)
    scrollArea:EnableMouse(true)
    scrollArea:EnableMouseWheel(true)
    scrollArea:SetScript("OnMouseWheel", function(_, delta)
        ScrollCopyWindow(delta)
    end)

    -- Prat-style copy surface: one plain scrollable EditBox.
    -- The EditBox owns mouse selection; only the title/borders can move the popup.
    local eb = CreateFrame("EditBox", "ChatifyCopySelectableEditBox", scrollArea)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(COPY_WINDOW_MAX_CHARS + 1000)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(0.94, 0.94, 0.94, 1)
    if eb.SetHighlightColor then
        eb:SetHighlightColor(0.95, 0.72, 0.18, 0.35)
    end
    if eb.SetTextInsets then
        eb:SetTextInsets(4, 4, 4, 4)
    end
    if eb.SetSpacing then
        eb:SetSpacing(2)
    end
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("TOP")
    eb:SetWidth(580)
    eb:SetHeight(1)
    eb:EnableMouse(true)
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(_, delta)
        ScrollCopyWindow(delta)
    end)
    eb:SetScript("OnMouseDown", function(self)
        self:SetFocus()
    end)
    eb:SetScript("OnEditFocusGained", function()
        if copyHint then
            copyHint:SetText(L("Select the needed text, then press Ctrl+C."))
        end
    end)
    eb:SetScript("OnEditFocusLost", function()
        if copyHint then
            copyHint:SetText(L("Click Select All for the full export, or select part of the text manually."))
        end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(self, x, y, w, h)
        end
    end)
    eb:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(self, elapsed, scrollArea)
        end
    end)

    -- 12.1 adds Frame:SetOnUpdateMode. RunWhenVisible is the default, so this is
    -- not a behaviour change; it is stated explicitly so the copy window keeps its
    -- current cost if the default is ever reconsidered, and it costs nothing on
    -- clients that lack the API.
    if type(eb.SetOnUpdateMode) == "function" then
        pcall(eb.SetOnUpdateMode, eb, "RunWhenVisible")
    end
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not copySettingText then
            local cursor = self:GetCursorPosition() or 0
            copySettingText = true
            self:SetText(copyTextValue or "")
            self:SetCursorPosition(math.min(cursor, #(copyTextValue or "")))
            copySettingText = false
            return
        end

        if scrollArea.UpdateScrollChildRect then
            scrollArea:UpdateScrollChildRect()
        end
    end)
    scrollArea:SetScrollChild(eb)

    local content = eb

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(116, 24)
    btn:SetPoint("BOTTOMRIGHT", -18, 18)
    btn:SetText(L("Select All"))
    btn:SetScript("OnClick", function()
        if copyEditBox then
            copyEditBox:SetFocus()
            copyEditBox:SetCursorPosition(0)
            copyEditBox:HighlightText(0, -1)
        end
        if copyHint then
            copyHint:SetText(L("Selected text is ready. Press Ctrl+C to copy."))
        end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 22)
    hint:SetPoint("RIGHT", btn, "LEFT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L("Click Select All for the full export, or select part of the text manually."))

    titleBar:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
    close:SetFrameLevel((f:GetFrameLevel() or 1) + 3)

    copyFrame = f
    copyEditBox = eb
    copyTitle = title
    copyScroll = scrollArea
    copyContent = content
    copyHint = hint
    copyButton = btn
    copyPreviewBg = previewBg
    copyTabs = tabs
    copyTabPrevButton = prevTab
    copyTabNextButton = nextTab
end

local BuildTextFromEntries
local IsBlankCopyEntries
local BuildBlankCopyEntries

local function SetCopyEditText(text)
    copyTextValue = text or ""
    if copyContent and type(copyContent.SetText) == "function" then
        copySettingText = true
        copyContent:SetText(copyTextValue)
        copyContent:SetCursorPosition(0)
        copyContent:HighlightText(0, 0)
        copyContent:ClearFocus()
        copySettingText = false
    end
end

local function ClearCopyPreview()
    SetCopyEditText("")
end

local function RenderCopyPreview(entries)
    if not copyContent then
        return
    end

    local width = 545
    if copyScroll and copyScroll.GetWidth then
        width = math.max(260, math.floor((copyScroll:GetWidth() or 575) - 12))
    end

    local text = BuildTextFromEntries(entries, COPY_WINDOW_MAX_CHARS)
    copyContent:SetWidth(width)
    SetCopyEditText(text)

    local lineCount = 1
    for _ in string.gmatch(text or "", "\n") do
        lineCount = lineCount + 1
    end
    copyContent:SetHeight(math.max(1, lineCount * 16 + 24))
end

BuildTextFromEntries = function(entries, maxChars)
    local lines = {}
    local chars = 0
    maxChars = tonumber(maxChars) or COPY_WINDOW_MAX_CHARS

    if IsBlankCopyEntries(entries) then
        return ""
    end

    if type(entries) ~= "table" then
        return L("Chat buffer is empty. Send or receive a new message, then open this window again.")
    end

    for i = 1, #entries do
        local line = BuildPlainLine(entries[i])
        if IsNonEmptyString(line) then
            chars = chars + #line + 1
            if chars > maxChars then
                lines[#lines + 1] = "..."
                break
            end
            lines[#lines + 1] = line
        end
    end

    if #lines == 0 then
        lines[#lines + 1] = L("No readable chat lines were available for the copy window.")
        if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
            lines[#lines + 1] = L("Use Shift+Left Click on the copy button for Blizzard direct chat selection.")
        end
    end

    return table.concat(lines, "\n")
end

local function ApplyCopyWindowModeStyle(mode)
    local isHistory = mode == "history"
    if copyPreviewBg and copyPreviewBg.SetBackdropBorderColor then
        if isHistory then
            copyPreviewBg:SetBackdropBorderColor(0.28, 0.50, 0.85, 0.95)
        else
            copyPreviewBg:SetBackdropBorderColor(0.42, 0.32, 0.12, 0.95)
        end
    end

    if copyButton then
        copyButton:SetText(isHistory and L("Select History") or L("Select All"))
    end
end

local function ShowCopyWindow(entries, title, chatFrame, maxLines, mode)
    if not copyFrame then CreateCopyWindow() end

    if type(entries) == "string" then
        entries = { BuildEntry(entries) or entries }
    elseif type(entries) ~= "table" then
        entries = {}
    end

    copyFrame:Show()
    copyCurrentFrame = chatFrame or copyCurrentFrame
    copyCurrentMaxLines = tonumber(maxLines) or copyCurrentMaxLines or COPY_WINDOW_MAX_LINES
    copyWindowMode = mode == "history" and "history" or "copy"
    if copyTitle then
        copyTitle:SetText(title or (copyWindowMode == "history" and L("Chatify History") or L("Chatify Copy")))
    end
    ApplyCopyWindowModeStyle(copyWindowMode)
    RefreshCopyTabs(false)
    if copyHint then
        if copyWindowMode == "history" then
            copyHint:SetText(L("Chat history is shown only here. Click Select History or select only the needed lines."))
        else
            copyHint:SetText(L("Click Select All for the full export, or select part of the text manually."))
        end
    end

    RenderCopyPreview(entries)

    if IsBlankCopyEntries(entries) and copyHint then
        copyHint:SetText(entries.__chatifyHint or (copyWindowMode == "history" and L("This chat tab has no saved history yet.") or L("This chat tab has no messages to copy.")))
    end

    if copyEditBox then
        copyEditBox:ClearFocus()
        copyEditBox:HighlightText(0, 0)
    end
    if copyScroll and copyScroll.SetVerticalScroll then
        copyScroll:SetVerticalScroll(0)
    end
end

local function BuildCachedChatEntries(maxLines, maxChars)
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES
    maxChars = tonumber(maxChars) or COPY_WINDOW_MAX_CHARS

    local entries = {}
    local chars = 0
    local startIndex = math.max(1, fullChatIndex - maxLines + 1)

    for i = startIndex, fullChatIndex do
        local entry = fullChatCache[i]
        local line = BuildPlainLine(entry)
        if IsNonEmptyString(line) then
            chars = chars + #line + 1
            if chars > maxChars then
                entries[#entries + 1] = BuildEntry("...")
                break
            end
            entries[#entries + 1] = entry
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function ReadVisibleLineMessages(chatFrame)
    if not chatFrame or type(chatFrame.visibleLines) ~= "table" then
        return nil
    end

    local entries = {}
    for i = 1, #chatFrame.visibleLines do
        local line = chatFrame.visibleLines[i]
        local text

        if line and line.messageInfo then
            text = line.messageInfo.message
        end

        if not text and line and type(line.GetText) == "function" then
            local ok, value = pcall(line.GetText, line)
            if ok then
                text = value
            end
        end

        local entry = BuildEntry(text)
        if entry then
            entries[#entries + 1] = entry
        elseif IsProtectedChatValue(text) then
            entries[#entries + 1] = BuildProtectedEntry()
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

-- Whether the on-screen contents of this frame are actually this frame's.
--
-- Docked chat tabs share the same area: only the selected one is rendered, and
-- the others are not visible. Scraping FontStrings or visibleLines from a frame
-- that is not on screen therefore returns whatever the dock is currently showing,
-- which is how General's lines ended up in the Guild tab's copy window.
--
-- The frame's own history buffer, read through GetMessageInfo, is per-frame and
-- unaffected; only the display-scraping fallbacks need this guard.
local function IsFrameDisplayingItsOwnContent(chatFrame)
    if not chatFrame then
        return false
    end

    if type(chatFrame.IsVisible) == "function" then
        local ok, visible = pcall(chatFrame.IsVisible, chatFrame)
        if ok and not visible then
            return false
        end
    end

    -- A docked frame is only rendering its own lines while it is the selected tab.
    local dock = chatFrame.isDocked and _G.GENERAL_CHAT_DOCK
    if dock and dock.selected and dock.selected ~= chatFrame then
        return false
    end

    return true
end

local function ReadVisibleChatLines(chatFrame)
    if not IsFrameDisplayingItsOwnContent(chatFrame) then
        return nil
    end

    local visibleLineEntries = ReadVisibleLineMessages(chatFrame)
    if visibleLineEntries then
        return visibleLineEntries
    end

    if not chatFrame or type(chatFrame.GetRegions) ~= "function" then
        return nil
    end

    local entries = {}
    local regions = { chatFrame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
            local ok, text = pcall(region.GetText, region)
            if ok then
                local entry = BuildEntry(text)
                if entry then
                    entries[#entries + 1] = entry
                elseif IsProtectedChatValue(text) then
                    entries[#entries + 1] = BuildProtectedEntry()
                end
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function AddHistoryEntry(entries, rawText, author, timestamp)
    local payload = GetMessagePayload(rawText)
    local payloadAuthor = author or GetMessageAuthor(rawText)
    local entry = BuildEntry(payload, payloadAuthor, timestamp)
    if entry then
        entries[#entries + 1] = entry
        return true
    end

    if IsProtectedChatValue(payload) then
        entries[#entries + 1] = BuildProtectedEntry(nil, timestamp)
        return true
    end

    return false
end

local function HasReadableEntries(entries)
    if type(entries) ~= "table" or #entries == 0 then
        return false
    end

    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and not entry.protected and IsNonEmptyString(entry.text) then
            return true
        elseif type(entry) == "string" and IsNonEmptyString(entry) then
            return true
        end
    end

    return false
end

local function HasAnyCopyEntries(entries)
    return type(entries) == "table" and #entries > 0
end

IsBlankCopyEntries = function(entries)
    return type(entries) == "table" and entries.__chatifyBlank == true
end

BuildBlankCopyEntries = function(hint)
    return {
        __chatifyBlank = true,
        __chatifyHint = hint or L("This chat tab has no messages to copy."),
    }
end

local function IsMainCopyFrame(chatFrame)
    if not chatFrame then
        return false
    end

    return chatFrame == DEFAULT_CHAT_FRAME or chatFrame == _G.ChatFrame1 or GetChatFrameID(chatFrame) == 1
end

local function CanUseGlobalCopyFallback(chatFrame, messageCount, entries)
    -- Global event cache is useful only for the main chat when the client does
    -- not expose history. For secondary tabs it creates false content in empty
    -- windows, e.g. an empty Whisper tab showing General/Party system lines.
    if not IsMainCopyFrame(chatFrame) then
        return false
    end

    if type(messageCount) == "number" and messageCount == 0 then
        return false
    end

    return not HasAnyCopyEntries(entries) or HasReadableEntries(entries) == false
end

local function ReadMessageHistory(chatFrame, maxLines)
    if not chatFrame then
        return nil
    end

    local entries = {}
    maxLines = tonumber(maxLines) or COPY_WINDOW_MAX_LINES

    local count = GetChatFrameMessageCount(chatFrame) or 0

    -- Prat's copy window uses GetMessageInfo first. Keep that path, but
    -- collect only the first return value and never treat normal Retail text
    -- as protected just because canaccessvalue() exists.
    if count > 0 and type(chatFrame.GetMessageInfo) == "function" then
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, msg, r, g, b, messageId, extraData = pcall(chatFrame.GetMessageInfo, chatFrame, i)
            if ok then
                AddHistoryEntry(entries, msg, nil, nil)
            end
        end
    end

    if not HasReadableEntries(entries) and count > 0 and chatFrame.historyBuffer and type(chatFrame.historyBuffer.GetEntryAtIndex) == "function" then
        local fallbackEntries = {}
        local first = math.max(1, count - maxLines + 1)
        for i = first, count do
            local ok, historyEntry = pcall(chatFrame.historyBuffer.GetEntryAtIndex, chatFrame.historyBuffer, i)
            if ok then
                AddHistoryEntry(fallbackEntries, historyEntry)
            end
        end
        if HasReadableEntries(fallbackEntries) or #entries == 0 then
            entries = fallbackEntries
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function GetFrameMouseEnabled(frame)
    if not frame or type(frame.IsMouseEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameTextCopyable(frame)
    if not frame or type(frame.IsTextCopyable) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsTextCopyable, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameMouseClickEnabled(frame)
    if not frame or type(frame.IsMouseClickEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function GetFrameMouseMotionEnabled(frame)
    if not frame or type(frame.IsMouseMotionEnabled) ~= "function" then
        return nil
    end

    local ok, enabled = pcall(frame.IsMouseMotionEnabled, frame)
    if ok then
        return enabled and true or false
    end

    return nil
end

local function IsNativeCopyFrame(frame)
    return type(frame) == "table" and type(frame.SetTextCopyable) == "function"
end

local function GetFrameDebugName(frame)
    if type(frame) == "table" and type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return "chat frame"
end

local function AddNativeCandidate(list, seen, frame)
    if not IsNativeCopyFrame(frame) or seen[frame] then
        return false
    end

    if IsCopyBlockedChatFrame(frame, GetChatFrameID(frame)) then
        return false
    end

    seen[frame] = true
    list[#list + 1] = frame
    return true
end

local function AddNamedChatFrameCandidates(list, seen, visibleOnly)
    local total = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    if type(ns.GetMaxChatWindows) == "function" then
        local ok, maxWindows = pcall(ns.GetMaxChatWindows)
        if ok and type(maxWindows) == "number" and maxWindows > 0 then
            total = maxWindows
        end
    end

    if total < 1 then
        total = 10
    elseif total > 20 then
        total = 20
    end

    for i = 1, total do
        local frame = _G["ChatFrame" .. i]
        if frame and (not visibleOnly or type(frame.IsShown) ~= "function" or frame:IsShown()) then
            AddNativeCandidate(list, seen, frame)
        end
    end
end

local function GetDockSelectedFrame()
    if type(_G.FCFDock_GetSelectedWindow) == "function" and _G.GeneralDockManager then
        local ok, frame = pcall(_G.FCFDock_GetSelectedWindow, _G.GeneralDockManager)
        if ok and frame then
            return frame
        end
    end

    if _G.GeneralDockManager then
        return _G.GeneralDockManager.selected or _G.GeneralDockManager.primary
    end

    return nil
end

function GetPreferredChatFrame(preferred)
    if IsNativeCopyFrame(preferred) then
        return preferred
    end

    if type(ns.GetSelectedChatFrame) == "function" then
        local ok, frame = pcall(ns.GetSelectedChatFrame)
        if ok and IsNativeCopyFrame(frame) then
            return frame
        end
    end

    if IsNativeCopyFrame(SELECTED_CHAT_FRAME) then
        return SELECTED_CHAT_FRAME
    end

    local dockFrame = GetDockSelectedFrame()
    if IsNativeCopyFrame(dockFrame) then
        return dockFrame
    end

    if IsNativeCopyFrame(DEFAULT_CHAT_FRAME) then
        return DEFAULT_CHAT_FRAME
    end

    if IsNativeCopyFrame(_G.ChatFrame1) then
        return _G.ChatFrame1
    end

    return nil
end

local function GetMainChatFrame()
    if IsNativeCopyFrame(DEFAULT_CHAT_FRAME) then
        return DEFAULT_CHAT_FRAME
    end
    if IsNativeCopyFrame(_G.ChatFrame1) then
        return _G.ChatFrame1
    end
    return GetPreferredChatFrame(nil)
end

local function UseVisibleNativeFrames()
    local db = GetCopyDB()
    return db and db.copyNativeUseVisibleFrames == true
end

local function ResolveNativeCopyFrames(preferred)
    local list = {}
    local seen = {}

    -- Keep the default path intentionally simple and close to Prat:
    -- one likely ScrollingMessageFrame gets SetTextCopyable(true). The
    -- optional compatibility mode enables every visible chat frame only for
    -- custom layouts where the sidebar is not attached to the real frame.
    if UseVisibleNativeFrames() then
        AddNativeCandidate(list, seen, preferred)
        AddNativeCandidate(list, seen, GetPreferredChatFrame(preferred))
        AddNativeCandidate(list, seen, SELECTED_CHAT_FRAME)
        AddNativeCandidate(list, seen, GetDockSelectedFrame())
        AddNativeCandidate(list, seen, DEFAULT_CHAT_FRAME)
        AddNativeCandidate(list, seen, _G.ChatFrame1)
        AddNamedChatFrameCandidates(list, seen, true)
    else
        AddNativeCandidate(list, seen, preferred)
        if #list == 0 then
            AddNativeCandidate(list, seen, GetPreferredChatFrame(preferred))
        end
        if #list == 0 then
            AddNativeCandidate(list, seen, GetMainChatFrame())
        end
    end

    if #list == 0 then
        AddNamedChatFrameCandidates(list, seen, false)
    end

    return list
end

local function RestoreNativeFrame(frame, session)
    if not frame or not session then
        return
    end

    if session.changedCallback then
        SafeFrameCall(frame, "SetOnTextCopiedCallback", nil)
    end

    if session.changedCopyable then
        SafeFrameCall(frame, "SetTextCopyable", session.originalCopyable and true or false)
    end

    -- Only restore the mouse flag if Chatify was the one that enabled it. This
    -- prevents fighting ElvUI/Prat/Blizzard layouts that already owned mouse
    -- handling for the chat frame.
    if session.changedMouseEnabled then
        SafeFrameCall(frame, "EnableMouse", session.originalMouseEnabled and true or false)
    end
end

local function RestoreNativeCopySession(sessionId)
    local restored = false
    for frame, session in pairs(nativeCopySessions) do
        if session and (not sessionId or session.id == sessionId) then
            nativeCopySessions[frame] = nil
            RestoreNativeFrame(frame, session)
            restored = true
        end
    end

    if not sessionId or nativeCopyActiveSessionId == sessionId then
        nativeCopyActiveSessionId = nil
    end

    return restored
end

local function HasNativeCopySession()
    for _, session in pairs(nativeCopySessions) do
        if session then
            return true
        end
    end
    return false
end

local function RestoreNativeChatCopyMode(frame, sessionId)
    local session = frame and nativeCopySessions[frame]
    if not session or session.id ~= sessionId then
        return
    end

    RestoreNativeCopySession(sessionId)
end

local function EnableNativeCopyOnFrame(frame, sessionId)
    if not IsNativeCopyFrame(frame) then
        return false
    end

    local session = {
        id = sessionId,
        originalMouseEnabled = GetFrameMouseEnabled(frame),
        originalCopyable = GetFrameTextCopyable(frame),
        changedMouseEnabled = false,
        changedCopyable = false,
        changedCallback = false,
    }

    nativeCopySessions[frame] = session

    -- In combat lockdown, changing Blizzard chat frame interaction state can taint
    -- other addons and produce the "action only available to Blizzard UI" popup.
    if IsInCombatLockdown() then
        nativeCopySessions[frame] = nil
        return false, "combat"
    end

    if not SafeFrameCall(frame, "SetTextCopyable", true) then
        nativeCopySessions[frame] = nil
        return false, "copyable"
    end
    session.changedCopyable = true

    -- Do not call EnableMouse(true) if the frame already had mouse enabled.
    -- This keeps selection limited to the actual chat frame and avoids changing
    -- click-through behavior more than needed.
    if session.originalMouseEnabled ~= true then
        if SafeFrameCall(frame, "EnableMouse", true) then
            session.changedMouseEnabled = true
        end
    end

    if type(frame.SetOnTextCopiedCallback) == "function" then
        local ok = SafeFrameCall(frame, "SetOnTextCopiedCallback", function(this)
            RestoreNativeChatCopyMode(this or frame, sessionId)
        end)
        session.changedCallback = ok and true or false
    end

    return true
end

local function PrintChatifySystemMessage(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cffffd200Chatify:|r " .. message)
    end
end

local function NotifyNativeCopyEnabled(enabledCount, firstFrame)
    local db = GetCopyDB()
    if db and db.copyNativeAnnounce == false then
        return
    end

    local frameName = GetFrameDebugName(firstFrame)
    local count = tonumber(enabledCount) or 1
    if count <= 1 then
        PrintChatifySystemMessage(string.format(L("direct chat selection enabled on %s. Select text in chat, then press Ctrl+C."), frameName))
    else
        PrintChatifySystemMessage(string.format(L("direct chat selection enabled on %d chat frames. Select text in chat, then press Ctrl+C."), count))
    end
end


local function NotifyNativeCopyDisabled()
    local db = GetCopyDB()
    if db and db.copyNativeAnnounce == false then
        return
    end
    PrintChatifySystemMessage(L("direct chat selection disabled."))
end

local function NotifyNativeCopyCombatBlocked()
    local now = type(GetTime) == "function" and GetTime() or time()
    if now - nativeCopyLastBlockedWarning < 2 then
        return
    end
    nativeCopyLastBlockedWarning = now
    PrintChatifySystemMessage(L("direct chat selection is blocked during combat to avoid Blizzard taint popups."))
end

function ns.IsNativeChatCopyModeActive()
    return nativeCopyActiveSessionId ~= nil and HasNativeCopySession()
end

function ns.EnterNativeChatCopyMode(chatFrame)
    local db = GetCopyDB()
    if db and db.copyNativeSelection == false then
        return false
    end

    if IsInCombatLockdown() then
        NotifyNativeCopyCombatBlocked()
        return false
    end

    -- Starting a fresh session first restores any stale state left by another
    -- target frame from a previous attempt.
    RestoreNativeCopySession(nil)

    local frames = ResolveNativeCopyFrames(chatFrame)
    if type(frames) ~= "table" or #frames == 0 then
        PrintChatifySystemMessage(L("direct chat selection is unavailable on this client/chat frame."))
        return false
    end

    nativeCopySessionId = nativeCopySessionId + 1
    local sessionId = nativeCopySessionId
    local enabledCount = 0
    local firstFrame
    local blockedByCombat = false

    for i = 1, #frames do
        local ok, reason = EnableNativeCopyOnFrame(frames[i], sessionId)
        if ok then
            enabledCount = enabledCount + 1
            firstFrame = firstFrame or frames[i]
        elseif reason == "combat" then
            blockedByCombat = true
        end
    end

    if enabledCount == 0 then
        RestoreNativeCopySession(sessionId)
        if blockedByCombat then
            NotifyNativeCopyCombatBlocked()
        else
            PrintChatifySystemMessage(L("direct chat selection is unavailable on this client/chat frame."))
        end
        return false
    end

    nativeCopyActiveSessionId = sessionId
    NotifyNativeCopyEnabled(enabledCount, firstFrame)

    local timeout = tonumber(db and db.copyNativeTimeout) or 30
    if timeout and timeout > 0 then
        local function delayedRestore()
            if RestoreNativeCopySession(sessionId) then
                NotifyNativeCopyDisabled()
            end
        end

        if type(ns.SafeAfter) == "function" then
            ns.SafeAfter(timeout, delayedRestore)
        elseif C_Timer and type(C_Timer.After) == "function" then
            pcall(C_Timer.After, timeout, delayedRestore)
        end
    end

    return true
end

function ns.ToggleNativeChatCopyMode(chatFrame)
    if ns.IsNativeChatCopyModeActive() then
        if RestoreNativeCopySession(nil) then
            NotifyNativeCopyDisabled()
        end
        return true, false
    end

    return ns.EnterNativeChatCopyMode(chatFrame), true
end

function ns.ExitNativeChatCopyMode(silent)
    local restored = RestoreNativeCopySession(nil)
    if restored and not silent then
        NotifyNativeCopyDisabled()
    end
end

local function GetFirstAllowedCopyFrame(preferred)
    local candidates = CollectCopyFrameCandidates(preferred)
    BuildUniqueCopyLabels(candidates)
    for i = 1, #candidates do
        local info = candidates[i]
        if info.frame and not IsCopyBlockedChatFrame(info.frame, info.index) and info.visible then
            return info.frame
        end
    end
    for i = 1, #candidates do
        local info = candidates[i]
        if info.frame and not IsCopyBlockedChatFrame(info.frame, info.index) then
            return info.frame
        end
    end
    return nil
end

function ns.GetChatifyCopyFrameID(chatFrame)
    return GetChatFrameID(chatFrame)
end

function ns.GetChatifyCopyFrameLabel(chatFrame)
    return GetChatFrameDisplayName(chatFrame, GetChatFrameID(chatFrame))
end

function ns.IsChatifyCopyFrameAllowed(chatFrame)
    return chatFrame ~= nil and not IsCopyBlockedChatFrame(chatFrame, GetChatFrameID(chatFrame))
end

local function GetHistoryWindowLimit(maxLines)
    local db = GetCopyDB and GetCopyDB()
    local limit = tonumber(maxLines) or tonumber(db and db.historyLimit) or HISTORY_WINDOW_MAX_LINES
    if limit < 10 then
        limit = 10
    elseif limit > 1000 then
        limit = 1000
    end
    return limit
end

local function ReadStoredHistoryForFrame(chatFrame, maxLines)
    if type(ns.GetChatifyHistoryEntriesForFrame) ~= "function" then
        return nil
    end

    local ok, entries = pcall(ns.GetChatifyHistoryEntriesForFrame, chatFrame, maxLines)
    if ok and HasAnyCopyEntries(entries) then
        return entries
    end

    return nil
end

function ns.OpenChatHistoryWindow(chatFrame, maxLines)
    chatFrame = chatFrame or (type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame()) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if IsCopyBlockedChatFrame(chatFrame, GetChatFrameID(chatFrame)) then
        chatFrame = GetFirstAllowedCopyFrame(chatFrame)
        if not chatFrame then
            ShowCopyWindow({ BuildEntry(L("This chat window is excluded from ChatCopy.")) }, L("Chatify History"), nil, maxLines, "history")
            return
        end
    end

    local limit = GetHistoryWindowLimit(maxLines)
    local entries = ReadStoredHistoryForFrame(chatFrame, limit)

    -- If the persistent store is empty for a fresh install/reload, fall back to the
    -- live ScrollingMessageFrame buffer. This mirrors Prat/Chattynator behaviour
    -- while keeping the same blocked-frame and protected-line rules as ChatCopy.
    if not HasReadableEntries(entries) then
        local liveEntries = ReadMessageHistory(chatFrame, limit)
        if HasReadableEntries(liveEntries) or (not HasAnyCopyEntries(entries) and HasAnyCopyEntries(liveEntries)) then
            entries = liveEntries
        end
    end

    if not HasAnyCopyEntries(entries) then
        entries = BuildBlankCopyEntries(L("This chat tab has no saved history yet."))
    elseif not HasReadableEntries(entries) and type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        entries[#entries + 1] = BuildEntry(L("Some lines are protected by Blizzard and cannot be exported by addons."))
    end

    local frameLabel = GetChatFrameDisplayName(chatFrame, GetChatFrameID(chatFrame))
    ShowCopyWindow(entries, string.format("%s — %s", L("Chatify History"), frameLabel), chatFrame, limit, "history")
end

function ns.OpenChatCopyWindow(chatFrame, maxLines)
    chatFrame = chatFrame or (type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame()) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if IsCopyBlockedChatFrame(chatFrame, GetChatFrameID(chatFrame)) then
        chatFrame = GetFirstAllowedCopyFrame(chatFrame)
        if not chatFrame then
            ShowCopyWindow({ BuildEntry(L("This chat window is excluded from ChatCopy.")) }, L("Chatify Copy"), nil, maxLines)
            return
        end
    end

    -- Match Prat's behavior: copy the selected chat frame first. The global
    -- event cache is intentionally restricted to the main chat frame only; using
    -- it for empty secondary tabs makes Whisper/Guild/Party show unrelated
    -- General/system lines that are not present in the original tab.
    local messageCount = GetChatFrameMessageCount(chatFrame)
    local entries = ReadMessageHistory(chatFrame, maxLines)
    if not HasReadableEntries(entries) then
        local visibleEntries = ReadVisibleChatLines(chatFrame)
        if HasReadableEntries(visibleEntries) or (not HasAnyCopyEntries(entries) and HasAnyCopyEntries(visibleEntries)) then
            entries = visibleEntries
        end
    end

    if not HasReadableEntries(entries) and CanUseGlobalCopyFallback(chatFrame, messageCount, entries) then
        local cachedEntries = BuildCachedChatEntries(maxLines, COPY_WINDOW_MAX_CHARS)
        if HasReadableEntries(cachedEntries) or (not HasAnyCopyEntries(entries) and HasAnyCopyEntries(cachedEntries)) then
            entries = cachedEntries
        end
    end

    if not HasAnyCopyEntries(entries) then
        if IsMainCopyFrame(chatFrame) then
            entries = { BuildEntry(L("Chat buffer is empty. Send or receive a new message, then open this window again.")) }
        else
            entries = BuildBlankCopyEntries(L("This chat tab has no messages to copy."))
        end
    elseif not HasReadableEntries(entries) and type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        entries[#entries + 1] = BuildEntry(L("Some lines are protected by Blizzard and cannot be exported by addons. Use Shift+Left Click on the copy button for direct chat selection."))
    end

    local frameLabel = GetChatFrameDisplayName(chatFrame, GetChatFrameID(chatFrame))
    ShowCopyWindow(entries, string.format("%s — %s", L("Chatify Copy"), frameLabel), chatFrame, maxLines)
end

-- =========================================================
-- 3. ПОПАП ДЛЯ URL
-- =========================================================
if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["CHATIFY_COPY_URL"] = {
        text = L("Press Ctrl+C to copy the link:"),
        button1 = L("OK"),
        hasEditBox = true,
        editBoxWidth = 350,
        OnShow = function(self, data)
            local eb = self.editBox or self.EditBox
            if eb then
                eb:SetText(type(data) == "string" and data or tostring(data or ""))
                eb:SetFocus()
                eb:HighlightText()
            end
        end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function ShowUrlCopyPopup(url)
    url = SafeChatText(url) or tostring(url or "")
    if type(StaticPopup_Show) == "function" and type(StaticPopupDialogs) == "table" and StaticPopupDialogs["CHATIFY_COPY_URL"] then
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, url)
        return
    end
    ShowCopyWindow({ BuildEntry(url) or url }, L("Chatify Copy — link"))
end

-- =========================================================
-- 4. ПЕРЕХОПЛЕННЯ КЛІКІВ
-- =========================================================
local function GetCaptureEventsForClient()
    if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild() then
        return RETAIL_CHAT_CAPTURE_EVENTS
    end
    return CHAT_CAPTURE_EVENTS
end

local function OnCaptureEvent(_, event, msg, author, ...)
    if type(ns.ShouldBypassChatCaptureEvent) == "function" and ns.ShouldBypassChatCaptureEvent(event) then
        return
    end

    if type(ns.CanMutateChatPayload) == "function" then
        if not ns.CanMutateChatPayload(event, msg, author, ...) then
            return
        end
    elseif type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
        return
    end

    local safeMsg = SafeChatText(msg)
    if not IsNonEmptyString(safeMsg) then
        return
    end

    local safeAuthor = SafeChatText(author)
    ns.SaveToCache(safeMsg, safeAuthor, time())
end

local function EnsureChatCapture()
    if captureFrame then
        return
    end

    local okFrame, frame = pcall(CreateFrame, "Frame")
    if not okFrame or not frame then
        return
    end

    captureFrame = frame
    captureRegisteredCount = 0
    for _, eventName in ipairs(GetCaptureEventsForClient()) do
        if not (type(ns.ShouldBypassChatCaptureEvent) == "function" and ns.ShouldBypassChatCaptureEvent(eventName))
            and (type(ns.IsEventSupported) ~= "function" or ns.IsEventSupported(eventName)) then
            local ok = pcall(captureFrame.RegisterEvent, captureFrame, eventName)
            if ok then
                captureRegisteredCount = captureRegisteredCount + 1
            end
        end
    end

    if captureRegisteredCount > 0 then
        pcall(captureFrame.SetScript, captureFrame, "OnEvent", OnCaptureEvent)
    else
        captureFrame = nil
    end
end

local function DisableChatCapture()
    if not captureFrame then
        return
    end

    if type(captureFrame.UnregisterAllEvents) == "function" then
        pcall(captureFrame.UnregisterAllEvents, captureFrame)
    end
    if type(captureFrame.SetScript) == "function" then
        pcall(captureFrame.SetScript, captureFrame, "OnEvent", nil)
    end
    captureFrame = nil
    captureRegisteredCount = 0
end


local function EnsureNativeCopyGuard()
    if nativeCopyGuardFrame or type(CreateFrame) ~= "function" then
        return
    end

    local okFrame, frame = pcall(CreateFrame, "Frame")
    if not okFrame or not frame then
        return
    end

    nativeCopyGuardFrame = frame
    if type(ns.IsEventSupported) ~= "function" or ns.IsEventSupported("PLAYER_REGEN_DISABLED") then
        pcall(nativeCopyGuardFrame.RegisterEvent, nativeCopyGuardFrame, "PLAYER_REGEN_DISABLED")
    end
    if type(ns.IsEventSupported) ~= "function" or ns.IsEventSupported("PLAYER_ENTERING_WORLD") then
        pcall(nativeCopyGuardFrame.RegisterEvent, nativeCopyGuardFrame, "PLAYER_ENTERING_WORLD")
    end
    pcall(nativeCopyGuardFrame.SetScript, nativeCopyGuardFrame, "OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Turn selection off before combat lockdown can turn a harmless chat
            -- copy mode into a taint source for other addons.
            RestoreNativeCopySession(nil)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Clear stale callbacks after reload/instance transitions.
            RestoreNativeCopySession(nil)
        end
    end)
end

local function DisableNativeCopyGuard()
    if not nativeCopyGuardFrame then
        return
    end

    if type(nativeCopyGuardFrame.UnregisterAllEvents) == "function" then
        pcall(nativeCopyGuardFrame.UnregisterAllEvents, nativeCopyGuardFrame)
    end
    if type(nativeCopyGuardFrame.SetScript) == "function" then
        pcall(nativeCopyGuardFrame.SetScript, nativeCopyGuardFrame, "OnEvent", nil)
    end
    nativeCopyGuardFrame = nil
end

local function CallOriginalSetItemRef(module, link, text, button, chatFrame)
    local hooks = module and module.hooks
    local original = hooks and hooks.SetItemRef
    if type(original) == "function" then
        return original(link, text, button, chatFrame)
    end
end

function CopyModule:OnEnable()
    if type(SetItemRef) == "function" and (type(self.IsHooked) ~= "function" or not self:IsHooked("SetItemRef")) then
        pcall(self.RawHook, self, "SetItemRef", true)
    end
    EnsureChatCapture()
    EnsureNativeCopyGuard()
    if Chatify and type(Chatify.RegisterChatCommand) == "function" then
        if type(Chatify.UnregisterChatCommand) == "function" then
            pcall(Chatify.UnregisterChatCommand, Chatify, "chatcopy")
        end
        pcall(Chatify.RegisterChatCommand, Chatify, "chatcopy", function(input)
            local command = type(input) == "string" and input:lower():match("^%s*(.-)%s*$") or ""
            local frame = (type(ns.GetSelectedChatFrame) == "function" and ns.GetSelectedChatFrame()) or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME

            if command == "full" or command == "all" then
                ns.OpenChatCopyWindow(frame, 5000)
                return
            end

            ns.OpenChatCopyWindow(frame, COPY_WINDOW_MAX_LINES)
        end)
    end
end

function CopyModule:SetItemRef(link, text, button, chatFrame)
    local safeLink = SafeChatText(link)
    if not IsNonEmptyString(safeLink) then
        return CallOriginalSetItemRef(self, link, text, button, chatFrame)
    end

    if safeLink:sub(1, 9) == "chatcopy:" then
        local id = tonumber(safeLink:sub(10))
        local payload = (ns.GetCachedChatLine and ns.GetCachedChatLine(id)) or msgCache[id]
        if id and payload then
            ShowCopyWindow({ payload }, L("Chatify Copy — selected line"))
        end
        return
    end

    if safeLink:sub(1, 4) == "url:" then
        ShowUrlCopyPopup(safeLink:sub(5))
        return
    end

    return CallOriginalSetItemRef(self, link, text, button, chatFrame)
end


function CopyModule:OnDisable()
    if type(ns.ExitNativeChatCopyMode) == "function" then
        ns.ExitNativeChatCopyMode(true)
    end
    DisableChatCapture()
    DisableNativeCopyGuard()
    if type(self.IsHooked) == "function" and self:IsHooked("SetItemRef") then
        pcall(self.Unhook, self, "SetItemRef")
    end
    if Chatify and type(Chatify.UnregisterChatCommand) == "function" then
        pcall(Chatify.UnregisterChatCommand, Chatify, "chatcopy")
    end
end
