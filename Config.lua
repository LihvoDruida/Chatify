local addonName, ns = ...

ns.Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

-- Every module is written against a global `Chatify` (e.g. `if Chatify and
-- Chatify.db then return Chatify.db.profile end`), but the addon object was only
-- ever stored on the private namespace. AceAddon does not create a global for you,
-- so all of those guards silently evaluated to nil and fell through to their
-- fallback path. That quietly disabled the /chatcopy slash command, the retail
-- safe-mode enforcement in ChatFilters/ChatHistory, and the per-character
-- auto-reply state. Publish the object under the name the rest of the addon uses.
_G.Chatify = ns.Chatify

-- =========================================================
-- 1. LIBS & MEDIA REGISTRATION
-- =========================================================
local LSM = LibStub("LibSharedMedia-3.0", true)

-- =========================================================
-- 2. GLOBAL LISTS (CONSTANTS)
-- =========================================================
ns.Lists = ns.Lists or {}

local ADDON_FONT_ROOT = "Interface\\AddOns\\Chatify\\assets\\Fonts\\"
local CHATIFY_DEFAULT_SOUND = "Interface\\AddOns\\Chatify\\assets\\alert\\notification-0.ogg"
local CHATIFY_DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local function AddFont(list, name, path, opts)
    if type(name) ~= "string" or name == "" or type(path) ~= "string" or path == "" then
        return
    end
    opts = opts or {}
    list[#list + 1] = {
        name = name,
        path = path,
        internal = opts.internal == true,
        family = opts.family,
        weight = opts.weight,
        aliases = opts.aliases,
        hidden = opts.hidden == true,
        register = opts.register ~= false,
        recommended = opts.recommended == true,
    }
end

-- Список шрифтів. Це fallback-реєстр Chatify і джерело для LibSharedMedia.
-- Внутрішні шрифти реєструються як звичайні LSM fonts, якщо файли є в assets/Fonts.
ns.Lists.Fonts = {}
AddFont(ns.Lists.Fonts, "Friz Quadrata (WoW)", "Fonts\\FRIZQT__.TTF", { family = "WoW" })
AddFont(ns.Lists.Fonts, "Arial Narrow (WoW)", "Fonts\\ARIALN.TTF", { family = "WoW" })
AddFont(ns.Lists.Fonts, "Skurri (WoW)", "Fonts\\skurri.ttf", { family = "WoW" })
AddFont(ns.Lists.Fonts, "Morpheus (Quest)", "Fonts\\MORPHEUS.TTF", { family = "WoW" })

-- Internal chat fonts. Only readable, chat-safe static TTF variants are exposed.
-- Exo2.ttf is kept as a legacy file/alias path, but it is not shown as a
-- separate dropdown row because it duplicates the Regular face.
AddFont(ns.Lists.Fonts, "Chatify: Exo 2", ADDON_FONT_ROOT .. "Exo2-Regular.ttf", {
    internal = true,
    family = "Exo 2",
    weight = "Regular",
    recommended = true,
    aliases = {
        "Chatify: Exo 2 Regular",
        "Exo2",
        "EXO2",
        "Exo 2",
        ADDON_FONT_ROOT .. "Exo2.ttf",
    },
})
AddFont(ns.Lists.Fonts, "Chatify: Exo 2 Medium", ADDON_FONT_ROOT .. "Exo2-Medium.ttf", { internal = true, family = "Exo 2", weight = "Medium", recommended = true })
AddFont(ns.Lists.Fonts, "Chatify: Exo 2 SemiBold", ADDON_FONT_ROOT .. "Exo2-SemiBold.ttf", { internal = true, family = "Exo 2", weight = "SemiBold", recommended = true })
AddFont(ns.Lists.Fonts, "Chatify: Exo 2 Bold", ADDON_FONT_ROOT .. "Exo2-Bold.ttf", { internal = true, family = "Exo 2", weight = "Bold" })
AddFont(ns.Lists.Fonts, "Chatify: Exo 2 Italic", ADDON_FONT_ROOT .. "Exo2-Italic.ttf", { internal = true, family = "Exo 2", weight = "Italic" })

AddFont(ns.Lists.Fonts, "Chatify: Inter", ADDON_FONT_ROOT .. "Inter-Regular.ttf", {
    internal = true,
    family = "Inter",
    weight = "Regular",
    recommended = true,
    aliases = { "Chatify: Inter Regular", "Inter", "INTER" },
})
AddFont(ns.Lists.Fonts, "Chatify: Inter Medium", ADDON_FONT_ROOT .. "Inter-Medium.ttf", { internal = true, family = "Inter", weight = "Medium", recommended = true })
AddFont(ns.Lists.Fonts, "Chatify: Inter SemiBold", ADDON_FONT_ROOT .. "Inter-SemiBold.ttf", { internal = true, family = "Inter", weight = "SemiBold", recommended = true })
AddFont(ns.Lists.Fonts, "Chatify: Inter Bold", ADDON_FONT_ROOT .. "Inter-Bold.ttf", { internal = true, family = "Inter", weight = "Bold" })

-- Inter Display is readable enough for compact buttons/headings, but less ideal
-- than Inter for dense chat logs. Keep it available when the matching static
-- TTF files are installed.
AddFont(ns.Lists.Fonts, "Chatify: Inter Display", ADDON_FONT_ROOT .. "InterDisplay-Regular.ttf", {
    internal = true,
    family = "Inter Display",
    weight = "Regular",
    aliases = { "Chatify: Inter Display Regular", "Inter Display" },
})
AddFont(ns.Lists.Fonts, "Chatify: Inter Display Medium", ADDON_FONT_ROOT .. "InterDisplay-Medium.ttf", { internal = true, family = "Inter Display", weight = "Medium" })
AddFont(ns.Lists.Fonts, "Chatify: Inter Display SemiBold", ADDON_FONT_ROOT .. "InterDisplay-SemiBold.ttf", { internal = true, family = "Inter Display", weight = "SemiBold" })
AddFont(ns.Lists.Fonts, "Chatify: Inter Display Bold", ADDON_FONT_ROOT .. "InterDisplay-Bold.ttf", { internal = true, family = "Inter Display", weight = "Bold" })

-- Legacy Exo2.ttf support for old profiles and manual installs. Hidden entries
-- are never registered in LibSharedMedia, so they cannot duplicate the dropdown.
AddFont(ns.Lists.Fonts, "Chatify: Exo 2 Legacy", ADDON_FONT_ROOT .. "Exo2.ttf", {
    internal = true,
    family = "Exo 2",
    weight = "Regular",
    hidden = true,
    register = false,
    aliases = { "Exo2.ttf" },
})

-- Список форматів часу
-- Joined channel discovery.
--
-- GetChannelList returns a flat id, name, disabled triplet run and exists on
-- every flavour. The name it hands back for zone channels carries a suffix
-- ("General - Elwynn Forest"), which has to come off before the name can be used
-- as a stable key - otherwise a label set in Elwynn would not apply in Durotar.
--
-- Cached, because the options panel asks for this on every redraw. Invalidated by
-- ns.InvalidateChannelListCache, wired to the channel events in ChatVisuals.
local joinedChannelCache
local joinedChannelById

local function SafeChannelText(value)
    if value == nil then
        return nil
    end

    local issecretvalue = _G.issecretvalue
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then
            return nil
        end
    end

    local canaccessvalue = _G.canaccessvalue
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok and accessible == false then
            return nil
        end
    end

    local valueType = type(value)
    if valueType == "string" then
        return value
    end
    if valueType == "number" then
        return tostring(value)
    end

    return nil
end

function ns.NormalizeChannelName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    -- Strip the zone suffix. Blizzard's separator is " - " in every locale that
    -- uses one; a name with no separator is returned unchanged.
    local base = name:match("^(.-)%s+%-%s+.+$") or name
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then
        return nil
    end

    return base
end

function ns.ChannelNameKey(name)
    local base = ns.NormalizeChannelName(name)
    if not base then
        return nil
    end
    -- Upper-cased and stripped of spaces and punctuation so "LookingForGroup",
    -- "Looking For Group" and "lookingforgroup" all resolve to one key.
    return (base:upper():gsub("[%s%p]", ""))
end

