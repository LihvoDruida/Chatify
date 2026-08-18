local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
-- Підключаємо LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0", true)
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")
local visualsFiltersInstalled = false
local visualsApplyQueued = false
local registeredTimestampFilters = {}
local TimestampFilter
-- Weak keys: temporary chat windows (whisper tabs, pet battle logs) are created
-- and thrown away constantly, and a strong key here pinned every one of them for
-- the whole session.
local frameStyleCache = setmetatable({}, { __mode = "k" })
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

-- Modern Retail (12.0+ secret values): only public/group chat is timestamped, and
-- whisper/BNet/boss events are never filtered. Two reasons: (1) Blizzard routes
-- whispers to General and temporary tabs through protected payloads, so returning a
-- reformatted line can blank those tabs; (2) during chat messaging lockdown the
-- sender is a secret value, and a filter must never launder it back into Blizzard's
-- handler. The pass-through branches below therefore return nothing (keep Blizzard's
-- original, untainted varargs) rather than re-emitting `...`.
local retailTimestampEvents = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
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
    if type(chatFrame) ~= "table" then return nil end
    if chatFrame.editBox then return chatFrame.editBox end

    -- GetName/GetID are called, not assumed. A caller that handed us a table which
    -- is not a frame used to die here with "attempt to call a nil value", and this
    -- is a leaf helper that other addons' code paths can reach through our hooks.
    if type(chatFrame.GetName) == "function" then
        local okName, name = pcall(chatFrame.GetName, chatFrame)
        if okName and type(name) == "string" and name ~= "" then
            local suffixBox = _G[name .. "EditBox"]
            if suffixBox then return suffixBox end
        end
    end

    if type(chatFrame.GetID) == "function" then
        local okID, id = pcall(chatFrame.GetID, chatFrame)
        if okID and id then
            local idBox = _G["ChatFrame" .. id .. "EditBox"]
            if idBox then return idBox end
        end
    end

    return ChatFrame1EditBox
end

-- =========================================================
-- 2. FONT STYLING
-- =========================================================
local function StyleFrame(frame)
    -- Every caller of this function is a hook on a public Blizzard API, so the
    -- argument is whatever the addon that called that API passed in.
    if type(ns.IsChatFrame) == "function" then
        if not ns.IsChatFrame(frame) then return end
    elseif not frame then
        return
    end

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
-- 2b. FRAME BEHAVIOUR (TAINT-FREE)
-- =========================================================
-- Everything below is plain ScrollingMessageFrame API. None of it registers a
-- message-event filter, rewrites a GlobalString or otherwise runs on Blizzard's
-- chat dispatch, so none of it can taint anything - which makes it the only class
-- of feature that still works on 12.0+ while the text-mutating features stand
-- down. Prat's Scroll, Fading, Paragraph and OriginalButtons modules cover the
-- same ground the same way; the notes below record where the behaviour differs.
--
-- Not all of these methods exist on every flavour, so each one is probed rather
-- than assumed. On Classic the missing ones simply do nothing.

local behaviourCache = setmetatable({}, { __mode = "k" })

local function IsCombatLogFrame(frame)
    if not frame then return false end
    if frame == _G.ChatFrame2 then return true end

    local id = type(frame.GetID) == "function" and select(2, pcall(frame.GetID, frame)) or nil
    if type(id) == "number" then
        local ok, isCombatLog = ns.CallChatAPI("FCF_IsWindowIDCombatLog", "IsWindowIDCombatLog", id)
        if ok and isCombatLog then
            return true
        end
    end

    return false
end

-- Chat replacement addons own the chat frames outright. Prat has the same carve
-- out for WIM; ours covers ElvUI, GW2_UI and friends via the shared detector.
local function ChatFramesAreForeignOwned()
    if type(ns.IsChatReplacementLoaded) ~= "function" then
        return false
    end
    local ok, loaded = pcall(ns.IsChatReplacementLoaded)
    return ok and loaded and true or false
end

local function ScrollByLines(frame, up, lines)
    for _ = 1, lines do
        if up then
            if type(frame.ScrollUp) == "function" then pcall(frame.ScrollUp, frame) end
        else
            if type(frame.ScrollDown) == "function" then pcall(frame.ScrollDown, frame) end
        end
    end
end

-- Scroll speed.
--
-- Prat replaces the frame's OnMouseWheel script outright. This hooks it instead
-- and only adds the extra notches on top, which matters for three reasons:
-- Blizzard's own handler keeps running (so the scroll-to-bottom button and the
-- chatMouseScroll CVar still behave), ElvUI's replacement is not clobbered, and
-- turning the feature off needs no script restore because the hook simply stops
-- doing anything. Shift is left entirely to Blizzard, which already jumps to the
-- far end; ctrl adds page scrolling, which Blizzard has no binding for.
local function OnChatMouseWheelExtra(frame, delta)
    local db = GetVisualDB()
    if not db or db.enableScrollTweaks == false then
        return
    end
    if ChatFramesAreForeignOwned() then
        return
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        return
    end

    local up = (delta or 0) > 0

    if IsControlKeyDown and IsControlKeyDown() then
        local pager = up and frame.PageUp or frame.PageDown
        if type(pager) == "function" then
            pcall(pager, frame)
            return
        end
    end

    -- Blizzard already moved one line, so only the remainder is ours.
    local extra = (tonumber(db.scrollLinesPerNotch) or 3) - 1
    if extra > 9 then extra = 9 end
    if extra > 0 then
        ScrollByLines(frame, up, extra)
    end
