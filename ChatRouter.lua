local addonName, ns = ...
local Chatify = ns.Chatify
local Router = Chatify:NewModule("Router", "AceEvent-3.0")

local _G = _G
local pairs = pairs
local type = type
local tostring = tostring
local tonumber = tonumber
local date = date
local time = time
local pcall = pcall
local hooksecurefunc = hooksecurefunc
local tinsert = table.insert
local tremove = table.remove
local GetServerTime = GetServerTime
local C_Timer = C_Timer
local GetTime = GetTime

local hookedFrames = {}
local proxyFrames = {}
local originalAddMessage = {}
local hiddenFrames = {}
local cache = {}
local cacheIndex = 0
local CACHE_LIMIT = 800
local routerHooksInstalled = false

-- Anti-flood state for virtual mode.
-- The same chat event can be routed to multiple frames in a very small time window,
-- so we allow a short "fan-out" window before we treat repeated text as spam.
local recentLines = {}
local FANOUT_WINDOW = 0.08


local function IsRetailSecretValueBuild()
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
        return false
    end

    if type(GetBuildInfo) ~= "function" then
        return true
    end

    local interfaceVersion = select(4, GetBuildInfo())
    return type(interfaceVersion) == "number" and interfaceVersion >= 120000
end

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns.db
end

local function IsVirtualEnabled()
    local db = DB()
    if not db or not db.useVirtualChat then
        return false
    end

    if IsRetailSecretValueBuild() then
        return false
    end

    return true
end

local function SafeString(raw)
    if type(ns.TryMakeSafeText) == "function" then
        return ns.TryMakeSafeText(raw)
    end

    if raw == nil then
        return nil
    end

    local rawType = type(raw)
    if rawType == "number" then
        return tostring(raw)
    end
    if rawType == "string" then
        return raw
    end

    return nil
end

local function NormalizeText(text)
    local safe = SafeString(text)
    if not safe then
        return nil
    end

    local ok, normalized = pcall(function()
        local v = safe
        v = v:gsub("|c%x%x%x%x%x%x%x%x", "")
        v = v:gsub("|r", "")
        v = v:gsub("|H.-|h(.-)|h", "%1")
        v = v:gsub("[%s%p%c]", "")
        v = v:upper()
        return v
    end)

    if ok and type(normalized) == "string" then
        return normalized
    end

    return nil
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
    if not frameID or frameID == 2 or not text then
        return
    end

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
    if not db or not db.useVirtualChat or not db.enableHistory then
        return
    end

    if not ChatifyHistoryDB or not ChatifyHistoryDB.Virtual then
        return
    end

    for frameID, messages in pairs(ChatifyHistoryDB.Virtual) do
        local frame = _G["ChatFrame" .. frameID]
        if frame and messages and #messages > 0 then
            local orig = originalAddMessage[frame] or (frame and frame.AddMessage)
            if type(orig) == "function" then
                orig(frame, "|cff666666---------------- Chatify History ----------------|r")
                for i = 1, #messages do
                    local msg = SafeString(messages[i])
                    if msg then
                        if db.historyAlpha then
                            orig(frame, "|cff888888" .. msg .. "|r")
                        else
                            orig(frame, msg)
                        end
                    end
                end
                orig(frame, "|cff666666-----------------------------------------------|r")
            end
        end
    end
end

local function ApplyTimestamp(text)
    local db = DB()
    if not db or not db.enableTimestamps then
        return text
    end

    local formatStr = "%H:%M"
    if ns.Lists and ns.Lists.TimeFormats and db.timestampID then
        local entry = ns.Lists.TimeFormats[db.timestampID]
        if entry then
            if entry.format == nil then
                return text
            end
            formatStr = entry.format or formatStr
        end
    end

    local nowValue = time()
    if db.useServerTime and type(GetServerTime) == "function" then
        local ok, serverNow = pcall(GetServerTime)
        if ok and serverNow then
            nowValue = serverNow
        end
    end

    local stamp = date(formatStr, nowValue)
    local id = SaveCopyPayload(text)
    local color = db.timestampColor or "68ccef"
    local prefix = string.format("|cff%s|Hchatcopy:%d|h[%s]|h|r", color, id, stamp)

    if db.timestampPost then
        return text .. " " .. prefix
    end

    return prefix .. " " .. text
end