function ns.GetJoinedChannels()
    if joinedChannelCache then
        return joinedChannelCache, joinedChannelById
    end

    local list, byId = {}, {}

    if type(GetChannelList) == "function" then
        local ok, results = pcall(function()
            return { GetChannelList() }
        end)

        if ok and type(results) == "table" then
            for i = 1, #results, 3 do
                local id = tonumber(results[i])
                local name = SafeChannelText(results[i + 1])
                if id and name and name ~= "" then
                    local base = ns.NormalizeChannelName(name) or name
                    local entry = {
                        id = id,
                        name = base,
                        fullName = name,
                        key = ns.ChannelNameKey(name),
                    }
                    list[#list + 1] = entry
                    byId[id] = entry
                end
            end
        end
    end

    joinedChannelCache = list
    joinedChannelById = byId
    return list, byId
end

-- Records the readable name for every joined channel, so labels stay identifiable
-- in the options panel after you leave the channel. Cheap and idempotent; called
-- from the options build and from the label refresh.
function ns.RememberChannelNames(db)
    if type(db) ~= "table" then
        return
    end

    local joined = ns.GetJoinedChannels()
    if #joined == 0 then
        return
    end

    db.channelLabelNames = db.channelLabelNames or {}
    for _, entry in ipairs(joined) do
        if entry.key and entry.name then
            db.channelLabelNames[entry.key] = entry.name
        end
    end
end

-- Resolves a key back to something a person recognises. Falls back to the key
-- itself, which is at least the channel name upper-cased.
function ns.GetChannelDisplayName(db, key)
    if type(key) ~= "string" or key == "" then
        return ""
    end

    local _, byId = ns.GetJoinedChannels()
    if byId then
        for _, entry in pairs(byId) do
            if entry.key == key then
                return entry.name
            end
        end
    end

    local names = type(db) == "table" and db.channelLabelNames
    if type(names) == "table" and type(names[key]) == "string" and names[key] ~= "" then
        return names[key]
    end

    return key
end

-- Every key that has a label or a remembered name, joined or not, merged with the
-- currently joined list. This is what the options panel iterates, so a channel
-- created by hand with /join keeps its row after you leave it.
function ns.GetKnownChannelKeys(db)
    local seen, list = {}, {}

    for _, entry in ipairs(ns.GetJoinedChannels()) do
        if entry.key and not seen[entry.key] then
            seen[entry.key] = true
            list[#list + 1] = {
                key = entry.key,
                name = entry.name,
                id = entry.id,
                joined = true,
            }
        end
    end

    if type(db) == "table" then
        for _, source in ipairs({ db.channelLabelsNamed, db.channelLabelNames }) do
            if type(source) == "table" then
                for key, value in pairs(source) do
                    if type(key) == "string" and key ~= "" and not seen[key]
                        and type(value) == "string" and value ~= "" then
                        seen[key] = true
                        list[#list + 1] = {
                            key = key,
                            name = ns.GetChannelDisplayName(db, key),
                            joined = false,
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        -- Joined channels first, in their in-game order; everything else after,
        -- alphabetically, so the list does not reshuffle between openings.
        if a.joined ~= b.joined then
            return a.joined
        end
        if a.joined and b.joined then
            return (a.id or 0) < (b.id or 0)
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return list
end

function ns.InvalidateChannelListCache()
    joinedChannelCache = nil
    joinedChannelById = nil
end

-- Prat-style channel state invalidation. Channel membership events cover most
-- changes, but Blizzard can also change the effective channel map when a
-- Communities stream is added/removed or numbered channels are swapped. Hook
-- those API entry points once so cached ids/names cannot drift behind FrameXML.
local channelStateHooksInstalled = false
local channelStateHookedTargets = {}

local function RefreshChannelStateCaches()
    ns.InvalidateChannelListCache()
    if type(ns.InvalidateChannelLabelCache) == "function" then
        ns.InvalidateChannelLabelCache()
    end
    if type(ns.InvalidateChannelNoticeCache) == "function" then
        ns.InvalidateChannelNoticeCache()
    end

    if type(ns.ScheduleUnique) == "function" then
        ns.ScheduleUnique("channel-state-refresh", 0, function()
            if type(ns.ApplyVisuals) == "function" then
                ns.ApplyVisuals()
            end
            local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
            if registry and type(registry.NotifyChange) == "function" then
                pcall(registry.NotifyChange, registry, "Chatify")
            end
        end)
    end
end

local function HookChannelStateFunction(owner, method)
    local key = tostring(owner) .. ":" .. tostring(method)
    if channelStateHookedTargets[key] then
        return true
    end

    local ok = false
    if type(owner) == "string" then
        if type(_G[owner]) == "function" and type(hooksecurefunc) == "function" then
            ok = pcall(hooksecurefunc, owner, RefreshChannelStateCaches)
        end
    elseif type(owner) == "table" and type(method) == "string" and type(owner[method]) == "function" and type(hooksecurefunc) == "function" then
        ok = pcall(hooksecurefunc, owner, method, RefreshChannelStateCaches)
    end

    if ok then
        channelStateHookedTargets[key] = true
    end
    return ok and true or false
end

function ns.InstallChannelStateHooks()
    local installed = false

    -- Old FrameXML globals first, then the modern ChatFrameUtil methods used by
    -- Retail, Forever and current Classic branches.
    installed = HookChannelStateFunction("ChatFrame_AddCommunitiesChannel") or installed
    installed = HookChannelStateFunction("ChatFrame_RemoveCommunitiesChannel") or installed

    local util = _G.ChatFrameUtil
    if type(util) == "table" then
        installed = HookChannelStateFunction(util, "AddCommunitiesChannel") or installed
        installed = HookChannelStateFunction(util, "RemoveCommunitiesChannel") or installed
    end

    local chatInfo = _G.C_ChatInfo
    if type(chatInfo) == "table" then
        installed = HookChannelStateFunction(chatInfo, "SwapChatChannelsByChannelIndex") or installed
    end

    channelStateHooksInstalled = channelStateHooksInstalled or installed
    return channelStateHooksInstalled
end

-- One-time move of labels that were keyed by number in 0.11.26. A number can only
-- be resolved to a name while that channel is joined, so anything that cannot be
-- matched is dropped rather than guessed at.
function ns.MigrateChannelLabels(db)
    if type(db) ~= "table" then
        return
    end

    local numbered = db.channelLabelsNumbered
    if type(numbered) ~= "table" or not next(numbered) then
        return
    end

    db.channelLabelsNamed = db.channelLabelsNamed or {}

    local _, byId = ns.GetJoinedChannels()
    for key, value in pairs(numbered) do
        local id = tonumber(key)
        local entry = id and byId and byId[id]
        if entry and entry.key and type(value) == "string" and value ~= "" then
            if db.channelLabelsNamed[entry.key] == nil then
                db.channelLabelsNamed[entry.key] = value
            end
        end
    end

    db.channelLabelsNumbered = {}
    ns.RememberChannelNames(db)
end

-- Channel label tokens.
--
-- `token` is what appears inside the chat hyperlink, which is locale-independent
-- and identical on every flavour - that is why the rewrite matches on it rather
-- than on the visible label. `short` is the built-in abbreviation used when
-- "Shorten Channel Names" is on and no custom label is set.
-- `global` is the GlobalString holding the label the game itself shows, which is
-- what the options panel pre-fills the field with. Reading it beats hardcoding an
-- English name: on a French client the Party field should read "Groupe", and the
-- fallback `name` is only used where the global is missing.
-- Channel types, split by how the label reaches the rendered line.
--
-- kind = "link": the label sits inside a chat hyperlink,
--   |Hchannel:PARTY|h[Party]|h, so it can be swapped by rewriting the bracket
--   contents. Safe, locale-independent, and what Chatify has always done.
--
-- kind = "template": say, yell and whispers carry no channel link at all. The
--   game renders them from a GlobalString like CHAT_WHISPER_GET ("%s whispers: "),
--   so there is no tag to replace - one has to be introduced, and the phrasing
--   that surrounds the player name has to be removed. Prat can do this cleanly
--   because it works on message components before they are assembled; we only
--   ever see the finished line, so the pattern is derived from the GlobalString at
--   runtime. That is exact rather than guessed, but it is still surgery on a
--   rendered string, which is why these default to off.
--
-- `short` is the built-in abbreviation. `global` holds the label the game itself
-- shows, used to pre-fill the options field.
ns.Lists.ChannelLabels = {
    { token = "GUILD",           kind = "link", short = "G",   name = "Guild",           global = "GUILD",                 template = "CHAT_GUILD_GET" },
    { token = "OFFICER",         kind = "link", short = "O",   name = "Officer",         global = "OFFICER",               template = "CHAT_OFFICER_GET" },
    { token = "PARTY",           kind = "link", short = "P",   name = "Party",           global = "PARTY",                 template = "CHAT_PARTY_GET" },
    { token = "PARTY_LEADER",    kind = "link", short = "PL",  name = "Party Leader",    global = "PARTY_LEADER",          template = "CHAT_PARTY_LEADER_GET" },
    { token = "RAID",            kind = "link", short = "R",   name = "Raid",            global = "RAID",                  template = "CHAT_RAID_GET" },
    { token = "RAID_LEADER",     kind = "link", short = "RL",  name = "Raid Leader",     global = "RAID_LEADER",           template = "CHAT_RAID_LEADER_GET" },
    -- Retail/Midnight may render Raid Warning through CHAT_RAID_WARNING_GET
    -- without a channel hyperlink. Keep link handling for clients that provide
    -- one, but also register a locale-safe template fallback.
    { token = "RAID_WARNING",    kind = "link", short = "RW",  name = "Raid Warning",    global = "RAID_WARNING",          template = "CHAT_RAID_WARNING_GET", templateFallback = true },
    { token = "INSTANCE",        kind = "link", short = "I",   name = "Instance",        global = "INSTANCE_CHAT",         template = "CHAT_INSTANCE_CHAT_GET" },
    { token = "INSTANCE_LEADER", kind = "link", short = "IL",  name = "Instance Leader", global = "INSTANCE_CHAT_LEADER",  template = "CHAT_INSTANCE_CHAT_LEADER_GET" },

    { token = "SAY",             kind = "template", short = "S",      name = "Say",              template = "CHAT_SAY_GET" },
    { token = "YELL",            kind = "template", short = "Y",      name = "Yell",             template = "CHAT_YELL_GET" },
    { token = "WHISPER",         kind = "template", short = "W From", name = "Whisper Received", template = "CHAT_WHISPER_GET" },
    { token = "WHISPER_INFORM",  kind = "template", short = "W To",   name = "Whisper Sent",     template = "CHAT_WHISPER_INFORM_GET" },
    { token = "BN_WHISPER",      kind = "template", short = "W From", name = "Battle.net Received", template = "CHAT_BN_WHISPER_GET" },
    { token = "BN_WHISPER_INFORM", kind = "template", short = "W To", name = "Battle.net Sent",  template = "CHAT_BN_WHISPER_INFORM_GET" },
}

-- How a channel's label is decided. Mirrors Prat's per-type `replace` toggle plus
-- its "Blank" option, but as one control instead of a toggle and a text box whose
-- emptiness silently means two different things.
ns.Lists.ChannelModes = {
    "default",  -- leave the label the game produced
    "short",    -- the built-in abbreviation, or the number for a numbered channel
    "custom",   -- whatever is in the text field
    "hidden",   -- drop the tag entirely, and the space after it
}

-- Types that are shortened when nothing has been chosen. Only the link kinds, so
-- turning the master switch on cannot silently start rewriting the sentence
-- structure of say, yell and whispers.
function ns.GetDefaultChannelMode(entry)
    if type(entry) == "table" and entry.kind == "template" then
        return "default"
    end
    return "short"
end

-- The hyperlink token a link-kind channel actually uses in rendered chat.
--
-- Our entry tokens are internal names and do not always match. Two cases bit us:
--
--   INSTANCE      -> the link says |Hchannel:INSTANCE_CHAT|h, so nothing matched
--                    and instance chat was never shortened.
--   PARTY_LEADER  -> the link says |Hchannel:party|h, exactly like PARTY, so the
--                    leader line picked up the party label ([P] instead of [PL]).
--
-- Reading the token out of the GlobalString is authoritative for the running
-- client instead of a table that has to be kept in step with Blizzard.
function ns.GetChannelLinkToken(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local template = entry.template and _G[entry.template]
    if type(template) == "string" then
        local token = template:match("|Hchannel:([^|:]+)")
        if token and token ~= "" then
            return token:upper()
        end
    end

    return entry.token
end

-- Resolve the format string the same way current Blizzard FrameXML and Prat do.
-- ChatFrameUtil.GetOutMessageFormatKey is preferred because it tracks modern
-- client changes (including Forever). CHAT_*_GET remains the fallback for older
-- Classic branches and for chat types that do not expose the util helper.
local CHAT_FORMAT_TYPE_ALIASES = {
    INSTANCE = "INSTANCE_CHAT",
    INSTANCE_LEADER = "INSTANCE_CHAT_LEADER",
}

function ns.GetChatOutputTemplate(templateName, chatType)
    local util = _G.ChatFrameUtil
    local resolvedType = CHAT_FORMAT_TYPE_ALIASES[chatType] or chatType
    if type(util) == "table" and type(util.GetOutMessageFormatKey) == "function" and type(resolvedType) == "string" then
        local ok, value = pcall(util.GetOutMessageFormatKey, resolvedType)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end

    local legacy = templateName and _G[templateName]
    if type(legacy) == "string" and legacy ~= "" then
        return legacy
    end

    return nil
end

-- Splits a chat GlobalString template into the literal text around its player
-- name placeholder.
--
-- CHAT_WHISPER_GET is "%s whispers: " -> prefix "", suffix " whispers: "
-- CHAT_WHISPER_INFORM_GET is "To %s: " -> prefix "To ", suffix ": "
--
-- Deriving this at runtime is what makes the template rewrite locale-correct: on
-- a German client the suffix is whatever Blizzard ships, not a guess. Returns nil
-- for anything that does not have exactly one placeholder, which is the signal to
-- leave that chat type alone.
function ns.SplitChatTemplate(templateName, chatType)
    local template = ns.GetChatOutputTemplate(templateName, chatType)
    if type(template) ~= "string" or template == "" then
        return nil
    end

    local prefix, suffix = template:match("^(.-)%%s(.*)$")
    if not prefix or not suffix then
        return nil
    end

    -- A second placeholder means the message body is part of the template, which
    -- this simple two-part split cannot represent safely.
    if prefix:find("%%s") or suffix:find("%%s") then
        return nil
    end

    if suffix == "" then
        return nil
    end

    return prefix, suffix
end

-- The label the game would show for a built-in channel, used to pre-fill the
-- options field so it displays the value in force rather than an empty box.
function ns.GetBuiltinChannelDefault(entry)
    if type(entry) ~= "table" then
        return ""
    end

    -- Template kinds have no tag of their own, so there is nothing the game would
    -- have shown; the abbreviation is the only sensible starting point.
    if entry.kind == "template" then
        return entry.short or entry.name or ""
    end

    local global = entry.global and _G[entry.global]
    if type(global) == "string" and global ~= "" then
        return global
    end

    return entry.name or ""
end

-- The mode in force for a channel, honouring the master switch.
function ns.GetChannelMode(db, key, entry)
    if type(db) ~= "table" then
        return "default"
    end

    -- Master switch off means the game's labels, whatever the per-channel
    -- settings say. Those settings are kept, not cleared, so turning it back on
    -- restores them.
    if not db.shortChannels then
        return "default"
    end

    local modes = db.channelModes
    local mode = type(modes) == "table" and modes[key] or nil
    if mode == "default" or mode == "short" or mode == "custom" or mode == "hidden" then
        return mode
    end

    return ns.GetDefaultChannelMode(entry)
end

ns.Lists.TimeFormats = {
    [1] = { name = "None",                     format = nil },
    [2] = { name = "HH:MM (12:30)",            format = "%H:%M" },
    [3] = { name = "HH:MM:SS (12:30:45)",      format = "%H:%M:%S" },
    [4] = { name = "AM/PM (12:30 PM)",         format = "%I:%M %p" },
    [5] = { name = "D.M HH:MM (08.02 12:30)",  format = "%d.%m %H:%M" },
}

-- Single source for "what does a Chatify timestamp look like right now".
--
-- This resolution was written out three times: twice in ChatVisuals and once, as a
-- hardcoded "%H:%M", in ChatHistory. The hardcoded one is why the History window
-- dropped the seconds for anyone who had configured HH:MM:SS - the setting was
-- simply not consulted there.
--
-- Returns nil when the user has chosen "None", which means "no timestamp" rather
-- than "use the default".
function ns.GetTimestampFormat(db)
    db = db or ns.db
    if type(db) ~= "table" then
        return "%H:%M"
    end

    local formats = ns.Lists and ns.Lists.TimeFormats
    if not formats or db.timestampID == nil then
        return "%H:%M"
    end

    local formatData = formats[db.timestampID]
    if type(formatData) ~= "table" then
        return "%H:%M"
    end

    -- A nil format is the "None" entry and is meaningful; do not fall back.
    return formatData.format
end

-- The clock reading Chatify should stamp a message with, honouring the server-time
-- preference. Callers that already know when the message arrived pass it in.
function ns.GetTimestampSeconds(db, when)
    if tonumber(when) then
        return tonumber(when)
    end

    db = db or ns.db
    if type(db) == "table" and db.useServerTime and type(GetServerTime) == "function" then
        local ok, serverTime = pcall(GetServerTime)
        if ok and tonumber(serverTime) then
            return serverTime
        end
    end

    return time()
end

-- Formatted timestamp, or nil when the user has timestamps switched off.
function ns.FormatChatTimestamp(db, when)
    local format = ns.GetTimestampFormat(db)
    if type(format) ~= "string" or format == "" then
        return nil
    end

    local ok, text = pcall(date, format, ns.GetTimestampSeconds(db, when))
    if ok and type(text) == "string" and text ~= "" then
        return text
    end

    return nil
end

local fontAliasLookup
local fontUsabilityCache = {}
local fontProbeSerial = 0
local registeredMedia = {}

local function IsBuiltinWoWFontPath(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local lower = string.lower(path)
    return string.sub(lower, 1, 6) == "fonts\\" or string.sub(lower, 1, 6) == "fonts/"
end

local function CanUseFontAsset(path)
    if type(path) ~= "string" or path == "" then
        return false
    end

    if fontUsabilityCache[path] ~= nil then
        return fontUsabilityCache[path]
    end

    -- Blizzard's built-in Fonts\*.TTF entries are safe to expose even before
    -- a Font object is available on very early load paths.
    if IsBuiltinWoWFontPath(path) then
        fontUsabilityCache[path] = true
        return true
    end

    if type(CreateFont) ~= "function" then
        -- Do not expose optional addon fonts until the client can validate them.
        fontUsabilityCache[path] = false
        return false
    end

    fontProbeSerial = fontProbeSerial + 1
    local fontName = "ChatifyFontProbe" .. tostring(fontProbeSerial)
    local okCreate, probe = pcall(CreateFont, fontName)
    if not okCreate or not probe or type(probe.SetFont) ~= "function" then
        fontUsabilityCache[path] = false
        return false
    end

    local okSet, applied = pcall(probe.SetFont, probe, path, 12, "")
    local usable = okSet and applied ~= false
    fontUsabilityCache[path] = usable
    return usable
end

function ns.IsFontPathAvailable(path)
    return CanUseFontAsset(path)
end

function ns.IsFontEntryAvailable(entry)
    return entry and CanUseFontAsset(entry.path) or false
end

local function BuildFontAliasLookup()
    local lookup = {}
    for _, entry in ipairs(ns.Lists.Fonts or {}) do
        if entry and type(entry.name) == "string" and type(entry.path) == "string" and CanUseFontAsset(entry.path) then
            lookup[entry.name] = entry.path
            lookup[string.lower(entry.name)] = entry.path
            lookup[entry.path] = entry.path
            if type(entry.aliases) == "table" then
                for _, alias in ipairs(entry.aliases) do
                    if type(alias) == "string" and alias ~= "" then
                        lookup[alias] = entry.path
                        lookup[string.lower(alias)] = entry.path
                    end
                end
            end
        end
    end
    return lookup
end

local function RegisterMediaOnce(mediaType, name, path)
    if not (LSM and type(LSM.Register) == "function") then
        return
    end
    if type(mediaType) ~= "string" or type(name) ~= "string" or name == "" or type(path) ~= "string" or path == "" then
        return
    end

    local key = mediaType .. "\031" .. name .. "\031" .. path
    if registeredMedia[key] then
        return
    end

    local ok = pcall(LSM.Register, LSM, mediaType, name, path)
    if ok then
        registeredMedia[key] = true
    end
end

local function RegisterChatifyMedia()
    if not (LSM and type(LSM.Register) == "function") then
        return
    end

    RegisterMediaOnce("sound", "Chatify Default", CHATIFY_DEFAULT_SOUND)

    for _, entry in ipairs(ns.Lists.Fonts or {}) do
        if entry and entry.register ~= false and not entry.hidden and type(entry.name) == "string" and type(entry.path) == "string" and CanUseFontAsset(entry.path) then
            RegisterMediaOnce("font", entry.name, entry.path)
        end
    end
end

ns.RegisterChatifyMedia = RegisterChatifyMedia
RegisterChatifyMedia()

-- =========================================================
-- 3. MEDIA RESOLVERS
-- =========================================================
function ns.ResolveFontPath(fontID)
    if type(fontID) ~= "string" or fontID == "" then
        return CHATIFY_DEFAULT_FONT
    end

    if string.find(fontID, "\\", 1, true) or string.find(fontID, "/", 1, true) then
        return fontID
    end

    local fromLSM = LSM and LSM.Fetch and LSM:Fetch("font", fontID, true)
    if fromLSM and type(fromLSM) == "string" and CanUseFontAsset(fromLSM) then
        return fromLSM
    end

    fontAliasLookup = fontAliasLookup or BuildFontAliasLookup()
    local fromAlias = fontAliasLookup[fontID] or fontAliasLookup[string.lower(fontID)]
    if type(fromAlias) == "string" and fromAlias ~= "" then
        return fromAlias
    end

    return CHATIFY_DEFAULT_FONT
end

function ns.ResolveSoundPath(soundID)
    if type(soundID) ~= "string" or soundID == "" or soundID == "None" then
        return nil
    end

    if string.find(soundID, "\\", 1, true) or string.find(soundID, "/", 1, true) then
        return soundID
    end

    local fromLSM = LSM and LSM.Fetch and LSM:Fetch("sound", soundID, true)
    if fromLSM and type(fromLSM) == "string" then
        return fromLSM
    end

    if soundID == "Chatify Default" then
        return CHATIFY_DEFAULT_SOUND
    end

    return nil
end

-- =========================================================
-- 4. DEFAULT SETTINGS
-- =========================================================
ns.defaults = {
    profile = {
        -- === VISUALS ===
        fontID = "Friz Quadrata (WoW)", -- Дефолтний шрифт клієнта WoW
        fontOutline = "",    -- Контур тексту для кращої читабельності
        
        -- === TIME ===
        enableTimestamps = true,     -- Таймстемпи: virtual mode через Router, normal/retail через safe filter path
        timestampID = 2,            -- За замовчуванням HH:MM
        timestampColor = "68ccef",  -- Колір часу (світло-блакитний)
        useServerTime = false,      -- Використовувати локальний час ПК
        timestampPost = false,      -- Час на початку повідомлення

        -- === HISTORY ===
        useVirtualChat = false,      -- На modern Retail лишається вимкненим: прямий chat-frame layer конфліктує з secret values
        enableHistory = true,
        historyLimit = 250,         -- Зберігати 250 рядків для History popup
        historyStorageKB = 128,     -- Proactive SavedVariables budget for persistent chat history

        -- Keep a marker in history where a line could not be read, matching what the
        -- copy window has always done. Consecutive markers collapse, so a boss fight
        -- costs one line rather than one per suppressed message.
        historyKeepProtected = true,

        -- The taint-free mention route: a second, highlighted line printed by Chatify
        -- rather than a rewrite of Blizzard's. Shown only when neither in-line route
        -- is live, so a mention is never announced twice. See ns.AnnounceMentionAlert.
        mentionEcho = true,
        historyAlpha = true,        -- Legacy SavedVariables key; history is no longer replayed into chat frames

        -- === SPAM FILTERS (Updated) ===
        enableSpamFilter = true,
        
        -- Anti-Flood / Filter Engine 3.0
        enableThrottle = true,      -- Блокувати повтор повідомлень
        throttleTime = 60,          -- Час блокування (сек)
        throttleMinLength = 20,     -- Мінімальна довжина нормалізованого повідомлення для anti-flood
        spamFilterMode = "block",  -- block або log: log тільки записує в debug без блокування
        spamLogLimit = 20,          -- Останні N подій у runtime debug-log
        spamWhitelist = {
            guild = true,           -- Не фільтрувати гільдійський/офіцерський чат
            friends = true,         -- Не фільтрувати Battle.net/звичайних друзів, коли їх можна безпечно визначити
            party = true,           -- Не фільтрувати party чат
            raid = true,            -- Не фільтрувати raid/instance чат
        },
        spamChannelRules = {
            CHANNEL = true,         -- Загальний fallback для CHAT_MSG_CHANNEL
            TRADE = true,
            SERVICES = true,
            GENERAL = true,
            GUILD = false,
            OFFICER = false,
            PARTY = false,
            RAID = false,
            INSTANCE = false,
            SAY = true,
            YELL = true,
            COMMUNITY = true,
            LOOT = false,
        },
        
        -- System Cleaner
        hideSystemSpam = true,      -- Приховувати вхід/вихід з каналів

        -- Базовий список слів для блокування
        spamKeywords = { 
            "BOOST", "CARRY", "GOLD", "CHEAP", "WTS", "SELLING", "SERVICES", "VIP"
        },

        -- === MENTION MANAGER ===
        enableMentionManager = true,
        mentionRules = {
            {
                enabled = true,
                text = UnitName("player") or "",
                color = "ffd700",
                sound = "Chatify Default",
                channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
                ignoreCase = true,
                wholeWord = true,
                cooldown = 2,
                -- On WoW: Forever this one rule expands to the player's
                -- First, Surname, "First Surname", and "First-Surname" aliases.
                matchPlayerIdentity = true,
            },
            {
                enabled = false,
                text = "RL",
                color = "ff4040",
                sound = "None",
                channels = "GUILD,RAID,INSTANCE",
                ignoreCase = true,
                wholeWord = true,
                cooldown = 3,
            },
        },

        -- === SAFE CHAT TABS ===
        chatTabsTemplate = "RAID", -- PM, GUILD або RAID

        -- === FORMATTING ===
        -- Frame behaviour.
        --
        -- Everything in this group is pure ScrollingMessageFrame API - no chat
        -- message filter, no GlobalStrings, nothing on Blizzard's chat dispatch -
        -- so it is taint-free and keeps working on 12.0+ where the text-mutating
        -- features have to stand down. Compare Prat's Scroll, Fading, Paragraph
        -- and OriginalButtons modules, which take the same approach.
        --
        -- scrollbackLines: Blizzard keeps only 128 lines per window, which is the
        -- real reason scrollback runs out mid-fight. 0 leaves the client's value
        -- alone. Changing it clears the affected window once, because SetMaxLines
        -- reallocates the frame's buffer.
        scrollbackLines = 500,
        disableChatFade = false,
        chatFadeTime = 120,
        lineSpacing = 0,
        indentWrappedLines = false,
        enableScrollTweaks = true,
        scrollLinesPerNotch = 3,
        hideBlizzardChatButtons = false,
        -- Custom channel labels.
        --
        -- Keys are the channel tokens that appear inside the chat hyperlink
        -- (|Hchannel:PARTY|h[Party]|h), plus a numeric key per numbered channel
        -- (channelLabelsNumbered["1"] = "Gen"). Empty or absent means "leave the
        -- game's label alone"; shortChannels supplies the fallback.
        -- Per-channel mode, keyed by token for built-in types and by name key for
        -- numbered channels. Absent means ns.GetDefaultChannelMode decides.
        channelModes = {},

        channelLabels = {},

        -- Numbered channels are keyed by NAME, not by the number shown in chat.
        -- The number is just the join order and changes when you leave a channel
        -- or move between zones, so a label pinned to "3" would follow whatever
        -- happened to land in slot 3. Keys are the uppercased base name with any
        -- " - Zone" suffix removed, e.g. GENERAL, TRADE, LOOKINGFORGROUP.
        channelLabelsNamed = {},

        -- Human-readable name per key in channelLabelsNamed, so a channel you are
        -- not currently in can still be listed as "General" rather than GENERAL.
        -- Written whenever a channel is seen joined, or typed in by hand.
        channelLabelNames = {},

        -- Legacy, kept only so ns.MigrateChannelLabels can move existing entries
        -- across on first load. Not read anywhere else.
        channelLabelsNumbered = {},
        shortChannels = true,       -- [Party] -> [P]
        shortPlayerNames = false,    -- Keep full player-link target but shorten visible Name-Realm label
        senderRaceIcon = false,      -- Optional race atlas before the sender label when metadata is readable
        senderClassIcon = false,     -- Optional class atlas before the sender label when metadata is readable
        senderIconScale = 85,        -- Inline sender icon size relative to chat font
        senderIconOffset = 0,        -- Fine baseline adjustment for inline sender icons
        urlColor = "0099FF",        -- Колір посилань
        hoverHyperlinkTooltips = true, -- Показувати тултіпи при наведенні на item/spell/link у чаті
        quickChatButtons = true,      -- Вертикальні кнопки швидкого вибору типу чату біля бокового меню
        quickChatButtonSize = 26,   -- Базова ширина кнопок швидкого перемикання чату у пропорціях Blizzard sidebar
        quickChatButtonGap = 18,    -- Відступ кнопок від правого краю чату
        quickChatButtonYOffset = -4, -- Додатковий вертикальний зсув стеку швидких кнопок
        quickChatButtonAlpha = 0.92, -- Прозорість кнопок швидкого чату
        quickChatPanelAlpha = 0.0, -- Прозорість фону контейнера швидких кнопок (0 = повністю прозорий)
        quickChatButtonTheme = "AUTO", -- AUTO follows active chat addons; manual skins are appearance-only and do not require those addons
        quickChatButtonSpacing = 4, -- Вертикальний відступ між кнопками швидкого чату
        quickChatButtonFontScale = 1.0, -- Масштаб літери на кнопках швидкого чату
        quickChatSettingsButton = true, -- Кнопка налаштувань у лівому блоці біля активного чат-фрейму

        -- === LONG MESSAGE COMPOSER ===
        composer = {
            enabled = false,
            importCurrentDraft = true,
            autoPreview = true,
            autoAdvance = true,
            automationEnabled = false,
            automationDelay = 1.5,
            automationAutoStart = false,
            automationResumeAfterManual = true,
            automationResumeAfterLockdown = false,
            lockFinalChunk = true,
            rememberWhisperTarget = true,
            spellcheckIntegration = true,
            whisperTarget = "",
            chunkLimit = 245,
            showCounter = true,
            continuation = "BOTH",
            defaultChannel = "SAY",
        },

        -- === COPY CHAT ===
        copyNativeSelection = true, -- Shift + Left Click enables Blizzard direct chat selection
        copyNativeUseVisibleFrames = false, -- Optional compatibility mode for custom chat layouts
        copyNativeTimeout = 30, -- Auto-disable native selection after N seconds; 0 = until copied/toggled/reload
        copyNativeAnnounce = true, -- Print a short hint when native selection mode is enabled
        copyTabMode = "VISIBLE", -- ALL, VISIBLE, PINNED, SELECTED
        copyTabFrames = {}, -- per chat-frame include/exclude overrides for ChatCopy 2.0 tabs
        language = "client", -- Мова аддона: client, enUS, ukUA

        -- === RETAIL SECRET-VALUE BEHAVIOUR ===
        -- When true, Chatify never mutates whisper/BNet payloads on modern Retail,
        -- even outside chat messaging lockdown. Off by default: whispers behave like
        -- any other channel during normal play and are only left untouched while the
        -- client is actually protecting chat.
        retailWhisperSafeMode = false,

        -- Off by default. On 12.0+ any addon message-event filter taints Blizzard's
        -- chat dispatch and eventually produces "string conversion on a secret
        -- string value" errors. Enabling this trades that error back for spam
        -- filtering / keyword highlighting / custom link formatting.
        -- How aggressively Chatify uses Blizzard's message-event filters on 12.0+.
        --   "full"     - always filtered. Maximum features; a filter closure sits on
        --                Blizzard's chat dispatch even while chat payloads carry
        --                secret values, which is the condition that can produce
        --                "string conversion on a secret string value".
        --   "lockdown" - filtered during normal play, withdrawn for the whole taint
        --                risk window (inside instanced content, and any encounter or
        --                key within it). Opt-in on 12.0+: a filter that ran earlier
        --                in the session can still have tainted the dispatch, which
        --                shows up as no player chat at all during the encounter.
        --   "off"      - never filtered on 12.0+. Timestamps fall back to the game's
        --                own rendering; spam filtering and highlighting are lost.
        --                This is the effective default on secret-value builds unless
        --                the user picks another mode (retailChatFilterModeUserSet).
        retailChatFilterMode = "lockdown",
        retailChatFilterModeUserSet = false,

        -- Diagnostic lever, off by default and not exposed in the options UI.
        --
        -- 0.11.51 made the AddMessage wrapper unconditional on 12.0+, which removed
        -- the only way to run the protected-chat taint isolation experiment:
        -- filters on, wrapper off, whisper inside instanced content. Set
        -- via /chatifytaint filtertest, cleared via /chatifytaint reset.
        disableRenderHook = false,

        -- === SOUNDS ===
        sounds = {
            enable = true,
            masterVolume = true, -- Програвати через Master (чути навіть якщо вимкнені ефекти)
            events = {
                ["WHISPER"] = "Chatify Default",
                ["GUILD"]   = "None",
                ["PARTY"]   = "None",
                ["RAID"]    = "None",
            }
        },

        -- === AUTO REPLY ===
        -- Default messages are stored as stable English source strings rather than
        -- being localized at load time. AceDB persists these literally, so wrapping
        -- them in L() would freeze whichever locale happened to be active at first
        -- login and never follow a later language change. These are free-text fields
        -- the user edits directly; the options UI localizes labels, not the values.
        autoReply = {
            enabled = false,
            busyMode = false,
            onlyFriends = false,
            autoNotify = true,
            guildReplyEnabled = false,
            cooldown = 5,
            afkMessage = "I'm currently AFK. I'll be back later!",
            queueMessage = "I'm in queue. Estimated wait time: %s minutes.",
            raidMessage = "I'm currently in a raid. I'll message you when I'm free!",
            dungeonMessage = "I'm currently in a dungeon. I'll message you when I'm done!",
            pvpMessage = "I'm currently in PvP. I'll message you when I'm free!",
            busyMessage = "I'm currently busy. I'll get back to you soon!",
            returnMessage = "I'm back now! What did you need?",
        }
    },
    char = {
        pendingWhispers = {},
        pendingGuildMentions = {},
        wasInActivity = false,
        lastReplyTime = {},
    }
}

-- =========================================================
-- 5. BUILD / SECURITY HELPERS
-- =========================================================
-- Secret Values were introduced in Patch 12.0.0 (Midnight). WoW: Forever is
-- deliberately NOT a Classic API client: it uses the modern Mainline UI stack and
-- inherits Midnight's addon restrictions even though its own TOC is Interface 16001.
-- Never infer capability from the numeric interface alone.
local SECRET_VALUES_MIN_INTERFACE = 120000

local function IsForeverLoadTarget()
    return type(ns.Client) == "table" and ns.Client.isForever == true
end

local secretApiProbed, secretApiAvailable
function ns.HasSecretValueAPI()
    -- Forever is beta and can load hybrid UI pieces in a different order. A
    -- negative probe there is not considered session-final; re-check until one
    -- of the inspectors appears. Other clients keep the old cached hot path.
    if secretApiProbed and (secretApiAvailable or not IsForeverLoadTarget()) then
        return secretApiAvailable
    end

    secretApiProbed = true
    secretApiAvailable = type(_G.issecretvalue) == "function"
        or type(_G.hasanysecretvalues) == "function"
        or type(_G.canaccessvalue) == "function"
        or type(_G.canaccessallvalues) == "function"
        or (type(_G.C_Secrets) == "table" and type(_G.C_Secrets.HasSecretRestrictions) == "function")
    return secretApiAvailable
end

local function GetSecretRestrictionState()
    if type(_G.C_Secrets) ~= "table" or type(_G.C_Secrets.HasSecretRestrictions) ~= "function" then
        return nil
    end

    local ok, restricted = pcall(_G.C_Secrets.HasSecretRestrictions)
    if not ok then
        return nil
    end
    return restricted and true or false
end

-- Session-constant like GetBuildInterface, and queried even more often: cache it.
local cachedModernSecretBuild

function ns.IsModernSecretValueBuild()
    if cachedModernSecretBuild ~= nil then
        return cachedModernSecretBuild
    end

    -- Prefer the API's own master switch when it exists. This avoids treating the
    -- Forever 1.60.x TOC as an old client merely because 16001 is numerically below
    -- 120000, and it also future-proofs new protected game types.
    local reported = GetSecretRestrictionState()
    if reported ~= nil then
        -- A positive runtime answer is authoritative. On Forever, keep the
        -- conservative load-target fallback if a beta build briefly reports
        -- false while its hybrid UI/security pieces are still initializing.
        if reported or not IsForeverLoadTarget() then
            cachedModernSecretBuild = reported
            return reported
        end
    end

    local result = false
    if IsForeverLoadTarget() then
        -- Forever logs confirm secret values are active, but the beta mixes
        -- Camelot/Mainline/VanillaStyle UI code. Treat the load target only as a
        -- conservative safety hint; individual operations still probe their API.
        result = ns.HasSecretValueAPI()
            or (type(ns.Client) == "table" and ns.Client.usesSecretValues == true)
    elseif ns.HasSecretValueAPI() then
        -- For non-Forever clients, only current protected-interface generations
        -- use the interface number as a fallback. Do not infer this from
        -- WOW_PROJECT_ID: progression and beta clients can reuse project identity.
        result = ns.GetBuildInterface() >= SECRET_VALUES_MIN_INTERFACE
    end

    -- Do not freeze a false answer on a modern beta/current client merely
    -- because security globals were not available at the first probe.
    if result or (not IsForeverLoadTarget() and ns.GetBuildInterface() < SECRET_VALUES_MIN_INTERFACE) then
        cachedModernSecretBuild = result
    end
    return result
end

-- Compatibility name retained for existing modules. It now means
-- "modern client with Midnight-style secret chat restrictions", which includes
-- both Retail and WoW: Forever.
function ns.IsRetailSecretValueBuild()
    return ns.IsModernSecretValueBuild()
end

-- Chat messaging lockdown (12.0.0+). While it is active Blizzard blocks
-- addon-initiated SendChatMessage / BNSendWhisper with ADDON_ACTION_BLOCKED and
-- delivers whisper payloads as secret values. Outside of it, chat behaves normally.
--
-- This is polled per chat message, so the answer is cached. Unlike the build
-- checks it does change during a session, so the cache is dropped by
-- ns.InvalidateLockdownCache() from the same event watcher that drives
-- RefreshMessageFilters (ADDON_RESTRICTION_STATE_CHANGED plus encounter and
-- challenge-mode fallbacks), which is exactly when the state can flip.
local cachedLockdown

function ns.InvalidateLockdownCache()
    cachedLockdown = nil
end

function ns.InChatMessagingLockdown(forceFresh)
    if not forceFresh and cachedLockdown ~= nil then
        return cachedLockdown
    end

    local result = false
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok then
            result = locked and true or false
        end
    end

    cachedLockdown = result
    return result
end

-- Taint risk window (12.0+).
--
-- Chat payloads only carry secret values while chat messaging lockdown is active,
-- but taint is not symmetrical with it: a filter closure that ran BEFORE the
-- encounter has already marked Blizzard's chat dispatch and the shared state
-- ChatHistory_GetAccessID/GetToken write into, and that mark survives until the
-- next /reload. Withdrawing the filter at ENCOUNTER_START is therefore too late.
--
-- The last moment at which withdrawal still buys anything is the instance
-- transition, so the risk window is "lockdown OR inside instanced content".
-- IsInInstance is a cheap C call and is not cached; only the lockdown half is.
function ns.InChatTaintRiskWindow()
    if not ns.IsRetailSecretValueBuild() then
        return false
    end

    if ns.InChatMessagingLockdown() then
        return true
    end

    if type(IsInInstance) == "function" then
        local ok, inInstance, instanceType = pcall(IsInInstance)
        if ok and inInstance and instanceType ~= "none" then
            return true
        end
    end

    return false
end

-- Single gate for every outgoing addon-initiated chat message. Deliberately reads
-- the lockdown state fresh rather than from cache: this runs only when something is
-- actually about to be sent, and a stale "not locked" answer here would produce the
-- ADDON_ACTION_BLOCKED popup this gate exists to prevent.
function ns.CanSendAddonChat()
    if not ns.IsRetailSecretValueBuild() then
        return true
    end
    return not ns.InChatMessagingLockdown(true)
end

local whisperSensitiveEvents = {
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_BN_CONVERSATION = true,
}

function ns.IsWhisperSensitiveEvent(eventName)
    return whisperSensitiveEvents[eventName] and true or false
end

-- On any client that reports active secret-value restrictions, whisper/BNet payloads
-- are treated conservatively: mutation is bypassed whenever the payload can be secret.
-- Chat history is captured on Chatify's own event frame, not through Blizzard's
-- message-event filter chain, so nothing here can taint Blizzard's chat dispatch.
-- The only real requirement is to never operate on a secret payload, and
-- CanMutateChatPayload already enforces that per message. Blanket-skipping whole
-- event types on retail therefore only cost features (no whisper, emote or
-- achievement history) without buying any safety.
--
-- Kept as a function because modules call it, and so a specific event can be
-- excluded again quickly if one turns out to need it.
function ns.ShouldBypassChatCaptureEvent(eventName)
    return false
end

-- Blizzard exposes batch inspectors that examine an entire vararg in a single C
-- call. They are both cheaper than looping in Lua (these run for every chat line,
-- once per chat frame the event is registered on) and more reliable, since they
-- also see values a per-item check can miss. Resolved once at load; on clients
-- without them the original element-wise loop is used.
local hasAnySecretValues = _G.hasanysecretvalues
local canAccessAllValues = _G.canaccessallvalues

function ns.HasSecretChatValue(...)
    -- Nothing can be secret without the API, and this is the single hottest
    -- function in the addon (once per message, per chat frame registered for the
    -- event). Bailing here removes the whole vararg walk on every Classic client
    -- and on pre-12 Retail.
    if not ns.HasSecretValueAPI() then
        return false
    end

    if type(hasAnySecretValues) ~= "function" then
        hasAnySecretValues = _G.hasanysecretvalues
    end
    if type(hasAnySecretValues) == "function" then
        local ok, result = pcall(hasAnySecretValues, ...)
        if ok then
            return result and true or false
        end
    end

    local count = select("#", ...)
    for i = 1, count do
        if ns.IsSecretValue(select(i, ...)) then
            return true
        end
    end
    return false
end

function ns.CanAccessChatValue(...)
    if not ns.HasSecretValueAPI() then
        return true
    end

    local count = select("#", ...)
    if count == 0 then
        return true
    end

    if type(canAccessAllValues) ~= "function" then
        canAccessAllValues = _G.canaccessallvalues
    end
    if type(canAccessAllValues) == "function" then
        local ok, result = pcall(canAccessAllValues, ...)
        if ok then
            return result and true or false
        end
    end

    for i = 1, count do
        local value = select(i, ...)
        if ns.IsProtectedChatValue(value) then
            return false
        end
    end

    return true
end

-- Whether Chatify must leave a whisper/BNet payload completely untouched.
--
-- Referenced unguarded by CanMutateChatPayload, which runs for every chat message,
-- so this has to exist on every client. Only whisper-family events are ever
-- bypassed, and only on secret-value builds: either because the user asked for it
-- via retailWhisperSafeMode, or because chat is currently locked down, which is
-- when those payloads actually carry secret senders.
function ns.ShouldBypassWhisperMutation(eventName)
    if not ns.IsRetailSecretValueBuild() then
        return false
    end

    if not ns.IsWhisperSensitiveEvent(eventName) then
        return false
    end

    local db = ns.db
    local addon = ns.Chatify
    if addon and addon.db and addon.db.profile then
        db = addon.db.profile
    end

    if db and db.retailWhisperSafeMode then
        return true
    end

    return ns.InChatMessagingLockdown()
end

-- === Chat entry-point breadcrumbs ===
--
-- When a secret value is touched inside an encounter, the resulting error carries
-- nothing usable: debugstack() and debuglocals() come back as secrets themselves,
-- so the report reads "execution tainted by 'Chatify'" and names no file or line.
-- Two of these have already been diagnosed by reading code and guessing.
--
-- So Chatify leaves its own trail. Every handler that receives a chat payload
-- records that it was entered, and records again once its guard has cleared the
-- payload. The handler that appears last with cleared = true is the one that went
-- on to touch the value.
--
-- Only the event name is ever stored. That is Blizzard's own constant string and is
-- never secret; no part of the payload is read here, which would defeat the point.
local chatEntryTrace = {}
local CHAT_TRACE_LIMIT = 24

local function ChatTraceNow()
    return type(GetTime) == "function" and GetTime() or 0
end

function ns.NoteChatEntryPoint(name, eventName)
    if type(name) ~= "string" then
        return
    end

    local event = type(eventName) == "string" and eventName or "?"
    local last = chatEntryTrace[#chatEntryTrace]
    if last and last.name == name and last.event == event and not last.cleared then
        last.count = (last.count or 1) + 1
        last.at = ChatTraceNow()
        return
    end

    if #chatEntryTrace >= CHAT_TRACE_LIMIT then
        table.remove(chatEntryTrace, 1)
    end

    chatEntryTrace[#chatEntryTrace + 1] = {
        name = name,
        event = event,
        count = 1,
        cleared = false,
        at = ChatTraceNow(),
    }
end

-- Called after the guard has accepted the payload, i.e. from here on the handler is
-- doing string work on it.
function ns.NoteChatEntryCleared(name)
    local last = chatEntryTrace[#chatEntryTrace]
    if last and last.name == name then
        last.cleared = true
    end
end

function ns.GetChatEntryTrace()
    local out = {}
    for i = #chatEntryTrace, 1, -1 do
        local entry = chatEntryTrace[i]
        out[#out + 1] = string.format("%s  %s  x%d  %s",
            entry.cleared and "PAST GUARD" or "bailed    ",
            entry.name,
            entry.count or 1,
            entry.event)
    end

    if #out == 0 then
        out[1] = "no chat entry points recorded yet"
    end

    return out
end

function ns.CanMutateChatPayload(eventName, msg, author, ...)
    -- Prat-style guard: decide before doing ANY string operation on the payload.
    if type(eventName) == "string" and ns.ShouldBypassWhisperMutation(eventName) then
        return false
    end

    if ns.HasSecretChatValue(msg, author, ...) then
        return false
    end

    if type(ns.CanAccessChatValue) == "function" and not ns.CanAccessChatValue(msg, author, ...) then
        return false
    end

    return type(msg) == "string" or type(msg) == "number"
end

function ns.GetMaxChatWindows()
    if type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS > 0 then
        return NUM_CHAT_WINDOWS
    end

    if Constants and Constants.ChatFrameConstants and type(Constants.ChatFrameConstants.MaxChatWindows) == "number" then
        return Constants.ChatFrameConstants.MaxChatWindows
    end

    return 10
end



-- =========================================================
-- 5a. CROSS-VERSION API COMPATIBILITY HELPERS
-- =========================================================
-- Based on the safer patterns used by Prat 3 and ElvUI: detect the project at
-- runtime, never assume a client-only API exists, and probe events before
-- registering them. These helpers are intentionally small and side-effect free.
local function SafeGlobalCall(func, ...)
    if type(func) ~= "function" then
        return false, nil
    end
    return pcall(func, ...)
end

-- CVars.
--
-- Modern Retail moved these into C_CVar and keeps the flat globals only as
-- deprecation shims; Classic has the flat globals and no namespace at all. Call
-- sites go through here so neither side is assumed to exist.
function ns.GetCVarCompat(name)
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        local ok, value = pcall(C_CVar.GetCVar, name)
        if ok then return value end
    end
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, name)
        if ok then return value end
    end
    return nil
end

function ns.SetCVarCompat(name, value)
    -- 12.1 added C_CVar.AreCVarsLoaded. A write issued before the CVar system is
    -- ready is dropped silently, which is exactly the window ApplyNativeTimestamps
    -- can land in during login. Where the probe exists, wait rather than lose it.
    if C_CVar and type(C_CVar.AreCVarsLoaded) == "function" then
        local okProbe, loaded = pcall(C_CVar.AreCVarsLoaded)
        if okProbe and not loaded then
            return false
        end
    end

    if C_CVar and type(C_CVar.SetCVar) == "function" then
        if pcall(C_CVar.SetCVar, name, value) then
            return true
        end
    end
    if type(SetCVar) == "function" then
        return pcall(SetCVar, name, value) and true or false
    end
    return false
end

-- Chat helper resolution.
--
-- Modern FrameXML moved a number of loose ChatFrame_* / ChatEdit_* helpers into
-- ChatFrameUtil (not every FCF_* helper moved; current FloatingChatFrame still
-- exposes several FCF_* globals). The flat global is preferred where it is still
-- real, because ElvUI, GW2_UI and Prat may hook it. ChatFrameUtil is the fallback
-- only for helpers Blizzard actually exposes there.
--
-- Successful routing is memoised, never the function object. A missing route is
-- deliberately NOT cached: Blizzard can load parts of the chat UI later in the
-- login sequence, and caching "missing" would permanently hide a feature that
-- becomes valid a few frames later.
local chatApiRoute = {}

function ns.GetChatAPI(legacyName, utilName)
    local key = tostring(legacyName) .. "/" .. tostring(utilName)
    local route = chatApiRoute[key]

    if route == nil then
        local util = _G.ChatFrameUtil
        if legacyName and type(_G[legacyName]) == "function" then
            route = "global"
        elseif utilName and type(util) == "table" and type(util[utilName]) == "function" then
            route = "util"
        else
            return nil, nil
        end
        chatApiRoute[key] = route
    end

    if route == "global" then
        local fn = legacyName and _G[legacyName]
        if type(fn) == "function" then
            return fn, nil
        end
        chatApiRoute[key] = nil
        return ns.GetChatAPI(legacyName, utilName)
    end

    if route == "util" then
        local util = _G.ChatFrameUtil
        if type(util) == "table" and type(util[utilName]) == "function" then
            return util[utilName], util
        end
        chatApiRoute[key] = nil
        return ns.GetChatAPI(legacyName, utilName)
    end

    return nil, nil
end

-- Blizzard's util namespaces are plain function tables rather than mixins, so
-- the namespace entries take no implicit self. Earlier call sites passed the
-- table through as the first argument, which made `text` the namespace itself
-- and would have broken every fallback path the moment the flat globals go
-- away. Plain style is tried first and the mixin form is kept as a one-shot
-- retry, memoised per function, so a future signature change cannot strand us.
local chatUtilCallStyle = {}

function ns.CallChatAPI(legacyName, utilName, ...)
    local fn, owner = ns.GetChatAPI(legacyName, utilName)
    if type(fn) ~= "function" then
        return false
    end

    if not owner then
        return pcall(fn, ...)
    end

    local key = tostring(utilName)
    if chatUtilCallStyle[key] == "method" then
        return pcall(fn, owner, ...)
    end

    local ok, result = pcall(fn, ...)
    if ok then
        chatUtilCallStyle[key] = "plain"
        return true, result
    end

    local okMethod, methodResult = pcall(fn, owner, ...)
    if okMethod then
        chatUtilCallStyle[key] = "method"
        return true, methodResult
    end

    return false
end

-- Operations owned by ChatFrameMixin are methods on the frame on current UI
-- builds. Keep legacy ChatFrame_* globals only for old compatibility targets;
-- do not route these through ChatFrameUtil, which does not own these methods.
function ns.CallChatFrameMethod(frame, methodName, legacyName, ...)
    if frame == nil or type(methodName) ~= "string" then
        return false
    end

    -- Frames are tables on current clients but older branches have exposed
    -- userdata-backed frame objects. Read the method defensively so the
    -- compatibility helper does not reject those clients before trying them.
    local okMethod, method = pcall(function() return frame[methodName] end)
    if okMethod and type(method) == "function" then
        return pcall(method, frame, ...)
    end

    local legacy = type(legacyName) == "string" and _G[legacyName] or nil
    if type(legacy) == "function" then
        return pcall(legacy, frame, ...)
    end

    return false
end

function ns.ResetChatAPICache()
    chatApiRoute = {}
    chatUtilCallStyle = {}
end

function ns.GetAddonMetadata(name, key)
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, name, key)
        if ok then return value end
    end
    if type(GetAddOnMetadata) == "function" then
        local ok, value = pcall(GetAddOnMetadata, name, key)
        if ok then return value end
    end
    return nil
end

function ns.IsAddOnLoadedCompat(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok then return loaded and true or false end
    end
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, name)
        if ok then return loaded and true or false end
    end
    return false
end

function ns.LoadAddOnCompat(name)
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        local ok, loadedOrReason = pcall(C_AddOns.LoadAddOn, name)
        return ok and loadedOrReason ~= false, loadedOrReason
    end
    if type(LoadAddOn) == "function" then
        local ok, loadedOrReason = pcall(LoadAddOn, name)
        return ok and loadedOrReason ~= false, loadedOrReason
    end
    return false, "missing LoadAddOn API"
end

-- Friend-list compatibility. Current Retail, Era, TBC Anniversary and MoP
-- expose C_FriendList.GetFriendInfo(name); older retired Classic branches may only
-- have the indexed global GetFriendInfo. Keep that legacy path isolated here so
-- feature modules never call a removed global with the modern name-based signature.
function ns.GetFriendInfoByNameCompat(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    if type(C_FriendList) == "table" and type(C_FriendList.GetFriendInfo) == "function" then
        local ok, info = pcall(C_FriendList.GetFriendInfo, name)
        if ok and type(info) == "table" and type(info.name) == "string" then
            return info
        end
    end


    if type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
        local okCount, count = pcall(GetNumFriends)
        if okCount and type(count) == "number" then
            local wanted = name:match("^[^-]+") or name
            for index = 1, count do
                local okInfo, friendName, level, className, area, connected, status, notes, rafLinkType, guid = pcall(GetFriendInfo, index)
                if okInfo and type(friendName) == "string" then
                    local short = friendName:match("^[^-]+") or friendName
                    if friendName == name or short == wanted then
                        return {
                            name = friendName, level = level, className = className, area = area,
                            connected = connected, status = status, notes = notes, rafLinkType = rafLinkType, guid = guid,
                        }
                    end
                end
            end
        end
    end

    return nil
end

function ns.IsFriendCompat(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    -- C_FriendList.IsFriend expects a player GUID, not a character name. Using it
    -- with CHAT_MSG_* sender names is therefore the wrong modern replacement for
    -- the old friend lookup. GetFriendInfo(name) is the current name-based API and
    -- already tells us whether the character exists in the friend list.
    return ns.GetFriendInfoByNameCompat(name) ~= nil
end


local addonCompatibilityCache
local CHATIFY_COMPAT_ADDONS = {
    chattynator = { "Chattynator" },
    prat = { "Prat-3.0", "Prat" },
    elvui = { "ElvUI" },
    gw2ui = { "GW2_UI" },
    glass = { "Glass" },
    chatter = { "Chatter" },
    basicChatMods = { "BasicChatMods" },
}

function ns.ResetAddonCompatibilityCache()
    addonCompatibilityCache = nil
end

local function IsAnyCompatAddonLoaded(names)
    if type(names) ~= "table" then
        return false
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" and ns.IsAddOnLoadedCompat(name) then
            return true
        end
    end
    return false
end

function ns.GetChatAddonCompatibilityState()
    if addonCompatibilityCache then
        return addonCompatibilityCache
    end

    local state = {
        chattynator = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.chattynator),
        prat = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.prat),
        elvui = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.elvui),
        gw2ui = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.gw2ui),
        glass = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.glass),
        chatter = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.chatter),
        basicChatMods = IsAnyCompatAddonLoaded(CHATIFY_COMPAT_ADDONS.basicChatMods),
    }

    state.chatReplacement = state.chattynator or state.glass
    state.layoutSensitive = state.chatReplacement or state.prat or state.elvui or state.gw2ui or state.chatter or state.basicChatMods
    state.safeQuickButtonMode = state.chatReplacement and "detached" or "native"
    state.signature = table.concat({
        state.chattynator and "chattynator" or "-",
        state.prat and "prat" or "-",
        state.elvui and "elvui" or "-",
        state.gw2ui and "gw2ui" or "-",
        state.glass and "glass" or "-",
        state.chatter and "chatter" or "-",
        state.basicChatMods and "basicchatmods" or "-",
        state.safeQuickButtonMode,
    }, ":")

    addonCompatibilityCache = state
    return state