end

local function ApplyScrollTweaks(frame)
    if type(ns.SafeHookScript) == "function" then
        ns.SafeHookScript(frame, "OnMouseWheel", OnChatMouseWheelExtra, "ChatifyScrollSpeed")
    end

    -- Blizzard leaves the wheel enabled on chat frames, but a temporary window
    -- created by another addon might not.
    if type(frame.EnableMouseWheel) == "function" then
        pcall(frame.EnableMouseWheel, frame, true)
    end
end

local function ApplyFrameBehaviour(frame)
    local db = GetVisualDB()
    if not frame or not db then return end

    local signature = table.concat({
        tostring(db.scrollbackLines or 0),
        tostring(db.disableChatFade and 1 or 0),
        tostring(db.chatFadeTime or 120),
        tostring(db.lineSpacing or 0),
        tostring(db.indentWrappedLines and 1 or 0),
    }, "|")

    ApplyScrollTweaks(frame)

    if behaviourCache[frame] == signature then
        return
    end
    behaviourCache[frame] = signature

    -- Scrollback depth.
    --
    -- SetMaxLines reallocates the frame's buffer and therefore wipes whatever is
    -- currently displayed - Prat's Scroll module relies on exactly that as a reset
    -- trick. So it is only ever called when the value genuinely differs, which
    -- makes the whole path idempotent and keeps repeat ApplyVisuals passes from
    -- clearing anyone's chat.
    local wanted = tonumber(db.scrollbackLines) or 0
    if wanted > 0 and type(frame.SetMaxLines) == "function" then
        if wanted < 128 then wanted = 128 end
        if wanted > 10000 then wanted = 10000 end

        local current
        if type(frame.GetMaxLines) == "function" then
            local ok, value = pcall(frame.GetMaxLines, frame)
            current = ok and value or nil
        end

        if current ~= wanted then
            pcall(frame.SetMaxLines, frame, wanted)
        end
    end

    -- Fading. The combat log is left alone: it is a log, and Blizzard ships it
    -- with fading off already.
    if not IsCombatLogFrame(frame) then
        if type(frame.SetFading) == "function" then
            pcall(frame.SetFading, frame, not db.disableChatFade)
        end
        if not db.disableChatFade and type(frame.SetTimeVisible) == "function" then
            local visible = tonumber(db.chatFadeTime) or 120
            if visible < 5 then visible = 5 end
            if visible > 3600 then visible = 3600 end
            pcall(frame.SetTimeVisible, frame, visible)
        end
    end

    -- Line spacing and hanging indent for wrapped lines. SetIndentedWordWrap is
    -- Retail-only, hence the probe rather than a flavour check - if Blizzard ever
    -- backports it, Classic picks it up for free.
    if type(frame.SetSpacing) == "function" then
        local spacing = tonumber(db.lineSpacing) or 0
        if spacing < 0 then spacing = 0 end
        if spacing > 10 then spacing = 10 end
        pcall(frame.SetSpacing, frame, spacing)
    end

    if type(frame.SetIndentedWordWrap) == "function" then
        pcall(frame.SetIndentedWordWrap, frame, db.indentWrappedLines and true or false)
    end

end

-- Blizzard's own chat buttons.
--
-- Hiding is not enough on its own: Blizzard shows them again on various UI
-- updates, so the OnShow handler has to push back. Same technique as Prat's
-- OriginalButtons module. The original handler is kept so the toggle is reversible
-- without a reload.
local blizzardButtonState = {}

local function ApplyBlizzardButtonVisibility()
    local db = GetVisualDB()
    if not db then return end

    local hide = db.hideBlizzardChatButtons and true or false

    for _, name in ipairs({ "ChatFrameMenuButton", "QuickJoinToastButton" }) do
        local button = _G[name]
        if button and type(button.Hide) == "function" then
            if hide then
                if blizzardButtonState[name] == nil then
                    local ok, original = pcall(button.GetScript, button, "OnShow")
                    blizzardButtonState[name] = (ok and original) or false
                end
                pcall(button.SetScript, button, "OnShow", function(self)
                    pcall(self.Hide, self)
                end)
                pcall(button.Hide, button)
            elseif blizzardButtonState[name] ~= nil then
                local original = blizzardButtonState[name]
                pcall(button.SetScript, button, "OnShow", original or nil)
                pcall(button.Show, button)
                blizzardButtonState[name] = nil
            end
        end
    end
end

