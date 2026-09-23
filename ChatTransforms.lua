local addonName, ns = ...
local Chatify = ns.Chatify or LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Module = Chatify:NewModule("ChatTransforms", "AceEvent-3.0")

local hookedFrames = setmetatable({}, { __mode = "k" })
local spamDecisionByArgs = setmetatable({}, { __mode = "k" })
local stats = { observed = 0, transformed = 0, removedSpam = 0, skipped = 0, errors = 0 }

local function DB()
    if Chatify and Chatify.db and Chatify.db.profile then return Chatify.db.profile end
    return ns.db
end

local function Safe(value)
    if type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(value) then return false end
    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(value) then return false end
    return true
end

local function SafeText(value)
    if type(ns.TryMakeSafeText) == "function" then return ns.TryMakeSafeText(value) end
    if not Safe(value) then return nil end
    if type(value) == "string" then return value end
    if type(value) == "number" then return tostring(value) end
    return nil
end

local function FrameSupportsTransform(frame)
    return type(frame) == "table" and type(frame.TransformMessages) == "function" and type(hooksecurefunc) == "function"
end

local function FrameSupportsRemoval(frame)
    return type(frame) == "table" and type(frame.RemoveMessagesByPredicate) == "function" and type(hooksecurefunc) == "function"
end

local function FrameSupportsObservation(frame)
    return (FrameSupportsTransform(frame) or FrameSupportsRemoval(frame)) and type(frame.AddMessage) == "function"
end

function ns.HasSecurePostRenderAPI()
    local candidates = { SELECTED_CHAT_FRAME, DEFAULT_CHAT_FRAME, _G.ChatFrame1 }
    for i = 1, #candidates do
        if FrameSupportsTransform(candidates[i]) then return true end
    end
    local maxFrames = (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows()) or NUM_CHAT_WINDOWS or 10
    for i = 1, maxFrames do
        if FrameSupportsTransform(_G["ChatFrame" .. i]) then return true end
    end
    return false
end

function ns.HasSecureSpamRemovalAPI()
    local candidates = { SELECTED_CHAT_FRAME, DEFAULT_CHAT_FRAME, _G.ChatFrame1 }
    for i = 1, #candidates do
        if FrameSupportsRemoval(candidates[i]) then return true end
    end
    local maxFrames = (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows()) or NUM_CHAT_WINDOWS or 10
    for i = 1, maxFrames do
        if FrameSupportsRemoval(_G["ChatFrame" .. i]) then return true end
    end
    return false
end

local function ShortenVisiblePlayerNames(text)
    local db = DB()
    if not db or not db.shortPlayerNames or type(text) ~= "string" then return text end
    local ok, result = pcall(function()
        return (text:gsub("(|Hplayer:[^|]+|h)(.-)(|h)", function(open, label, close)
            local plain = label:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
            local bracketed = plain:sub(1, 1) == "[" and plain:sub(-1) == "]"
            local inner = bracketed and plain:sub(2, -2) or plain
            local first = inner:match("^([^%-]+)%-.") or inner:match("^(%S+)%s+%S+")
            if not first or first == "" then return open .. label .. close end
            local color = label:match("|[cC]%x%x%x%x%x%x%x%x") or ""
            local reset = color ~= "" and "|r" or ""
            return open .. (bracketed and "[" or "") .. color .. first .. reset .. (bracketed and "]" or "") .. close
        end))
    end)
    return ok and type(result) == "string" and result or text
end

local function AtlasMarkup(atlas, size, offset)
    if type(atlas) ~= "string" or atlas == "" then return "" end
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not ok or not info then return "" end
    end
    return string.format("|A:%s:%d:%d:0:%d|a", atlas, size, size, offset)
end

local function IconLayout(frame)
    local db = DB() or {}
    local fontHeight = 14
    if frame and type(frame.GetFont) == "function" then
        local ok, _, height = pcall(frame.GetFont, frame)
        if ok and type(height) == "number" and height > 0 and height < 64 then fontHeight = height end
    end
    local scale = tonumber(db.senderIconScale) or 85
    if scale < 60 then scale = 60 elseif scale > 110 then scale = 110 end
    local size = math.max(8, math.floor(fontHeight * scale / 100 + 0.5))
    local fine = tonumber(db.senderIconOffset) or 0
    if fine < -6 then fine = -6 elseif fine > 6 then fine = 6 end
    local offset = -math.floor(fontHeight * 0.28 + 0.5) + fine
    return size, offset
end

