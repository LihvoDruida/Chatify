local addonName, ns = ...

ns.Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

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
ns.Lists.TimeFormats = {
    [1] = { name = "None",                     format = nil },
    [2] = { name = "HH:MM (12:30)",            format = "%H:%M" },
    [3] = { name = "HH:MM:SS (12:30:45)",      format = "%H:%M:%S" },
    [4] = { name = "AM/PM (12:30 PM)",         format = "%I:%M %p" },
    [5] = { name = "D.M HH:MM (08.02 12:30)",  format = "%d.%m %H:%M" },
}

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
        historyAlpha = true,        -- Legacy SavedVariables key; history is no longer replayed into chat frames

        -- === SPAM FILTERS (Updated) ===
        enableSpamFilter = true,
        
        -- Anti-Flood / Spam Filter 2.0
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
        shortChannels = true,       -- [Party] -> [P]
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
        -- Off by default. Chatify already withdraws its chat filters for the
        -- duration of chat messaging lockdown (encounters, Mythic+, rated PvP) and
        -- reinstalls them afterwards, which is what prevents the tainted-dispatch
        -- "secret string value" error. This switch is a troubleshooting escape
        -- hatch that keeps them withdrawn permanently on 12.0+; it costs spam
        -- filtering, keyword highlighting and custom link formatting.
        retailDisableChatFilters = false,

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
-- Secret Values were introduced in Patch 12.0.0 (Midnight) and are, per Blizzard's
-- own 12.0.5 notes, "entirely disabled on Classic builds". Never treat 11.x Retail
-- or any Classic flavour as a secret-value build: doing so silently disables
-- timestamps, history, virtual chat and auto-reply on clients that do not need it.
local SECRET_VALUES_MIN_INTERFACE = 120000

local secretApiProbed, secretApiAvailable
function ns.HasSecretValueAPI()
    if not secretApiProbed then
        secretApiProbed = true
        secretApiAvailable = type(_G.issecretvalue) == "function"
    end
    return secretApiAvailable
end

function ns.IsRetailSecretValueBuild()
    if WOW_PROJECT_ID == nil or WOW_PROJECT_MAINLINE == nil then
        return false
    end

    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
        return false
    end

    if not ns.HasSecretValueAPI() then
        return false
    end

    return ns.GetBuildInterface() >= SECRET_VALUES_MIN_INTERFACE
end

-- Chat messaging lockdown (12.0.0+). While it is active Blizzard blocks
-- addon-initiated SendChatMessage / BNSendWhisper with ADDON_ACTION_BLOCKED and
-- delivers whisper payloads as secret values. Outside of it, chat behaves normally.
function ns.InChatMessagingLockdown()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok then
            return locked and true or false
        end
    end
    return false
end

-- Single gate for every outgoing addon-initiated chat message.
function ns.CanSendAddonChat()
    if not ns.IsRetailSecretValueBuild() then
        return true
    end
    return not ns.InChatMessagingLockdown()
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

-- On modern Retail, Chatify never mutates whisper/BNet payloads at all: they route
-- through protected tabs and carry secret senders during chat lockdown. This is a
-- hard, unconditional bypass.
function ns.ShouldBypassWhisperMutation(eventName)
    return ns.IsRetailSecretValueBuild() and ns.IsWhisperSensitiveEvent(eventName)
end

local retailCaptureBypassEvents = {
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_BN_CONVERSATION = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_ACHIEVEMENT = true,
    CHAT_MSG_GUILD_ACHIEVEMENT = true,
}

function ns.ShouldBypassChatCaptureEvent(eventName)
    if not ns.IsRetailSecretValueBuild() then
        return false
    end
    return retailCaptureBypassEvents[eventName] and true or false
end

function ns.HasSecretChatValue(...)
    local count = select("#", ...)
    for i = 1, count do
        if ns.IsSecretValue(select(i, ...)) then
            return true
        end
    end
    return false
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

function ns.GetBuildInterface()
    if type(GetBuildInfo) ~= "function" then
        return 0
    end
    local ok, _, _, _, interfaceVersion = pcall(GetBuildInfo)
    if ok and type(interfaceVersion) == "number" then
        return interfaceVersion
    end
    return 0
end

