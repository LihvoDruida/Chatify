local addonName, ns = ...

-- =========================================================
-- 1. GLOBAL LISTS (CONSTANTS)
-- This section defines options for the settings menu.
-- =========================================================
ns.Lists = {}

-- Font List
ns.Lists.Fonts = {
    [1] = { name = "Exo 2 (Addon Font)",   path = "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf" },
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
-- 2. DEFAULT SETTINGS
-- These values are used upon the first addon load.
-- =========================================================
ns.defaults = {
    profile = {
        -- === VISUALS ===
        fontID = 1,                      -- Refers to Exo 2
        fontOutline = "",                -- Variants: "NONE", "OUTLINE", "THICKOUTLINE"
        enableSoundAlerts = true,        -- Sound on whisper or name mention

        -- === CHAT HISTORY ===
        enableHistory = true,            -- Save chat history after reload/relog
        historyLimit = 50,               -- Number of lines to save
        historyAlpha = true,             -- Gray out old history messages

        -- === SPAM FILTERS ===
        enableSpamFilter = true,
        spamKeywords = { 
            "BOOST", "CARRY", "GOLD", "CHEAP", "WTS", "SELLING", "SERVICES" 
        },

        -- === FORMATTING ===
        shortChannels = true,            -- Shorten channel names
        channelMap = {
            ["Guild"] = "[G]", 
            ["Party"] = "[P]", 
            ["Raid"] = "[R]",
            ["Officer"] = "[O]", 
            ["General"] = "[Gen]", 
            ["Trade"] = "[T]",
            ["Services"] = "[S]", 
            ["LocalDefense"] = "[LD]",
            ["LookingForGroup"] = "[LFG]",
            ["Instance Chat"] = "[I]"
        },

        -- === COLORS ===
        myHighlightColor = "ff0000",     -- Red for highlighting keywords
        highlightKeywords = { UnitName("player") }, -- Auto-add player name
        urlColor = "0099FF",             -- Color for clickable links

        -- === TIME (UPDATED) ===
        timestampID = 1,                 -- Refers to %H:%M
        timestampColor = "68ccef",
        useServerTime = false,           -- [NEW] Use Realm Time
        timestampPost = false,           -- [NEW] Show at end of message
    }
}