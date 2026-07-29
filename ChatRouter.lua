local addonName, ns = ...
local Chatify = ns.Chatify
local Router = Chatify:NewModule("Router", "AceEvent-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

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

local tooltipLinkTypes = {
    item = true,
    enchant = true,
    spell = true,
    quest = true,
    achievement = true,
    currency = true,
    battlepet = true,
}

-- Weak keys so a temporary chat window that Blizzard discards does not stay
-- referenced (and its original AddMessage retained) until the next reload.
local hookedFrames = setmetatable({}, { __mode = "k" })
local originalAddMessage = setmetatable({}, { __mode = "k" })
local cache = {}
local cacheIndex = 0
local CACHE_LIMIT = 800
local routerHooksInstalled = false

-- Anti-flood state for virtual mode.
-- The same chat event can be routed to multiple frames in a very small time window,
-- so we allow a short "fan-out" window before we treat repeated text as spam.
local recentLines = {}
local FANOUT_WINDOW = 0.08
local recentLinesPruneCounter = 0
local RECENT_LINES_PRUNE_INTERVAL = 50


local function IsRetailSecretValueBuild()
    if type(ns.IsRetailSecretValueBuild) == "function" then
        return ns.IsRetailSecretValueBuild()
    end

    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
        return false
    end

    if type(issecretvalue) == "function" or type(canaccessvalue) == "function" then
        return true
    end

    if type(GetBuildInfo) ~= "function" then
        return true
    end

    local interfaceVersion = select(4, GetBuildInfo())
    return type(interfaceVersion) == "number" and interfaceVersion >= 110000
end

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return ns.db
end

local function SafeAfter(delay, callback)
    if type(ns.SafeAfter) == "function" then
        return ns.SafeAfter(delay, callback)
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0, function()
            pcall(callback)
        end)
        return true
    end

    if type(callback) == "function" then
        pcall(callback)
        return true
    end

    return false
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