end

function ns.IsChatReplacementLoaded()
    local state = ns.GetChatAddonCompatibilityState()
    return state and state.chatReplacement or false
end

function ns.GetAddonCompatibilitySignature()
    local state = ns.GetChatAddonCompatibilityState()
    return state and state.signature or "none"
end

function ns.IncrementRuntimeCounter(key)
    ns.Runtime = ns.Runtime or { errors = {}, counters = {} }
    ns.Runtime.counters = ns.Runtime.counters or {}
    key = tostring(key or "unknown")
    ns.Runtime.counters[key] = (ns.Runtime.counters[key] or 0) + 1
    return ns.Runtime.counters[key]
end

-- The build interface cannot change while the client is running, but this sits in
-- the chat hot path (reached for every message, once per chat frame the event is
-- registered on), so the pcall is done once and the answer reused.
local cachedBuildInterface

function ns.GetBuildInterface()
    if cachedBuildInterface ~= nil then
        return cachedBuildInterface
    end

    cachedBuildInterface = 0
    if type(GetBuildInfo) == "function" then
        local ok, _, _, _, interfaceVersion = pcall(GetBuildInfo)
        if ok and type(interfaceVersion) == "number" then
            cachedBuildInterface = interfaceVersion
        end
    end

    return cachedBuildInterface