local function GetSenderIcons(eventArgs, frame)
    local db = DB()
    if not db or (not db.senderRaceIcon and not db.senderClassIcon) then return "", nil end
    if type(eventArgs) ~= "table" or not Safe(eventArgs) then return "", nil end
    if type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, eventArgs)
        if ok and not accessible then return "", nil end
    end

    local okArgs, sender, guid = pcall(function() return eventArgs[2], eventArgs[12] end)
    if not okArgs then return "", nil end
    sender, guid = SafeText(sender), SafeText(guid)
    if not sender or not guid or type(GetPlayerInfoByGUID) ~= "function" then return "", nil end

    local okInfo, _, englishClass, _, englishRace, sex = pcall(GetPlayerInfoByGUID, guid)
    if not okInfo then return "", sender end
    englishClass = SafeText(englishClass)
    englishRace = SafeText(englishRace)
    if not Safe(sex) then sex = nil end

    local size, offset = IconLayout(frame)
    local icons = {}
    if db.senderRaceIcon and englishRace and type(GetRaceAtlas) == "function" and type(sex) == "number" then
        local gender = sex == 2 and "male" or sex == 3 and "female" or nil
        if gender then
            local okAtlas, atlas = pcall(GetRaceAtlas, englishRace:lower(), gender)
            if okAtlas then
                local mark = AtlasMarkup(atlas, size, offset)
                if mark ~= "" then icons[#icons + 1] = mark end
            end
        end
    end
    if db.senderClassIcon and englishClass and type(GetClassAtlas) == "function" then
        local okAtlas, atlas = pcall(GetClassAtlas, englishClass:lower())
        if okAtlas then
            local mark = AtlasMarkup(atlas, size, offset)
            if mark ~= "" then icons[#icons + 1] = mark end
        end
    end
    return table.concat(icons, " "), sender
end

local function NormalizeSender(value)
    if type(value) ~= "string" then return nil end
    return value:lower():gsub("[%s%-]", "")
end

local function DecorateSender(text, eventArgs, frame)
    local icons, sender = GetSenderIcons(eventArgs, frame)
    if icons == "" or not sender or type(text) ~= "string" then return text end
    local wanted = NormalizeSender(sender)
    local added = false
    local ok, result = pcall(function()
        return (text:gsub("(|Hplayer:([^:|]+)[^|]*|h)(.-)(|h)", function(open, target, label, close)
            if not added and NormalizeSender(target) == wanted then
                added = true
                return icons .. " " .. open .. label .. close
            end
            return open .. label .. close
        end))
    end)
    return ok and type(result) == "string" and result or text
end

local function TransformText(text, event, eventArgs, frame)
    if type(text) ~= "string" or not Safe(text) then return text end
    local output = text
    if type(ns.ApplyChannelLabels) == "function" then
        -- Pass Blizzard's source event through to the label transformer. Raid
        -- Warning has no channel hyperlink on modern clients, and its rendered
        -- prefix can sit after a timestamp; the event lets the fallback rewrite
        -- that prefix safely without scanning unrelated chat lines.
        local ok, value = pcall(ns.ApplyChannelLabels, output, event)
        if ok and type(value) == "string" then output = value end
    end
    output = ShortenVisiblePlayerNames(output)
    output = DecorateSender(output, eventArgs, frame)
    if type(ns.HighlightMentionsInRenderedLine) == "function" then
        local ok, value = pcall(ns.HighlightMentionsInRenderedLine, output)
        if ok and type(value) == "string" then output = value end
    end
    if type(ns.DecorateLinksInText) == "function" then
        local ok, value = pcall(ns.DecorateLinksInText, output)
        if ok and type(value) == "string" then output = value end
    end
    return output
end

ns.TransformRenderedChatLine = TransformText

local function CanReadEventArgs(eventArgs)
    -- A SafePack table can contain a mixture of readable and secret fields.
    -- Requiring canaccesstable(eventArgs) would reject the whole message merely
    -- because an unrelated field is protected. Index only the three fields the
    -- spam engine needs inside pcall and validate each value separately instead.
    return type(eventArgs) == "table" and Safe(eventArgs)
end

local function ReadSpamPayload(eventArgs)
    if not CanReadEventArgs(eventArgs) then return nil end

    local ok, rawMessage, rawAuthor, rawChannel = pcall(function()
        return eventArgs[1], eventArgs[2], eventArgs[4]
    end)
    if not ok then return nil end

    local message = SafeText(rawMessage)
    if not message or message == "" then return nil end

    local author = SafeText(rawAuthor)
    local channel = SafeText(rawChannel)
    local db = DB()
    -- If sender identity is protected, do not accidentally bypass the user's
    -- friend whitelist just to gain a few extra filtered lines.
    if not author and db and db.spamWhitelist and db.spamWhitelist.friends then
        return nil
    end

    return message, author, channel
end

local function ShouldRemoveSpam(event, eventArgs)
    if type(ns.AreMessageFiltersInstalled) == "function" and ns.AreMessageFiltersInstalled() then
        return false
    end
    if type(ns.ProcessSpamMessage) ~= "function" or type(event) ~= "string" then
        return false
    end
    if not CanReadEventArgs(eventArgs) then return false end

    local cached = spamDecisionByArgs[eventArgs]
    if cached ~= nil then return cached == 1 end

    if type(ns.ShouldHideSystemChatEvent) == "function" and ns.ShouldHideSystemChatEvent(event) then
        spamDecisionByArgs[eventArgs] = 1
        return true
    end

    local message, author, channel = ReadSpamPayload(eventArgs)
    if not message then
        spamDecisionByArgs[eventArgs] = 0
        return false
    end

    local ok, blocked = pcall(ns.ProcessSpamMessage, event, message, author, channel)
    if not ok then
        stats.errors = stats.errors + 1
        spamDecisionByArgs[eventArgs] = 0
        return false
    end

    spamDecisionByArgs[eventArgs] = blocked and 1 or 0
    return blocked and true or false
end

local function RemoveExactEntry(frame, text, event, eventArgs)
    if not FrameSupportsRemoval(frame) or type(text) ~= "string" or type(event) ~= "string" then return false end
    if not Safe(text) or not Safe(event) or not CanReadEventArgs(eventArgs) then return false end

    local ok = pcall(frame.RemoveMessagesByPredicate, frame,
        function(message, r, g, b, ...)
            local storedEvent, storedArgs = select(4, ...), select(5, ...)
            if not Safe(message) or not Safe(storedEvent) or not Safe(storedArgs) then return false end
            return message == text and storedEvent == event and storedArgs == eventArgs
        end)
    if ok then stats.removedSpam = stats.removedSpam + 1 end
    return ok
end

local function TransformExactEntry(frame, text, event, eventArgs)
    if not FrameSupportsTransform(frame) or type(text) ~= "string" or type(event) ~= "string" then return end
    if not Safe(text) or not Safe(event) or not Safe(eventArgs) then return end

    local ok = pcall(frame.TransformMessages, frame,
        function(message, r, g, b, ...)
            local storedEvent, storedArgs = select(4, ...), select(5, ...)
            if not Safe(message) or not Safe(storedEvent) or not Safe(storedArgs) then return false end
            return message == text and storedEvent == event and storedArgs == eventArgs
        end,
        function(message, r, g, b, ...)
            local rendered = TransformText(message, event, eventArgs, frame)
            if rendered ~= message then stats.transformed = stats.transformed + 1 end
            return rendered, r, g, b, ...
        end)
    if not ok then stats.errors = stats.errors + 1 end
end

local function ObserveAddMessage(self, text, ...)
    stats.observed = stats.observed + 1
    if not Safe(text) or type(text) ~= "string" then stats.skipped = stats.skipped + 1; return end
    local event, eventArgs = select(7, ...), select(8, ...)
    if not Safe(event) or type(event) ~= "string" or not Safe(eventArgs) then stats.skipped = stats.skipped + 1; return end

    -- Filter Engine 3.0 fallback: when protected clients deliberately keep
    -- ChatFrame_AddMessageEventFilter detached, inspect Blizzard's original
    -- readable eventArgs after render and remove only this exact stored line.
    if FrameSupportsRemoval(self) and ShouldRemoveSpam(event, eventArgs) then
        RemoveExactEntry(self, text, event, eventArgs)
        return
    end

    TransformExactEntry(self, text, event, eventArgs)
end

local function Attach(frame)
    if not FrameSupportsObservation(frame) or hookedFrames[frame] then return end
    local ok = pcall(hooksecurefunc, frame, "AddMessage", ObserveAddMessage)
    if ok then hookedFrames[frame] = true end
end

local function AttachAll()
    local maxFrames = (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows()) or NUM_CHAT_WINDOWS or 10
    for i = 1, maxFrames do Attach(_G["ChatFrame" .. i]) end
end

function ns.RefreshSecureChatTransforms()
    AttachAll()
    if type(ns.RefreshChannelLabelHook) == "function" then pcall(ns.RefreshChannelLabelHook) end
end

function ns.GetChatTransformStats()
    return { observed = stats.observed, transformed = stats.transformed, removedSpam = stats.removedSpam, skipped = stats.skipped, errors = stats.errors }
end

function Module:OnEnable()
    AttachAll()
    if type(ns.RegisterEventIfSupported) == "function" then
        ns.RegisterEventIfSupported(self, "PLAYER_ENTERING_WORLD", "Refresh")
        ns.RegisterEventIfSupported(self, "UPDATE_CHAT_WINDOWS", "Refresh")
        ns.RegisterEventIfSupported(self, "UPDATE_FLOATING_CHAT_WINDOWS", "Refresh")
    else
        pcall(self.RegisterEvent, self, "PLAYER_ENTERING_WORLD", "Refresh")
        pcall(self.RegisterEvent, self, "UPDATE_CHAT_WINDOWS", "Refresh")
        pcall(self.RegisterEvent, self, "UPDATE_FLOATING_CHAT_WINDOWS", "Refresh")
    end
end

function Module:Refresh()
    AttachAll()
end
