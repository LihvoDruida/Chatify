local addonName, ns = ...
local Chatify = ns.Chatify

local function GetAddonMetadataValue(key)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, key)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addonName, key)
    end
    return nil
end

local function GetLSMFontValues()
    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font then
        return AceGUIWidgetLSMlists.font
    end

    local values = {}
    if LibStub and LibStub("LibSharedMedia-3.0", true) then
        local LSM = LibStub("LibSharedMedia-3.0")
        local ok, hash = pcall(LSM.HashTable, LSM, "font")
        if ok and type(hash) == "table" then
            for name in pairs(hash) do
                values[name] = name
            end
        end
    end

    if next(values) == nil and ns.Lists and ns.Lists.Fonts then
        for _, entry in ipairs(ns.Lists.Fonts) do
            if entry and entry.name then
                values[entry.name] = entry.name
            end
        end
    end

    return values
end

local function GetLSMSoundValues()
    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound then
        return AceGUIWidgetLSMlists.sound
    end

    local values = { ["None"] = "None" }
    if LibStub and LibStub("LibSharedMedia-3.0", true) then
        local LSM = LibStub("LibSharedMedia-3.0")
        local ok, hash = pcall(LSM.HashTable, LSM, "sound")
        if ok and type(hash) == "table" then
            for name in pairs(hash) do
                values[name] = name
            end
        end
    end

    values["Chatify Default"] = "Chatify Default"
    return values
end

local function GetLSMFontControl()
    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font then
        return "LSM30_Font"
    end
    return nil
end

local function GetLSMSoundControl()
    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound then
        return "LSM30_Sound"
    end
    return nil
