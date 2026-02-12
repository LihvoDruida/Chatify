local addonName, ns = ...

-- =========================================================
-- 1. LIBS & MEDIA REGISTRATION
-- =========================================================
local LSM = LibStub("LibSharedMedia-3.0")

-- Реєструємо ваші асети в глобальну бібліотеку
-- Це дозволяє вибирати їх у випадаючих списках Config.lua
LSM:Register("sound", "Chatify Default", "Interface\\AddOns\\Chatify\\Assets\\Alert\\notification-0.ogg")
LSM:Register("font", "Exo 2 (Chatify)", "Interface\\AddOns\\Chatify\\Assets\\Fonts\\Exo2.ttf")

-- =========================================================
-- 2. GLOBAL LISTS (CONSTANTS)
-- =========================================================
ns.Lists = {}

-- Список шрифтів (Fallback, якщо LSM не працює)
ns.Lists.Fonts = {
    [1] = { name = "Exo 2 (Chatify)",      path = "Interface\\AddOns\\Chatify\\Assets\\Fonts\\Exo2.ttf" },
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
-- 3. DEFAULT SETTINGS
-- =========================================================
ns.defaults = {
    profile = {
        -- === VISUALS ===
        fontID = "Exo 2 (Chatify)", -- Дефолтний шрифт (по назві з LSM)
        fontOutline = "",    -- Контур тексту для кращої читабельності
        
        -- === TIME ===
        timestampID = 2,            -- За замовчуванням HH:MM
        timestampColor = "68ccef",  -- Колір часу (світло-блакитний)
        useServerTime = false,      -- Використовувати локальний час ПК
        timestampPost = false,      -- Час на початку повідомлення

        -- === HISTORY ===
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
        }
    }
}