local addonName, ns = ...

-- 1. ГЛОБАЛЬНІ СПИСКИ (Джерело правди)
ns.Lists = {}

ns.Lists.Fonts = {
    [1] = { name = "Exo 2 (Ваш вибір)",    path = "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf" },
    [2] = { name = "Friz Quadrata (WoW)",  path = "Fonts\\FRIZQT__.TTF" },
    [3] = { name = "Arial Narrow (WoW)",   path = "Fonts\\ARIALN.TTF" },
    [4] = { name = "Skurri (WoW)",         path = "Fonts\\skurri.ttf" },
    [5] = { name = "Morpheus (Quest)",     path = "Fonts\\MORPHEUS.TTF" },
}

ns.Lists.TimeFormats = {
    [1] = { name = "ГГ:ХВ (12:30)",            format = "%H:%M" },
    [2] = { name = "ГГ:ХВ:С (12:30:45)",       format = "%H:%M:%S" },
    [3] = { name = "Д.М-ГГ:ХВ (08.02-12:30)",  format = "%d.%m-%H:%M" },
}

-- 2. ДЕФОЛТНІ НАЛАШТУВАННЯ (Зберігаємо тільки ID!)
local defaults = {
    -- ВІЗУАЛ (ID)
    fontID = 1,             -- Посилається на Exo 2
    fontOutline = "",       -- "NONE", "OUTLINE", "THICKOUTLINE"
    
    enableSoundAlerts = true, -- або false, як забажаєш

    -- ІСТОРІЯ ЧАТУ
    enableHistory = true,      -- Увімкнути історію
    historyLimit = 50,         -- Кількість повідомлень для збереження
    historyAlpha = true,       -- Робити історію трохи прозорою/сірою
    
    -- ФІЛЬТРИ
    enableSpamFilter = true,
    spamKeywords = { "BOOST", "CARRY", "GOLD", "CHEAP" },

    -- ФОРМАТУВАННЯ
    shortChannels = true, 
    channelMap = {
        ["Guild"] = "[G]", ["Party"] = "[P]", ["Raid"] = "[R]",
        ["Officer"] = "[O]", ["General"] = "[Gen]", ["Trade"] = "[T]",
        ["Services"] = "[S]", ["LocalDefense"] = "[LD]"
    },

    -- КОЛЬОРИ
    myHighlightColor = "ff0000",
    highlightKeywords = {"Dmytro", "Khayen"},
    urlColor = "0099FF",

    -- ЧАС (ID)
    timestampID = 1,        -- Посилається на %H:%M
    timestampColor = "68ccef"
}

function ns.LoadConfig()
    if not ChatifyDB then
        ChatifyDB = CopyTable(defaults)
    else
        for key, value in pairs(defaults) do
            if ChatifyDB[key] == nil then ChatifyDB[key] = value end
        end
    end
    ns.db = ChatifyDB
end