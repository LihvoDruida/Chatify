local addonName, ns = ...

-- Create Addon Object
local Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify", "AceConsole-3.0")

-- =========================================================
-- 4. SETTINGS TABLE (ACE CONFIG)
-- =========================================================
function Chatify:GetOptions()
    local options = {
        name = "Chatify", 
        handler = Chatify,
        type = "group",
        childGroups = "tab", 
        args = {
            -- HEADER
            headerInfo = {
                order = 0,
                type = "description",
                name = " |cff33ff99Chatify|r  |cff777777v" .. (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0") .. "|r\n" ..
                       " |cffffffffMinimalist Chat Enhancer|r\n" ..
                       " |cff999999Tabs • Spam Filter • Sounds • History|r",
                fontSize = "large",
                image = "Interface\\AddOns\\Chatify\\Assets\\icon", 
                imageWidth = 64, 
                imageHeight = 64,
            },

            headerSpacer = {
                order = 0.5,
                type = "description",
                name = "\n", 
            },

            -- TAB 1: GENERAL & APPEARANCE
            tabGeneral = {
                name = "General & Visuals",
                type = "group",
                order = 10,
                args = {
                    headerText = { order = 1, type = "header", name = "Text Formatting" },
                    
                    shortChannels = {
                        order = 2,
                        name = "Shorten Channel Names",
                        desc = "Compact channel names to save space.\n\nExample:\n|cffaaaaaa[Party]|r becomes |cffaaaaaa[P]|r",
                        type = "toggle",
                        width = "full", 
                        set = function(info, val) self.db.profile.shortChannels = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.shortChannels end,
                    },

                    fontID = {
                        order = 3,
                        name = "Chat Font",
                        desc = "Select the typeface used for chat messages.",
                        type = "select",
                        width = "double",
                        dialogControl = "LSM30_Font",
                        values = AceGUIWidgetLSMlists.font, -- Auto-fill from LSM
                        set = function(info, val) self.db.profile.fontID = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.fontID end,
                    },

                    headerTime = { order = 10, type = "header", name = "Timestamps" },

                    timestampID = {
                        order = 11,
                        name = "Time Format",
                        type = "select",
                        width = "normal",
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
                    },
                    
                    useServerTime = {
                        order = 12,
                        name = "Use Server Time",
                        desc = "If checked, uses Realm time.\nIf unchecked, uses Local Computer time.",
                        type = "toggle",
                        set = function(info, val) self.db.profile.useServerTime = val end,
                        get = function(info) return self.db.profile.useServerTime end,
                    },
                    
                    timestampPost = {
                        order = 13,
                        name = "Show at End",
                        desc = "Place timestamp at the end of the message.",
                        type = "toggle",
                        set = function(info, val) self.db.profile.timestampPost = val end,
                        get = function(info) return self.db.profile.timestampPost end,
                    }
                }
            },

            -- TAB 2: SOUNDS
            tabSounds = {
                name = "Sounds",
                type = "group",
                order = 20,
                args = {
                    headerMaster = { order = 1, type = "header", name = "Master Settings" },
                    
                    enable = {
                        order = 2,
                        name = "Enable Chat Sounds",
                        desc = "Toggle all sound effects.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.sounds.enable = val end,
                        get = function(info) return self.db.profile.sounds.enable end,
                    },
                    masterChannel = {
                        order = 3,
                        name = "Force Master Channel",
                        desc = "Play sounds through 'Master' channel to hear them even if SFX is muted.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.masterVolume = val end,
                        get = function(info) return self.db.profile.sounds.masterVolume end,
                    },

                    headerEvents = { order = 10, type = "header", name = "Event Notifications" },
                    
                    soundWhisper = {
                        order = 11,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Whisper Received",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["WHISPER"] = val end,
                        get = function(info) return self.db.profile.sounds.events["WHISPER"] end,
                    },
                    soundMention = {
                        order = 12,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Name Mentioned",
                        desc = "Plays when someone types your name.",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["MENTION"] = val end,
                        get = function(info) return self.db.profile.sounds.events["MENTION"] end,
                    },
                    
                    spacer1 = { order = 12.5, type = "description", name = " " }, 

                    soundGuild = {
                        order = 13,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Guild Chat",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["GUILD"] = val end,
                        get = function(info) return self.db.profile.sounds.events["GUILD"] end,
                    },
                    soundParty = {
                        order = 14,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Party Chat",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["PARTY"] = val end,
                        get = function(info) return self.db.profile.sounds.events["PARTY"] end,
                    },
                    soundRaid = {
                        order = 15,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Raid Chat",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["RAID"] = val end,
                        get = function(info) return self.db.profile.sounds.events["RAID"] end,
                    },
                }
            },

            -- TAB 3: FILTERS & HISTORY
            tabTools = {
                name = "Filters & History",
                type = "group",
                order = 30,
                args = {
                    -- 1. SPAM FILTER GROUP
                    groupSpam = {
                        name = "Spam & System Filters",
                        type = "group",
                        inline = true, 
                        order = 1,
                        args = {
                            enableSpamFilter = {
                                order = 1,
                                name = "Enable Keyword Blocking",
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.enableSpamFilter = val; if ns.UpdateSpamCache then ns.UpdateSpamCache() end end,
                                get = function(info) return self.db.profile.enableSpamFilter end,
                            },
                            
                            -- NEW: Anti-Flood & System Cleaners
                            enableThrottle = {
                                order = 2,
                                name = "Block Repeated Messages (Anti-Flood)",
                                desc = "Prevents people from spamming the exact same message multiple times in a row.",
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableThrottle = val end,
                                get = function(info) return self.db.profile.enableThrottle end,
                            },
                            hideSystemSpam = {
                                order = 3,
                                name = "Hide Join/Leave Messages",
                                desc = "Hides yellow system messages when players join or leave channels.",
                                type = "toggle",
                                set = function(info, val) self.db.profile.hideSystemSpam = val end,
                                get = function(info) return self.db.profile.hideSystemSpam end,
                            },

                            headerKeywords = { order = 4, type = "header", name = "Blocklist Management" },

                            addKeyword = {
                                order = 5,
                                name = "Add Keyword",
                                desc = "Type a word to block (e.g., 'boost', 'WTS') and press Enter.",
                                type = "input",
                                width = "full",
                                set = function(info, val)
                                    if val and val ~= "" then
                                        table.insert(self.db.profile.spamKeywords, val)
                                        if ns.UpdateSpamCache then ns.UpdateSpamCache() end -- Update Cache immediately
                                    end
                                end,
                                get = function(info) return "" end,
                            },
                            removeKeyword = {
                                order = 6,
                                name = "Remove Keyword",
                                type = "select",
                                style = "dropdown",
                                width = "full",
                                values = function()
                                    local t = {}
                                    for i, word in ipairs(self.db.profile.spamKeywords) do t[i] = word end
                                    return t
                                end,
                                set = function(info, key) 
                                    table.remove(self.db.profile.spamKeywords, key)
                                    if ns.UpdateSpamCache then ns.UpdateSpamCache() end -- Update Cache immediately
                                end,
                                get = function(info) return nil end,
                                confirm = true,
                                confirmText = "Remove this keyword?",
                            },
                            curList = {
                                order = 7,
                                type = "description",
                                name = function() 
                                    if #self.db.profile.spamKeywords == 0 then return "\n|cff888888(Blocklist is empty)|r" end
                                    return "\n|cffff0000Blocked Words:|r " .. table.concat(self.db.profile.spamKeywords, ", ") 
                                end,
                            }
                        }
                    },

                    -- 2. HISTORY GROUP
                    groupHistory = {
                        name = "Chat History",
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            enableHistory = {
                                order = 1,
                                name = "Enable History",
                                desc = "Restores chat messages after you reload the UI or login.",
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableHistory = val end,
                                get = function(info) return self.db.profile.enableHistory end,
                            },
                            historyAlpha = {
                                order = 2,
                                name = "Fade Old Messages",
                                desc = "Make restored history messages appear gray.",
                                type = "toggle",
                                disabled = function() return not self.db.profile.enableHistory end,
                                set = function(info, val) self.db.profile.historyAlpha = val end,
                                get = function(info) return self.db.profile.historyAlpha end,
                            },
                            historyLimit = {
                                order = 3,
                                name = "History Size",
                                desc = "Lines to keep.",
                                type = "range",
                                min = 10, max = 100, step = 10,
                                disabled = function() return not self.db.profile.enableHistory end,
                                set = function(info, val) self.db.profile.historyLimit = val end,
                                get = function(info) return self.db.profile.historyLimit end,
                            }
                        }
                    }
                }
            },

            -- TAB 4: SETUP / MAINTENANCE
            tabSetup = {
                name = "Setup & Reset",
                type = "group",
                order = 99, 
                args = {
                    headerSetup = { order = 1, type = "header", name = "Chat Tabs Setup" },
                    descSetup = {
                        order = 2,
                        type = "description",
                        name = "Automatically create separate chat tabs for Whispers, Guild, and Party chats.\n|cffffcc00Warning: Modifies chat window layout.|r",
                        fontSize = "medium",
                    },
                    btnSetup = {
                        order = 3,
                        name = "Run Auto-Setup",
                        type = "execute",
                        func = "SetupDefaultTabs", 
                        width = "full",
                        confirm = true,
                        confirmText = "Create new chat tabs?",
                    },

                    headerMaintenance = { order = 10, type = "header", name = "Maintenance" },
                    btnReset = {
                        order = 12,
                        name = "Reset All Settings",
                        desc = "|cffff0000Cannot be undone!|r",
                        type = "execute",
                        func = function() 
                            self.db:ResetProfile()
                            if ns.UpdateSpamCache then ns.UpdateSpamCache() end
                            self:Print("Configuration reset.")
                        end,
                        width = "full",
                        confirm = true,
                        confirmText = "|cffff0000WARNING:|r Reset all settings?",
                    },
                    btnReload = {
                        order = 13,
                        name = "Reload UI",
                        type = "execute",
                        func = function() ReloadUI() end,
                        width = "full",
                        confirm = true,
                        confirmText = "Reload UI now?",
                    },
                }
            }
        }
    }
    return options