end

function ns.IsForeverClient()
    return IsForeverLoadTarget()
end

function ns.GetProjectKey()
    -- Product identity is resolved from the most specific signal first.
    -- Forever must beat WOW_PROJECT_MAINLINE, and current progression clients can
    -- reuse an older WOW_PROJECT_* identity. Interface ranges therefore beat the
    -- project constants for every packaging target, not only Forever/Titan.
    if ns.IsForeverClient() then return "forever" end

    local interfaceVersion = ns.GetBuildInterface()
    if interfaceVersion >= 120000 then return "retail" end
    if interfaceVersion >= 50500 and interfaceVersion < 50600 then return "mists" end
    if interfaceVersion >= 40400 and interfaceVersion < 40500 then return "cata" end
    if interfaceVersion >= 38000 and interfaceVersion < 38100 then return "titan" end
    if interfaceVersion >= 30400 and interfaceVersion < 30500 then return "wrath" end
    if interfaceVersion >= 20500 and interfaceVersion < 20600 then return "tbc" end
    if interfaceVersion >= 11500 and interfaceVersion < 11600 then return "vanilla" end

    -- Fallback for unusual/test clients where GetBuildInfo is unavailable or a
    -- future Interface range is not known yet.
    local project = WOW_PROJECT_ID
    if WOW_PROJECT_MAINLINE and project == WOW_PROJECT_MAINLINE then return "retail" end
    if WOW_PROJECT_MISTS_CLASSIC and project == WOW_PROJECT_MISTS_CLASSIC then return "mists" end
    if WOW_PROJECT_CATACLYSM_CLASSIC and project == WOW_PROJECT_CATACLYSM_CLASSIC then return "cata" end
    if WOW_PROJECT_WRATH_CLASSIC and project == WOW_PROJECT_WRATH_CLASSIC then return "wrath" end
    if WOW_PROJECT_BURNING_CRUSADE_CLASSIC and project == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then return "tbc" end
    if WOW_PROJECT_CLASSIC and project == WOW_PROJECT_CLASSIC then return "vanilla" end

    -- Preserve pre-Midnight Retail compatibility when an older mainline build is
    -- used for testing and exposes neither a known current range nor project ID.
    if interfaceVersion >= 100000 then return "retail" end
    return "unknown"
