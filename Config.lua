local addonName, ns = ...

-- =========================================================
-- 1. LIBS & MEDIA REGISTRATION
-- =========================================================
local LSM = LibStub("LibSharedMedia-3.0")

LSM:Register("sound", "Chatify Default", "Interface\\AddOns\\Chatify\\Assets\\Alert\\notification-0.ogg")

-- =========================================================
-- 2. GLOBAL LISTS (CONSTANTS)
-- =========================================================
ns.Lists = {}

-- Font List
ns.Lists.Fonts = {
    [1] = { name = "Exo 2 (Addon Font)",   path = "Interface\\AddOns\\Chatify\\Assets\\Fonts\\Exo2.ttf" },
    [2] = { name = "Friz Quadrata (WoW)",  path = "Fonts\\FRIZQT__.TTF" },
    [3] = { name = "Arial Narrow (WoW)",   path = "Fonts\\ARIALN.TTF" },
    [4] = { name = "Skurri (WoW)",         path = "Fonts\\skurri.ttf" },
    [5] = { name = "Morpheus (Quest)",     path = "Fonts\\MORPHEUS.TTF" },
}

-- Time Format List
ns.Lists.TimeFormats = {
    [1] = { name = "HH:MM (12:30)",            format = "%H:%M" },
    [2] = { name = "HH:MM:SS (12:30:45)",      format = "%H:%M:%S" },
    [3] = { name = "D.M-HH:MM (08.02-12:30)",  format = "%d.%m-%H:%M" },
}

-- =========================================================
-- 3. DEFAULT SETTINGS
-- =========================================================
ns.defaults = {
    profile = {
        -- === VISUALS ===
        fontID = 1,
        fontOutline = "",
        
        -- === TIME ===
        timestampID = 1,
        timestampColor = "68ccef",
        useServerTime = false,
        timestampPost = false,

        -- === HISTORY ===
        enableHistory = true,
        historyLimit = 50,
        historyAlpha = true,

        -- === SPAM FILTERS ===
        enableSpamFilter = true,
        spamKeywords = { "BOOST", "CARRY", "GOLD", "CHEAP", "WTS", "SELLING", "SERVICES" },

        -- === FORMATTING ===
        shortChannels = true,
        channelMap = {
            ["Guild"] = "[G]", ["Party"] = "[P]", ["Raid"] = "[R]",
            ["Officer"] = "[O]", ["General"] = "[Gen]", ["Trade"] = "[T]",
            ["Services"] = "[S]", ["LocalDefense"] = "[LD]",
            ["LookingForGroup"] = "[LFG]", ["Instance Chat"] = "[I]"
        },

        -- === COLORS ===
        myHighlightColor = "ff0000",
        highlightKeywords = { UnitName("player") },
        urlColor = "0099FF",

        -- === SOUNDS (NEW) ===
        sounds = {
            enable = true,
            masterVolume = true, -- Use Master channel instead of SFX
            events = {
                ["WHISPER"] = "Chatify Default",
                ["GUILD"]   = "None",
                ["PARTY"]   = "None",
                ["RAID"]    = "None",
                ["MENTION"] = "Chatify Default", -- Custom sound for name highlight
            }
        }
    }
}