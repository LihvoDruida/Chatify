local addonName, ns = ...
local Chatify = ns.Chatify
local Router = Chatify:NewModule("Router", "AceEvent-3.0")

local _G = _G
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local tonumber = tonumber
local string_format = string.format
local string_gsub = string.gsub
local string_find = string.find
local string_upper = string.upper
local date = date
local time = time
local pcall = pcall
local next = next
local unpack = unpack or table.unpack
local tinsert = table.insert
local tremove = table.remove
local GetTime = GetTime
local UnitName = UnitName

local PLAYER_NAME = UnitName("player")

local hookedFrames = {}
local proxyFrames = {}
local originalAddMessage = {}
local lineTime = {}
local lineId = {}
local hiddenFrames = {}
local cache = {}
local cacheIndex = 0
local CACHE_LIMIT = 600

local function DB()
    return Chatify and Chatify.db and Chatify.db.profile or ns.db
end

local function IsVirtualEnabled()
    local db = DB()
    return db and db.useVirtualChat
end

local function SafeString(raw)
    if raw == nil then return nil end
    if type(raw) == "number" then return tostring(raw) end
    if type(raw) ~= "string" then return nil end

    local ok, clean = pcall(string_format, "%s", raw)
    if ok and clean ~= "" then
        return clean
    end
    return nil
end

local function NormalizeText(text)
    text = SafeString(text)
    if not text then return "" end
    text = string_gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string_gsub(text, "|r", "")
    text = string_gsub(text, "|H.-|h(.-)|h", "%1")
    text = string_gsub(text, "[%s%p%c]", "")
    return string_upper(text)
end

local function SaveCopyPayload(text)
    cacheIndex = cacheIndex + 1
    cache[cacheIndex] = text

    local pruneBefore = cacheIndex - CACHE_LIMIT
    if pruneBefore > 0 then
        cache[pruneBefore] = nil
    end

    return cacheIndex
end

function ns.GetCachedChatLine(id)
    return id and cache[id] or nil
end

local function EnsureHistoryStore()
    ChatifyHistoryDB = ChatifyHistoryDB or {}
    ChatifyHistoryDB.Virtual = ChatifyHistoryDB.Virtual or {}
    return ChatifyHistoryDB.Virtual
end

local function SaveVirtualLine(frameID, text, limit)
    if not frameID or frameID == 2 or not text then return end

    local store = EnsureHistoryStore()
    store[frameID] = store[frameID] or {}
    local bucket = store[frameID]
    tinsert(bucket, text)

    while #bucket > limit do
        tremove(bucket, 1)
    end
end

local function RestoreVirtualHistory()
    local db = DB()
    if not db or not db.useVirtualChat or not db.enableHistory then return end
    if not ChatifyHistoryDB or not ChatifyHistoryDB.Virtual then return end

    for frameID, messages in pairs(ChatifyHistoryDB.Virtual) do
        local proxy = proxyFrames[frameID]
        if proxy and messages then
            proxy:AddMessage("|cff666666---------------- Chatify History ----------------|r")
            for i = 1, #messages do
                local msg = SafeString(messages[i])
                if msg then
                    proxy:AddMessage(db.historyAlpha and ("|cff888888" .. msg .. "|r") or msg)
                end
            end
            proxy:AddMessage("|cff666666-----------------------------------------------|r")
        end
    end
end

local function PassThrough(frame, ...)
    local orig = originalAddMessage[frame]
    if orig then
        return orig(frame, ...)
    end
end

local function ApplyTimestamp(text)
    local db = DB()
    if not db or not db.enableTimestamps then return text end

    local formatStr = "%H:%M"
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
        local entry = ns.Lists.TimeFormats[db.timestampID]
        if entry and entry.format then
            formatStr = entry.format
        elseif entry and entry.format == nil then
            return text
        end
    end

    local stamp = date(formatStr, (db.useServerTime and GetServerTime and GetServerTime()) or time())
    local id = SaveCopyPayload(text)
    local color = db.timestampColor or "68ccef"
    local prefix = string_format("|cff%s|Hchatcopy:%d|h[%s]|h|r", color, id, stamp)

    if db.timestampPost then
        return text .. " " .. prefix
    end
    return prefix .. " " .. text
end

local function MaybeHideSpam(text)
    local db = DB()
    if not db then return false end

    local normalized = NormalizeText(text)
    if normalized == "" then return false end

    if db.enableSpamFilter and db.spamKeywords then
        for i = 1, #db.spamKeywords do
            local keyword = NormalizeText(db.spamKeywords[i])
            if keyword ~= "" and string_find(normalized, keyword, 1, true) then
                return true
            end
        end
    end

    if db.enableThrottle then
        local now = GetTime()
        local lastSeen = lineTime[normalized]
        local expires = tonumber(db.throttleTime) or 60
        if lastSeen and (now - lastSeen) < expires then
            return true
        end
        lineTime[normalized] = now
    end

    return false
end