end

function ns.IsMainlineClient()
    return ns.GetProjectKey() == "retail"
end

-- Capability helper: Forever is a separate game flavor, but it uses the modern
-- Mainline UI/API architecture. Use this for frame/API choices; use
-- IsForeverClient/GetProjectKey when actual game identity matters.
function ns.UsesMainlineUI()
    local key = ns.GetProjectKey()
    return key == "retail" or key == "forever"
end

function ns.IsClassicClient()
    local key = ns.GetProjectKey()
    return key ~= "retail" and key ~= "forever" and key ~= "unknown"
end

-- =========================================================
-- 5b. PER-CLIENT CAPABILITY MODEL
-- =========================================================
-- Identity and capability are deliberately separate. Current Classic clients
-- inherit a surprising amount of modern API surface (C_AddOns, C_ChatInfo,
-- C_BattleNet, C_Secrets, GetMouseFoci), while Forever identifies like Mainline
-- at runtime. Feature code should therefore ask for a capability, not guess from
-- expansion names or interface numbers.
local FEATURE_SUPPORTED = "supported"
local FEATURE_WARNING = "warning"
local FEATURE_UNAVAILABLE = "unavailable"

ns.FEATURE_SUPPORTED = FEATURE_SUPPORTED
ns.FEATURE_WARNING = FEATURE_WARNING
ns.FEATURE_UNAVAILABLE = FEATURE_UNAVAILABLE

local CLIENT_DISPLAY_NAMES = {
    retail = "Retail / Midnight",
    forever = "World of Warcraft: Forever",
    vanilla = "Classic Era",
    tbc = "Burning Crusade Classic Anniversary",
    mists = "Mists of Pandaria Classic",
    titan = "Titan Reforged / Wrath progression",
    wrath = "Wrath Classic (legacy target)",
    cata = "Cataclysm Classic (legacy target)",
    unknown = "Unknown WoW client",
}

function ns.GetClientDisplayName()
    local key = ns.GetProjectKey()
    return CLIENT_DISPLAY_NAMES[key] or CLIENT_DISPLAY_NAMES.unknown
end

function ns.GetClientSupportTier()
    local key = ns.GetProjectKey()
    if key == "forever" then
        return "beta"
    end
    if key == "wrath" or key == "cata" then
        return "legacy"
    end
    if key == "retail" or key == "vanilla" or key == "tbc" or key == "mists" or key == "titan" then
        return "current"
    end
    return "unknown"
end

function ns.IsLegacyCompatibilityTarget()
    local key = ns.GetProjectKey()
    return key == "wrath" or key == "cata"
end

