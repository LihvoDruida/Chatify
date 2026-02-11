local addonName, ns = ...

-- Create Addon Object
local Chatify = LibStub("AceAddon-3.0"):NewAddon("Chatify", "AceConsole-3.0")

-- =========================================================
-- 4. SETTINGS TABLE (ACE CONFIG)
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
                }
            },

            -- 2. VISUALS & TIME
            groupVisuals = {
                name = "Visuals & Time",
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
                    },
                    useServerTime = {
                        order = 3,
                        name = "Server Time",
                        desc = "Use Realm time instead of Local computer time",
                        type = "toggle",
                        set = function(info, val) self.db.profile.useServerTime = val end,
                        get = function(info) return self.db.profile.useServerTime end,
                    },
                    timestampPost = {
                        order = 4,
                        name = "Time at End",
                        desc = "Show timestamp at the end of the message",
                        type = "toggle",
                        set = function(info, val) self.db.profile.timestampPost = val end,
                        get = function(info) return self.db.profile.timestampPost end,
                    }
                }
            },

            -- 3. SPAM FILTER
            groupSpam = {
                name = "Spam Filter",
                type = "group",
                order = 30,
                args = {
                    enableSpamFilter = {
                        order = 1,
                        name = "Enable Filter",
                        type = "toggle",
                        set = function(info, val) self.db.profile.enableSpamFilter = val end,
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
                            for i, word in ipairs(self.db.profile.spamKeywords) do t[i] = word end
                            return t
                        end,
                        set = function(info, key) table.remove(self.db.profile.spamKeywords, key) end,
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

            -- 4. CHAT HISTORY
            groupHistory = {
                name = "Chat History",
                type = "group",
                order = 40,
                inline = true,
                args = {
                    enableHistory = {
                        order = 1,
                        name = "Save History",
                        type = "toggle",
                        set = function(info, val) self.db.profile.enableHistory = val end,
                        get = function(info) return self.db.profile.enableHistory end,
                    },
                    historyAlpha = {
                        order = 2,
                        name = "Gray History",
                        type = "toggle",
                        set = function(info, val) self.db.profile.historyAlpha = val end,
                        get = function(info) return self.db.profile.historyAlpha end,
                    },
                    historyLimit = {
                        order = 3,
                        name = "Line Limit",
                        type = "range",
                        min = 10, max = 100, step = 10,
                        set = function(info, val) self.db.profile.historyLimit = val end,
                        get = function(info) return self.db.profile.historyLimit end,
                    }
                }
            },

            -- 5. SOUNDS (LSM INTEGRATION)
            groupSounds = {
                name = "Sounds",
                type = "group",
                order = 50,
                args = {
                    enable = {
                        order = 1,
                        name = "Enable Sounds",
                        type = "toggle",
                        set = function(info, val) self.db.profile.sounds.enable = val end,
                        get = function(info) return self.db.profile.sounds.enable end,
                    },
                    masterChannel = {
                        order = 2,
                        name = "Use Master Channel",
                        desc = "Play sounds even if SFX is muted",
                        type = "toggle",
                        set = function(info, val) self.db.profile.sounds.masterVolume = val end,
                        get = function(info) return self.db.profile.sounds.masterVolume end,
                    },
                    headerEvents = { order = 10, type = "header", name = "Events" },
                    
                    soundWhisper = {
                        order = 11,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Whisper",
                        values = AceGUIWidgetLSMlists.sound,
                        set = function(info, val) self.db.profile.sounds.events["WHISPER"] = val end,
                        get = function(info) return self.db.profile.sounds.events["WHISPER"] end,
                    },
                    soundMention = {
                        order = 12,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Name Mention",
                        values = AceGUIWidgetLSMlists.sound,
                        set = function(info, val) self.db.profile.sounds.events["MENTION"] = val end,
                        get = function(info) return self.db.profile.sounds.events["MENTION"] end,
                    },
                    soundGuild = {
                        order = 13,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Guild / Officer",
                        values = AceGUIWidgetLSMlists.sound,
                        set = function(info, val) self.db.profile.sounds.events["GUILD"] = val end,
                        get = function(info) return self.db.profile.sounds.events["GUILD"] end,
                    },
                    soundParty = {
                        order = 14,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Party",
                        values = AceGUIWidgetLSMlists.sound,
                        set = function(info, val) self.db.profile.sounds.events["PARTY"] = val end,
                        get = function(info) return self.db.profile.sounds.events["PARTY"] end,
                    },
                    soundRaid = {
                        order = 15,
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Raid",
                        values = AceGUIWidgetLSMlists.sound,
                        set = function(info, val) self.db.profile.sounds.events["RAID"] = val end,
                        get = function(info) return self.db.profile.sounds.events["RAID"] end,
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