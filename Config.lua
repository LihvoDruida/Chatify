local addonName, ns = ...

ns.Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify",
    "AceConsole-3.0",
    "AceEvent-3.0"
)

-- =========================================================
-- 1. LIBS & MEDIA REGISTRATION
-- =========================================================
local LSM = LibStub("LibSharedMedia-3.0")

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
        enableTimestamps = true,     -- Віртуальний чат додає таймстемпи у власному шарі
        timestampID = 2,            -- За замовчуванням HH:MM
        timestampColor = "68ccef",  -- Колір часу (світло-блакитний)
        useServerTime = false,      -- Використовувати локальний час ПК
        timestampPost = false,      -- Час на початку повідомлення

        -- === HISTORY ===
        useVirtualChat = false,      -- На Retail 12.x вимкнено: прямий chat-frame layer конфліктує з secret values
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
function ns.IsRetailSecretValueBuild()
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
        return false
    end

    if type(GetBuildInfo) ~= "function" then
        return true
    end

    local interfaceVersion = select(4, GetBuildInfo())
    return type(interfaceVersion) == "number" and interfaceVersion >= 120000
end

-- =========================================================
-- 6. SAFE TEXT HELPERS (WoW 12.0.x / Secret Values)
-- =========================================================
local tostring = tostring
local pcall = pcall
local type = type
local canaccessvalue = canaccessvalue

function ns.CanAccessChatValue(...)
    if type(canaccessvalue) ~= "function" then
        return true
    end

    local ok, accessible = pcall(canaccessvalue, ...)
    return ok and accessible or false
end

function ns.EnforceRetailSafeMode(db)
    if not db or not ns.IsRetailSecretValueBuild() then
        return false
    end

    -- Runtime-only safe mode for Retail 12.x.
    -- Do NOT rewrite user preferences here, otherwise the same SavedVariables
    -- stay crippled when the addon is loaded on older Retail clients.
    return true
end

function ns.RunRetailCompatibilityMigration(db)
    if not db or ns.IsRetailSecretValueBuild() then
        return false
    end

    if db._chatifyCompatMigrated then
        return false
    end

    -- Older safe-retail builds force-disabled several features directly in the DB.
    -- If we detect that exact legacy pattern on a pre-12.x Retail build, restore
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

function ns.TryMakeSafeText(raw)
    if raw == nil then
        return nil
    end

    local rawType = type(raw)
    if rawType == "number" then
        return tostring(raw)
    end

    if rawType == "string" then
        if not ns.CanAccessChatValue(raw) then
            return nil
        end
        return raw
    end

    return nil
end
