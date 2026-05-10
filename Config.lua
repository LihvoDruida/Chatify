local addonName, ns = ...

ns.Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

-- =========================================================
-- 1. LIBS & MEDIA REGISTRATION
-- =========================================================
local LSM = LibStub("LibSharedMedia-3.0")
local L = (ns.L and function(key) return ns.L(key) end) or function(key) return key end

-- Реєструємо ваші асети в глобальну бібліотеку
-- Це дозволяє вибирати їх у випадаючих списках Config.lua
LSM:Register("sound", "Chatify Default", "Interface\\AddOns\\Chatify\\assets\\alert\\notification-0.ogg")
LSM:Register("font", "Exo 2 (Chatify)", "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf")

-- =========================================================
-- 2. GLOBAL LISTS (CONSTANTS)
-- =========================================================
ns.Lists = {}

-- Список шрифтів (Fallback, якщо LSM не працює)
ns.Lists.Fonts = {
    [1] = { name = "Exo 2 (Chatify)",      path = "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf" },
    [2] = { name = "Friz Quadrata (WoW)",  path = "Fonts\\FRIZQT__.TTF" },
    [3] = { name = "Arial Narrow (WoW)",   path = "Fonts\\ARIALN.TTF" },
    [4] = { name = "Skurri (WoW)",         path = "Fonts\\skurri.ttf" },
    [5] = { name = "Morpheus (Quest)",     path = "Fonts\\MORPHEUS.TTF" },
}

-- Список форматів часу
ns.Lists.TimeFormats = {
    [1] = { name = "None",                     format = nil },
    [2] = { name = "HH:MM (12:30)",            format = "%H:%M" },
    [3] = { name = "HH:MM:SS (12:30:45)",      format = "%H:%M:%S" },
    [4] = { name = "AM/PM (12:30 PM)",         format = "%I:%M %p" },
    [5] = { name = "D.M HH:MM (08.02 12:30)",  format = "%d.%m %H:%M" },
}

-- =========================================================
-- 3. MEDIA RESOLVERS
-- =========================================================
local CHATIFY_DEFAULT_SOUND = "Interface\\AddOns\\Chatify\\assets\\alert\\notification-0.ogg"
local CHATIFY_DEFAULT_FONT = "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf"