function ns.GetProjectKey()
    local project = WOW_PROJECT_ID
    if WOW_PROJECT_MAINLINE and project == WOW_PROJECT_MAINLINE then return "retail" end
    if WOW_PROJECT_CLASSIC and project == WOW_PROJECT_CLASSIC then return "vanilla" end
    if WOW_PROJECT_BURNING_CRUSADE_CLASSIC and project == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then return "tbc" end
    if WOW_PROJECT_WRATH_CLASSIC and project == WOW_PROJECT_WRATH_CLASSIC then return "wrath" end
    if WOW_PROJECT_CATACLYSM_CLASSIC and project == WOW_PROJECT_CATACLYSM_CLASSIC then return "cata" end
    if WOW_PROJECT_MISTS_CLASSIC and project == WOW_PROJECT_MISTS_CLASSIC then return "mists" end

    local interfaceVersion = ns.GetBuildInterface()
    if interfaceVersion >= 120000 then return "retail" end
    if interfaceVersion >= 50500 and interfaceVersion < 50600 then return "mists" end
    if interfaceVersion >= 38000 and interfaceVersion < 38100 then return "titan" end
    if interfaceVersion >= 30400 and interfaceVersion < 30500 then return "wrath" end
    if interfaceVersion >= 20500 and interfaceVersion < 20600 then return "tbc" end
    if interfaceVersion >= 11500 and interfaceVersion < 11600 then return "vanilla" end
    return "unknown"
end

function ns.IsMainlineClient()
    return ns.GetProjectKey() == "retail"
end

function ns.IsClassicClient()
    local key = ns.GetProjectKey()
    return key ~= "retail" and key ~= "unknown"
end

function ns.GetSelectedChatFrame()
    if SELECTED_CHAT_FRAME then return SELECTED_CHAT_FRAME end
    if _G and _G.GeneralDockManager and _G.GeneralDockManager.selected then
        return _G.GeneralDockManager.selected
    end
    if type(FCF_GetCurrentChatFrame) == "function" then
        local ok, frame = pcall(FCF_GetCurrentChatFrame)
        if ok and frame then return frame end
    end
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
    local util = _G.ChatFrameUtil
    if type(ChatFrame_OpenChat) == "function" then
        return pcall(ChatFrame_OpenChat, text or "", chatFrame)
    end
    if util and type(util.OpenChat) == "function" then
        return pcall(util.OpenChat, util, text or "", chatFrame)
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
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    return ok and secret or false
end

function ns.IsProtectedChatValue(value)
    -- Prat only treats actual secret values as unreadable. Calling
    -- canaccessvalue() on every normal chat string is too aggressive on
    -- modern Retail and can make the copy window think every line is hidden.
    if ns.IsSecretValue(value) then
        return true
    end

    return false
end

function ns.CanAccessChatValue(...)
    local count = select("#", ...)
    if count == 0 then
        return true
    end

    for i = 1, count do
        local value = select(i, ...)
        if ns.IsProtectedChatValue(value) then
            return false
        end
    end

    return true
end

function ns.EnforceRetailSafeMode(db)
    if not db or not ns.IsRetailSecretValueBuild() then
        return false
    end

    -- Runtime-only safe mode for modern Retail.
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
        local lockdown = ns.InChatMessagingLockdown()
        local whisperSafe = db and db.retailWhisperSafeMode
        status.history = "public/group chat only"
        status.virtualChat = "disabled on modern Retail"
        if whisperSafe then
            status.whisperAutoReply = "whispers never modified (user setting)"
        elseif lockdown then
            status.whisperAutoReply = "paused during chat lockdown"
        else
            status.whisperAutoReply = "available"
        end
        status.nativeCopy = "recommended"
    elseif db and db.copyNativeSelection == false then
        status.nativeCopy = "optional"
    end

    return status
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
function ns.CanUseMessageEventFilters()
    if not ns.IsRetailSecretValueBuild() then
        return true
    end

    local db = GetProfile()
    if db and db.retailDisableChatFilters then
        return false
    end

    return not ns.InChatMessagingLockdown()
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
    }) do
        pcall(watcher.RegisterEvent, watcher, evt)
    end
    watcher:SetScript("OnEvent", function()
        if type(ns.RefreshMessageFilters) == "function" then
            ns.RefreshMessageFilters()
        end
    end)
end

function ns.AddMessageEventFilterIfSupported(eventName, callback)
    if type(ChatFrame_AddMessageEventFilter) ~= "function" or type(callback) ~= "function" then
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

    local ok = pcall(ChatFrame_AddMessageEventFilter, eventName, callback)
    if ok then
        messageFilterRegistry[eventName][callback] = true
    end

    return ok and true or false
end

function ns.RemoveMessageEventFilterIfSupported(eventName, callback)
    if type(ChatFrame_RemoveMessageEventFilter) ~= "function" or type(callback) ~= "function" then
        return false
    end

    if not ns.IsEventSupported(eventName) then
        return false
    end

    local ok = pcall(ChatFrame_RemoveMessageEventFilter, eventName, callback)
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

    local hasLegacyMentionSound = db.sounds.events["MENTION"] ~= nil
    if db._chatifyMentionSettingsMigrated and not hasLegacyHighlights and not hasLegacyMentionSound then
        return changed
    end

    local playerName = type(UnitName) == "function" and UnitName("player") or nil
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

    local function ensureRule(text, color, sound, channels)
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
        })
        changed = true
    end

    if not db._chatifyMentionSettingsMigrated and type(playerName) == "string" and playerName ~= "" then
        ensureRule(playerName, legacyColor, legacyMentionSound, "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL")
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
