local addonName, ns = ...

-- Create Addon Object
local Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify", "AceConsole-3.0")

-- =========================================================
-- 1. SETTINGS TABLE (ACE CONFIG)
-- =========================================================
function Chatify:GetOptions()
    local options = {
        name = "Chatify Settings",
        handler = Chatify,
        type = "group",
        args = {
            -- HEADER
            headerInfo = {
                order = 0,
                type = "description",
                name = "|cff33ff99Chatify|r v" .. (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0"),
                fontSize = "medium",
            },
            
            -- TABS BUTTON
            btnSetup = {
                order = 1,
                name = "Create Chat Tabs",
                desc = "Automatically creates Whisper, Guild, and Party tabs",
                type = "execute",
                func = "SetupDefaultTabs", 
                width = "full",
            },

            -- 1. GENERAL
            groupGeneral = {
                name = "General",
                type = "group",
                order = 10,
                inline = true,
                args = {
                    shortChannels = {
                        order = 1,
                        name = "Shorten Channels",
                        desc = "Example: [Party] -> [P]",
                        type = "toggle",
                        set = function(info, val) self.db.profile.shortChannels = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.shortChannels end,
                    },
                    enableSoundAlerts = {
                        order = 2,
                        name = "Sound Alerts",
                        desc = "Play sound on Whisper or name mention",
                        type = "toggle",
                        set = function(info, val) self.db.profile.enableSoundAlerts = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.enableSoundAlerts end,
                    },
                }
            },

            -- 2. VISUALS
            groupVisuals = {
                name = "Visuals",
                type = "group",
                order = 20,
                inline = true,
                args = {
                    fontID = {
                        order = 1,
                        name = "Chat Font",
                        type = "select",
                        values = function() 
                            local t = {}
                            if ns.Lists and ns.Lists.Fonts then
                                for i, v in ipairs(ns.Lists.Fonts) do t[i] = v.name end
                            else
                                t[1] = "Default"
                            end
                            return t 
                        end,
                        set = function(info, val) self.db.profile.fontID = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.fontID end,
                    },
                    timestampID = {
                        order = 2,
                        name = "Time Format",
                        type = "select",
                        values = function()
                            local t = {}
                            if ns.Lists and ns.Lists.TimeFormats then
                                for i, v in ipairs(ns.Lists.TimeFormats) do t[i] = v.name end
                            else
                                t[1] = "None"
                            end
                            return t
                        end,
                        set = function(info, val) self.db.profile.timestampID = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.timestampID end,
                    }
                }
            },

            -- 3. SPAM FILTER (Order 30)
            groupSpam = {
                name = "Spam Filter",
                type = "group",
                order = 30,
                args = {
                    enableSpamFilter = {
                        order = 1,
                        name = "Enable Filter",
                        type = "toggle",
                        set = function(info, val) self.db.profile.enableSpamFilter = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.enableSpamFilter end,
                    },
                    addKeyword = {
                        order = 2,
                        name = "Add Keyword",
                        desc = "Type a word and press Enter to add",
                        type = "input",
                        set = function(info, val)
                            if val and val ~= "" then
                                table.insert(self.db.profile.spamKeywords, val)
                                ns.ApplyVisuals()
                            end
                        end,
                        get = function(info) return "" end,
                    },
                    removeKeyword = {
                        order = 3,
                        name = "Remove Keyword",
                        type = "select",
                        style = "dropdown",
                        values = function()
                            local t = {}
                            for i, word in ipairs(self.db.profile.spamKeywords) do
                                t[i] = word
                            end
                            return t
                        end,
                        set = function(info, key)
                            table.remove(self.db.profile.spamKeywords, key)
                            ns.ApplyVisuals()
                        end,
                        get = function(info) return nil end,
                        confirm = true,
                        confirmText = "Delete this keyword?",
                    },
                    listDesc = {
                        order = 4,
                        type = "description",
                        name = function() return "\n|cffaaaaaaBlocklist:|r " .. table.concat(self.db.profile.spamKeywords, ", ") end,
                    }
                }
            },

            -- 4. CHAT HISTORY (Order 40)
            groupHistory = {
                name = "Chat History",
                type = "group",
                order = 40,
                inline = true,
                args = {
                    enableHistory = {
                        order = 1,
                        name = "Save History",
                        desc = "Restores chat messages after reload or relog",
                        type = "toggle",
                        set = function(info, val) 
                            self.db.profile.enableHistory = val 
                        end,
                        get = function(info) return self.db.profile.enableHistory end,
                    },
                    historyAlpha = {
                        order = 2,
                        name = "Gray History",
                        desc = "Makes restored messages gray to distinguish them from new ones",
                        type = "toggle",
                        set = function(info, val) 
                            self.db.profile.historyAlpha = val 
                        end,
                        get = function(info) return self.db.profile.historyAlpha end,
                    },
                    historyLimit = {
                        order = 3,
                        name = "Line Limit",
                        desc = "Number of lines to save per chat window",
                        type = "range",
                        min = 10, 
                        max = 100, 
                        step = 10,
                        set = function(info, val) 
                            self.db.profile.historyLimit = val 
                        end,
                        get = function(info) return self.db.profile.historyLimit end,
                    }
                }
            }
        }
    }
    return options
end

-- =========================================================
-- 2. INITIALIZATION LOGIC
-- =========================================================
function Chatify:OnInitialize()
    -- Перевірка дефолтних налаштувань
    if not ns.defaults then
        ns.defaults = { profile = { spamKeywords = {} } } -- Fallback
    end

    -- Ініціалізація бази даних
    self.db = LibStub("AceDB-3.0"):New("ChatifyDB", ns.defaults, true)
    
    -- Колбеки для зміни профілю
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    -- Прив'язка до ns.db
    ns.db = self.db.profile 

    -- Реєстрація меню
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Chatify", self:GetOptions())
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Chatify", "Chatify")

    -- Реєстрація команд
    self:RegisterChatCommand("chatify", "OpenConfig")
    self:RegisterChatCommand("mcm", "OpenConfig")
    
    -- Хук для візуалізації
    ns.ApplyVisuals = ns.ApplyVisuals or function() end
end

-- Функція оновлення конфігу при зміні профілю
function Chatify:RefreshConfig()
    ns.db = self.db.profile
    if ns.ApplyVisuals then ns.ApplyVisuals() end
end

function Chatify:OnEnable()
    ns.ApplyVisuals()
end

function Chatify:OpenConfig()
    -- Відкриття налаштувань (нове API vs старе API)
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsFrame.name)
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

-- =========================================================
-- 3. AUTO TABS FUNCTION
-- =========================================================
function Chatify:SetupDefaultTabs()
    if InCombatLockdown() then return end
    
    local tabs = {
        { name = "Whisper", groups = { "WHISPER", "BN_WHISPER" } },
        { name = "Guild", groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
        { name = "Party", groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } }
    }

    local count = 0
    for _, tabInfo in ipairs(tabs) do
        local frame = FCF_OpenNewWindow(tabInfo.name)
        if frame then
            count = count + 1
            ChatFrame_RemoveAllMessageGroups(frame)
            ChatFrame_RemoveAllChannels(frame)
            for _, group in ipairs(tabInfo.groups) do
                ChatFrame_AddMessageGroup(frame, group)
            end
            if FCF_SelectDockFrame then FCF_SelectDockFrame(frame) end
        end
    end
    self:Print("Tabs created: " .. count)
end