local function CopyFrameSettings(source, target)
    if not source or not target then return end

    local font, size, flags = source:GetFont()
    if font then
        target:SetFont(font, size or 14, flags)
    end

    if target.SetIndentedWordWrap then target:SetIndentedWordWrap(true) end
    if source.GetMaxLines and target.SetMaxLines then target:SetMaxLines(source:GetMaxLines() or 128) end
    if source.GetFading and target.SetFading then target:SetFading(source:GetFading()) end
    if source.GetTimeVisible and target.SetTimeVisible then target:SetTimeVisible(source:GetTimeVisible()) end
    if source.GetFadeDuration and target.SetFadeDuration then target:SetFadeDuration(source:GetFadeDuration()) end
    if source.GetSpacing and target.SetSpacing then target:SetSpacing(source:GetSpacing() or 0) end
    if source.GetInsertMode and target.SetInsertMode then target:SetInsertMode(source:GetInsertMode()) end
    if source.GetJustifyH and target.SetJustifyH then target:SetJustifyH(source:GetJustifyH() or "LEFT") end
    if target.SetHyperlinksEnabled then target:SetHyperlinksEnabled(true) end
end

local function EnsureProxy(frame)
    if not frame or frame.ChatifyProxy then
        return frame and frame.ChatifyProxy or nil
    end

    local proxy = CreateFrame("ScrollingMessageFrame", nil, frame)
    proxy:SetAllPoints(frame)
    proxy:SetFrameLevel(frame:GetFrameLevel() + 5)
    proxy:EnableMouseWheel(true)
    proxy:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    proxy:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then
            SetItemRef(link, text, button, frame)
        end
    end)
    proxy:SetScript("OnSizeChanged", function(self)
        local source = self:GetParent()
        if source then
            CopyFrameSettings(source, self)
        end
    end)

    CopyFrameSettings(frame, proxy)

    frame.ChatifyProxy = proxy
    proxyFrames[frame:GetID()] = proxy
    return proxy
end

local function HideOriginalFrame(frame)
    if not frame or hiddenFrames[frame] then return end
    hiddenFrames[frame] = true

    if frame.Clear then
        pcall(frame.Clear, frame)
    end

    local tab = _G[frame:GetName() .. "Tab"]
    if tab then
        tab:SetAlpha(1)
    end

    local buttonFrame = _G[frame:GetName() .. "ButtonFrame"]
    if buttonFrame then
        buttonFrame:SetAlpha(1)
    end

    local editBox = ns.GetEditBox and ns.GetEditBox(frame)
    if editBox then
        editBox:SetAlpha(1)
    end
end

local function HandleVirtualAddMessage(frame, text, ...)
    if not IsVirtualEnabled() then
        return PassThrough(frame, text, ...)
    end

    local safeText = SafeString(text)
    if not safeText then
        return
    end

    if MaybeHideSpam(safeText) then
        return
    end

    local out = ApplyTimestamp(safeText)
    local proxy = EnsureProxy(frame)
    if not proxy then
        return
    end

    local ok = pcall(proxy.AddMessage, proxy, out, ...)
    if ok then
        local db = DB()
        if db and db.enableHistory then
            SaveVirtualLine(frame:GetID(), safeText, tonumber(db.historyLimit) or 50)
        end
    end
end

local function HookFrame(frame)
    if not frame or hookedFrames[frame] or not frame.AddMessage then return end
    if frame.GetName and frame:GetName() == "ChatFrame2" then return end

    hookedFrames[frame] = true
    originalAddMessage[frame] = frame.AddMessage
    EnsureProxy(frame)
    HideOriginalFrame(frame)

    frame.AddMessage = function(self, ...)
        return HandleVirtualAddMessage(self, ...)
    end
end

function Router:ApplyToAllFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            HookFrame(frame)
        end
    end
end

function Router:RefreshProxies()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            local proxy = EnsureProxy(frame)
            if proxy then
                CopyFrameSettings(frame, proxy)
            end
        end
    end
end

function Router:SaveHistory()
    if not IsVirtualEnabled() then return end
    EnsureHistoryStore()
end

function Router:OnEnable()
    self:ApplyToAllFrames()
    self:RegisterEvent("PLAYER_LOGIN", "ApplyToAllFrames")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "RefreshProxies")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "RefreshProxies")
    self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")

    if hooksecurefunc then
        hooksecurefunc("FCF_OpenTemporaryWindow", function(frame)
            if frame then HookFrame(frame) end
            self:RefreshProxies()
        end)
        hooksecurefunc("FCF_OpenNewWindow", function(frame)
            if frame then HookFrame(frame) end
            self:RefreshProxies()
        end)
        hooksecurefunc("FCF_SetChatWindowFontSize", function(frame)
            if frame then
                local proxy = EnsureProxy(frame)
                if proxy then
                    CopyFrameSettings(frame, proxy)
                end
            end
        end)
    end

    C_Timer.After(1, function()
        self:ApplyToAllFrames()
        self:RefreshProxies()
        RestoreVirtualHistory()
    end)
end