local function ShouldSuppressForSpam(frameID, text)
    local db = DB()
    if not db then
        return false
    end

    local normalized = NormalizeText(text)
    if not normalized then
        return false
    end

    local now = GetTime()
    local state = recentLines[normalized]

    if db.enableSpamFilter and ns.IsSpamMessage and ns.IsSpamMessage(normalized) then
        return true
    end

    if not db.enableThrottle then
        return false
    end

    local throttleTime = tonumber(db.throttleTime) or 60

    if not state then
        recentLines[normalized] = {
            lastSeen = now,
            seenFrames = { [frameID] = true },
        }
        return false
    end

    local delta = now - (state.lastSeen or 0)

    if delta <= FANOUT_WINDOW then
        if state.seenFrames[frameID] then
            return true
        end

        state.seenFrames[frameID] = true
        return false
    end

    if delta < throttleTime then
        state.lastSeen = now
        state.seenFrames = { [frameID] = true }
        return true
    end

    state.lastSeen = now
    state.seenFrames = { [frameID] = true }
    return false
end

local function CopyFrameSettings(source, target)
    if not source or not target then
        return
    end

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

local function ShouldShowHoverHyperlinkTooltips()
    local db = DB()
    if not db or db.hoverHyperlinkTooltips == nil then
        return true
    end

    return db.hoverHyperlinkTooltips
end

local function ShowHyperlinkTooltip(owner, link)
    if not owner or not link or link == "" then
        return
    end

    if not ShouldShowHoverHyperlinkTooltips() then
        return
    end

    if type(link) ~= "string" then
        return
    end

    if link:match("^chatcopy:") or link:match("^url:") then
        return
    end

    if GameTooltip and GameTooltip.SetOwner and GameTooltip.SetHyperlink then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")

        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then
            GameTooltip:Show()
            return
        end
    end

    local handler = _G.SetItemRef or ChatFrame_OnHyperlinkShow
    if ItemRefTooltip and ItemRefTooltip.SetOwner and type(handler) == "function" then
        ItemRefTooltip:SetOwner(owner, "ANCHOR_PRESERVE")
        pcall(handler, link, nil, "LeftButton", owner)
    end
end

local function HideHyperlinkTooltip(owner)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == owner then
        GameTooltip:Hide()
    end

    if ItemRefTooltip and ItemRefTooltip.GetOwner and ItemRefTooltip:GetOwner() == owner then
        ItemRefTooltip:Hide()
    end
end

local interactiveFrames = {}

local function EnsureFrameHyperlinks(frame)
    if not frame then
        return
    end

    if frame.SetHyperlinksEnabled then
        pcall(frame.SetHyperlinksEnabled, frame, true)
    end

    if interactiveFrames[frame] then
        return
    end

    interactiveFrames[frame] = true

    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnHyperlinkEnter", function(self, link)
            if type(link) ~= "string" then
                return
            end

            if link:match("^url:") or link:match("^chatcopy:") then
                return
            end

            if not ShouldShowHoverHyperlinkTooltips() then
                HideHyperlinkTooltip(self)
                return
            end

            ShowHyperlinkTooltip(self, link)
        end)

        pcall(frame.HookScript, frame, "OnHyperlinkLeave", function(self)
            HideHyperlinkTooltip(self)
        end)
    end
end

local function EnsureProxy(frame)
    return nil
end

local function HideOriginalFrame(frame)
    if not frame or hiddenFrames[frame] then
        return
    end

    hiddenFrames[frame] = true

    if frame.Clear then
        pcall(frame.Clear, frame)
    end

    local tab = frame.GetName and _G[frame:GetName() .. "Tab"] or nil
    if tab then
        tab:SetAlpha(1)
    end

    local buttonFrame = frame.GetName and _G[frame:GetName() .. "ButtonFrame"] or nil
    if buttonFrame then
        buttonFrame:SetAlpha(1)
    end

    local editBox = ns.GetEditBox and ns.GetEditBox(frame)
    if editBox then
        editBox:SetAlpha(1)
    end
end

local function PassThrough(frame, ...)
    local orig = originalAddMessage[frame]
    if orig then
        return orig(frame, ...)
    end
end

