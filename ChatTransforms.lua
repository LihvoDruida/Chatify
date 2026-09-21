local addonName, ns = ...
local Chatify = ns.Chatify or LibStub("AceAddon-3.0"):GetAddon("Chatify")
local Module = Chatify:NewModule("ChatTransforms", "AceEvent-3.0")

local hookedFrames = setmetatable({}, { __mode = "k" })
local stats = { observed = 0, transformed = 0, skipped = 0, errors = 0 }

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
        local ok, value = pcall(ns.ApplyChannelLabels, output)
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
    TransformExactEntry(self, text, event, eventArgs)
end

local function Attach(frame)
    if not FrameSupportsTransform(frame) or hookedFrames[frame] or type(frame.AddMessage) ~= "function" then return end
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
    return { observed = stats.observed, transformed = stats.transformed, skipped = stats.skipped, errors = stats.errors }
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