-- =========================================================
-- 3. CHANNEL SHORTENING
-- =========================================================
-- =========================================================
-- 3b. CHANNEL LABELS (TAINT-FREE)
-- =========================================================
-- The old implementation overwrote Blizzard's CHAT_*_GET GlobalStrings. That is
-- free per message, but it writes into the shared global environment, it collides
-- with Prat and ElvUI doing the same, it cannot touch numbered channels
-- ([1. General]) at all, and on 12.0+ it was disabled outright because those
-- globals feed the secure chat handler - which is exactly why users on Retail
-- reported "Shorten Channel Names" doing nothing.
--
-- This rewrites the label inside the rendered line instead, in Chatify's own
-- AddMessage hook. The match is on the channel token inside the hyperlink
-- (|Hchannel:PARTY|h[Party]|h), which is locale-independent and identical on
-- every flavour, so one implementation now covers Classic and Retail alike and
-- numbered channels come along for free.

local channelLabelCache
local channelLabelSignature

local function EscapeChatPattern(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function BuildChannelLabelMap(db)
    -- Signature covers everything the resolution depends on, so the cache is
    -- rebuilt exactly when a setting that matters has moved.
    local parts = { tostring(db.shortChannels and 1 or 0) }
    for _, source in ipairs({ db.channelModes, db.channelLabels, db.channelLabelsNamed }) do
        if type(source) == "table" then
            local keys = {}
            for key, value in pairs(source) do
                if type(value) == "string" and value ~= "" then
                    keys[#keys + 1] = tostring(key) .. "=" .. value
                end
            end
            table.sort(keys)
            parts[#parts + 1] = table.concat(keys, ",")
        else
            parts[#parts + 1] = ""
        end
    end
    local signature = table.concat(parts, "|")

    if channelLabelSignature == signature and channelLabelCache then
        return channelLabelCache
    end

    local map = {
        -- Leader variants share a hyperlink token with their base channel
        -- (|Hchannel:party|h for both Party and Party Leader), so the token alone
        -- cannot tell them apart. The visible label can: it comes from separate
        -- GlobalStrings. byLabel is therefore consulted first and byToken is the
        -- fallback for anything it does not cover.
        byLabel = {},        -- exact current label -> replacement, or false to hide
        byToken = {},        -- link token -> replacement, or false to hide
        byName = {},         -- numbered channels: name key -> replacement or false
        numberedFallback = nil,  -- "short" when unset numbered channels shorten
        templates = {},      -- say/yell/whisper rewrites
        active = false,
    }

    local labels = type(db.channelLabels) == "table" and db.channelLabels or {}
    local named = type(db.channelLabelsNamed) == "table" and db.channelLabelsNamed or {}

    for _, entry in ipairs(ns.Lists.ChannelLabels or {}) do
        local mode = ns.GetChannelMode(db, entry.token, entry)

        local replacement
        if mode == "short" then
            replacement = entry.short
        elseif mode == "custom" then
            local custom = labels[entry.token]
            -- A custom mode with nothing typed yet falls back to the abbreviation
            -- rather than blanking the tag; hiding is its own mode.
            replacement = (type(custom) == "string" and custom ~= "") and custom or entry.short
        elseif mode == "hidden" then
            replacement = false
        end

        if replacement ~= nil then
            if entry.kind == "template" then
                local prefix, suffix = ns.SplitChatTemplate(entry.template)
                if prefix then
                    -- Anchored, with the name captured non-greedily so it stops at
                    -- the first occurrence of the suffix. The trailing () yields
                    -- the index just past the match, which is where the message
                    -- body starts.
                    map.templates[#map.templates + 1] = {
                        label = replacement,
                        pattern = "^" .. EscapeChatPattern(prefix)
                            .. "(.-)" .. EscapeChatPattern(suffix) .. "()",
                    }
                    map.active = true
                end
            else
                local label = entry.global and _G[entry.global]
                if type(label) == "string" and label ~= "" then
                    map.byLabel[label] = replacement
                end

                -- Only claim the shared token for the base channel. Writing the
                -- leader's replacement here too would make whichever entry was
                -- processed last win for both.
                local token = ns.GetChannelLinkToken(entry)
                if token and map.byToken[token] == nil then
                    map.byToken[token] = replacement
                end
                map.active = true
            end
        end
    end

    -- Numbered channels. An explicit mode per channel wins; anything without one
    -- follows the master switch, which is what makes [1. General] shorten to [1]
    -- without needing a row per channel.
    local modes = type(db.channelModes) == "table" and db.channelModes or {}
    for key, value in pairs(named) do
        if type(value) == "string" and value ~= "" then
            local mode = ns.GetChannelMode(db, key, nil)
            if mode == "custom" then
                map.byName[key] = value
                map.active = true
            end
        end
    end
    for key, mode in pairs(modes) do
        if map.byName[key] == nil then
            local resolved = ns.GetChannelMode(db, key, nil)
            if resolved == "hidden" then
                map.byName[key] = false
                map.active = true
            elseif resolved == "custom" then
                local custom = named[key]
                if type(custom) == "string" and custom ~= "" then
                    map.byName[key] = custom
                    map.active = true
                end
            elseif resolved == "default" and db.shortChannels then
                -- Explicitly opted out of shortening while the master switch is on.
                map.byName[key] = nil
            end
        end
    end

    if db.shortChannels then
        map.numberedFallback = "short"
        map.active = true
    end

    channelLabelCache = map
    channelLabelSignature = signature
    return map
end

-- Resolves the numbered channel in a rendered line to a stable name key.
--
-- The authoritative source is GetChannelList, keyed by the id in the hyperlink.
-- When that misses - the channel was left, or the list has not refreshed yet -
-- the visible label is parsed instead ("1. General - Elwynn Forest"), which needs
-- no API at all and is what keeps labels working during zone transitions.
local function ResolveNumberedChannelKey(id, label)
    local _, byId = ns.GetJoinedChannels()
    local entry = byId and byId[tonumber(id) or -1]
    if entry and entry.key then
        return entry.key
    end

    if type(label) == "string" then
        local name = label:match("^%s*%d+%.%s*(.+)$")
        if name then
            return ns.ChannelNameKey(name)
        end
    end

    return nil
end

-- Prat's convention: a custom label beginning with "#" keeps the channel number
-- in front of it, so "#Trade" renders as "2. Trade" rather than "Trade".
local function ExpandNumberedLabel(label, index)
    if type(label) ~= "string" then
        return label
    end
    local rest = label:match("^#(.*)$")
    if rest == nil then
        return label
    end
    if rest == "" then
        return index
    end
    return index .. ". " .. rest
end

-- Pure string transform. Takes and returns a plain string; no globals are touched
-- and nothing is registered on Blizzard's chat dispatch, so it cannot taint.
-- Channel system notices.
--
-- "Changed Channel: [1. General]" carries a real channel hyperlink, so the label
-- rewrite happily turned it into "Changed Channel: [1. G]" - which defeats the
-- point of the notice, since it exists precisely to tell you which channel you
-- are now in.
--
-- These lines are built from the CHAT_*_NOTICE GlobalStrings. Rather than listing
-- them (there are around twenty, and Blizzard adds more), the prefixes are
-- harvested from _G once per session, which is locale-correct for free and needs
-- no maintenance.
--
-- Only notices whose literal text comes BEFORE the placeholder can be recognised
-- this way: those are matched anchored at the start of the line, which cannot
-- produce a false positive. A template that opens with its placeholder has no
-- anchor to key on and is left to the normal rewrite - accepting a shortened
-- label in a rare notice is much better than risking a match against ordinary
-- chat that happens to contain the same words.
local channelNoticePrefixes
local channelFormatterA = "|Hchannel:%d|h"
local channelFormatterB = "|Hchannel:CHANNEL:%d|h"

local function GetChannelNoticePrefixes()
    if channelNoticePrefixes then
        return channelNoticePrefixes
    end

    channelNoticePrefixes = {}

    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string"
            and key:find("^CHAT_") and key:find("_NOTICE") then

            local prefix
            -- Remove the channel name placeholder from the end of a string to find the prefix
            if value:sub(-6, -3) == "[%s]" then
                prefix = value:sub(1, -7)
            else
                prefix = value:match("^(.-)%%s")
            end

            if prefix then
                -- Remove these two non-renderable strings
                if prefix:find(channelFormatterA, 1, true) then
                    prefix = prefix:sub(1, prefix:find(channelFormatterA, 1, true) - 1)
                end
                if prefix:find(channelFormatterB, 1, true) then
                    prefix = prefix:sub(1, prefix:find(channelFormatterB, 1, true) - 1)
                end

                -- Three characters is enough to be distinctive while excluding the
                -- empty prefix of a placeholder-first template.
                if #prefix >= 3 then
                    channelNoticePrefixes[#channelNoticePrefixes + 1] = prefix
                end
            end
        end
    end

    return channelNoticePrefixes
end

-- Exposed so the notice list can be re-harvested if something reloads
-- GlobalStrings mid-session; nothing in Chatify does, but it costs one line.
function ns.InvalidateChannelNoticeCache()
    channelNoticePrefixes = nil
end

local function IsChannelNoticeLine(text)
    local prefixes = GetChannelNoticePrefixes()
    for i = 1, #prefixes do
        if text:find(prefixes[i], 1, true) == 1 then
            return true
        end
    end
    return false
end

function ns.ApplyChannelLabels(text)
    if type(text) ~= "string" then
        return text
    end

    local db = GetVisualDB()
    if not db then
        return text
    end

    local map = BuildChannelLabelMap(db)
    if not map.active then
        return text
    end

    local hasLink = text:find("|Hchannel:", 1, true) ~= nil
    if not hasLink and #map.templates == 0 then
        -- Cheapest possible rejection: this runs once per rendered line.
        return text
    end

    -- Tested only when a channel link is present, so ordinary chat never pays for
    -- the scan.
    if hasLink and IsChannelNoticeLine(text) then
        return text
    end

    local ok, result = pcall(function()
        local value = text

        if hasLink then
            -- Named channels: |Hchannel:PARTY|h[Party]|h
            value = value:gsub("(|Hchannel:)([A-Za-z_]+)(|h%[)(.-)(%]|h)%s?",
                function(open, token, mid, label, close)
                    -- Label first: it is the only thing that separates a leader
                    -- line from its base channel.
                    local replacement = map.byLabel[label]
                    if replacement == nil then
                        replacement = map.byToken[token:upper()]
                    end
                    if replacement == nil then
                        return nil
                    end
                    if replacement == false then
                        -- Hidden: the tag and the space that followed it both go,
                        -- otherwise the line starts with a stray gap.
                        return ""
                    end
                    return open .. token .. mid .. replacement .. close .. " "
                end)

            -- Numbered channels: |Hchannel:CHANNEL:1|h[1. General]|h
            value = value:gsub("(|Hchannel:[Cc][Hh][Aa][Nn][Nn][Ee][Ll]:)(%d+)(|h%[)(.-)(%]|h)%s?",
                function(open, index, mid, label, close)
                    local replacement
                    local key = ResolveNumberedChannelKey(index, label)
                    if key ~= nil and map.byName[key] ~= nil then
                        replacement = map.byName[key]
                    elseif map.numberedFallback == "short" then
                        replacement = index
                    end

                    if replacement == nil then
                        return nil
                    end
                    if replacement == false then
                        return ""
                    end

                    replacement = ExpandNumberedLabel(replacement, index)
                    return open .. index .. mid .. replacement .. close .. " "
                end)
        end

        -- Say, yell and whispers. These carry no tag of their own, so the phrasing
        -- the game wrote around the player name ("Bob whispers: ") is replaced by
        -- one ("[W From] Bob: ").
        --
        -- Only the first matching rule fires: a line is exactly one chat type, and
        -- letting a second rule run would re-match the text just produced.
        for i = 1, #map.templates do
            local rule = map.templates[i]
            local name, tail = value:match(rule.pattern)
            if name and name ~= "" and tail then
                local head
                if rule.label == false or rule.label == "" then
                    head = name .. ": "
                else
                    head = "[" .. rule.label .. "] " .. name .. ": "
                end
                value = head .. value:sub(tail)
                break
            end
        end

        return value
    end)

    if ok and type(result) == "string" and result ~= "" then
        return result
    end

    return text
end

local function IsRetailRestricted()
    return type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
end

-- The AddMessage hook.
--
-- ChatRouter already replaces AddMessage when virtual chat is on, and its pipeline
-- calls ns.ApplyChannelLabels itself. This hook therefore installs only when the
-- router is not driving the frame, so a line is never rewritten twice and the two
-- modules never fight over frame.AddMessage.
--
-- Rather than swapping the method outright, the previous function is kept, so
-- removal restores the exact original - including another addon's replacement, if
-- it hooked before us.
local channelHookOriginal = setmetatable({}, { __mode = "k" })
local channelHookWrapper = setmetatable({}, { __mode = "k" })

local function RouterOwnsAddMessage()
    local db = GetVisualDB()
    -- The router replaces AddMessage in virtual mode and runs ns.FormatMessage
    -- itself, which already covers both channel labels and mention highlighting.
    return (db and db.useVirtualChat and not IsRetailRestricted()) and true or false
end

local function ChannelLabelsWanted()
    local db = GetVisualDB()
    if not db then
        return false
    end

    if RouterOwnsAddMessage() then
        return false
    end

    return BuildChannelLabelMap(db).active
end

-- True only on clients where the message-event filters are absent, which is where
-- ns.ApplyMentionRules never runs and this wrapper is the only thing that can put
-- the highlight on screen. See the render-time mention block in ChatFilters.lua.
local function MentionHighlightWanted()
    if RouterOwnsAddMessage() then
        return false
    end
    if type(ns.ShouldHighlightMentionsOnRender) ~= "function" then
        return false
    end

    local ok, wanted = pcall(ns.ShouldHighlightMentionsOnRender)
    return ok and wanted and true or false
end

local function RenderHookWanted()
    return ChannelLabelsWanted() or MentionHighlightWanted()
end

local function InstallChannelLabelHook(frame)
    if not frame or type(frame.AddMessage) ~= "function" then
        return
    end
    if channelHookWrapper[frame] and frame.AddMessage == channelHookWrapper[frame] then
        return
    end

    local original = frame.AddMessage
    channelHookOriginal[frame] = original

    local wrapper = function(self, text, ...)
        local output = text
        if type(text) == "string" then
            -- Secret values must be handed through untouched: reading one to build
            -- a replacement string is what produces "string conversion on a secret
            -- string value" during an encounter.
            local safe = true
            if type(ns.IsSecretValue) == "function" then
                local okSecret, isSecret = pcall(ns.IsSecretValue, text)
                safe = okSecret and not isSecret
            end
            if safe then
                if ChannelLabelsWanted() then
                    local ok, rewritten = pcall(ns.ApplyChannelLabels, output)
                    if ok and type(rewritten) == "string" then
                        output = rewritten
                    end
                end

                -- Deliberately after the labels. The label templates match on the
                -- phrasing Blizzard wrote around the player name ("Bob whispers: "),
                -- and a colour code inserted into that name first would stop them
                -- matching. Colouring last cannot break anything the other way: the
                -- swap is a plain substring replacement of the raw message.
                if type(ns.ApplyPendingMentionRender) == "function" then
                    local okMention, highlighted = pcall(ns.ApplyPendingMentionRender, output)
                    if okMention and type(highlighted) == "string" then
                        output = highlighted
                    end
                end
            end
        end
        return original(self, output, ...)
    end

    channelHookWrapper[frame] = wrapper
    frame.AddMessage = wrapper
end

local function RemoveChannelLabelHookFromFrame(frame)
    if not frame then
        return
    end
    local wrapper = channelHookWrapper[frame]
    if wrapper and frame.AddMessage == wrapper then
        frame.AddMessage = channelHookOriginal[frame] or frame.AddMessage
    end
    channelHookWrapper[frame] = nil
    channelHookOriginal[frame] = nil
end

local function ForEachChatFrame(callback)
    local count = (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows())
        or NUM_CHAT_WINDOWS or 10
    for i = 1, count do
        local frame = _G["ChatFrame" .. i]
        if frame then
            callback(frame)
        end
    end
end

function ns.RefreshChannelLabelHook()
    if RenderHookWanted() then
        ForEachChatFrame(InstallChannelLabelHook)
    else
        ForEachChatFrame(RemoveChannelLabelHookFromFrame)
    end
end

function ns.RemoveChannelLabelHook()
    ForEachChatFrame(RemoveChannelLabelHookFromFrame)
end

function ns.InvalidateChannelLabelCache()
    channelLabelCache = nil
    channelLabelSignature = nil
end




local function RegisterTimestampFilter(eventName)
    if registeredTimestampFilters[eventName] then
        return
    end

    -- Never install a filter closure on Blizzard's chat dispatch on 12.0+ clients:
    -- doing so taints the dispatch and breaks secret-value handling elsewhere.
    if type(ns.CanUseMessageEventFilters) == "function" and not ns.CanUseMessageEventFilters() then
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

-- Timestamp ownership on 12.0+ depends on the filter mode.
--
-- In "lockdown" and "off" the filter is absent for at least part of the time, so a
-- filter-based timestamp would vanish mid-encounter and reappear afterwards, and
-- running it alongside the CVar would print the time twice. Blizzard's own
-- showTimestamps rendering is secure, survives lockdown and looks identical
-- throughout, so it owns timestamps there.
--
-- In "full" the filter is always present, so Chatify renders timestamps itself and
-- the user gets the configured format and colour back.
local function InstallTimestampFilters()
    local db = GetVisualDB()
    local retailRestricted = IsRetailRestricted()
    local ownTimestamps = not retailRestricted
        or (type(ns.GetRetailChatFilterMode) == "function" and ns.GetRetailChatFilterMode() == "full")

    if not ownTimestamps then
        ns.ApplyNativeTimestamps(db)
        return
    end

    if retailRestricted then
        -- Reclaiming timestamps: make sure the native CVar is not also printing.
        ns.ApplyNativeTimestamps(db)
    end

    local virtualActive = db and db.useVirtualChat and not retailRestricted
    if visualsFiltersInstalled or virtualActive then
        return
    end

    local filterEvents = retailRestricted and retailTimestampEvents or eventsToHandle
    for evt in pairs(filterEvents) do
        RegisterTimestampFilter(evt)
    end
    visualsFiltersInstalled = true
end

function ns.RefreshTimestampFilterState(allowed)
    if allowed then
        InstallTimestampFilters()
    else
        UnregisterTimestampFilters()
    end
    -- Native timestamps carry the feature while the filter is withdrawn.
    if type(ns.ApplyNativeTimestamps) == "function" then
        ns.ApplyNativeTimestamps()
    end
end

if type(ns.RegisterFilterRefreshHandler) == "function" then
    ns.RegisterFilterRefreshHandler(ns.RefreshTimestampFilterState)
end


-- Taint-free timestamp path for 12.0+ clients.
--
-- Chatify cannot install a message-event filter on these builds (see
-- ns.CanUseMessageEventFilters), so timestamps are delegated to Blizzard's own
-- native rendering via the showTimestamps CVar. This runs entirely inside secure
-- code, so it works during chat lockdown and on secret payloads alike.
--
-- Chatify only writes the CVar while its own timestamp option is enabled, and
-- restores whatever the user had before as soon as the option is turned off, so a
-- manual client setting is never silently clobbered.
local nativeTimestampPrevious = nil
local nativeTimestampApplied = false
local nativeTimestampRetryQueued = false

-- ns.RefreshTimestampFilterState fires on every lockdown flip, and the first of
-- those is ENCOUNTER_START / CHALLENGE_MODE_START, i.e. mid-combat. SetCVar from
-- addon code during combat lockdown is refused and surfaces as an
-- ADDON_ACTION_BLOCKED popup, so the write is deferred to the end of combat.
local function DeferNativeTimestampsUntilOutOfCombat()
    if nativeTimestampRetryQueued then
        return
    end

    local frame = _G.ChatifyTimestampCVarGuard
    if not frame then
        if type(CreateFrame) ~= "function" then
            return
        end
        local okFrame, created = pcall(CreateFrame, "Frame")
        if not okFrame or not created then
            return
        end
        frame = created
        _G.ChatifyTimestampCVarGuard = frame
        frame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            nativeTimestampRetryQueued = false
            pcall(ns.ApplyNativeTimestamps)
        end)
    end

    if pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED") then
        nativeTimestampRetryQueued = true
    end
end

function ns.ApplyNativeTimestamps(db)
    if not ns.IsRetailSecretValueBuild() then
        return
    end
    if type(ns.GetCVarCompat) ~= "function" or type(ns.SetCVarCompat) ~= "function" then
        return
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        DeferNativeTimestampsUntilOutOfCombat()
        return
    end

    db = db or GetVisualDB()
    if not db then return end

    -- In "full" mode Chatify's own filter draws the timestamps, so the native CVar
    -- must stay off or every line would carry two.
    local chatifyOwnsTimestamps = type(ns.GetRetailChatFilterMode) == "function"
        and ns.GetRetailChatFilterMode() == "full"

    local wanted = nil
    if db.enableTimestamps and not chatifyOwnsTimestamps then
        -- A nil format is the "None" entry in Chatify's list and means the CVar
        -- should stay off entirely.
        local fmt = ns.GetTimestampFormat(db)
        if type(fmt) ~= "string" or fmt == "" then
            wanted = nil
            fmt = nil
        end
        if fmt then
            wanted = fmt .. " "
        end
    end

    if wanted then
        if not nativeTimestampApplied then
            nativeTimestampPrevious = ns.GetCVarCompat("showTimestamps")
            nativeTimestampApplied = true
        end
        if not ns.SetCVarCompat("showTimestamps", wanted) then
            -- The write was refused, most likely because the CVar system is not
            -- ready yet during login. Retry once the world is in.
            if type(ns.SafeAfter) == "function" then
                ns.SafeAfter(2, function() pcall(ns.ApplyNativeTimestamps) end)
            end
        end
    elseif nativeTimestampApplied then
        ns.SetCVarCompat("showTimestamps", nativeTimestampPrevious or "none")
        nativeTimestampApplied = false
        nativeTimestampPrevious = nil
    end
end

-- Runs one stage of the visual pass in isolation.
--
-- ApplyVisuals is called from PLAYER_LOGIN, so anything that throws here takes
-- the whole pass down with it and the user gets a Lua error the moment they log
-- in. That is not hypothetical: 0.11.29 shipped with a block of hook management
-- functions removed by a bad edit while their call sites stayed, and the nil call
-- aborted ApplyVisuals before channel labels were ever installed - which is why
-- the error and "shortening does nothing" were the same bug.
--
-- Each stage is now independent, so a fault in one costs that feature rather than
-- every feature, and the cause is named in the message instead of a line number.
-- Routed through ns.SafeCall so a failure lands in the Runtime Debug panel with
-- the stage name attached, instead of a bare line number in the error frame.
-- SafeCall also treats a missing function as a handled failure, which is exactly
-- the case that shipped.
local function RunVisualStage(label, fn, ...)
    if type(ns.SafeCall) == "function" then
        return (ns.SafeCall("ApplyVisuals:" .. label, fn, ...))
    end

    -- Config.lua defines SafeCall, so this only runs if load order changes.
    if type(fn) ~= "function" then
        return false
    end
    return (pcall(fn, ...))
end

function ns.ApplyVisuals()
    local db = GetVisualDB()
    if not db then return end

    RunVisualStage("timestamps", ns.ApplyNativeTimestamps, db)

    for i = 1, (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame"..i]
        if frame then
            RunVisualStage("style", StyleFrame, frame)
            RunVisualStage("behaviour", ApplyFrameBehaviour, frame)
        end
    end

    RunVisualStage("buttons", ApplyBlizzardButtonVisibility)

    -- Channel labels are applied per rendered line in the AddMessage hook now, so
    -- nothing here writes to the global environment any more. Any CHAT_*_GET a
    -- pre-0.11.26 build overwrote is restored by FrameXML on the next /reload.
    RunVisualStage("labelCache", ns.InvalidateChannelLabelCache)
    RunVisualStage("labelHook", ns.RefreshChannelLabelHook)
end

-- =========================================================
-- 4. TIMESTAMPS (SECURE)
-- =========================================================
TimestampFilter = function(self, event, msg, author, ...)
    local retailRestricted = IsRetailRestricted()
    -- Never touch whisper/BNet payloads on modern Retail: they route through
    -- protected tabs and, during chat lockdown, carry secret senders.
    if retailRestricted and type(ns.IsWhisperSensitiveEvent) == "function" and ns.IsWhisperSensitiveEvent(event) then
        return
    end

    local db = GetVisualDB()
    if not db then return end
    if not db.enableTimestamps then return end
    local allowedEvents = retailRestricted and retailTimestampEvents or eventsToHandle
    if not allowedEvents[event] then return end

    -- Taint safety: if we cannot safely read/mutate this payload (secret value or
    -- inaccessible during lockdown), return NOTHING so Blizzard keeps its original,
    -- untainted varargs. Returning `false, msg, author, ...` here would re-emit the
    -- secret sender through addon code, tainting it and breaking Blizzard's history
    -- token conversion ("string conversion on a secret string value").
    if type(ns.CanMutateChatPayload) == "function" then
        if not ns.CanMutateChatPayload(event, msg, author, ...) then
            return
        end
    else
        if IsSecretValue(msg) or IsSecretValue(author) then
            return
        end

        if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
            return
        end
    end

    local safeMsg = GetSafeText(msg)
    if not safeMsg or type(safeMsg) ~= "string" then
        return
    end

    if safeMsg:find("|Hchatcopy:", 1, true) then
        return
    end

    -- Resolved through the shared helper so the chat frames, the history window and
    -- the copy window cannot drift apart on what a timestamp looks like.
    local timestampFormat = ns.GetTimestampFormat(db)
    if type(timestampFormat) ~= "string" or timestampFormat == "" then
        -- "None": the user asked for no timestamps.
        return
    end

    local timestamp = ns.GetTimestampSeconds(db)

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
        return
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
        -- Channel numbers and membership change without any chat window change,
        -- so the joined-channel cache needs its own triggers.
        ns.RegisterEventIfSupported(self, "CHANNEL_UI_UPDATE", "ChannelListChanged")
        ns.RegisterEventIfSupported(self, "CHANNEL_COUNT_UPDATE", "ChannelListChanged")
        ns.RegisterEventIfSupported(self, "CHAT_MSG_CHANNEL_NOTICE", "ChannelListChanged")
    else
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyStyle")
        self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyStyle")
        self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyStyle")
        self:RegisterEvent("CHANNEL_UI_UPDATE", "ChannelListChanged")
        self:RegisterEvent("CHANNEL_COUNT_UPDATE", "ChannelListChanged")
        self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", "ChannelListChanged")
    end

    if type(FCF_OpenTemporaryWindow) == "function" then
        pcall(self.SecureHook, self, "FCF_OpenTemporaryWindow", function() QueueApplyVisuals(0) end)
    end
    if type(FCF_OpenNewWindow) == "function" then
        pcall(self.SecureHook, self, "FCF_OpenNewWindow", function() QueueApplyVisuals(0) end)
    end
    if type(FCF_SetTemporaryWindowType) == "function" then
        -- FCF_SetTemporaryWindowType(chatFrame, chatType, chatTarget): here the
        -- frame really is the first argument. StyleFrame validates it anyway.
        pcall(self.SecureHook, self, "FCF_SetTemporaryWindowType", function(chatFrame)
            StyleFrame(chatFrame)
            QueueApplyVisuals(0)
        end)
    end

    -- FCF_SetChatWindowFontSize(self, chatFrame, fontSize).
    --
    -- The first argument is the caller, not the frame. Reading it as the frame was
    -- wrong even with Blizzard's own font-size dropdown, where `self` is the
    -- dropdown button: the styling silently went to the button and the chat frame
    -- was never restyled. It only became visible as an error when another addon
    -- (Prat's Font module) called the API with a plain table as `self`, which has no
    -- frame methods for ns.GetEditBox to call.
    if type(hooksecurefunc) == "function" and type(FCF_SetChatWindowFontSize) == "function" then
        pcall(hooksecurefunc, "FCF_SetChatWindowFontSize", function(_, chatFrame)
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
        if type(ns.CanUseMessageEventFilters) ~= "function" or ns.CanUseMessageEventFilters() then
            InstallTimestampFilters()
        end
    end

    ns.ApplyVisuals()
end

function VisualsModule:ChannelListChanged()
    ns.InvalidateChannelListCache()
    ns.InvalidateChannelLabelCache()

    -- The options panel lists joined channels by name, so it has to be told the
    -- list moved; without this a channel joined while the panel is open never
    -- appears in it.
    local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if registry and type(registry.NotifyChange) == "function" then
        pcall(registry.NotifyChange, registry, "Chatify")
    end
end

function VisualsModule:PLAYER_LOGIN()
    -- Deferred, not run at OnEnable: GetChannelList is empty until the channels
    -- are actually joined, and a number that resolves to nothing is dropped.
    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(5, function()
            local db = GetVisualDB()
            if db then
                ns.InvalidateChannelListCache()
                ns.MigrateChannelLabels(db)
                ns.InvalidateChannelLabelCache()
            end
        end)
    end

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

    ns.RemoveChannelLabelHook()
end