end

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
                name = " |cff33ff99Chatify|r  |cff777777v" .. (GetAddonMetadataValue("Version") or "1.0") .. "|r\n" ..
                       " |cffffffffMinimalist Chat Enhancer|r\n" ..
                       " |cff999999Tabs • Spam Filter • Sounds • History|r",
                fontSize = "large",
                image = "Interface\\AddOns\\Chatify\\assets\\icon", 
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
                name = "General & Visual",
                type = "group",
                order = 10,
                args = {
                    headerText = { order = 1, type = "header", name = "Text Formatting" },
                    
                    shortChannels = {
                        order = 2,
                        name = "Shorten Channel Names",
                        desc = "Compact channel names to save space.\n\nExample:\n|cffaaaaaa[Party]|r becomes |cffaaaaaa[P]|r\n\n|cff999999Retail 12.x: applied through the safe formatting path.|r",
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
                        dialogControl = GetLSMFontControl(),
                        values = GetLSMFontValues(),
                        set = function(info, val) self.db.profile.fontID = val; ns.ApplyVisuals() end,
                        get = function(info) return self.db.profile.fontID end,
                    },

                    hoverHyperlinkTooltips = {
                        order = 4,
                        name = "Show Link Tooltips on Hover",
                        desc = "When enabled, item/spell/achievement links in chat show their tooltip on mouseover.\n" ..
                               "Disable this if hover-tooltips keep getting in your way.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.hoverHyperlinkTooltips = val end,
                        get = function(info)
                            if self.db.profile.hoverHyperlinkTooltips == nil then
                                return true
                            end
                            return self.db.profile.hoverHyperlinkTooltips
                        end,
                    },

                    headerQuickChat = { order = 5, type = "header", name = "Quick Chat Buttons" },

                    quickChatButtons = {
                        order = 6,
                        name = "Enable Quick Chat Buttons",
                        desc = "Show quick channel buttons on the right side of the chat frame, anchored from the bottom.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.quickChatButtons = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            if self.db.profile.quickChatButtons == nil then
                                return true
                            end
                            return self.db.profile.quickChatButtons
                        end,
                    },

                    quickChatButtonTheme = {
                        order = 7,
                        name = "Quick Button Skin",
                        desc = "Choose how quick chat buttons are styled. Auto prefers GW2 UI when its chat module is active, otherwise ElvUI, otherwise the standard Chatify style.",
                        type = "select",
                        width = "normal",
                        values = {
                            AUTO = "Auto",
                            STANDARD = "Standard",
                            ELVUI = "ElvUI",
                            GW2UI = "GW2 UI",
                        },
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonTheme = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonTheme or "AUTO"
                        end,
                    },

                    quickChatButtonSize = {
                        order = 8,
                        name = "Quick Button Size",
                        desc = "Adjust the base size of the quick chat buttons. They still resize down automatically when the chat frame becomes smaller.",
                        type = "range",
                        min = 16,
                        max = 40,
                        step = 1,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonSize = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonSize or 24
                        end,
                    },

                    quickChatButtonSpacing = {
                        order = 9,
                        name = "Quick Button Spacing",
                        desc = "Adjust the vertical spacing between quick chat buttons.",
                        type = "range",
                        min = 2,
                        max = 10,
                        step = 1,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonSpacing = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonSpacing or 4
                        end,
                    },

                    quickChatButtonFontScale = {
                        order = 10,
                        name = "Quick Button Label Scale",
                        desc = "Adjust the text scale inside the quick chat buttons.",
                        type = "range",
                        min = 0.8,
                        max = 1.3,
                        step = 0.05,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonFontScale = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonFontScale or 1
                        end,
                    },

                    quickChatButtonGap = {
                        order = 11,
                        name = "Quick Button Offset",
                        desc = "Adjust how far the quick chat buttons sit from the right side of the chat frame.",
                        type = "range",
                        min = 8,
                        max = 36,
                        step = 1,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonGap = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonGap or 18
                        end,
                    },

                    quickChatButtonAlpha = {
                        order = 12,
                        name = "Quick Button Opacity",
                        desc = "Adjust the opacity of the quick chat buttons.",
                        type = "range",
                        min = 0.25,
                        max = 1,
                        step = 0.05,
                        isPercent = true,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonAlpha = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonAlpha or 0.92
                        end,
                    },

                    headerTime = { order = 13, type = "header", name = "Timestamps" },

                    timestampID = {
                        order = 16,
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
                        order = 15,
                        name = "Use Server Time",
                        desc = "If checked, uses Realm time.\nIf unchecked, uses Local Computer time.",
                        type = "toggle",
                        set = function(info, val) self.db.profile.useServerTime = val end,
                        get = function(info) return self.db.profile.useServerTime end,
                    },
                    
                    timestampPost = {
                        order = 13,
                        name = "Show at End",
                        desc = "Place timestamp at the end of the message.\n\n|cff999999Retail 12.x: applied only for safely accessible chat payloads.|r",
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
                        dialogControl = GetLSMSoundControl(),
                        name = "Whisper Received",
                        values = GetLSMSoundValues(),
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["WHISPER"] = val end,
                        get = function(info) return self.db.profile.sounds.events["WHISPER"] end,
                    },
                    soundMention = {
                        order = 12,
                        type = "select",
                        dialogControl = GetLSMSoundControl(),
                        name = "Name Mentioned",
                        desc = "Plays when someone types your name.",
                        values = GetLSMSoundValues(),
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["MENTION"] = val end,
                        get = function(info) return self.db.profile.sounds.events["MENTION"] end,
                    },
                    
                    spacer1 = { order = 12.5, type = "description", name = " " }, 

                    soundGuild = {
                        order = 13,
                        type = "select",
                        dialogControl = GetLSMSoundControl(),
                        name = "Guild Chat",
                        values = GetLSMSoundValues(),
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["GUILD"] = val end,
                        get = function(info) return self.db.profile.sounds.events["GUILD"] end,
                    },
                    soundParty = {
                        order = 14,
                        type = "select",
                        dialogControl = GetLSMSoundControl(),
                        name = "Party Chat",
                        values = GetLSMSoundValues(),
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.events["PARTY"] = val end,
                        get = function(info) return self.db.profile.sounds.events["PARTY"] end,
                    },
                    soundRaid = {
                        order = 15,
                        type = "select",
                        dialogControl = GetLSMSoundControl(),
                        name = "Raid Chat",
                        values = GetLSMSoundValues(),
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
                                desc = "Hides yellow system messages when players join or leave channels.\n\n|cff999999Retail 12.x: handled through the same safe message filter path as Prat-style processing.|r",
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
                                desc = "Restores chat messages after you reload the UI or login.\n\n|cff999999Retail 12.x: restores only messages captured through the safe event path.|r",
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

            -- TAB 4: AUTO REPLY
            tabAutoReply = {
                name = "Auto Reply",
                type = "group",
                order = 40,
                args = {
                    headerAutoReply = {
                        order = 1,
                        type = "description",
                        name = "Automatically reply to whispers when you are AFK, in queue, inside an instance, or manually marked as busy.\n\n|cff999999Retail 12.x: uses chat events and timers only, without tainting Blizzard chat frames.|r",
                        fontSize = "medium",
                    },
                    enableAutoReply = {
                        order = 2,
                        name = "Enable Auto Reply",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.enabled = val end,
                        get = function(info) return self.db.profile.autoReply.enabled end,
                    },
                    busyMode = {
                        order = 3,
                        name = "Busy Mode",
                        desc = "Force the busy message even when you are not AFK or inside an activity.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.autoReply.enabled end,
                        set = function(info, val) self.db.profile.autoReply.busyMode = val end,
                        get = function(info) return self.db.profile.autoReply.busyMode end,
                    },
                    onlyFriends = {
                        order = 4,
                        name = "Only Friends / Guild",
                        desc = "Reply only to Battle.net friends, regular friends, or guild members.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.autoReply.enabled end,
                        set = function(info, val) self.db.profile.autoReply.onlyFriends = val end,
                        get = function(info) return self.db.profile.autoReply.onlyFriends end,
                    },
                    autoNotify = {
                        order = 5,
                        name = "Send Return Message",
                        desc = "When you are back, whisper everyone who contacted you while you were busy.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.autoReply.enabled end,
                        set = function(info, val) self.db.profile.autoReply.autoNotify = val end,
                        get = function(info) return self.db.profile.autoReply.autoNotify end,
                    },
                    guildReplyEnabled = {
                        order = 6,
                        name = "Reply to Guild Mentions",
                        desc = "When your name is mentioned in guild chat during activity, send one throttled guild response and remember that player for the return whisper.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.autoReply.enabled end,
                        set = function(info, val) self.db.profile.autoReply.guildReplyEnabled = val end,
                        get = function(info) return self.db.profile.autoReply.guildReplyEnabled end,
                    },
                    cooldown = {
                        order = 7,
                        name = "Reply Cooldown (minutes)",
                        desc = "How often Chatify may auto-reply to the same player.",
                        type = "range",
                        min = 1, max = 60, step = 1,
                        disabled = function() return not self.db.profile.autoReply.enabled end,
                        set = function(info, val) self.db.profile.autoReply.cooldown = val end,
                        get = function(info) return self.db.profile.autoReply.cooldown end,
                    },
                    headerMessages = { order = 10, type = "header", name = "Messages" },
                    afkMessage = {
                        order = 11,
                        name = "AFK Message",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.afkMessage = val end,
                        get = function(info) return self.db.profile.autoReply.afkMessage end,
                    },
                    queueMessage = {
                        order = 12,
                        name = "Queue Message",
                        desc = "Use %s to inject the wait time in minutes.",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.queueMessage = val end,
                        get = function(info) return self.db.profile.autoReply.queueMessage end,
                    },
                    dungeonMessage = {
                        order = 13,
                        name = "Dungeon Message",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.dungeonMessage = val end,
                        get = function(info) return self.db.profile.autoReply.dungeonMessage end,
                    },
                    raidMessage = {
                        order = 14,
                        name = "Raid Message",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.raidMessage = val end,
                        get = function(info) return self.db.profile.autoReply.raidMessage end,
                    },
                    pvpMessage = {
                        order = 15,
                        name = "PvP Message",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.pvpMessage = val end,
                        get = function(info) return self.db.profile.autoReply.pvpMessage end,
                    },
                    busyMessage = {
                        order = 16,
                        name = "Busy Message",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.busyMessage = val end,
                        get = function(info) return self.db.profile.autoReply.busyMessage end,
                    },
                    returnMessage = {
                        order = 17,
                        name = "Return Message",
                        desc = "Sent automatically when you become available again.",
                        type = "input",
                        width = "full",
                        set = function(info, val) self.db.profile.autoReply.returnMessage = val end,
                        get = function(info) return self.db.profile.autoReply.returnMessage end,
                    },
                }
            },

            -- TAB 5: SETUP / MAINTENANCE
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
    if type(ns.RunRetailCompatibilityMigration) == "function" then
        ns.RunRetailCompatibilityMigration(ns.db)
    end
    if type(ns.EnforceRetailSafeMode) == "function" then
        ns.EnforceRetailSafeMode(ns.db)
    end

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
    if type(ns.RunRetailCompatibilityMigration) == "function" then
        ns.RunRetailCompatibilityMigration(ns.db)
    end
    if ns.ApplyVisuals then ns.ApplyVisuals() end
    if ns.UpdateSpamCache then ns.UpdateSpamCache() end -- Rebuild cache on profile change
    if ns.NotifyQuickChatSettingsChanged then ns.NotifyQuickChatSettingsChanged() end
end

function Chatify:OnEnable()
    if ns.ApplyVisuals then ns.ApplyVisuals() end
    if ns.UpdateSpamCache then ns.UpdateSpamCache() end
    if ns.NotifyQuickChatSettingsChanged then ns.NotifyQuickChatSettingsChanged() end
end

function Chatify:OpenConfig()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsFrame.name)
        Settings.OpenToCategory(self.optionsFrame.name)
        return
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
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
