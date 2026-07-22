local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Підключаємо LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0", true)
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")
local visualsFiltersInstalled = false
local visualsApplyQueued = false
local registeredTimestampFilters = {}
local TimestampFilter
local frameStyleCache = {}
local C_Timer = C_Timer
local GetServerTime = GetServerTime

local function IsSecretValue(value)
    return type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value)
end

local function GetVisualDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns and ns.db or nil
end

local function QueueApplyVisuals(delay)
    delay = tonumber(delay) or 0
    if delay < 0 then
        delay = 0
    end

    local after = ns.SafeAfter
    if type(after) ~= "function" and (not C_Timer or not C_Timer.After) then
        pcall(ns.ApplyVisuals)
        return
    end

    if delay > 0 then
        if type(after) == "function" then
            after(delay, function() pcall(ns.ApplyVisuals) end)
        else
            pcall(C_Timer.After, delay, function() pcall(ns.ApplyVisuals) end)
        end
        return
    end

    if visualsApplyQueued then
        return
    end

    visualsApplyQueued = true
    local function runApply()
        visualsApplyQueued = false
        pcall(ns.ApplyVisuals)
    end
    if type(after) == "function" then
        after(0, runApply)
    else
        pcall(C_Timer.After, 0, runApply)
    end
end

-- =========================================================
-- SAFE EVENT WHITELIST (КРИТИЧНО ВАЖЛИВО)
-- =========================================================
-- Ми додаємо таймстемпи ТІЛЬКИ до цих подій.
-- На modern Retail whisper/BNet whisper події не мутуємо: Blizzard сам дублює їх
-- у General, temporary tabs і popup-вікна.
local eventsToHandle = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_BN_CONVERSATION = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_AFK = true,
    CHAT_MSG_DND = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_LOOT = true,
}

-- On modern Retail whisper/BNet events are also timestamped, but only outside of
-- chat messaging lockdown. CanMutateChatPayload() returns false while the payload
-- is secret (lockdown), so the filter passes those lines through untouched and
-- avoids the 12.0.x "timestamps during lockdown" Lua error. Users who prefer the
-- old never-touch-whispers behaviour can enable db.retailWhisperSafeMode.
local retailTimestampEvents = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_BN_CONVERSATION = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_LOOT = true,
}

-- =========================================================
-- 1. UTILITIES & SAFETY
-- =========================================================
local function NormalizeFontSize(size)
    if type(size) ~= "number" or size <= 0 then return 14 end
    local rounded = math.floor(size + 0.5)
    if rounded <= 0 or rounded > 64 then return 14 end
    return rounded
end

local function CleanTextTags(text)
    if not text then return "" end
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

-- Безпечне отримання тексту (Deep Sanitization)
local function GetSafeText(rawText)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(rawText)
    end

    if rawText == nil then return nil end
    if type(rawText) == "number" then return tostring(rawText) end
    if type(rawText) ~= "string" then return nil end
    return rawText
end