local function IsSecretValue(value)
    return type(ns.IsSecretValue) == "function" and ns.IsSecretValue(value)
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
    if type(ns.NormalizeSpamText) == "function" then
        local ok, forms = pcall(ns.NormalizeSpamText, text)
        if ok and type(forms) == "table" and type(forms.compact) == "string" then
            return forms.compact
        end
    end

    local safe = SafeString(text)
    if not safe then
        return nil
    end

    local ok, normalized = pcall(function()
        local v = safe
        v = v:gsub("|H.-|h(.-)|h", "%1")
        v = v:gsub("|c%x%x%x%x%x%x%x%x", "")
        v = v:gsub("|r", "")
        v = v:gsub("|T.-|t", " ")
        v = v:gsub("|A.-|a", " ")
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
    if type(ns.SaveToCache) == "function" then
        local ok, externalId = pcall(ns.SaveToCache, text)
        if ok and externalId then
            return externalId
        end
    end

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

local function PruneRecentLines(maxAge)
    local now = GetTime()
    local cutoff = now - math.max(maxAge or 5, FANOUT_WINDOW, 5)

    for normalized, state in pairs(recentLines) do
        if type(state) ~= "table" or type(state.lastSeen) ~= "number" or state.lastSeen < cutoff then
            recentLines[normalized] = nil
        end
    end
end

-- Group and whisper traffic must never be dropped by the router.
--
-- ns.ProcessSpamMessage (the filter path) already exempts GUILD/PARTY/RAID/
-- WHISPER/LOOT by default, but the router sees rendered lines with no event name
-- attached and used to apply both the keyword filter and the duplicate throttle to
-- everything. In a Mythic+ or raid that silently ate the short repeated calls the
-- group actually depends on ("go", "kick", "stop", "pull"), which reads exactly
-- like chat having stopped working.
local groupChannelTokens = {
    "|Hchannel:PARTY",
    "|Hchannel:RAID",
    "|Hchannel:INSTANCE",
    "|Hchannel:GUILD",
    "|Hchannel:OFFICER",
    "|HBNplayer:",
}

local function IsProtectedGroupLine(text)
    if type(text) ~= "string" then
        return false
    end

    for i = 1, #groupChannelTokens do
        if text:find(groupChannelTokens[i], 1, true) then
            return true
        end
    end

    -- Whispers carry no channel link, so match the localized templates instead.
    for _, template in ipairs({
        _G.CHAT_WHISPER_GET, _G.CHAT_WHISPER_INFORM_GET,
        _G.CHAT_BN_WHISPER_GET, _G.CHAT_BN_WHISPER_INFORM_GET,
        _G.CHAT_RAID_WARNING_GET,
    }) do
        if type(template) == "string" then
            local prefix = template:match("^([^%%]+)")
            if prefix and #prefix >= 2 and text:find(prefix, 1, true) then
                return true
            end
        end
    end

    return false
end

local function ShouldSuppressForSpam(frameID, text)
    local db = DB()
    if not db then
        return false
    end

    if IsProtectedGroupLine(text) then
        return false
    end

    local normalized = NormalizeText(text)
    if not normalized then
        return false
    end

    local throttleTime = tonumber(db.throttleTime) or 60
    recentLinesPruneCounter = recentLinesPruneCounter + 1
    if recentLinesPruneCounter >= RECENT_LINES_PRUNE_INTERVAL then
        recentLinesPruneCounter = 0
        PruneRecentLines(throttleTime)
    end

    local now = GetTime()
    local state = recentLines[normalized]

    if db.enableSpamFilter and ns.IsSpamMessage and ns.IsSpamMessage(text) then
        return true
    end

    if not db.enableThrottle then
        return false
    end

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

local function ShouldShowHoverHyperlinkTooltips()
    local db = DB()
    if not db or db.hoverHyperlinkTooltips == nil then
        return true
    end

    return db.hoverHyperlinkTooltips
end

local function IsSafeHyperlink(link)
    if IsSecretValue(link) then
        return false
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(link) then
        return false
    end

    if type(link) ~= "string" or link == "" then
        return false
    end

    return true
end

local function ShowHyperlinkTooltip(owner, link)
    if not owner or not IsSafeHyperlink(link) then
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

    local linkType = link:match("^([^:]+):")
    if not tooltipLinkTypes[linkType] then
        return
    end

    if GameTooltip then
        GameTooltip:Hide()
    end
    if BattlePetTooltip then
        BattlePetTooltip:Hide()
    end

    if linkType == "battlepet" and BattlePetToolTip_ShowLink and GameTooltip and GameTooltip.SetOwner then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
        local ok = pcall(BattlePetToolTip_ShowLink, link)
        if ok then
            return
        end
        GameTooltip:Hide()
    end

    if GameTooltip and GameTooltip.SetOwner and GameTooltip.SetHyperlink then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")

        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then
            GameTooltip:Show()
            return
        end
        GameTooltip:Hide()
    end

    -- Avoid SetItemRef / ItemRefTooltip fallback on hover. That path is more prone to
    -- tooltip/chat taint on modern Retail and is not required for standard hover previews.
end

local function HideHyperlinkTooltip(owner)
    if GameTooltip then
        local owned = (GameTooltip.IsOwned and owner and GameTooltip:IsOwned(owner)) or (GameTooltip.GetOwner and GameTooltip:GetOwner() == owner)
        if owned then
            GameTooltip:Hide()
        end
    end

    if ItemRefTooltip then
        local owned = (ItemRefTooltip.IsOwned and owner and ItemRefTooltip:IsOwned(owner)) or (ItemRefTooltip.GetOwner and ItemRefTooltip:GetOwner() == owner)
        if owned then
            ItemRefTooltip:Hide()
        end
    end

    if BattlePetTooltip then
        local owned = (BattlePetTooltip.IsOwned and owner and BattlePetTooltip:IsOwned(owner)) or (BattlePetTooltip.GetOwner and BattlePetTooltip:GetOwner() == owner)
        if owned and BattlePetTooltip.Hide then
            BattlePetTooltip:Hide()
        end
    end
end

local interactiveFrames = setmetatable({}, { __mode = "k" })

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
        local hook = ns.SafeHookScript
        local function onEnter(self, link)
            if not IsSafeHyperlink(link) then
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
        end
        local function onLeave(self)
            HideHyperlinkTooltip(self)
        end

        if type(hook) == "function" then
            hook(frame, "OnHyperlinkEnter", onEnter, "__chatifyRouterHyperlinkEnter")
            hook(frame, "OnHyperlinkLeave", onLeave, "__chatifyRouterHyperlinkLeave")
        else
            pcall(frame.HookScript, frame, "OnHyperlinkEnter", onEnter)
            pcall(frame.HookScript, frame, "OnHyperlinkLeave", onLeave)
        end
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

    -- Only ever re-stick to the bottom when the frame positively told us it was
    -- already there. The old default was `true`, so a missing or erroring AtBottom
    -- yanked the view down on every incoming line and made scrollback unusable
    -- exactly when chat is busiest (raid fights, Mythic+). Blizzard's
    -- ScrollingMessageFrame already auto-follows when the user is at the bottom,
    -- so doing nothing is the correct fallback.
    local stickToBottom = false
    if frame and frame.AtBottom then
        local okBottom, atBottom = pcall(frame.AtBottom, frame)
        if okBottom and atBottom then
            stickToBottom = true
        end
    end

    -- A user who has scrolled up stays scrolled up, whatever AtBottom reports.
    if stickToBottom and frame.GetScrollOffset then
        local okOffset, offset = pcall(frame.GetScrollOffset, frame)
        if okOffset and type(offset) == "number" and offset > 0 then
            stickToBottom = false
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

local function RestoreHookFrame(frame)
    if not frame then
        return
    end

    local original = originalAddMessage[frame]
    if type(original) == "function" and frame.AddMessage ~= original then
        frame.AddMessage = original
    end

    hookedFrames[frame] = nil
    originalAddMessage[frame] = nil
end

local function RestoreAllHookedFrames()
    for frame in pairs(hookedFrames) do
        RestoreHookFrame(frame)
    end
end

local function HookFrame(frame)
    if not frame or not frame.AddMessage then
        return
    end

    if frame.GetName and frame:GetName() == "ChatFrame2" then
        return
    end

    EnsureFrameHyperlinks(frame)

    if IsRetailSecretValueBuild() or not IsVirtualEnabled() then
        RestoreHookFrame(frame)
        return
    end

    if hookedFrames[frame] then
        return
    end

    hookedFrames[frame] = true
    originalAddMessage[frame] = frame.AddMessage

    frame.AddMessage = function(self, ...)
        return HandleVirtualAddMessage(self, ...)
    end
end

function Router:ApplyToAllFrames()
    local virtualEnabled = IsVirtualEnabled() and not IsRetailSecretValueBuild()
    if not virtualEnabled then
        RestoreAllHookedFrames()
    end

    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            EnsureFrameHyperlinks(frame)
            if virtualEnabled then
                HookFrame(frame)
            end
        end
    end
end

function Router:RefreshProxies()
    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
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
    local function register(eventName, method)
        if type(ns.RegisterEventIfSupported) == "function" then
            return ns.RegisterEventIfSupported(self, eventName, method)
        end
        return pcall(self.RegisterEvent, self, eventName, method)
    end
    register("PLAYER_LOGIN", "ApplyToAllFrames")
    register("UPDATE_CHAT_WINDOWS", "RefreshProxies")
    register("UPDATE_FLOATING_CHAT_WINDOWS", "RefreshProxies")

    if not retailRestricted then
        register("PLAYER_LOGOUT", "SaveHistory")
        register("PLAYER_LEAVING_WORLD", "SaveHistory")
    end

    if not routerHooksInstalled and type(hooksecurefunc) == "function" then
        local function RefreshChatWindowsSoon(candidateFrame)
            if type(candidateFrame) == "table" then
                HookFrame(candidateFrame)
            end

            SafeAfter(0, function()
                self:ApplyToAllFrames()
                self:RefreshProxies()
            end)
        end

        if type(FCF_OpenTemporaryWindow) == "function" then
            pcall(hooksecurefunc, "FCF_OpenTemporaryWindow", RefreshChatWindowsSoon)
        end
        if type(FCF_OpenNewWindow) == "function" then
            pcall(hooksecurefunc, "FCF_OpenNewWindow", RefreshChatWindowsSoon)
        end
        if type(FCF_SetTemporaryWindowType) == "function" then
            pcall(hooksecurefunc, "FCF_SetTemporaryWindowType", RefreshChatWindowsSoon)
        end

        routerHooksInstalled = true
    end

    SafeAfter(1, function()
        self:ApplyToAllFrames()
        self:RefreshProxies()
        -- Saved history is intentionally not replayed into live chat frames.
    end)
end