function ns.ResolveFontPath(fontID)
    if type(fontID) ~= "string" or fontID == "" then
        return CHATIFY_DEFAULT_FONT
    end

    if string.find(fontID, "\\", 1, true) or string.find(fontID, "/", 1, true) then
        return fontID
    end

    local fromLSM = LSM and LSM.Fetch and LSM:Fetch("font", fontID, true)
    if fromLSM and type(fromLSM) == "string" then
        return fromLSM
    end

    if ns.Lists and ns.Lists.Fonts then
        for _, entry in ipairs(ns.Lists.Fonts) do
            if entry and (entry.name == fontID or entry.path == fontID) and type(entry.path) == "string" then
                return entry.path
            end
        end
    end

    if fontID == "Exo 2 (Chatify)" then
        return CHATIFY_DEFAULT_FONT
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
        fontID = "Exo 2 (Chatify)", -- Дефолтний шрифт (по назві з LSM)
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
        historyLimit = 50,          -- Зберігати 50 рядків
        historyAlpha = true,        -- Робити старі повідомлення сірими

        -- === SPAM FILTERS (Updated) ===
        enableSpamFilter = true,
        
        -- Anti-Flood (Нові налаштування)
        enableThrottle = true,      -- Блокувати повтор повідомлень
        throttleTime = 60,          -- Час блокування (сек)
        
        -- System Cleaner (Нові налаштування)
        hideSystemSpam = true,      -- Приховувати вхід/вихід з каналів

        -- Базовий список слів для блокування
        spamKeywords = { 
            "BOOST", "CARRY", "GOLD", "CHEAP", "WTS", "SELLING", "SERVICES"
        },

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
        language = "client", -- Мова аддона: client, enUS, ukUA

        -- === HIGHLIGHTS ===
        myHighlightColor = "ff0000", -- Колір підсвітки (Червоний)
        highlightKeywords = { UnitName("player") }, -- Автоматично додаємо нік гравця

        -- === SOUNDS ===
        sounds = {
            enable = true,
            masterVolume = true, -- Програвати через Master (чути навіть якщо вимкнені ефекти)
            events = {
                ["WHISPER"] = "Chatify Default",
                ["MENTION"] = "Chatify Default",
                ["GUILD"]   = "None",
                ["PARTY"]   = "None",
                ["RAID"]    = "None",
            }
        },

        -- === AUTO REPLY ===
        autoReply = {
            enabled = false,
            busyMode = false,
            onlyFriends = false,
            autoNotify = true,
            guildReplyEnabled = false,
            cooldown = 5,
            afkMessage = L("I'm currently AFK. I'll be back later!"),
            queueMessage = L("I'm in queue. Estimated wait time: %s minutes."),
            raidMessage = L("I'm currently in a raid. I'll message you when I'm free!"),
            dungeonMessage = L("I'm currently in a dungeon. I'll message you when I'm done!"),
            pvpMessage = L("I'm currently in PvP. I'll message you when I'm free!"),
            busyMessage = L("I'm currently busy. I'll get back to you soon!"),
            returnMessage = L("I'm back now! What did you need?"),
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
function ns.IsRetailSecretValueBuild()
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
        return false
    end

    -- Modern Retail protects parts of chat payloads with secret string values.
    -- Do not key this only to Interface >= 120000: the protection APIs can exist on
    -- 11.x builds too, and whisper routing/temporary windows break if we mutate or
    -- reformat those payloads outside Blizzard's own MessageEventHandler path.
    if type(issecretvalue) == "function" or type(canaccessvalue) == "function" then
        return true
    end

    if type(GetBuildInfo) ~= "function" then
        return true
    end

    local interfaceVersion = select(4, GetBuildInfo())
    return type(interfaceVersion) == "number" and interfaceVersion >= 110000
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

function ns.ShouldBypassWhisperMutation(eventName)
    return ns.IsRetailSecretValueBuild() and ns.IsWhisperSensitiveEvent(eventName)
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

function ns.CanAccessChatValue(...)
    local count = select("#", ...)
    if count == 0 then
        return true
    end

    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, ...)
        if ok then
            return accessible and true or false
        end
    end

    for i = 1, count do
        local value = select(i, ...)
        if ns.IsSecretValue(value) then
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



local eventSupportCache = {}
local eventProbeFrame

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

function ns.AddMessageEventFilterIfSupported(eventName, callback)
    if type(ChatFrame_AddMessageEventFilter) ~= "function" or type(callback) ~= "function" then
        return false
    end

    if not ns.IsEventSupported(eventName) then
        return false
    end

    local ok = pcall(ChatFrame_AddMessageEventFilter, eventName, callback)
    return ok and true or false
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

    local ok = false
    if type(primary) == "string" and primary ~= "" then
        ok = pcall(target.SetFont, target, primary, size, flags or "") and true or false
    end

    if ok then
        return true
    end

    local fallback = fallbackFont
    if type(fallback) ~= "string" or fallback == "" then
        if ChatFontNormal and ChatFontNormal.GetFont then
            fallback = ChatFontNormal:GetFont()
        end
    end

    if type(fallback) == "string" and fallback ~= "" then
        return pcall(target.SetFont, target, fallback, size, flags or "") and true or false
    end

    return false
end

function ns.TryMakeSafeText(raw)
    if raw == nil then
        return nil
    end

    local rawType = type(raw)
    if rawType == "number" then
        return tostring(raw)
    end

    if rawType == "string" then
        if ns.IsSecretValue(raw) then
            return nil
        end
        if not ns.CanAccessChatValue(raw) then
            return nil
        end
        return raw
    end

    return nil
end