function ns.GetEditBox(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.editBox then return chatFrame.editBox end

    local name = chatFrame:GetName()
    if name then
        local suffixBox = _G[name .. "EditBox"]
        if suffixBox then return suffixBox end
    end

    local id = chatFrame:GetID()
    if id then
        local idBox = _G["ChatFrame" .. id .. "EditBox"]
        if idBox then return idBox end
    end

    return ChatFrame1EditBox
end

-- =========================================================
-- 2. FONT STYLING
-- =========================================================
local function StyleFrame(frame)
    if not frame then return end
    local db = GetVisualDB()
    if not db then return end

    local fontPath = nil
    if type(ns.ResolveFontPath) == "function" then
        fontPath = ns.ResolveFontPath(db.fontID)
    elseif db.fontID then
        fontPath = LSM and LSM.Fetch and LSM:Fetch("font", db.fontID, true) or nil
    end

    if not fontPath and ChatFontNormal and ChatFontNormal.GetFont then
        fontPath = ChatFontNormal:GetFont()
    end

    local okFont, _, size, flags = pcall(frame.GetFont, frame)
    if not okFont then
        size, flags = 14, ""
    end
    size = NormalizeFontSize(size)
    local outline = db.fontOutline or flags or ""

    local signature = table.concat({ tostring(fontPath or ""), tostring(size), tostring(outline) }, "|")
    if frameStyleCache[frame] == signature then
        return
    end

    local ok = false
    if type(ns.SafeSetFont) == "function" then
        ok = ns.SafeSetFont(frame, fontPath, size, outline)
    elseif type(frame.SetFont) == "function" then
        local okCall, applied = pcall(frame.SetFont, frame, fontPath, size, outline)
        ok = okCall and applied ~= false
    end

    if not ok and ChatFontNormal and ChatFontNormal.GetFont then
        local fallbackPath = ChatFontNormal:GetFont()
        fontPath = fallbackPath or fontPath
        if type(frame.SetFont) == "function" then
            pcall(frame.SetFont, frame, fallbackPath, size, flags or "")
        end
    end

    if type(frame.SetShadowOffset) == "function" then
        pcall(frame.SetShadowOffset, frame, 1, -1)
    end

    local editBox = ns.GetEditBox(frame)
    if editBox then
        local editName = type(editBox.GetName) == "function" and editBox:GetName() or nil
        local header = editName and _G[editName.."Header"] or nil
        if header then
            if type(ns.SafeSetFont) == "function" then
                ns.SafeSetFont(header, fontPath, size, outline)
            else
                pcall(header.SetFont, header, fontPath, size, outline)
            end
        end

        local suffix = editName and _G[editName.."HeaderSuffix"] or nil
        if suffix then
            if type(ns.SafeSetFont) == "function" then
                ns.SafeSetFont(suffix, fontPath, size, outline)
            else
                pcall(suffix.SetFont, suffix, fontPath, size, outline)
            end
        end

        if type(ns.SafeSetFont) == "function" then
            ns.SafeSetFont(editBox, fontPath, size, outline)
        elseif type(editBox.SetFont) == "function" then
            pcall(editBox.SetFont, editBox, fontPath, size, outline)
        end
    end

    frameStyleCache[frame] = table.concat({ tostring(fontPath or ""), tostring(size), tostring(outline) }, "|")
end

-- =========================================================
-- 3. CHANNEL SHORTENING
-- =========================================================
local ShortChannelMaps = {
    CHAT_GUILD_GET              = "|Hchannel:GUILD|h[G]|h %s:\32",
    CHAT_OFFICER_GET            = "|Hchannel:OFFICER|h[O]|h %s:\32",
    CHAT_PARTY_GET              = "|Hchannel:PARTY|h[P]|h %s:\32",
    CHAT_PARTY_LEADER_GET       = "|Hchannel:PARTY|h[PL]|h %s:\32",
    CHAT_RAID_GET               = "|Hchannel:RAID|h[R]|h %s:\32",
    CHAT_RAID_LEADER_GET        = "|Hchannel:RAID|h[RL]|h %s:\32",
    CHAT_RAID_WARNING_GET       = "|Hchannel:RAID|h[RW]|h %s:\32",
    CHAT_INSTANCE_CHAT_GET      = "|Hchannel:INSTANCE|h[I]|h %s:\32",
    CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s:\32",
    CHAT_WHISPER_GET            = "[W] %s:\32",
    CHAT_WHISPER_INFORM_GET     = "[TO] %s:\32",
    CHAT_BN_WHISPER_GET         = "[BW] %s:\32",
    CHAT_BN_WHISPER_INFORM_GET  = "[BTO] %s:\32",
}

local OriginalChannelMaps = {}

local function IsRetailRestricted()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
end

local function RegisterTimestampFilter(eventName)
    if registeredTimestampFilters[eventName] then
        return
    end

    local ok = false
    if type(ns.AddMessageEventFilterIfSupported) == "function" then
        ok = ns.AddMessageEventFilterIfSupported(eventName, TimestampFilter)
    elseif type(ChatFrame_AddMessageEventFilter) == "function" then
        ok = pcall(ChatFrame_AddMessageEventFilter, eventName, TimestampFilter) and true or false
    end

    if ok then
        registeredTimestampFilters[eventName] = true
    end
end

local function UnregisterTimestampFilters()
    for eventName in pairs(registeredTimestampFilters) do
        if type(ns.RemoveMessageEventFilterIfSupported) == "function" then
            ns.RemoveMessageEventFilterIfSupported(eventName, TimestampFilter)
        elseif type(ChatFrame_RemoveMessageEventFilter) == "function" then
            pcall(ChatFrame_RemoveMessageEventFilter, eventName, TimestampFilter)
        end
    end

    registeredTimestampFilters = {}
    visualsFiltersInstalled = false
end

function ns.ApplyVisuals()
    local db = GetVisualDB()
    if not db then return end

    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame"..i]
        if frame then 
            StyleFrame(frame) 
        end
    end

    -- Short channel names only swap Blizzard GlobalStrings (CHAT_*_GET). These are
    -- plain format strings, not chat payloads, so they carry no secret values and
    -- are safe on modern Retail as well as every Classic flavour. Gate purely on
    -- the user preference.
    if db.shortChannels then
        if not next(OriginalChannelMaps) then
            for k, v in pairs(ShortChannelMaps) do
                if _G[k] then OriginalChannelMaps[k] = _G[k] end
            end
        end
        for k, v in pairs(ShortChannelMaps) do
            if _G[k] then _G[k] = v end
        end
    else
        if next(OriginalChannelMaps) then
            for k, v in pairs(OriginalChannelMaps) do
                _G[k] = v
            end
        end
    end
end

-- =========================================================
-- 4. TIMESTAMPS (SECURE)
-- =========================================================
TimestampFilter = function(self, event, msg, author, ...)
    local retailRestricted = IsRetailRestricted()
    -- Whispers are handled through CanMutateChatPayload() below, which bails while
    -- the payload is secret (lockdown) or when retailWhisperSafeMode is enabled.

    local db = GetVisualDB()
    if not db then return false, msg, author, ... end
    if not db.enableTimestamps then return false, msg, author, ... end
    local allowedEvents = retailRestricted and retailTimestampEvents or eventsToHandle
    if not allowedEvents[event] then return false, msg, author, ... end

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
    end

    local safeMsg = GetSafeText(msg)
    if not safeMsg or type(safeMsg) ~= "string" then
        return false, msg, author, ...
    end

    if safeMsg:find("|Hchatcopy:", 1, true) then
        return false, msg, author, ...
    end

    local timestampFormat = "%H:%M"
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
        local formatData = ns.Lists.TimeFormats[db.timestampID]
        if formatData then
            if formatData.format == nil then
                return false, msg, author, ...
            end
            timestampFormat = formatData.format or timestampFormat
        end
    end

    local timestamp = time()
    if db.useServerTime and type(GetServerTime) == "function" then
        local okServer, serverTime = pcall(GetServerTime)
        if okServer and serverTime then
            timestamp = serverTime
        end
    end

    local okBuild, finalMsg = pcall(function()
        local timeStr = date(timestampFormat, timestamp)
        local tsColor = db.timestampColor or "68ccef"
        local cacheId = nil
        if type(ns.SaveToCache) == "function" then
            cacheId = ns.SaveToCache(safeMsg, author, timestamp)
        end

        local styledTime
        if cacheId then
            styledTime = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", tsColor, cacheId, timeStr)
        else
            styledTime = string.format("|cff%s[%s]|r", tsColor, timeStr)
        end

        if db.timestampPost then
            return safeMsg .. " " .. styledTime
        end

        return styledTime .. " " .. safeMsg
    end)

    if not okBuild or type(finalMsg) ~= "string" then
        return false, msg, author, ...
    end

    return false, finalMsg, author, ...
end

-- =========================================================
-- 5. MODULE LIFECYCLE
-- =========================================================
function VisualsModule:OnEnable()
    if Chatify and Chatify.db and Chatify.db.profile then
        ns.EnforceRetailSafeMode(Chatify.db.profile)
    end

    local retailRestricted = IsRetailRestricted()

    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "PLAYER_LOGIN", "PLAYER_LOGIN")
        ns.RegisterEventIfSupported(self, "PLAYER_ENTERING_WORLD", "ApplyStyle")
        ns.RegisterEventIfSupported(self, "UPDATE_CHAT_WINDOWS", "ApplyStyle")
        ns.RegisterEventIfSupported(self, "UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")
    else
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyStyle")
        self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
        self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")
    end

    if type(FCF_OpenTemporaryWindow) == "function" then
        pcall(self.SecureHook, self, "FCF_OpenTemporaryWindow", function() QueueApplyVisuals(0) end)
    end
    if type(FCF_OpenNewWindow) == "function" then
        pcall(self.SecureHook, self, "FCF_OpenNewWindow", function() QueueApplyVisuals(0) end)
    end
    if type(FCF_SetTemporaryWindowType) == "function" then
        pcall(self.SecureHook, self, "FCF_SetTemporaryWindowType", function(chatFrame)
            StyleFrame(chatFrame)
            QueueApplyVisuals(0)
        end)
    end

    if type(hooksecurefunc) == "function" and type(FCF_SetChatWindowFontSize) == "function" then
        pcall(hooksecurefunc, "FCF_SetChatWindowFontSize", function(chatFrame)
            StyleFrame(chatFrame)
        end)
    end

    if not retailRestricted and type(ChatTypeInfo) == "table" then
        for _, info in pairs(ChatTypeInfo) do
            if type(info) == "table" then
                info.colorNameByClass = true
            end
        end
    end

    -- Віртуальний чат додає власні таймстемпи через Router, тому тут не дублюємо їх.
    -- На modern Retail useVirtualChat примусово неефективний, тому не даємо старому SavedVariables
    -- випадково вимкнути safe timestamp filter path.
    local db = GetVisualDB()
    local virtualActive = db and db.useVirtualChat and not retailRestricted
    if not visualsFiltersInstalled and not virtualActive then
        local filterEvents = retailRestricted and retailTimestampEvents or eventsToHandle
        for evt in pairs(filterEvents) do
            RegisterTimestampFilter(evt)
        end
        visualsFiltersInstalled = true
    end

    ns.ApplyVisuals()
end

function VisualsModule:PLAYER_LOGIN()
    QueueApplyVisuals(0)
    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(1, function() ns.ApplyVisuals() end)
        ns.SafeAfter(3, function() ns.ApplyVisuals() end)
    elseif C_Timer and C_Timer.After then
        pcall(C_Timer.After, 1, function() pcall(ns.ApplyVisuals) end)
        pcall(C_Timer.After, 3, function() pcall(ns.ApplyVisuals) end)
    end
end

function VisualsModule:ApplyStyle()
    QueueApplyVisuals(0)
end

function VisualsModule:OnDisable()
    UnregisterTimestampFilters()
    self:UnregisterAllEvents()
    if type(self.UnhookAll) == "function" then
        self:UnhookAll()
    end

    if next(OriginalChannelMaps) then
        for key, value in pairs(OriginalChannelMaps) do
            _G[key] = value
        end
    end
end