local function HasOutgoingChatAPI()
    return (type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function")
        or type(SendChatMessage) == "function"
end

local function HasBNetWhisperAPI()
    return (type(C_BattleNet) == "table" and type(C_BattleNet.SendWhisper) == "function")
        or type(BNSendWhisper) == "function"
end

local function HasMessageFilterAPI()
    local fn = ns.GetChatAPI and select(1, ns.GetChatAPI("ChatFrame_AddMessageEventFilter", "AddMessageEventFilter"))
    return type(fn) == "function"
end

local function HasPostRenderSpamRemovalAPI()
    if type(ns.HasSecureSpamRemovalAPI) == "function" then
        local ok, available = pcall(ns.HasSecureSpamRemovalAPI)
        if ok and available then return true end
    end

    local candidates = { SELECTED_CHAT_FRAME, DEFAULT_CHAT_FRAME, _G and _G.ChatFrame1 }
    for i = 1, #candidates do
        local frame = candidates[i]
        if type(frame) == "table"
            and type(frame.RemoveMessagesByPredicate) == "function"
            and type(hooksecurefunc) == "function" then
            return true
        end
    end
    return false
end

local function HasNativeChatSelectionAPI()
    local candidates = { SELECTED_CHAT_FRAME, DEFAULT_CHAT_FRAME, _G and _G.ChatFrame1 }
    for i = 1, #candidates do
        local frame = candidates[i]
        if type(frame) == "table" and type(frame.SetTextCopyable) == "function" then
            return true
        end
    end
    return false
end

local function HasChatTabManagementAPI()
    -- FCF_OpenNewWindow and GetChatWindowInfo are still global in current FrameXML.
    -- ChatFrameUtil has helpers around windows, but no OpenNewWindow replacement.
    return type(_G.FCF_OpenNewWindow) == "function"
        and type(_G.GetChatWindowInfo) == "function"
end

local function HasChatEditRoutingAPI()
    local openChat = ns.GetChatAPI and select(1, ns.GetChatAPI("ChatFrame_OpenChat", "OpenChat"))
    local parseText = type(_G.ChatEdit_ParseText) == "function"
        or (type(_G.ChatFrameEditBoxMixin) == "table" and type(_G.ChatFrameEditBoxMixin.ParseText) == "function")
        or (type(_G.ChatFrameEditBoxMixinBase) == "table" and type(_G.ChatFrameEditBoxMixinBase.ParseText) == "function")
        or (type(_G.ChatFrameEditBoxBaseMixin) == "table" and type(_G.ChatFrameEditBoxBaseMixin.ParseText) == "function")
    return type(openChat) == "function" and parseText
end

function ns.GetFeatureSupport(feature)
    local secretRestricted = type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()

    if feature == "securityControls" then
        return secretRestricted and FEATURE_WARNING or FEATURE_UNAVAILABLE
    elseif feature == "virtualChat" then
        return secretRestricted and FEATURE_UNAVAILABLE or FEATURE_SUPPORTED
    elseif feature == "spamFilters" then
        if not HasMessageFilterAPI() and not HasPostRenderSpamRemovalAPI() then
            return FEATURE_UNAVAILABLE
        end
        -- Protected clients prefer Filter Engine 3.0's post-render removal path
        -- when message-event filters are intentionally detached for taint safety.
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "mentions" then
        if secretRestricted then
            local canRender = type(ns.CanReplaceChatFrameAddMessage) == "function" and ns.CanReplaceChatFrameAddMessage()
            local canPostRender = type(ns.HasSecurePostRenderAPI) == "function" and ns.HasSecurePostRenderAPI()
            if not canRender and not canPostRender and not HasMessageFilterAPI() then
                return FEATURE_UNAVAILABLE
            end
            return FEATURE_WARNING
        end
        return HasMessageFilterAPI() and FEATURE_SUPPORTED or FEATURE_UNAVAILABLE
    elseif feature == "history" or feature == "copy" then
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "nativeCopy" then
        return HasNativeChatSelectionAPI() and FEATURE_SUPPORTED or FEATURE_UNAVAILABLE
    elseif feature == "autoReplyWhisper" then
        if not HasOutgoingChatAPI() then
            return FEATURE_UNAVAILABLE
        end
        -- Chatify intentionally does not subscribe to whisper payloads on a client
        -- that can make their sender/message secret. Do not expose settings that
        -- cannot work there.
        return secretRestricted and FEATURE_UNAVAILABLE or FEATURE_SUPPORTED
    elseif feature == "autoReplyBNet" then
        if not HasBNetWhisperAPI() then
            return FEATURE_UNAVAILABLE
        end
        return secretRestricted and FEATURE_UNAVAILABLE or FEATURE_SUPPORTED
    elseif feature == "autoReplyGuild" then
        if not HasOutgoingChatAPI() then
            return FEATURE_UNAVAILABLE
        end
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "autoReply" then
        local whisper = ns.GetFeatureSupport("autoReplyWhisper")
        local bnet = ns.GetFeatureSupport("autoReplyBNet")
        local guild = ns.GetFeatureSupport("autoReplyGuild")
        if whisper == FEATURE_UNAVAILABLE and bnet == FEATURE_UNAVAILABLE and guild == FEATURE_UNAVAILABLE then
            return FEATURE_UNAVAILABLE
        end
        if whisper == FEATURE_WARNING or bnet == FEATURE_WARNING or guild == FEATURE_WARNING or secretRestricted then
            return FEATURE_WARNING
        end
        return FEATURE_SUPPORTED
    elseif feature == "quickButtons" then
        if type(CreateFrame) ~= "function" or not HasChatEditRoutingAPI() then
            return FEATURE_UNAVAILABLE
        end
        return FEATURE_SUPPORTED
    elseif feature == "composer" then
        if not HasOutgoingChatAPI() or type(CreateFrame) ~= "function" then
            return FEATURE_UNAVAILABLE
        end
        -- User-authored composer text is safe to inspect, but modern protected
        -- clients can temporarily block addon-initiated sends. Keep the tool
        -- available and warn rather than hiding it.
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "composerAutomation" then
        if ns.GetFeatureSupport("composer") == FEATURE_UNAVAILABLE then
            return FEATURE_UNAVAILABLE
        end
        local hasTimer = (type(C_Timer) == "table" and type(C_Timer.After) == "function")
            or type(CreateFrame) == "function"
        if not hasTimer then
            return FEATURE_UNAVAILABLE
        end
        -- Automatic queue sends must still obey chat lockdown and per-channel
        -- hardware-event restrictions. Keep the controls visible with a warning
        -- on protected clients rather than pretending every channel can be timed.
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "channels" then
        if type(GetChannelList) ~= "function" then
            return FEATURE_UNAVAILABLE
        end
        return secretRestricted and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "sounds" then
        return type(PlaySoundFile) == "function" and FEATURE_SUPPORTED or FEATURE_UNAVAILABLE
    elseif feature == "chatTabs" then
        if not HasChatTabManagementAPI() then
            return FEATURE_UNAVAILABLE
        end
        return ns.IsLegacyCompatibilityTarget() and FEATURE_WARNING or FEATURE_SUPPORTED
    elseif feature == "communities" then
        return type(C_Club) == "table" and FEATURE_SUPPORTED or FEATURE_UNAVAILABLE
    end

    return FEATURE_SUPPORTED
end

function ns.IsFeatureAvailable(feature)
    return ns.GetFeatureSupport(feature) ~= FEATURE_UNAVAILABLE
end

function ns.IsFeatureRisky(feature)
    return ns.GetFeatureSupport(feature) == FEATURE_WARNING
end

local FEATURE_WARNING_TEXT = {
    channels = "Some protected chat lines cannot be renamed. Chatify skips them safely.",
    spamFilters = "Filter Engine 3.0 removes readable matched lines through the safest available path. Blizzard-protected/secret payloads are skipped rather than forced open.",
    mentions = "Protected messages may not be highlighted. Chatify skips them instead of forcing access.",
    history = "Protected messages cannot be saved. Readable messages are stored normally.",
    copy = "Protected messages cannot be copied. Readable messages remain available.",
    autoReply = "Whisper and Battle.net auto replies are disabled while protected chat is active.",
    composer = "WoW may temporarily block addon chat sends during protected activities. The composer stays available and sends only when the client allows it.",
    composerAutomation = "Automatic queue sending pauses when WoW requires a hardware click or blocks addon chat. Manual sending remains available.",
    autoReplyGuild = "Guild auto replies pause while Blizzard blocks addon chat.",
    chatTabs = "This older WoW client uses compatibility mode. Some tab actions may be unavailable.",
}

function ns.GetFeatureWarningText(feature)
    if not ns.IsFeatureRisky(feature) then
        return nil
    end
    return FEATURE_WARNING_TEXT[feature]
end

function ns.GetClientCompatibilityNotice()
    local key = ns.GetProjectKey()
    if key == "forever" then
        return "Forever is supported as a separate client. Because it is beta, some chat APIs may change between builds."
    end
    if key == "wrath" or key == "cata" then
        return "This older WoW client uses compatibility mode. Unsupported options are hidden automatically."
    end
    return nil
end

function ns.GetSelectedChatFrame()
    if SELECTED_CHAT_FRAME then return SELECTED_CHAT_FRAME end
    if _G and _G.GeneralDockManager and _G.GeneralDockManager.selected then
        return _G.GeneralDockManager.selected
    end
    local ok, frame = ns.CallChatAPI("FCF_GetCurrentChatFrame", "GetCurrentChatFrame")
    if ok and frame then return frame end
    return DEFAULT_CHAT_FRAME or _G.ChatFrame1
end

function ns.GetChatFrameByID(id)
    id = tonumber(id)
    if not id then return nil end
    return _G and _G["ChatFrame" .. id] or nil
end

function ns.GetChatEditBox(chatFrame)
    if chatFrame and chatFrame.editBox then return chatFrame.editBox end
    if chatFrame and type(chatFrame.GetName) == "function" then
        local ok, name = pcall(chatFrame.GetName, chatFrame)
        if ok and name and _G[name .. "EditBox"] then return _G[name .. "EditBox"] end
    end
    if ChatFrame1EditBox then return ChatFrame1EditBox end
    return nil
end

function ns.ChatFrameOpenChat(text, chatFrame)
    if ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", text or "", chatFrame) then
        return true
    end
    local editBox = ns.GetChatEditBox(chatFrame or ns.GetSelectedChatFrame())
    if editBox and type(editBox.SetText) == "function" and type(editBox.Show) == "function" then
        pcall(editBox.Show, editBox)
        pcall(editBox.SetText, editBox, text or "")
        pcall(editBox.SetFocus, editBox)
        return true
    end
    return false
end

function ns.RegisterEventIfSupported(target, eventName, method)
    if not target or type(target.RegisterEvent) ~= "function" then
        return false
    end

    if not ns.IsEventSupported(eventName) then
        return false
    end

    local ok = pcall(target.RegisterEvent, target, eventName, method)
    return ok and true or false
end

function ns.RegisterEventsIfSupported(target, events, method)
    local count = 0
    if type(events) ~= "table" then return count end
    for i = 1, #events do
        if ns.RegisterEventIfSupported(target, events[i], method) then
            count = count + 1
        end
    end
    return count
end

function ns.SafeSecureHook(module, target, method, callback)
    if not module or type(callback) ~= "function" or type(module.SecureHook) ~= "function" then
        return false
    end

    local ok
    if type(target) == "string" then
        if type(_G[target]) ~= "function" then return false end
        if type(module.IsHooked) == "function" and module:IsHooked(target) then return true end
        ok = pcall(module.SecureHook, module, target, callback)
    elseif type(target) == "table" and type(method) == "string" then
        if type(target[method]) ~= "function" then return false end
        if type(module.IsHooked) == "function" and module:IsHooked(target, method) then return true end
        ok = pcall(module.SecureHook, module, target, method, callback)
    else
        return false
    end
    return ok and true or false
end

-- =========================================================
-- 6. SAFE TEXT HELPERS (WoW 12.0.x / Secret Values)
-- =========================================================
local tostring = tostring
local pcall = pcall
local type = type
local select = select
local canaccessvalue = canaccessvalue
local issecretvalue = issecretvalue

function ns.IsSecretValue(value)
    if type(issecretvalue) ~= "function" then
        issecretvalue = _G.issecretvalue
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok then
            return secret and true or false
        end
    end

    -- Some beta/runtime combinations expose only the batch inspector. Use it as
    -- a fallback so a missing scalar helper never turns a secret value into text.
    if type(hasAnySecretValues) ~= "function" then
        hasAnySecretValues = _G.hasanysecretvalues
    end
    if type(hasAnySecretValues) == "function" then
        local ok, secret = pcall(hasAnySecretValues, value)
        if ok then
            return secret and true or false
        end
    end

    return false
end

function ns.IsProtectedChatValue(value)
    if ns.IsSecretValue(value) then
        return true
    end

    -- Do not call canaccessvalue() for every ordinary chat string when the scalar
    -- secret inspector is available; that produced false positives on modern WoW.
    -- It is only a fail-closed fallback for protected clients where the scalar
    -- inspector is missing or failed to load.
    if type(canaccessvalue) ~= "function" then
        canaccessvalue = _G.canaccessvalue
    end
    if type(issecretvalue) ~= "function"
        and ns.IsModernSecretValueBuild()
        and type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok then
            return true
        end
        if accessible == false then
            return true
        end
    end

    return false
end


-- Central outgoing chat wrapper shared by composer and reply features.
-- User-authored strings are validated before they reach Blizzard, and modern
-- clients are checked for messaging lockdown immediately before the send.
function ns.SendChatMessageCompat(message, chatType, languageID, target)
    if type(chatType) ~= "string" or chatType == "" then
        return false, "invalid chat type"
    end

    -- Blizzard explicitly allows an empty payload for AFK/DND to clear the state.
    local mayBeEmpty = chatType == "AFK" or chatType == "DND"
    if type(message) ~= "string" or (message == "" and not mayBeEmpty) then
        return false, "invalid message"
    end
    if ns.IsProtectedChatValue(message) then
        return false, "protected message"
    end
    if languageID ~= nil and type(languageID) ~= "number" then
        return false, "invalid language"
    end
    if target ~= nil then
        if ns.IsProtectedChatValue(target) then
            return false, "protected target"
        end
        if chatType == "CHANNEL" then
            local channel = tonumber(target)
            if not channel or channel <= 0 or channel % 1 ~= 0 then
                return false, "invalid channel target"
            end
            target = channel
        elseif type(target) ~= "string" or target == "" then
            return false, "invalid target"
        end
    end
    if type(ns.CanSendAddonChat) == "function" and not ns.CanSendAddonChat() then
        return false, "chat messaging lockdown"
    end

    if type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function" then
        local ok, err = pcall(C_ChatInfo.SendChatMessage, message, chatType, languageID, target)
        if ok then return true end
        if type(SendChatMessage) ~= "function" then
            return false, err
        end
    end

    if type(SendChatMessage) == "function" then
        local ok, err = pcall(SendChatMessage, message, chatType, languageID, target)
        if ok then return true end
        return false, err
    end

    return false, "chat send API unavailable"
end

function ns.EnforceRetailSafeMode(db)
    if not db or not ns.IsRetailSecretValueBuild() then
        return false
    end

    -- Runtime-only safe mode for any client that reports active secret-value restrictions.
    -- Do NOT rewrite user preferences here, otherwise the same SavedVariables
    -- stay crippled when the addon is loaded on older Retail clients.
    return true
end

function ns.GetRetailSafeModeStatus(db)
    local active = type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
    local status = {
        active = active and true or false,
        history = "available",
        virtualChat = "available",
        whisperAutoReply = "available",
        nativeCopy = "recommended",
    }

    if active then
        status.history = "readable messages only"
        status.virtualChat = "disabled while secret-value restrictions are active"
        status.whisperAutoReply = "hidden on this client for secret-value safety"
        status.nativeCopy = "recommended when available"
    elseif db and db.copyNativeSelection == false then
        status.nativeCopy = "optional"
    end

    return status
end


-- =========================================================
-- 6b. PLAYER NAME / SURNAME IDENTITY (WoW: Forever)
-- =========================================================
--
-- Forever uses a required two-part character name in a realmless namespace.
-- The public addon API currently exposes a surname-display predicate but no
-- documented GetFirstName()/GetSurname() pair. Read the least-modified identity
-- string the client provides, then split only on the Forever flavor.
--
-- UnitNameUnmodified is preferred because Blizzard's unit/name code uses it for
-- the canonical player identity. C_PlayerInfo.GetName is kept as a modern API
-- fallback, followed by UnitFullName and UnitName for beta/client drift.

local playerMentionIdentityCache
local playerMentionIdentityCachedAt = 0

local function TrimIdentityPart(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if type(ns.IsProtectedChatValue) == "function" and ns.IsProtectedChatValue(value) then
        return nil
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("%s+", " ")
    if value == "" then
        return nil
    end
    return value
end

local function CanonicalIdentityText(value)
    value = TrimIdentityPart(value)
    if not value then
        return nil
    end
    -- Forever's canonical/unit representation can use First-Surname while the
    -- visible UI uses First Surname. Treat those two separators as equivalent.
    value = value:gsub("%s*%-%s*", " ")
    value = value:gsub("%s+", " ")
    return string.lower(value)
end

local function AddIdentityCandidate(candidates, source, primary, secondary)
    primary = TrimIdentityPart(primary)
    secondary = TrimIdentityPart(secondary)
    if not primary then
        return
    end
    candidates[#candidates + 1] = {
        source = source,
        primary = primary,
        secondary = secondary,
    }
end

local function SplitForeverIdentity(primary, secondary)
    primary = TrimIdentityPart(primary)
    secondary = TrimIdentityPart(secondary)
    if not primary then
        return nil, nil, nil
    end

    local first, surname

    -- Visible form: "Sebas Moonbloom".
    first, surname = primary:match("^([^%s]+)%s+(.+)$")
    if not first then
        -- Canonical/unit form seen by current Forever tooling:
        -- "Sebas-Moonbloom". Forever is realmless, so the second component is
        -- not a realm suffix on this client.
        first, surname = primary:match("^([^%-]+)%-(.+)$")
    end

    if not first and secondary then
        -- Some unit APIs traditionally return (name, realm). On Forever there is
        -- no realm identity, so a second non-empty name component is a useful
        -- compatibility fallback if a beta build chooses to expose the surname
        -- there instead of joining it into the first return.
        first = primary
        surname = secondary
    end

    first = TrimIdentityPart(first or primary)
    surname = TrimIdentityPart(surname)

    if surname then
        return first, surname, first .. " " .. surname
    end
    return first, nil, primary
end

function ns.RefreshPlayerMentionIdentity()
    playerMentionIdentityCache = nil
    playerMentionIdentityCachedAt = 0
end

function ns.GetPlayerMentionIdentity(forceRefresh)
    if forceRefresh then
        playerMentionIdentityCache = nil
        playerMentionIdentityCachedAt = 0
    end
    if playerMentionIdentityCache then
        local complete = not playerMentionIdentityCache.isForever or playerMentionIdentityCache.surname ~= nil
        if complete then
            return playerMentionIdentityCache
        end

        -- Character identity can be incomplete for a moment during login. Retry
        -- an incomplete Forever result periodically instead of pinning the first
        -- name forever, but avoid re-running four API probes for every chat line.
        local now = type(GetTime) == "function" and GetTime() or 0
        if now <= 0 or (now - playerMentionIdentityCachedAt) < 2 then
            return playerMentionIdentityCache
        end
        playerMentionIdentityCache = nil
    end

    local identity = {
        isForever = type(ns.IsForeverClient) == "function" and ns.IsForeverClient() or false,
        first = nil,
        surname = nil,
        full = nil,
        canonical = nil,
        aliases = {},
        source = "unavailable",
        hasSurnameDisplayAPI = type(C_PlayerInfo) == "table"
            and type(C_PlayerInfo.ShouldDisplaySurname) == "function",
        shouldDisplaySurname = nil,
    }

    if identity.hasSurnameDisplayAPI then
        local ok, value = pcall(C_PlayerInfo.ShouldDisplaySurname)
        if not ok then
            -- Keep this as a compatibility probe only. If the beta changes the
            -- signature, trying the local player token is harmless and lets the
            -- diagnostics reveal the result without making matching depend on it.
            ok, value = pcall(C_PlayerInfo.ShouldDisplaySurname, "player")
        end
        if ok and type(value) == "boolean" then
            identity.shouldDisplaySurname = value
        end
    end

    local candidates = {}

    if type(UnitNameUnmodified) == "function" then
        local ok, a, b = pcall(UnitNameUnmodified, "player")
        if ok then
            AddIdentityCandidate(candidates, "UnitNameUnmodified", a, b)
        end
    end

    if type(C_PlayerInfo) == "table" and type(C_PlayerInfo.GetName) == "function" then
        local ok, value = pcall(C_PlayerInfo.GetName, { unit = "player" })
        if ok then
            AddIdentityCandidate(candidates, "C_PlayerInfo.GetName", value, nil)
        end
    end

    if type(UnitFullName) == "function" then
        local ok, a, b = pcall(UnitFullName, "player")
        if ok then
            AddIdentityCandidate(candidates, "UnitFullName", a, b)
        end
    end

    if type(UnitName) == "function" then
        local ok, a, b = pcall(UnitName, "player")
        if ok then
            AddIdentityCandidate(candidates, "UnitName", a, b)
        end
    end

    local best
    for i = 1, #candidates do
        local candidate = candidates[i]
        local first, surname, full
        if identity.isForever then
            first, surname, full = SplitForeverIdentity(candidate.primary, candidate.secondary)
        else
            first = candidate.primary
            full = candidate.primary
        end

        if first then
            local parsed = {
                first = first,
                surname = surname,
                full = full,
                source = candidate.source,
            }
            if not best or (surname and not best.surname) then
                best = parsed
            end
            if surname then
                break
            end
        end
    end

    if best then
        identity.first = best.first
        identity.surname = best.surname
        identity.full = best.full
        identity.source = best.source
        identity.canonical = CanonicalIdentityText(best.full or best.first)

        local seen = {}
        local function addAlias(value)
            value = TrimIdentityPart(value)
            if not value then
                return
            end
            -- Keep the visible-space and canonical-hyphen full-name forms as
            -- separate aliases; they compare as the same identity but can both
            -- appear literally in chat payloads.
            local key = string.lower(value:gsub("%s+", " "))
            if seen[key] then
                return
            end
            seen[key] = true
            identity.aliases[#identity.aliases + 1] = value
        end

        if identity.isForever and best.surname then
            -- Longest forms first so "Sebas Moonbloom" is highlighted as one
            -- mention instead of two nested/adjacent matches.
            addAlias(best.first .. " " .. best.surname)
            addAlias(best.first .. "-" .. best.surname)
            addAlias(best.first)
            addAlias(best.surname)
        else
            addAlias(best.full or best.first)
        end

        playerMentionIdentityCache = identity
        playerMentionIdentityCachedAt = type(GetTime) == "function" and GetTime() or 0
    end

    return identity
end

function ns.GetPlayerMentionAliases()
    local identity = ns.GetPlayerMentionIdentity()
    return identity and identity.aliases or {}, identity
end

function ns.IsPlayerMentionIdentityText(value)
    local canonical = CanonicalIdentityText(value)
    if not canonical then
        return false
    end

    local identity = ns.GetPlayerMentionIdentity()
    if not identity then
        return false
    end

    if identity.canonical == canonical then
        return true
    end

    for i = 1, #(identity.aliases or {}) do
        if CanonicalIdentityText(identity.aliases[i]) == canonical then
            return true
        end
    end
    return false
end


local eventSupportCache = {}
local eventProbeFrame
local messageFilterRegistry = {}

function ns.IsEventSupported(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return false
    end

    if eventSupportCache[eventName] ~= nil then
        return eventSupportCache[eventName]
    end

    if type(CreateFrame) ~= "function" then
        eventSupportCache[eventName] = false
        return false
    end

    eventProbeFrame = eventProbeFrame or CreateFrame("Frame")
    local ok = pcall(eventProbeFrame.RegisterEvent, eventProbeFrame, eventName)
    if ok then
        pcall(eventProbeFrame.UnregisterEvent, eventProbeFrame, eventName)
    end

    eventSupportCache[eventName] = ok and true or false
    return eventSupportCache[eventName]
end

-- 12.0+ TAINT WINDOW.
--
-- Secret values only block operations on a *tainted* execution path, and chat
-- payloads only carry secrets while chat messaging lockdown is active (encounters,
-- Mythic+, rated PvP). Outside that window there is nothing to taint and filters
-- behave exactly as they always have.
--
-- Inside the window a Chatify filter closure sitting on Blizzard's chat dispatch
-- can taint it and the shared state ChatHistory_GetAccessID/GetToken writes into,
-- which is what produces "string conversion on a secret string value" — often on a
-- later, unrelated event such as MONSTER_SAY.
--
-- So instead of disabling filters outright, Chatify withdraws them for the duration
-- of the lockdown and reinstalls them the moment it ends. Spam filtering, keyword
-- highlighting and link formatting keep working during normal play.
-- Resolved retail filter mode: "full", "lockdown" or "off". Always "full" on
-- clients without secret values, where none of this applies.
function ns.GetRetailChatFilterMode()
    if not ns.IsRetailSecretValueBuild() then
        return "full"
    end

    local db = ns.db
    local addon = ns.Chatify
    if addon and addon.db and addon.db.profile then
        db = addon.db.profile
    end
    if not db then
        -- Module enable can happen before AceDB attaches the profile. On protected
        -- clients, fail closed instead of briefly installing message filters.
        return "off"
    end

    local mode = db.retailChatFilterMode
    if mode == nil and db.retailDisableChatFilters ~= nil then
        mode = db.retailDisableChatFilters and "off" or "lockdown"
    end

    if mode == "full" or mode == "off" then
        return mode
    end

    -- Runtime-only downgrade of the shipped default on secret-value builds.
    --
    -- "lockdown" cannot actually protect chat there (see ns.InChatTaintRiskWindow):
    -- by the time the encounter starts, a filter that ran in the open world has
    -- already tainted Blizzard's chat dispatch, and the symptom is that no player
    -- message is rendered for the whole encounter or key. Users who explicitly pick
    -- Balanced keep it; nobody gets it by accident.
    --
    -- Resolved at read time rather than written back to the profile, so the same
    -- SavedVariables stay intact on Classic and pre-12 Retail.
    if ns.IsRetailSecretValueBuild() and not db.retailChatFilterModeUserSet then
        return "off"
    end

    return "lockdown"
end

function ns.CanUseMessageEventFilters()
    if not ns.IsRetailSecretValueBuild() then
        return true
    end

    -- Resolved inline rather than through a helper: this runs during module enable,
    -- before the saved variables are necessarily attached, so every step has to
    -- tolerate a missing db. ns.Chatify is the AceAddon object; note that there is
    -- no global named Chatify, so it must be reached through the namespace.
    local db = ns.db
    local addon = ns.Chatify
    if addon and addon.db and addon.db.profile then
        db = addon.db.profile
    end

    if not db then
        -- Secret-value clients must not install filters before the profile (and
        -- therefore the user's explicit mode) is available.
        return false
    end

    local mode = db.retailChatFilterMode
    -- Migrate the 0.11.18-0.11.20 boolean.
    if mode == nil and db.retailDisableChatFilters ~= nil then
        mode = db.retailDisableChatFilters and "off" or "lockdown"
        db.retailChatFilterMode = mode
        db.retailDisableChatFilters = nil
    end

    -- Route the remaining decision through GetRetailChatFilterMode so the
    -- secret-value downgrade of the "lockdown" default is applied in exactly one
    -- place. Anything that is not an explicit "full" is gated on the risk window.
    if mode ~= "full" then
        mode = ns.GetRetailChatFilterMode()
    end

    if mode == "off" then
        return false
    end

    if mode == "full" then
        return true
    end

    return not ns.InChatTaintRiskWindow()
end

-- Whether Chatify may replace frame.AddMessage on Blizzard's chat frames.
--
-- This is a harder question than the filter one, and it has to be answered
-- separately, because the two taints do not land in the same place.
--
--     660:  local msg = MessageFormatter(arg1)
--     661:  local accessID = ChatHistory_GetAccessID(...)
--     667:  self:AddMessage(msg, ..., accessID, typeID, event, eventArgs, ...)
--     672:  ChatFrameUtil.SetLastTellTarget(arg2, type)
--     684:  ChatFrameUtil.FlashTabIfNotShown(...)
--
-- A message-event filter runs at line 304, upstream of all of that, which is why
-- filters can make a message never appear at all during an encounter and why
-- ns.CanUseMessageEventFilters withholds them by default on 12.0+.
--
-- Replacing frame.AddMessage taints from line 667 down, and reading a tainted table
-- field is enough to taint the execution. Everything downstream of 667 is listed
-- above, and exactly one entry in it touches a secret: SetLastTellTarget, which does
-- strupper(target) on a whisper sender that is a secret string inside instanced
-- content. That single call is what raised
-- "attempt to perform string conversion on a secret string value" in 0.11.49.
--
-- 0.11.50 answered that by tying the wrapper to the filter mode. That was too blunt:
-- it charged the wrapper the filters' price and took mention highlighting and short
-- channel names away from every 12.x player to protect one whisper convenience.
-- ns.EnsureLastTellTargetGuard neutralises the one victim instead, so the wrapper is
-- allowed again wherever that guard can be installed.
--
-- Note that withdrawing the wrapper still does not undo it: restoring the original
-- is itself a write from tainted code, so the field stays tainted until /reload.
-- That is why the guard, once installed, is never removed either.
function ns.CanReplaceChatFrameAddMessage()
    -- Modern chat frames can transform already-rendered entries without replacing
    -- AddMessage. Prefer that path whenever it exists: owning AddMessage is a taint
    -- vector and is no longer necessary for labels/mentions/URLs on Forever/Midnight.
    if type(ns.HasSecurePostRenderAPI) == "function" then
        local ok, available = pcall(ns.HasSecurePostRenderAPI)
        if ok and available then
            return false
        end
    end

    -- Checked before anything else so the diagnostic lever works on every client, not
    -- only the ones with secret values.
    local db = ns.db
    if type(db) == "table" and db.disableRenderHook then
        return false
    end

    if not ns.IsRetailSecretValueBuild() then
        return true
    end

    -- If the guard cannot be built on this client, fall back to the 0.11.50
    -- position: the wrapper is only for someone who explicitly accepted the errors.
    if not ns.CanGuardLastTellTarget() then
        return ns.GetRetailChatFilterMode() == "full"
    end

    return true
end

-- Everything the guard in ns.EnsureLastTellTargetGuard needs in order to exist.
function ns.CanGuardLastTellTarget()
    if type(issecretvalue) ~= "function" then
        issecretvalue = _G.issecretvalue
    end
    if type(issecretvalue) ~= "function" then
        -- Without this we cannot tell a secret sender from an ordinary one, and a
        -- guard that skipped every target would break /r everywhere.
        return false
    end

    local util = _G.ChatFrameUtil
    return type(util) == "table" and type(util.SetLastTellTarget) == "function"
end

local lastTellTargetGuarded = false
local lastTellTargetGuardMode = "none"
local foreignChatTaintOwner
local foreignChatTaintSurface

local function GetTaintOwner(tbl, key)
    if type(issecurevariable) ~= "function" or tbl == nil or type(key) ~= "string" then
        return nil, false
    end

    local ok, secure, owner = pcall(issecurevariable, tbl, key)
    if not ok then
        return nil, false
    end
    if secure then
        return nil, true
    end

    if owner == nil or owner == "" then
        return "unknown", true
    end
    return tostring(owner), true
end

-- Detect a third-party write on the part of Blizzard's chat dispatch that executes
-- before SetLastTellTarget. A secure post-hook does not taint these variables, so a
-- positive result means the dispatch is already unsafe before Chatify does anything.
--
-- This matters on Midnight/Forever because the whisper sender may be a secret string.
-- Blizzard's SetLastTellTarget calls strupper(target); that is legal on a clean
-- Blizzard stack and throws immediately when an earlier addon has tainted the stack.
function ns.GetForeignChatTaintInfo()
    if not ns.IsRetailSecretValueBuild() then
        return nil, nil
    end

    local checks = {
        { _G.ChatFrameMixin, "MessageEventHandler", "ChatFrameMixin.MessageEventHandler" },
        { _G.ChatFrameMixin, "OnEvent", "ChatFrameMixin.OnEvent" },
        { _G.ChatFrameUtil, "ProcessMessageEventFilters", "ChatFrameUtil.ProcessMessageEventFilters" },
        { _G.ChatFrameUtil, "GetDecoratedSenderName", "ChatFrameUtil.GetDecoratedSenderName" },
        { _G.ChatFrameUtil, "SetLastTellTarget", "ChatFrameUtil.SetLastTellTarget" },
    }

    for i = 1, #checks do
        local owner, inspected = GetTaintOwner(checks[i][1], checks[i][2])
        if inspected and owner and owner ~= addonName and owner ~= "Chatify" then
            return owner, checks[i][3]
        end
    end

    local maxFrames = (type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows())
        or NUM_CHAT_WINDOWS or 10
    for i = 1, maxFrames do
        local frame = _G["ChatFrame" .. i]
        if frame then
            local owner, inspected = GetTaintOwner(frame, "AddMessage")
            if inspected and owner and owner ~= addonName and owner ~= "Chatify" then
                return owner, "ChatFrame" .. i .. ".AddMessage"
            end
        end
    end

    return nil, nil
end

-- Installed when Chatify itself has already placed a wrapper on the chat render path,
-- or when another addon has already tainted that path. It is never installed on an
-- otherwise clean modern chat stack: doing so would create the very taint we are
-- trying to contain.
--
-- On 12.x clients securecallfunction can re-enter Blizzard's original helper in its
-- native security context. That preserves the /r target even when the caller is
-- tainted. If the client lacks that bridge (or rejects the call), the fallback only
-- drops a secret target; normal whispers still use Blizzard's original function.
function ns.EnsureLastTellTargetGuard()
    if lastTellTargetGuarded or not ns.IsRetailSecretValueBuild() then
        return lastTellTargetGuarded
    end

    if not ns.CanGuardLastTellTarget() then
        return false
    end

    local util = _G.ChatFrameUtil
    local original = util.SetLastTellTarget
    local secureCall = _G.securecallfunction

    util.SetLastTellTarget = function(target, chatType)
        if type(secureCall) == "function" then
            -- Do not inspect/convert target before the secure barrier. Passing a
            -- secret value through is permitted; the Blizzard function then runs in
            -- its own security context and can perform its strupper comparisons.
            local ok, a, b, c, d = pcall(secureCall, original, target, chatType)
            if ok then
                return a, b, c, d
            end
        end

        -- Older/partial clients: issecretvalue itself is permitted from tainted code.
        -- Skipping is preferable to exploding in Blizzard's strupper() loop. The
        -- only lost behavior is updating /r for that protected whisper.
        if ns.IsSecretValue(target) then
            return
        end

        return original(target, chatType)
    end

    lastTellTargetGuardMode = type(secureCall) == "function" and "secure-bridge" or "secret-skip"
    lastTellTargetGuarded = true
    return true
end

-- If somebody else has already tainted Blizzard's chat path, installing the guard no
-- longer creates a new risk: the dispatch is tainted before it reaches us anyway. Do
-- this early (ADDON_LOADED / world-entry / restriction transitions) so the first
-- protected BNet whisper cannot hit SetLastTellTarget unguarded.
function ns.RefreshForeignChatTaintGuard()
    if lastTellTargetGuarded or not ns.IsRetailSecretValueBuild() then
        return lastTellTargetGuarded
    end

    local owner, surface = ns.GetForeignChatTaintInfo()
    if not owner then
        return false
    end

    foreignChatTaintOwner = owner
    foreignChatTaintSurface = surface
    return ns.EnsureLastTellTargetGuard()
end

function ns.IsLastTellTargetGuarded()
    return lastTellTargetGuarded
end

function ns.GetLastTellTargetGuardMode()
    return lastTellTargetGuardMode
end

function ns.GetDetectedForeignChatTaint()
    return foreignChatTaintOwner, foreignChatTaintSurface
end

-- What the client can actually tell us about chat taint, gathered in one place.
--
-- This exists because the central protected-chat taint question is not answerable
-- offline. Reading Blizzard's ChatFrameFilters.lua shows that on 12.x an
-- addon's message-event filter is wrapped so that it is SKIPPED ENTIRELY when any
-- argument is a secret (canaccessvalue) and is invoked through securecallfunction,
-- which restores the caller's taint afterwards. If both hold at runtime then a filter
-- cannot be the cause of the whisper error, and Chatify's default of withholding
-- filters on 12.0+ is defending against a hazard Blizzard has since closed.
--
-- Lua cannot observe taint, and the stub cannot model it, so none of that is provable
-- from tooling. What IS queryable is which of those mechanisms the running client has
-- and who currently owns the fields involved. That is what this returns; the
-- conclusion is drawn by a person looking at the output in game, not here.
function ns.GetChatTaintReport()
    local report = {}

    local function add(label, value)
        report[#report + 1] = { label = label, value = value }
    end

    add("Client flavor", type(ns.GetProjectKey) == "function" and ns.GetProjectKey() or "unknown")
    add("Support tier", type(ns.GetClientSupportTier) == "function" and ns.GetClientSupportTier() or "unknown")
    add("Interface", tostring(type(ns.GetBuildInterface) == "function" and ns.GetBuildInterface() or 0))
    add("Forever load marker", type(ns.IsForeverClient) == "function" and ns.IsForeverClient() and "yes" or "no")
    add("Client has secret values", ns.IsRetailSecretValueBuild() and "yes" or "no")
    if type(C_Secrets) == "table" and type(C_Secrets.HasSecretRestrictions) == "function" then
        local okSecrets, hasRestrictions = pcall(C_Secrets.HasSecretRestrictions)
        add("C_Secrets restrictions", okSecrets and (hasRestrictions and "enabled" or "disabled") or "query failed")
    else
        add("C_Secrets restrictions", "API absent")
    end
    add("securecallfunction", type(securecallfunction) == "function" and "present" or "absent")
    add("canaccessvalue", type(canaccessvalue) == "function" and "present" or "absent")
    add("issecretvalue", type(issecretvalue) == "function" and "present" or "absent")

    -- The 12.x filter registry. Its presence is what makes the two mechanisms above
    -- relevant to filters specifically rather than to the client in general.
    local util = _G.ChatFrameUtil
    local hasRegistry = type(util) == "table"
        and type(util.GetMessageEventFilters) == "function"
    add("Filter registry (12.x)", hasRegistry and "present" or "absent")

    add("Chatify filter mode", tostring(ns.GetRetailChatFilterMode()))
    add("Filters currently allowed", ns.CanUseMessageEventFilters() and "yes" or "no")
    add("AddMessage wrapper allowed", ns.CanReplaceChatFrameAddMessage() and "yes" or "no")
    add("Render hook disabled for test",
        (type(ns.db) == "table" and ns.db.disableRenderHook) and "yes" or "no")
    add("SetLastTellTarget guarded", ns.IsLastTellTargetGuarded() and "yes" or "no")
    add("SetLastTellTarget guard mode",
        type(ns.GetLastTellTargetGuardMode) == "function" and ns.GetLastTellTargetGuardMode() or "none")
    if type(ns.GetDetectedForeignChatTaint) == "function" then
        local taintOwner, taintSurface = ns.GetDetectedForeignChatTaint()
        if not taintOwner and type(ns.GetForeignChatTaintInfo) == "function" then
            taintOwner, taintSurface = ns.GetForeignChatTaintInfo()
        end
        add("External chat taint",
            taintOwner and ((taintSurface or "unknown surface") .. " <- " .. taintOwner) or "none detected")
    end

    if type(ns.GetFeatureSupport) == "function" then
        local features = { "channels", "sounds", "quickButtons", "composer", "composerAutomation", "spamFilters", "mentions", "history", "copy", "nativeCopy", "autoReplyWhisper", "autoReplyBNet", "autoReplyGuild", "chatTabs", "communities" }
        for i = 1, #features do
            local feature = features[i]
            add("Feature " .. feature, tostring(ns.GetFeatureSupport(feature)))
        end
    end

    if type(issecurevariable) == "function" and type(util) == "table" then
        local ok, secure, owner = pcall(issecurevariable, util, "SetLastTellTarget")
        if ok then
            add("SetLastTellTarget owner",
                secure and "secure" or (owner ~= nil and owner ~= "" and tostring(owner) or "tainted"))
        end
    end

    if type(issecurevariable) == "function" and type(_G.ChatFrameMixin) == "table" then
        local ok, secure, owner = pcall(issecurevariable, _G.ChatFrameMixin, "MessageEventHandler")
        if ok then
            add("MessageEventHandler owner",
                secure and "secure" or (owner ~= nil and owner ~= "" and tostring(owner) or "tainted"))
        end
    end

    local primary = _G.ChatFrame1 or _G.DEFAULT_CHAT_FRAME
    if type(issecurevariable) == "function" and primary then
        local ok, secure, owner = pcall(issecurevariable, primary, "AddMessage")
        if ok then
            add("ChatFrame1.AddMessage owner",
                secure and "secure" or (owner ~= nil and owner ~= "" and tostring(owner) or "tainted"))
        end
    end

    return report
end

-- Modules register a callback here; it fires whenever the lockdown state flips so
-- they can install or withdraw their filters.
local filterRefreshHandlers = {}

function ns.RegisterFilterRefreshHandler(fn)
    if type(fn) == "function" then
        filterRefreshHandlers[#filterRefreshHandlers + 1] = fn
    end
end

local lastKnownFilterGate = nil

function ns.RefreshMessageFilters()
    local allowed = ns.CanUseMessageEventFilters()
    if allowed == lastKnownFilterGate then
        return
    end
    lastKnownFilterGate = allowed

    for i = 1, #filterRefreshHandlers do
        pcall(filterRefreshHandlers[i], allowed)
    end
end

do
    local watcher = CreateFrame("Frame")
    -- ADDON_RESTRICTION_STATE_CHANGED is the 12.0 signal; the encounter/challenge
    -- events are a fallback for builds that do not fire it.
    for _, evt in ipairs({
        "ADDON_RESTRICTION_STATE_CHANGED",
        "ENCOUNTER_START", "ENCOUNTER_END",
        "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "PLAYER_ENTERING_WORLD",
        "ADDON_LOADED",
        -- Instance transitions matter as much as the encounter itself now that the
        -- gate is the taint risk window rather than the lockdown flag alone.
        "ZONE_CHANGED_NEW_AREA",
    }) do
        pcall(watcher.RegisterEvent, watcher, evt)
    end
    watcher:SetScript("OnEvent", function()
        -- Order matters: the cached lockdown answer has to be dropped before the
        -- gate is recomputed, or RefreshMessageFilters would re-read a stale value.
        if type(ns.InvalidateLockdownCache) == "function" then
            ns.InvalidateLockdownCache()
        end
        if type(ns.RefreshForeignChatTaintGuard) == "function" then
            ns.RefreshForeignChatTaintGuard()
        end
        if type(ns.RefreshMessageFilters) == "function" then
            ns.RefreshMessageFilters()
        end
    end)
end

function ns.AddMessageEventFilterIfSupported(eventName, callback)
    if type(callback) ~= "function" then
        return false
    end

    if type(ns.GetChatAPI("ChatFrame_AddMessageEventFilter", "AddMessageEventFilter")) ~= "function" then
        return false
    end

    if not ns.CanUseMessageEventFilters() then
        return false
    end

    if not ns.IsEventSupported(eventName) then
        return false
    end

    messageFilterRegistry[eventName] = messageFilterRegistry[eventName] or {}
    if messageFilterRegistry[eventName][callback] then
        return true
    end

    local ok = ns.CallChatAPI("ChatFrame_AddMessageEventFilter", "AddMessageEventFilter", eventName, callback)
    if ok then
        messageFilterRegistry[eventName][callback] = true
    end

    return ok and true or false
end

function ns.RemoveMessageEventFilterIfSupported(eventName, callback)
    if type(callback) ~= "function" then
        return false
    end

    if type(ns.GetChatAPI("ChatFrame_RemoveMessageEventFilter", "RemoveMessageEventFilter")) ~= "function" then
        return false
    end

    if not ns.IsEventSupported(eventName) then
        return false
    end

    local ok = ns.CallChatAPI("ChatFrame_RemoveMessageEventFilter", "RemoveMessageEventFilter", eventName, callback)
    if ok and messageFilterRegistry[eventName] then
        messageFilterRegistry[eventName][callback] = nil
    end

    return ok and true or false
end

function ns.NormalizeMentionSettings(db)
    if not db then
        return false
    end

    local changed = false
    if db.enableMentionManager == nil then
        db.enableMentionManager = true
        changed = true
    end

    local hasLegacyHighlights = type(db.highlightKeywords) == "table" or db.myHighlightColor ~= nil
    db.mentionRules = type(db.mentionRules) == "table" and db.mentionRules or {}
    db.sounds = type(db.sounds) == "table" and db.sounds or {}
    db.sounds.events = type(db.sounds.events) == "table" and db.sounds.events or {}

    for _, rule in ipairs(db.mentionRules) do
        if type(rule) == "table" then
            local normalizedColor = type(rule.color) == "string" and rule.color:gsub("#", "") or ""
            if normalizedColor:match("^%x%x%x%x%x%x%x%x$") then
                normalizedColor = normalizedColor:sub(3)
            end
            if not normalizedColor:match("^%x%x%x%x%x%x$") then
                normalizedColor = "ffd700"
            end
            if rule.color ~= normalizedColor then
                rule.color = normalizedColor
                changed = true
            end
            if type(rule.sound) ~= "string" or rule.sound == "" then
                rule.sound = "None"
                changed = true
            end
            if type(rule.channels) ~= "string" or rule.channels == "" then
                rule.channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL"
                changed = true
            end
            if rule.ignoreCase == nil then rule.ignoreCase = true; changed = true end
            if rule.wholeWord == nil then rule.wholeWord = true; changed = true end
            if rule.cooldown == nil then rule.cooldown = 2; changed = true end
        end
    end

    -- Keep the built-in "my name" rule attached to the actual player identity.
    -- On Forever this matters because one character has both a first name and a
    -- surname. Existing profiles from before 2.17.2 are upgraded in-place even
    -- when the old mention migration already ran.
    local identity = type(ns.GetPlayerMentionIdentity) == "function" and ns.GetPlayerMentionIdentity() or nil
    local playerName = identity and (identity.full or identity.first)
        or (type(UnitName) == "function" and UnitName("player") or nil)

    if identity and identity.isForever then
        for _, rule in ipairs(db.mentionRules) do
            if type(rule) == "table" then
                local text = rule.text or rule.word or rule.keyword
                local isIdentity = rule.matchPlayerIdentity == true
                    or (type(ns.IsPlayerMentionIdentityText) == "function" and ns.IsPlayerMentionIdentityText(text))
                if isIdentity and rule.matchPlayerIdentity ~= true then
                    rule.matchPlayerIdentity = true
                    changed = true
                end
            end
        end
    end

    local hasLegacyMentionSound = db.sounds.events["MENTION"] ~= nil
    if db._chatifyMentionSettingsMigrated and not hasLegacyHighlights and not hasLegacyMentionSound then
        return changed
    end

    local legacyColor = type(db.myHighlightColor) == "string" and db.myHighlightColor:gsub("#", "") or nil
    if type(legacyColor) ~= "string" or not legacyColor:match("^%x%x%x%x%x%x$") then
        legacyColor = "ffd700"
    end

    local legacyMentionSound = db.sounds.events["MENTION"]
    if type(legacyMentionSound) ~= "string" or legacyMentionSound == "" then
        legacyMentionSound = "Chatify Default"
    end

    local function sameText(a, b)
        if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then
            return false
        end
        return string.lower(a) == string.lower(b)
    end

    local function ensureRule(text, color, sound, channels, matchPlayerIdentity)
        if type(text) ~= "string" or text == "" then
            return
        end

        for _, rule in ipairs(db.mentionRules) do
            if type(rule) == "table" and sameText(rule.text or rule.word or rule.keyword, text) then
                if type(rule.text) ~= "string" or rule.text == "" then
                    rule.text = text
                    changed = true
                end
                if type(rule.color) ~= "string" or rule.color == "" then
                    rule.color = color or "ffd700"
                    changed = true
                end
                if (type(rule.sound) ~= "string" or rule.sound == "" or rule.sound == "None") and type(sound) == "string" and sound ~= "" then
                    rule.sound = sound
                    changed = true
                end
                if type(rule.channels) ~= "string" or rule.channels == "" then
                    rule.channels = channels or "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL"
                    changed = true
                end
                if rule.ignoreCase == nil then rule.ignoreCase = true; changed = true end
                if rule.wholeWord == nil then rule.wholeWord = true; changed = true end
                if rule.cooldown == nil then rule.cooldown = 2; changed = true end
                if matchPlayerIdentity and rule.matchPlayerIdentity ~= true then
                    rule.matchPlayerIdentity = true
                    changed = true
                end
                return
            end
        end

        table.insert(db.mentionRules, {
            enabled = true,
            text = text,
            color = color or "ffd700",
            sound = sound or "None",
            channels = channels or "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
            ignoreCase = true,
            wholeWord = true,
            cooldown = 2,
            matchPlayerIdentity = matchPlayerIdentity and true or nil,
        })
        changed = true
    end

    if not db._chatifyMentionSettingsMigrated and type(playerName) == "string" and playerName ~= "" then
        ensureRule(playerName, legacyColor, legacyMentionSound, "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL", true)
    end

    if type(db.highlightKeywords) == "table" then
        for _, keyword in ipairs(db.highlightKeywords) do
            if type(keyword) == "string" and keyword ~= "" and not sameText(keyword, playerName) then
                ensureRule(keyword, legacyColor, "None", "ALL")
            end
        end
        db.highlightKeywords = nil
        changed = true
    end

    if db.myHighlightColor ~= nil then
        db.myHighlightColor = nil
        changed = true
    end

    if db.sounds.events["MENTION"] ~= nil then
        db.sounds.events["MENTION"] = nil
        changed = true
    end

    if db._chatifyMentionSettingsMigrated ~= true then
        db._chatifyMentionSettingsMigrated = true
        changed = true
    end

    return changed
end

function ns.RunRetailCompatibilityMigration(db)
    if not db or ns.IsRetailSecretValueBuild() then
        return false
    end

    if db._chatifyCompatMigrated then
        return false
    end

    -- Older safe-retail builds force-disabled several features directly in the DB.
    -- If we detect that exact legacy pattern on a older Retail build, restore
    -- the non-destructive defaults so the addon works again without manual repair.
    if db.useVirtualChat == false
        and db.enableHistory == false
        and db.enableTimestamps == false
        and db.shortChannels == false
        and db.hideSystemSpam == false then
        db.enableHistory = true
        db.enableTimestamps = true
        db.shortChannels = true
        db.hideSystemSpam = true
        db._chatifyCompatMigrated = true
        return true
    end

    return false
end

function ns.SafeSetFont(target, fontPath, size, flags, fallbackFont)
    if not target or type(target.SetFont) ~= "function" then
        return false
    end

    local primary = fontPath
    if type(primary) ~= "string" or primary == "" then
        if ChatFontNormal and ChatFontNormal.GetFont then
            primary = ChatFontNormal:GetFont()
        end
    end

    if type(primary) == "string" and primary ~= "" then
        local ok, applied = pcall(target.SetFont, target, primary, size, flags or "")
        if ok and applied ~= false then
            return true
        end
    end

    local fallback = fallbackFont
    if type(fallback) ~= "string" or fallback == "" then
        if ChatFontNormal and ChatFontNormal.GetFont then
            fallback = ChatFontNormal:GetFont()
        end
    end

    if type(fallback) == "string" and fallback ~= "" and fallback ~= primary then
        local ok, applied = pcall(target.SetFont, target, fallback, size, flags or "")
        return ok and applied ~= false
    end

    return false
end

function ns.TryMakeSafeText(raw)
    -- Check Retail secret/protected payloads before any string operation or
    -- empty-string comparison. A tainted addon must not inspect those values.
    if ns.IsProtectedChatValue(raw) then
        return nil
    end
    if not ns.CanAccessChatValue(raw) then
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

-- Guards every entry point that is handed a "chat frame" by something outside
-- Chatify.
--
-- Blizzard's FCF_* functions are public, so any addon can call them with anything,
-- and a hook that trusts its argument blindly ends up calling frame methods on
-- whatever it was given. That is exactly how the FCF_SetChatWindowFontSize hook
-- failed: the function is declared FCF_SetChatWindowFontSize(self, chatFrame,
-- fontSize) and Chatify read the first argument, so a caller passing its own module
-- table as `self` produced "attempt to call a nil value" inside ns.GetEditBox.
--
-- The argument index is fixed at the call site; this exists so the next caller that
-- gets it wrong, in Chatify or in another addon, is a no-op instead of an error.
function ns.IsChatFrame(frame)
    if type(frame) ~= "table" then
        return false
    end

    return type(frame.AddMessage) == "function"
        and type(frame.GetName) == "function"
        and type(frame.GetID) == "function"
end

function ns.SafeAfter(delay, callback)
    if type(callback) ~= "function" then
        return false
    end

    delay = tonumber(delay) or 0
    if delay < 0 then
        delay = 0
    end

    if C_Timer and type(C_Timer.After) == "function" then
        local ok = pcall(C_Timer.After, delay, function()
            pcall(callback)
        end)
        if ok then
            return true
        end
    end

    pcall(callback)
    return true
end

local scheduledKeys = {}
function ns.ScheduleUnique(key, delay, callback)
    if type(key) ~= "string" or key == "" or type(callback) ~= "function" then
        return false
    end

    scheduledKeys[key] = (scheduledKeys[key] or 0) + 1
    local token = scheduledKeys[key]
    return ns.SafeAfter(delay or 0, function()
        if scheduledKeys[key] ~= token then
            return
        end
        scheduledKeys[key] = nil
        callback()
    end)
end


-- =========================================================
-- 7. LIGHTWEIGHT RUNTIME HELPERS
-- =========================================================
-- Small helpers inspired by large chat addons: keep expensive refreshes coalesced,
-- never let optional UI work break chat processing, and keep a tiny runtime error log
-- for diagnostics without spamming the user.
ns.Runtime = ns.Runtime or { errors = {}, counters = {} }
local Runtime = ns.Runtime

-- Colour code removal.
--
-- WoW has two colour opener syntaxes and both must be handled wherever |r is
-- removed, or the opener survives with nothing to close it and the colour bleeds
-- to the end of the line:
--
--   |cffa335ee                 classic, eight hex digits
--   |cnITEM_QUALITY4_COLOR:    named, added in 11.x
--
-- This lives in one place because the named form was originally fixed only in the
-- copy window while three other call sites - the author normalizer, the spam
-- normalizer and the router's duplicate key - kept the old pattern and silently
-- carried the code through. Anything that strips colours should call this.
function ns.StripColorCodes(value, keepReset)
    if type(value) ~= "string" then
        return value
    end

    -- The escape letter is matched case-insensitively for the same reason the
    -- name part is: the client accepts either, and a stray |CN... would otherwise
    -- survive and bleed exactly like the bug this function exists to prevent.
    value = value:gsub("|[cC]%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|[cC][nN][%w_]+:", "")
    if not keepReset then
        value = value:gsub("|[rR]", "")
    end
    return value
end

function ns.SafeCall(label, func, ...)
    if type(func) ~= "function" then
        return false, "missing function"
    end

    local ok, result = pcall(func, ...)
    if ok then
        return true, result
    end

    local errorText = tostring(result or "unknown error")
    local entry = {
        time = date and date("%H:%M:%S") or tostring(math.floor(GetTime and GetTime() or 0)),
        label = tostring(label or "runtime"),
        error = errorText,
    }
    table.insert(Runtime.errors, 1, entry)
    while #Runtime.errors > 20 do
        table.remove(Runtime.errors)
    end
    Runtime.counters[entry.label] = (Runtime.counters[entry.label] or 0) + 1
    return false, result
end

function ns.GetRuntimeDebugText()
    local lines = {}
    lines[#lines + 1] = "Runtime guarded errors: " .. tostring(#(Runtime.errors or {}))
    if not Runtime.errors or #Runtime.errors == 0 then
        lines[#lines + 1] = "|cff888888No guarded runtime errors this session.|r"
        return table.concat(lines, "\n")
    end
    for i = 1, math.min(#Runtime.errors, 10) do
        local entry = Runtime.errors[i]
        lines[#lines + 1] = string.format("%02d. [%s] %s: %s", i, entry.time or "?", entry.label or "?", entry.error or "?")
    end
    return table.concat(lines, "\n")
end

function ns.Debounce(key, delay, callback)
    return ns.ScheduleUnique("debounce:" .. tostring(key or "default"), delay or 0, callback)
end

function ns.SafeHookScript(frame, scriptName, callback, marker)
    if not frame or type(scriptName) ~= "string" or type(callback) ~= "function" then
        return false
    end
    if type(frame.HookScript) ~= "function" then
        return false
    end

    marker = marker or ("__chatifyHooked" .. scriptName)
    if frame[marker] then
        return true
    end

    local ok = pcall(frame.HookScript, frame, scriptName, function(...)
        ns.SafeCall("HookScript:" .. scriptName, callback, ...)
    end)
    if ok then
        frame[marker] = true
    end
    return ok and true or false
end

function ns.SafeBoolean(value, default)
    if value == nil then
        return default and true or false
    end
    return value and true or false
end
