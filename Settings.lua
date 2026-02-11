local addonName, ns = ...

-- Create Addon Object
local Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify", "AceConsole-3.0")

-- =========================================================
-- 4. SETTINGS TABLE (ACE CONFIG)
-- =========================================================
function Chatify:GetOptions()
    local options = {
        name = "Chatify", -- Main Title
        handler = Chatify,
        type = "group",
        childGroups = "tab", -- CRITICAL: Switches layout to Tabs
        args = {
            headerInfo = {
                order = 0,
                type = "description",
                name = " |cff33ff99Chatify|r  |cff777777v" .. (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0") .. "|r\n" ..
                       " |cffffffffEnhance your chat experience.|r\n" ..
                       " |cff999999Spam Filter • Sound Notifications • History|r\n",
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
            -- Combined general tweaks and visual settings
            tabGeneral = {
                name = "General & Visuals",
                type = "group",
                order = 10,
                args = {
                    -- Section: Text Formatting
                    headerText = { order = 1, type = "header", name = "Text Formatting" },
                    
                    shortChannels = {
                        order = 2,
                        name = "Shorten Channel Names",
                        desc = "Compact channel names to save space.\n\nExample:\n|cffaaaaaa[Party]|r becomes |cffaaaaaa[P]|r\n|cffaaaaaa[Guild]|r becomes |cffaaaaaa[G]|r",
                        type = "toggle",
                        width = "full", -- Takes full line for better readability
                        set = function(info, val) self.db.profile.shortChannels = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.shortChannels end,
                    },

                    fontID = {
                        order = 3,
                        name = "Chat Font",
                        desc = "Select the typeface used for chat messages.",
                        type = "select",
                        width = "double", -- Wider dropdown looks better
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

                    -- Section: Time Settings
                    headerTime = { order = 10, type = "header", name = "Timestamps" },

                    timestampID = {
                        order = 11,
                        name = "Time Format",
                        desc = "Choose how the time is displayed next to messages.",
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
                        desc = "If checked, uses the Realm time.\nIf unchecked, uses your Local Computer time.",
                        type = "toggle",
                        set = function(info, val) self.db.profile.useServerTime = val end,
                        get = function(info) return self.db.profile.useServerTime end,
                    },
                    
                    timestampPost = {
                        order = 13,
                        name = "Show at End",
                        desc = "Place the timestamp at the end of the message instead of the beginning.",
                        type = "toggle",
                        set = function(info, val) self.db.profile.timestampPost = val end,
                        get = function(info) return self.db.profile.timestampPost end,
                    }
                }
            },

            -- TAB 2: SOUNDS & NOTIFICATIONS
            -- Cleaned up the wall of dropdowns
            tabSounds = {
                name = "Sounds",
                type = "group",
                order = 20,
                args = {
                    headerMaster = { order = 1, type = "header", name = "Master Settings" },
                    
                    enable = {
                        order = 2,
                        name = "Enable Chat Sounds",
                        desc = "Toggle all sound effects from this addon.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.sounds.enable = val end,
                        get = function(info) return self.db.profile.sounds.enable end,
                    },
                    masterChannel = {
                        order = 3,
                        name = "Force Master Channel",
                        desc = "Play sounds through the 'Master' channel.\nThis ensures you hear notifications even if 'Sound Effects' are muted in WoW settings.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.sounds.enable end, -- UX: Disable if master toggle is off
                        set = function(info, val) self.db.profile.sounds.masterVolume = val end,
                        get = function(info) return self.db.profile.sounds.masterVolume end,
                    },

                    headerEvents = { order = 10, type = "header", name = "Event Notifications" },
                    
                    -- Grouping these specifically makes it look cleaner
                    soundWhisper = {
                        order = 11,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Whisper Received",
                        desc = "Sound to play when you receive a private message.",
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
                        desc = "Sound to play when someone types your character name in chat.",
                        values = AceGUIWidgetLSMlists.sound,
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["MENTION"] = val end,
                        get = function(info) return self.db.profile.sounds.events["MENTION"] end,
                    },
                    
                    spacer1 = { order = 12.5, type = "description", name = " " }, -- Visual spacer

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
            -- Combined privacy/utility features
            tabTools = {
                name = "Filters & History",
                type = "group",
                order = 30,
                args = {
                    -- Spam Filter Group
                    groupSpam = {
                        name = "Spam Filter",
                        type = "group",
                        inline = true, -- Makes it a box inside the tab
                        order = 1,
                        args = {
                            enableSpamFilter = {
                                order = 1,
                                name = "Enable Filter",
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableSpamFilter = val end,
                                get = function(info) return self.db.profile.enableSpamFilter end,
                            },
                            helpText = {
                                order = 2,
                                type = "description",
                                name = "|cffaaaaaaInstructions: To block a message containing a specific word, type the word below and press Enter.|r",
                            },
                            addKeyword = {
                                order = 3,
                                name = "Add Keyword",
                                desc = "Type a word to block (e.g., 'boost', 'WTS')",
                                type = "input",
                                width = "full",
                                set = function(info, val)
                                    if val and val ~= "" then
                                        table.insert(self.db.profile.spamKeywords, val)
                                    end
                                end,
                                get = function(info) return "" end,
                            },
                            removeKeyword = {
                                order = 4,
                                name = "Remove Keyword",
                                desc = "Select a keyword to stop blocking it.",
                                type = "select",
                                style = "dropdown",
                                width = "full",
                                values = function()
                                    local t = {}
                                    for i, word in ipairs(self.db.profile.spamKeywords) do t[i] = word end
                                    return t
                                end,
                                set = function(info, key) table.remove(self.db.profile.spamKeywords, key) end,
                                get = function(info) return nil end,
                                confirm = true,
                                confirmText = "Remove this keyword from the blocklist?",
                            },
                            -- Displaying the list nicely
                            curList = {
                                order = 5,
                                type = "description",
                                name = function() 
                                    if #self.db.profile.spamKeywords == 0 then return "\n|cff888888(Blocklist is empty)|r" end
                                    return "\n|cffff0000Blocked Words:|r " .. table.concat(self.db.profile.spamKeywords, ", ") 
                                end,
                            }
                        }
                    },

                    -- Chat History Group
                    groupHistory = {
                        name = "Chat History",
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            desc = {
                                order = 0,
                                type = "description",
                                name = "Retains chat messages between sessions/reloads.",
                            },
                            enableHistory = {
                                order = 1,
                                name = "Enable History",
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableHistory = val end,
                                get = function(info) return self.db.profile.enableHistory end,
                            },
                            historyAlpha = {
                                order = 2,
                                name = "Fade Old Messages",
                                desc = "Make restored history messages appear gray/faded to distinguish them from new messages.",
                                type = "toggle",
                                disabled = function() return not self.db.profile.enableHistory end,
                                set = function(info, val) self.db.profile.historyAlpha = val end,
                                get = function(info) return self.db.profile.historyAlpha end,
                            },
                            historyLimit = {
                                order = 3,
                                name = "History Size (Lines)",
                                desc = "How many messages to keep. Higher numbers use more memory.",
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
                    -- 1. SETUP SECTION
                    headerSetup = { order = 1, type = "header", name = "Chat Tabs Setup" },
                    
                    descSetup = {
                        order = 2,
                        type = "description",
                        name = "This tool will automatically create separate chat tabs for Whispers, Guild, and Party chats. \n\n|cffffcc00Warning: This will modify your current chat window layout.|r",
                        fontSize = "medium",
                    },

                    btnSetup = {
                        order = 3,
                        name = "Run Auto-Setup",
                        desc = "Creates default tabs: Whisper, Guild, Party",
                        type = "execute",
                        func = "SetupDefaultTabs", 
                        width = "full",
                        confirm = true,
                        confirmText = "This will create new chat tabs. Continue?",
                    },

                    -- 2. MAINTENANCE SECTION (RESET & RELOAD)
                    headerMaintenance = { order = 10, type = "header", name = "Maintenance & Danger Zone" },

                    descReset = {
                        order = 11,
                        type = "description",
                        name = "If something is broken or you want to start fresh, use the options below.\n",
                        fontSize = "medium",
                    },

                    btnReset = {
                        order = 12,
                        name = "Reset All Settings",
                        desc = "Reverts all Chatify settings to default values. \n|cffff0000Cannot be undone!|r",
                        type = "execute",
                        func = function() 
                            self.db:ResetProfile() -- Built-in AceDB function
                            self:Print("Configuration reset to defaults.")
                        end,
                        width = "full",
                        confirm = true, -- Safety popup
                        confirmText = "|cffff0000WARNING:|r Are you sure you want to RESET all settings?",
                    },

                    btnReload = {
                        order = 13,
                        name = "Reload UI (/reload)",
                        desc = "Reloads the game interface. Useful if settings don't update immediately.",
                        type = "execute",
                        func = function() ReloadUI() end, -- WoW API function
                        width = "full",
                        confirm = true,
                        confirmText = "Reload User Interface now?",
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
    if not ns.defaults then ns.defaults = { profile = { spamKeywords = {} } } end

    self.db = LibStub("AceDB-3.0"):New("ChatifyDB", ns.defaults, true)
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    ns.db = self.db.profile 

    LibStub("AceConfig-3.0"):RegisterOptionsTable("Chatify", self:GetOptions())
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Chatify", "Chatify")

    self:RegisterChatCommand("chatify", "OpenConfig")
    self:RegisterChatCommand("mcm", "OpenConfig")
    
    if ns.ApplyVisuals then ns.ApplyVisuals() end
end

function Chatify:RefreshConfig()
    ns.db = self.db.profile
    if ns.ApplyVisuals then ns.ApplyVisuals() end
end

function Chatify:OnEnable()
    if ns.ApplyVisuals then ns.ApplyVisuals() end
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