local function PrepareOutput(text)
    local rawType = type(text)
    if rawType ~= "string" and rawType ~= "number" then
        return nil, nil
    end

    local safeText = SafeString(text)
    if not safeText then
        -- Secret/tainted string: показуємо як є, але не чіпаємо форматування, таймстемпи, copy/cache.
        return text, nil
    end

    if type(ns.FormatMessage) == "function" then
        local ok, formatted = pcall(ns.FormatMessage, safeText)
        if ok and type(formatted) == "string" then
            safeText = formatted
        end
    end

    return ApplyTimestamp(safeText), safeText
end

local function HandleRetailRestrictedAddMessage(frame, text, ...)
    local orig = originalAddMessage[frame]
    if type(orig) ~= "function" then
        return
    end

    local output = text
    local rawType = type(text)
    if rawType == "string" or rawType == "number" then
        local safeText = SafeString(text)
        if safeText and type(ns.FormatLinksOnly) == "function" then
            local ok, formatted = pcall(ns.FormatLinksOnly, safeText)
            if ok and type(formatted) == "string" then
                output = formatted
            else
                output = safeText
            end
        elseif safeText then
            output = safeText
        end
    end

    return orig(frame, output, ...)
end

local function HandleVirtualAddMessage(frame, text, ...)
    if IsRetailSecretValueBuild() then
        return HandleRetailRestrictedAddMessage(frame, text, ...)
    end

    if not IsVirtualEnabled() then
        return PassThrough(frame, text, ...)
    end

    local frameID = frame and frame.GetID and frame:GetID() or 0
    if ShouldSuppressForSpam(frameID, text) then
        return
    end

    local output, plain = PrepareOutput(text)
    if output == nil then
        return
    end

    local orig = originalAddMessage[frame]
    if type(orig) ~= "function" then
        return
    end

    local stickToBottom = true
    if frame and frame.AtBottom then
        local okBottom, atBottom = pcall(frame.AtBottom, frame)
        if okBottom then
            stickToBottom = atBottom and true or false
        end
    end

    local ok = pcall(orig, frame, output, ...)
    if ok and stickToBottom and frame.ScrollToBottom then
        pcall(frame.ScrollToBottom, frame)
    end

    if ok and plain then
        local db = DB()
        if db and db.enableHistory then
            SaveVirtualLine(frameID, plain, tonumber(db.historyLimit) or 50)
        end
    end
end

local function HookFrame(frame)
    if not frame or hookedFrames[frame] or not frame.AddMessage then
        return
    end

    if frame.GetName and frame:GetName() == "ChatFrame2" then
        return
    end

    EnsureFrameHyperlinks(frame)

    if IsRetailSecretValueBuild() then
        -- Retail 12.x: never replace Blizzard-owned AddMessage on live chat frames.
        -- Use ChatFrame_AddMessageEventFilter instead, which Blizzard routes through
        -- a secure canaccessvalue(...) gate for inaccessible payloads.
        hookedFrames[frame] = true
        return
    end

    hookedFrames[frame] = true
    originalAddMessage[frame] = frame.AddMessage

    frame.AddMessage = function(self, ...)
        return HandleVirtualAddMessage(self, ...)
    end
end

function Router:ApplyToAllFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            EnsureFrameHyperlinks(frame)
            HookFrame(frame)
        end
    end
end

function Router:RefreshProxies()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            EnsureFrameHyperlinks(frame)
        end
    end
end

function Router:SaveHistory()
    if not IsVirtualEnabled() then
        return
    end
    EnsureHistoryStore()
end

function Router:OnEnable()
    local db = DB()
    if db then
        ns.EnforceRetailSafeMode(db)
    end

    local retailRestricted = IsRetailSecretValueBuild()

    self:ApplyToAllFrames()
    self:RegisterEvent("PLAYER_LOGIN", "ApplyToAllFrames")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "RefreshProxies")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "RefreshProxies")

    if not retailRestricted then
        self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
        self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")
    end

    if not routerHooksInstalled and type(hooksecurefunc) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function(frame)
            if frame then
                HookFrame(frame)
            end
            self:RefreshProxies()
        end)

        hooksecurefunc("FCF_OpenNewWindow", function(frame)
            if frame then
                HookFrame(frame)
            end
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

        routerHooksInstalled = true
    end

    C_Timer.After(1, function()
        self:ApplyToAllFrames()
        self:RefreshProxies()
        if not retailRestricted then
            RestoreVirtualHistory()
        end
    end)
end