end

-- =========================================================
-- 5. INITIALIZATION LOGIC
-- =========================================================
function Chatify:OnInitialize()
    -- Initialize DB
    if not ns.defaults then ns.defaults = { profile = { spamKeywords = {} } } end
    self.db = LibStub("AceDB-3.0"):New("ChatifyDB", ns.defaults, true)
    
    -- Register Callbacks
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    ns.db = self.db.profile 

    -- Setup Config GUI
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Chatify", self:GetOptions())
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Chatify", "Chatify")

    -- Chat Commands
    self:RegisterChatCommand("chatify", "OpenConfig")
    self:RegisterChatCommand("mcm", "OpenConfig")
    
    -- Initial Update
    if ns.ApplyVisuals then ns.ApplyVisuals() end
    if ns.UpdateSpamCache then ns.UpdateSpamCache() end -- Critical: Build cache on load
end

function Chatify:RefreshConfig()
    ns.db = self.db.profile
    if ns.ApplyVisuals then ns.ApplyVisuals() end
    if ns.UpdateSpamCache then ns.UpdateSpamCache() end -- Rebuild cache on profile change
end

function Chatify:OnEnable()
    if ns.ApplyVisuals then ns.ApplyVisuals() end
    if ns.UpdateSpamCache then ns.UpdateSpamCache() end
end

function Chatify:OpenConfig()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsFrame.name)
    else
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

-- =========================================================
-- 6. AUTO TABS FUNCTION
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