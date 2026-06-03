local addonName, ns = ...
local Chatify = ns.Chatify
local T = (ns.Locale and ns.Locale.Get and function(text) return ns.Locale:Get(text) end) or function(text) return text end
local ACD = LibStub("AceConfigDialog-3.0", true)

local function TrimInput(value)
    if type(value) ~= "string" then
        return ""
    end

    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeKeywordKey(value)
    local trimmed = TrimInput(value)
    if trimmed == "" then
        return ""
    end

    if type(ns.NormalizeSpamText) == "function" then
        local ok, forms = pcall(ns.NormalizeSpamText, trimmed)
        if ok and type(forms) == "table" and type(forms.compact) == "string" then
            return forms.compact
        end
    end

    return trimmed:gsub("[%s%p%c]", ""):upper()
end


local function GetAddonMetadataValue(key)
    if type(ns.GetAddonMetadata) == "function" then
        return ns.GetAddonMetadata(addonName, key)
    end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, addonName, key)
        if ok then return value end
    end
    if GetAddOnMetadata then
        local ok, value = pcall(GetAddOnMetadata, addonName, key)
        if ok then return value end
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
    local values = {}

    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.sound then
        for key, value in pairs(AceGUIWidgetLSMlists.sound) do
            values[key] = value
        end
    end

    if LibStub and LibStub("LibSharedMedia-3.0", true) then
        local LSM = LibStub("LibSharedMedia-3.0")
        local ok, hash = pcall(LSM.HashTable, LSM, "sound")
        if ok and type(hash) == "table" then
            for name in pairs(hash) do
                values[name] = values[name] or name
            end
        end
    end

    values["None"] = values["None"] or "None"
    values["Chatify Default"] = values["Chatify Default"] or "Chatify Default"
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


local function GetLanguageChoices()
    if ns.Locale and ns.Locale.GetOptionsValues then
        return ns.Locale:GetOptionsValues()
    end

    return {
        client = "Client Default",
        enUS = "English",
        ukUA = "Українська",
    }
end

local function GetLanguageOption()
    local db = Chatify and Chatify.db and Chatify.db.profile
    local value = db and db.language or "client"
    if value ~= "client" and value ~= "enUS" and value ~= "ukUA" then
        return "client"
    end
    return value
end

local function SetLanguageOption(value)
    if ns.Locale and ns.Locale.SetOverride then
        ns.Locale:SetOverride(value)
    elseif Chatify and Chatify.db and Chatify.db.profile then
        Chatify.db.profile.language = value
    end

    if ReloadUI then
        ReloadUI()
    end
end



local selectedMentionRuleIndex = 1

local function EnsureProfileTables(db)
    if not db then return end
    db.spamWhitelist = db.spamWhitelist or {}
    db.spamChannelRules = db.spamChannelRules or {}
    db.mentionRules = db.mentionRules or {}
    db.sounds = db.sounds or { events = {} }
    db.sounds.events = db.sounds.events or {}
    db.copyTabMode = db.copyTabMode or "ALL"
    db.copyTabFrames = db.copyTabFrames or {}
    if type(ns.NormalizeMentionSettings) == "function" then
        ns.NormalizeMentionSettings(db)
    end
end

local function GetRetailSafeDescription()
    local db = Chatify and Chatify.db and Chatify.db.profile
    local status = type(ns.GetRetailSafeModeStatus) == "function" and ns.GetRetailSafeModeStatus(db) or { active = false }
    local mode = status.active and "|cff33ff99active|r" or "|cff888888inactive|r"
    return table.concat({
        "|cffffd200Retail Safe Mode:|r " .. mode,
        "History: " .. (status.history or "available"),
        "Virtual Chat: " .. (status.virtualChat or "available"),
        "Whisper Auto Reply: " .. (status.whisperAutoReply or "available"),
        "Native Copy: " .. (status.nativeCopy or "optional"),
    }, "\n")
end

local function GetSpamLogDescription()
    if type(ns.GetSpamDebugText) == "function" then
        return ns.GetSpamDebugText()
    end
    return "|cff888888Spam debug log is not available yet.|r"
end

local function AddMentionRule(db, text)
    EnsureProfileTables(db)
    text = TrimInput(text)
    if text == "" then return end
    table.insert(db.mentionRules, {
        enabled = true,
        text = text,
        color = "ffd700",
        sound = "Chatify Default",
        channels = "GUILD,PARTY,RAID,INSTANCE,WHISPER,CHANNEL,COMMUNITY,SAY,YELL",
        ignoreCase = true,
        wholeWord = true,
        cooldown = 2,
    })
    selectedMentionRuleIndex = #db.mentionRules
end

local function GetMentionRuleValues(db)
    EnsureProfileTables(db)
    local values = {}
    for index, rule in ipairs(db.mentionRules) do
        local text = type(rule) == "table" and rule.text or nil
        if type(text) ~= "string" or text == "" then
            text = T("Rule ") .. index
        end
        values[index] = string.format("%d. %s%s", index, text, rule.enabled == false and " |cff888888" .. T("(disabled)") .. "|r" or "")
    end
    if #values == 0 then
        values[1] = T("No rules")
    end
    return values
end

local function GetSelectedMentionRule(db)
    EnsureProfileTables(db)
    if #db.mentionRules == 0 then
        return nil, nil
    end
    if selectedMentionRuleIndex < 1 or selectedMentionRuleIndex > #db.mentionRules then
        selectedMentionRuleIndex = 1
    end
    return db.mentionRules[selectedMentionRuleIndex], selectedMentionRuleIndex
end

local function PlaySelectedMentionRuleSound(db)
    local rule = GetSelectedMentionRule(db)
    local soundName = rule and rule.sound
    if type(soundName) ~= "string" or soundName == "" or soundName == "None" then
        if Chatify and Chatify.Print then
            Chatify:Print(T("Selected mention rule has no sound."))
        end
        return
    end

    local sounds = Chatify and Chatify.GetModule and Chatify:GetModule("Sounds", true)
    if sounds and type(sounds.Play) == "function" then
        sounds:Play(soundName)
        return
    end

    local soundFile = type(ns.ResolveSoundPath) == "function" and ns.ResolveSoundPath(soundName)
    if soundFile and type(PlaySoundFile) == "function" then
        local channel = db and db.sounds and db.sounds.masterVolume and "Master" or "SFX"
        pcall(PlaySoundFile, soundFile, channel)
    end
end

local function GetTabTemplateDefinitions()
    return {
        PM = { label = "PM only", tabs = { { name = T("Whisper"), groups = { "WHISPER", "BN_WHISPER" } } } },
        GUILD = { label = "Guild", tabs = {
            { name = T("Whisper"), groups = { "WHISPER", "BN_WHISPER" } },
            { name = T("Guild"), groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
        } },
        RAID = { label = "Raid / Guild / PM", tabs = {
            { name = T("Whisper"), groups = { "WHISPER", "BN_WHISPER" } },
            { name = T("Guild"), groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
            { name = T("Raid"), groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
        } },
    }
end

local function GetChatTabsPreview()
    local db = Chatify and Chatify.db and Chatify.db.profile
    local templateKey = db and db.chatTabsTemplate or "RAID"
    local definitions = GetTabTemplateDefinitions()
    local template = definitions[templateKey] or definitions.RAID
    local lines = { "|cffffd200Preview:|r " .. (template.label or templateKey) }
    for _, tab in ipairs(template.tabs) do
        local exists = type(ns.FindChatFrameByDisplayName) == "function" and ns.FindChatFrameByDisplayName(tab.name)
        local state = exists and "|cff33ff99update existing|r" or "|cffffcc00create|r"
        lines[#lines + 1] = string.format("- %s: %s", tab.name, state)
    end
    lines[#lines + 1] = "|cff999999Setup never creates duplicate tabs with the same visible name.|r"
    return table.concat(lines, "\n")
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
                       " |cffffffff" .. T("Minimalist Chat Enhancer") .. "|r\n" ..
                       " |cff999999" .. T("Tabs • Spam Filter • Sounds • History") .. "|r",
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
                    languageOverride = {
                        order = 0.75,
                        type = "select",
                        name = "Addon Language",
                        desc = "Choose the addon language. Client Default follows the game client language. The UI reloads immediately after changing this option.",
                        width = "double",
                        values = function()
                            return GetLanguageChoices()
                        end,
                        get = function()
                            return GetLanguageOption()
                        end,
                        set = function(_, value)
                            SetLanguageOption(value)
                        end,
                    },
                    languageSpacer = {
                        order = 0.8,
                        type = "description",
                        name = "\n",
                    },
                    retailSafeStatus = {
                        order = 0.9,
                        type = "description",
                        name = GetRetailSafeDescription,
                        fontSize = "medium",
                    },
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

                    quickChatSettingsButton = {
                        order = 6.5,
                        name = "Show Left Settings Button",
                        desc = "Show a dedicated settings button on the left side of the active chat frame. It opens Chatify settings without replacing the default chat behavior.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.quickChatSettingsButton = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            if self.db.profile.quickChatSettingsButton == nil then
                                return true
                            end
                            return self.db.profile.quickChatSettingsButton
                        end,
                    },

                    quickChatButtonTheme = {
                        order = 6.75,
                        name = "Quick Button Theme",
                        desc = "Choose the appearance for the quick chat buttons. Automatic follows supported chat UI addons when they are loaded; Standard keeps the Blizzard-style text buttons and matches the Chatify settings button style.",
                        type = "select",
                        width = "normal",
                        values = {
                            AUTO = "Automatic",
                            STANDARD = "Standard",
                            ELVUI = "ElvUI Style",
                            GW2UI = "GW2 Style",
                        },
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonTheme = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonTheme or "AUTO"
                        end,
                    },
                    quickChatPanelAlpha = {
                        order = 7,
                        name = "Quick Panel Background Opacity",
                        desc = "Adjust the background opacity of the quick chat panel container across all quick button themes. The default value is fully transparent.",
                        type = "range",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        isPercent = true,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatPanelAlpha = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatPanelAlpha or 0
                        end,
                    },

                    quickChatButtonSize = {
                        order = 8,
                        name = "Quick Button Size",
                        desc = "Adjust the base width of the quick chat buttons. By default they match the standard Blizzard sidebar button proportions and still resize down automatically when the chat frame becomes smaller.",
                        type = "range",
                        min = 16,
                        max = 40,
                        step = 1,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonSize = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            return self.db.profile.quickChatButtonSize or 26
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

                    quickChatButtonYOffset = {
                        order = 11.5,
                        name = "Quick Button Vertical Offset",
                        desc = "Move the quick chat stack a little higher or lower while keeping it anchored from the bottom edge of the chat frame.",
                        type = "range",
                        min = -24,
                        max = 16,
                        step = 1,
                        disabled = function() return self.db.profile.quickChatButtons == false end,
                        set = function(info, val) self.db.profile.quickChatButtonYOffset = val; ns.NotifyQuickChatSettingsChanged() end,
                        get = function(info)
                            if self.db.profile.quickChatButtonYOffset == nil then
                                return -4
                            end
                            return self.db.profile.quickChatButtonYOffset
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
                        desc = "Place timestamp at the end of the message.\n\n|cff999999Retail 12.x: applied only where Blizzard allows safe formatting.|r",
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
                        desc = "Toggle channel notification sounds.",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.sounds.enable = val end,
                        get = function(info) return self.db.profile.sounds.enable end,
                    },
                    masterChannel = {
                        order = 3,
                        name = "Use Master Channel",
                        desc = "Play channel notifications through Master. Mention alerts always use Master.",
                        type = "toggle",
                        width = "full",
                        disabled = function() return not self.db.profile.sounds.enable end,
                        set = function(info, val) self.db.profile.sounds.masterVolume = val end,
                        get = function(info) return self.db.profile.sounds.masterVolume end,
                    },

                    headerEvents = { order = 10, type = "header", name = "Channel Notifications" },
                    mentionRoutingNotice = {
                        order = 10.5,
                        type = "description",
                        name = "Channel notification sounds. Mention alerts are configured in Mention Manager.",
                    },

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
                            
                            spamFilterMode = {
                                order = 1.5,
                                name = "Spam Filter Mode",
                                desc = "Block removes matched messages. Log Only keeps chat visible but records debug entries for tuning rules.",
                                type = "select",
                                values = { block = "Block", log = "Log Only" },
                                set = function(info, val) self.db.profile.spamFilterMode = val end,
                                get = function(info) return self.db.profile.spamFilterMode or "block" end,
                            },

                            -- Anti-Flood & System Cleaners
                            enableThrottle = {
                                order = 2,
                                name = "Block Repeated Messages (Anti-Flood)",
                                desc = "Prevents the same author from repeating the same normalized message within the selected cooldown.",
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableThrottle = val end,
                                get = function(info) return self.db.profile.enableThrottle end,
                            },
                            throttleTime = {
                                order = 2.1,
                                name = "Repeat Cooldown",
                                desc = "Seconds before the same normalized message can appear again from the same sender/channel.",
                                type = "range",
                                min = 5, max = 300, step = 5,
                                disabled = function() return not self.db.profile.enableThrottle end,
                                set = function(info, val) self.db.profile.throttleTime = val end,
                                get = function(info) return tonumber(self.db.profile.throttleTime) or 60 end,
                            },
                            throttleMinLength = {
                                order = 2.2,
                                name = "Minimum Repeat Length",
                                desc = "Short common messages are ignored by anti-flood to avoid false positives.",
                                type = "range",
                                min = 8, max = 80, step = 1,
                                disabled = function() return not self.db.profile.enableThrottle end,
                                set = function(info, val) self.db.profile.throttleMinLength = val end,
                                get = function(info) return tonumber(self.db.profile.throttleMinLength) or 20 end,
                            },
                            hideSystemSpam = {
                                order = 3,
                                name = "Hide Join/Leave Messages",
                                desc = "Hides yellow system messages when players join or leave channels.\n\n|cff999999Retail 12.x: handled through the secure message filter path.|r",
                                type = "toggle",
                                set = function(info, val) self.db.profile.hideSystemSpam = val end,
                                get = function(info) return self.db.profile.hideSystemSpam end,
                            },

                            headerWhitelist = { order = 3.2, type = "header", name = "Whitelist" },
                            whitelistGuild = {
                                order = 3.3, name = "Guild / Officer", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamWhitelist.guild = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamWhitelist.guild ~= false end,
                            },
                            whitelistFriends = {
                                order = 3.4, name = "Friends", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamWhitelist.friends = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamWhitelist.friends ~= false end,
                            },
                            whitelistParty = {
                                order = 3.5, name = "Party", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamWhitelist.party = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamWhitelist.party ~= false end,
                            },
                            whitelistRaid = {
                                order = 3.6, name = "Raid / Instance", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamWhitelist.raid = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamWhitelist.raid ~= false end,
                            },

                            headerChannels = { order = 3.8, type = "header", name = "Channel Rules" },
                            scanTrade = { order = 3.9, name = "Trade", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.TRADE = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.TRADE ~= false end },
                            scanServices = { order = 4.0, name = "Services", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.SERVICES = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.SERVICES ~= false end },
                            scanGeneral = { order = 4.1, name = "General", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.GENERAL = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.GENERAL ~= false end },
                            scanGuild = { order = 4.15, name = "Guild / Officer", desc = "Only used when the guild whitelist is disabled.", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.GUILD = val; self.db.profile.spamChannelRules.OFFICER = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.GUILD == true or self.db.profile.spamChannelRules.OFFICER == true end },
                            scanSayYell = { order = 4.2, name = "Say / Yell", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.SAY = val; self.db.profile.spamChannelRules.YELL = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.SAY ~= false or self.db.profile.spamChannelRules.YELL ~= false end },
                            scanCommunity = { order = 4.3, name = "Communities", type = "toggle",
                                set = function(info, val) EnsureProfileTables(self.db.profile); self.db.profile.spamChannelRules.COMMUNITY = val end,
                                get = function(info) EnsureProfileTables(self.db.profile); return self.db.profile.spamChannelRules.COMMUNITY ~= false end },

                            headerKeywords = { order = 5, type = "header", name = "Blocklist Management" },

                            addKeyword = {
                                order = 5,
                                name = "Add Keyword",
                                desc = "Type a word to block (e.g., 'boost', 'WTS') and press Enter.",
                                type = "input",
                                width = "full",
                                set = function(info, val)
                                    local keyword = TrimInput(val)
                                    if keyword ~= "" then
                                        self.db.profile.spamKeywords = self.db.profile.spamKeywords or {}
                                        local normalized = NormalizeKeywordKey(keyword)
                                        local exists = false
                                        for _, current in ipairs(self.db.profile.spamKeywords) do
                                            if NormalizeKeywordKey(current) == normalized then
                                                exists = true
                                                break
                                            end
                                        end

                                        if not exists then
                                            table.insert(self.db.profile.spamKeywords, keyword)
                                        end

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
                                    for i, word in ipairs(self.db.profile.spamKeywords or {}) do t[i] = word end
                                    return t
                                end,
                                set = function(info, key) 
                                    if self.db.profile.spamKeywords then
                                        table.remove(self.db.profile.spamKeywords, key)
                                    end
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
                                    local keywords = self.db.profile.spamKeywords or {}
                                    if #keywords == 0 then return "\n|cff888888" .. T("(Blocklist is empty)") .. "|r" end
                                    return "\n|cffff0000" .. T("Blocked Words:") .. "|r " .. table.concat(keywords, ", ") 
                                end,
                            },
                            headerSpamDebug = { order = 8, type = "header", name = "Runtime Debug" },
                            spamDebugLog = {
                                order = 9,
                                type = "description",
                                name = GetSpamLogDescription,
                                fontSize = "medium",
                            },
                            resetSpamDebug = {
                                order = 10,
                                type = "execute",
                                name = "Reset Spam Debug Counters",
                                func = function() if ns.ResetSpamFilterStats then ns.ResetSpamFilterStats() end end,
                                width = "full",
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
                    },

                    -- 3. COPY CHAT GROUP
                    groupCopy = {
                        name = "Copy Chat",
                        type = "group",
                        inline = true,
                        order = 3,
                        args = {
                            copyNativeSelection = {
                                order = 1,
                                name = "Enable Direct Chat Selection",
                                desc = "Shift + Left Click the Copy Chat button toggles Blizzard direct selection inside the chat frame. Select text in chat, then press Ctrl+C. WoW addons cannot write to the system clipboard automatically.",
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.copyNativeSelection = val end,
                                get = function(info) return self.db.profile.copyNativeSelection ~= false end,
                            },
                            copyNativeUseVisibleFrames = {
                                order = 2,
                                name = "Compatibility Mode for Custom Chat Layouts",
                                desc = "Enable direct selection on all visible chat frames instead of only the best detected frame. Use this only if ElvUI/Prat/custom chat layouts prevent Shift + Left Click from selecting text. Keeping this off is safer.",
                                type = "toggle",
                                width = "full",
                                disabled = function() return self.db.profile.copyNativeSelection == false end,
                                set = function(info, val) self.db.profile.copyNativeUseVisibleFrames = val end,
                                get = function(info) return self.db.profile.copyNativeUseVisibleFrames == true end,
                            },
                            copyNativeTimeout = {
                                order = 3,
                                name = "Auto-disable Direct Selection",
                                desc = "Seconds before Chatify turns direct selection off automatically. Use 0 only if you want to turn it off manually with Shift + Left Click.",
                                type = "range",
                                min = 0, max = 120, step = 5,
                                width = "full",
                                disabled = function() return self.db.profile.copyNativeSelection == false end,
                                set = function(info, val) self.db.profile.copyNativeTimeout = val end,
                                get = function(info) return tonumber(self.db.profile.copyNativeTimeout) or 30 end,
                            },
                            copyNativeAnnounce = {
                                order = 4,
                                name = "Show Direct Selection Hint",
                                desc = "Print a short Chatify message when Shift + Left Click toggles direct chat selection.",
                                type = "toggle",
                                width = "full",
                                disabled = function() return self.db.profile.copyNativeSelection == false end,
                                set = function(info, val) self.db.profile.copyNativeAnnounce = val end,
                                get = function(info) return self.db.profile.copyNativeAnnounce ~= false end,
                            },
                            copyNativeHelp = {
                                order = 5,
                                type = "description",
                                name = "\n|cffffd200How it works:|r Left Click opens the normal copy window. Shift + Left Click toggles direct selection inside the chat frame only. Select text, then press Ctrl+C. Repeat Shift + Left Click to turn it off.\n|cff999999Direct OS clipboard writes are blocked by the WoW client, so selected chat text still needs Ctrl+C.|r",
                            },
                            copyTabsHeader = {
                                order = 10,
                                type = "header",
                                name = T("Copy Window Tabs"),
                            },
                            copyTabMode = {
                                order = 11,
                                name = T("Tabs shown in copy window"),
                                desc = T("Controls which Blizzard chat windows appear as tabs in the ChatCopy 2.0 popup."),
                                type = "select",
                                width = "full",
                                values = {
                                    ALL = T("All existing chat tabs"),
                                    VISIBLE = T("Visible or docked tabs only"),
                                    PINNED = T("Manual selection only"),
                                    SELECTED = T("Selected chat only"),
                                },
                                set = function(info, val)
                                    EnsureProfileTables(self.db.profile)
                                    self.db.profile.copyTabMode = val or "ALL"
                                    if type(ns.RefreshCopyChatTabs) == "function" then ns.RefreshCopyChatTabs() end
                                end,
                                get = function(info)
                                    EnsureProfileTables(self.db.profile)
                                    return self.db.profile.copyTabMode or "ALL"
                                end,
                            },
                            copyTabFrames = {
                                order = 12,
                                name = T("Chat tabs available for copy"),
                                desc = T("Enable or disable individual chat windows in the ChatCopy tab strip. Names are read from the current Blizzard chat windows, so renamed tabs are supported."),
                                type = "multiselect",
                                width = "full",
                                values = function()
                                    if type(ns.GetCopyChatFrameOptionValues) == "function" then
                                        return ns.GetCopyChatFrameOptionValues()
                                    end
                                    return { __none = T("No chat windows detected.") }
                                end,
                                set = function(info, key, val)
                                    EnsureProfileTables(self.db.profile)
                                    if type(ns.SetCopyChatFrameIncluded) == "function" then
                                        ns.SetCopyChatFrameIncluded(key, val)
                                    else
                                        self.db.profile.copyTabFrames[key] = val and true or false
                                    end
                                end,
                                get = function(info, key)
                                    EnsureProfileTables(self.db.profile)
                                    if type(ns.GetCopyChatFrameIncluded) == "function" then
                                        return ns.GetCopyChatFrameIncluded(key)
                                    end
                                    local saved = self.db.profile.copyTabFrames[key]
                                    if saved ~= nil then return saved == true end
                                    return self.db.profile.copyTabMode ~= "PINNED"
                                end,
                            },
                            resetCopyTabFrames = {
                                order = 13,
                                name = T("Reset copy tab selection"),
                                desc = T("Clears manual include/exclude choices for ChatCopy tabs."),
                                type = "execute",
                                width = "full",
                                func = function()
                                    EnsureProfileTables(self.db.profile)
                                    if type(ns.ResetCopyChatFrameFilter) == "function" then
                                        ns.ResetCopyChatFrameFilter()
                                    else
                                        self.db.profile.copyTabFrames = {}
                                    end
                                end,
                                confirm = true,
                                confirmText = T("Reset copy tab selection?"),
                            },
                        },
                    }
                }
            },

            -- TAB 4: MENTION MANAGER
            tabMentions = {
                name = "Mention Manager",
                type = "group",
                order = 35,
                args = {
                    headerMentions = {
                        order = 1,
                        type = "description",
                        name = "Create rules for names, words, or phrases. Each rule can highlight text, play a sound, limit channels, and use its own cooldown.",
                        fontSize = "medium",
                    },
                    enableMentionManager = {
                        order = 2,
                        name = "Enable Mention Manager",
                        type = "toggle",
                        width = "full",
                        set = function(info, val) self.db.profile.enableMentionManager = val end,
                        get = function(info) return self.db.profile.enableMentionManager ~= false end,
                    },
                    addMentionRule = {
                        order = 3,
                        name = "Add Word / Phrase",
                        desc = "Example: Sebas, RL, Ключ",
                        type = "input",
                        width = "full",
                        set = function(info, val) AddMentionRule(self.db.profile, val) end,
                        get = function(info) return "" end,
                    },
                    selectedMentionRule = {
                        order = 4,
                        name = "Selected Rule",
                        type = "select",
                        width = "double",
                        values = function() return GetMentionRuleValues(self.db.profile) end,
                        set = function(info, val) selectedMentionRuleIndex = tonumber(val) or 1 end,
                        get = function(info)
                            GetSelectedMentionRule(self.db.profile)
                            return selectedMentionRuleIndex
                        end,
                    },
                    removeMentionRule = {
                        order = 5,
                        name = "Remove Selected Rule",
                        type = "execute",
                        width = "full",
                        confirm = true,
                        confirmText = "Remove selected mention rule?",
                        func = function()
                            EnsureProfileTables(self.db.profile)
                            if selectedMentionRuleIndex >= 1 and selectedMentionRuleIndex <= #self.db.profile.mentionRules then
                                table.remove(self.db.profile.mentionRules, selectedMentionRuleIndex)
                                if selectedMentionRuleIndex > #self.db.profile.mentionRules then selectedMentionRuleIndex = #self.db.profile.mentionRules end
                                if selectedMentionRuleIndex < 1 then selectedMentionRuleIndex = 1 end
                            end
                        end,
                    },
                    headerEditMention = { order = 10, type = "header", name = "Edit Selected Rule" },
                    mentionEnabled = {
                        order = 11,
                        name = "Enabled",
                        type = "toggle",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.enabled = val end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.enabled ~= false or false end,
                    },
                    mentionText = {
                        order = 12,
                        name = "Word / Phrase",
                        type = "input",
                        width = "full",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.text = TrimInput(val) end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.text or "" end,
                    },
                    mentionColor = {
                        order = 13,
                        name = "Color Hex",
                        desc = "Use 6-digit RGB hex without #. Example: ffd700, ff4040, 68ccef.",
                        type = "input",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.color = TrimInput(val):gsub("#", "") end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.color or "ffd700" end,
                    },
                    mentionSound = {
                        order = 14,
                        type = "select",
                        dialogControl = GetLSMSoundControl(),
                        name = "Sound",
                        desc = "Sound for this mention rule. Choose None for highlight only.",
                        values = GetLSMSoundValues(),
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.sound = val end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.sound or "None" end,
                    },
                    testMentionSound = {
                        order = 14.5,
                        name = "Test Selected Sound",
                        type = "execute",
                        func = function() PlaySelectedMentionRuleSound(self.db.profile) end,
                    },
                    mentionChannels = {
                        order = 15,
                        name = "Channels",
                        desc = "Comma-separated. Supported: GUILD, PARTY, RAID, INSTANCE, WHISPER, CHANNEL, TRADE, SERVICES, GENERAL, COMMUNITY, SAY, YELL, ALL.",
                        type = "input",
                        width = "full",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.channels = TrimInput(val) end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.channels or "ALL" end,
                    },
                    mentionIgnoreCase = {
                        order = 16,
                        name = "Ignore Case",
                        type = "toggle",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.ignoreCase = val end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.ignoreCase ~= false or false end,
                    },
                    mentionWholeWord = {
                        order = 17,
                        name = "Whole Word Only",
                        desc = "Match the whole word instead of a part of another word. For non-Latin text, Chatify uses safe phrase matching.",
                        type = "toggle",
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.wholeWord = val end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.wholeWord ~= false or false end,
                    },
                    mentionCooldown = {
                        order = 18,
                        name = "Sound Cooldown",
                        type = "range",
                        min = 0, max = 60, step = 1,
                        set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.cooldown = val end end,
                        get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and tonumber(rule.cooldown) or 2 end,
                    },
                },
            },

            -- TAB 5: AUTO REPLY
            tabAutoReply = {
                name = "Auto Reply",
                type = "group",
                order = 40,
                args = {
                    headerAutoReply = {
                        order = 1,
                        type = "description",
                        name = "Automatically reply when you are AFK, in queue, inside an instance, or manually marked as busy.\n\n|cff999999Retail Safe Mode: whisper / BN whisper auto-replies are disabled on modern Retail; guild mention replies can still work when available.|r",
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
                        name = "Safely create or update chat tabs without duplicates. The selected template controls which tabs are created.\n|cffffcc00Warning: Modifies chat window layout, but does not run in combat.|r",
                        fontSize = "medium",
                    },
                    chatTabsTemplate = {
                        order = 3,
                        name = "Template",
                        type = "select",
                        values = { PM = "PM", GUILD = "Guild", RAID = "Raid / Guild / PM" },
                        set = function(info, val) self.db.profile.chatTabsTemplate = val end,
                        get = function(info) return self.db.profile.chatTabsTemplate or "RAID" end,
                    },
                    chatTabsPreview = {
                        order = 4,
                        type = "description",
                        name = GetChatTabsPreview,
                        fontSize = "medium",
                    },
                    btnSetup = {
                        order = 5,
                        name = "Apply Safe Tab Setup",
                        type = "execute",
                        func = "SetupDefaultTabs", 
                        width = "full",
                        confirm = true,
                        confirmText = "Create or update chat tabs for the selected template?",
                    },
                    btnRestoreDefaultTabs = {
                        order = 6,
                        name = "Restore Main Chat Groups",
                        desc = "Restores common message groups on the main General chat frame. It does not delete custom windows.",
                        type = "execute",
                        func = "RestoreDefaultChatTabs",
                        width = "full",
                        confirm = true,
                        confirmText = "Restore common message groups on the main chat frame?",
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
                            self:Print(T("Configuration reset."))
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
    if ns.Locale and ns.Locale.LocalizeOptions then
        ns.Locale:LocalizeOptions(options)
    end
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
    EnsureProfileTables(ns.db)
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
    
    -- Runtime modules refresh themselves on enable. Avoid doing a second full
    -- style/filter pass here because Ace will immediately enable modules after
    -- initialization.
end

local refreshQueued = false
local function RefreshRuntimeModulesNow()
    if type(ns.UpdateSpamCache) == "function" then
        pcall(ns.UpdateSpamCache)
    end

    -- One visual pass is enough. Calling both ns.ApplyVisuals() and the module
    -- method caused duplicate style/filter work during profile changes.
    if type(ns.ApplyVisuals) == "function" then
        pcall(ns.ApplyVisuals)
    end

    if type(ns.NotifyQuickChatSettingsChanged) == "function" then
        pcall(ns.NotifyQuickChatSettingsChanged)
    end

    local router = Chatify.GetModule and Chatify:GetModule("Router", true)
    if router then
        if type(router.ApplyToAllFrames) == "function" then
            pcall(router.ApplyToAllFrames, router)
        end
        if type(router.RefreshProxies) == "function" then
            pcall(router.RefreshProxies, router)
        end
    end

    local quickButtons = Chatify.GetModule and Chatify:GetModule("QuickButtons", true)
    if quickButtons and type(quickButtons.Refresh) == "function" then
        pcall(quickButtons.Refresh, quickButtons)
    end
end

local function RefreshRuntimeModules()
    if refreshQueued then
        return
    end

    refreshQueued = true
    local function run()
        refreshQueued = false
        RefreshRuntimeModulesNow()
    end

    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(0, run)
    else
        run()
    end
end

function Chatify:RefreshConfig()
    ns.db = self.db.profile
    EnsureProfileTables(ns.db)
    if type(ns.RunRetailCompatibilityMigration) == "function" then
        ns.RunRetailCompatibilityMigration(ns.db)
    end
    RefreshRuntimeModules()
end

function Chatify:OnEnable()
    RefreshRuntimeModules()
end

function Chatify:OpenConfig()
    if ACD and type(ACD.Open) == "function" then
        pcall(ACD.Open, ACD, "Chatify")
        return
    end

    local frame = self.optionsFrame
    if not frame then
        return
    end

    local category = frame.name or frame

    if Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, category)
        return
    end

    if InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, frame)
    end
end

-- =========================================================
-- 6. SAFE CHAT TABS
-- =========================================================
local function GetFrameDisplayName(frameID, frame)
    if type(frameID) == "number" and type(FCF_GetChatWindowInfo) == "function" then
        local ok, name = pcall(FCF_GetChatWindowInfo, frameID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    if frame and type(frame.GetName) == "function" then
        local okName, frameName = pcall(frame.GetName, frame)
        if okName and frameName and _G[frameName .. "Tab"] and _G[frameName .. "Tab"].GetText then
            local okText, text = pcall(_G[frameName .. "Tab"].GetText, _G[frameName .. "Tab"])
            if okText and type(text) == "string" and text ~= "" then
                return text
            end
        end
    end

    if frame and type(frame.name) == "string" and frame.name ~= "" then
        return frame.name
    end
    return nil
end

function ns.FindChatFrameByDisplayName(displayName)
    if type(displayName) ~= "string" or displayName == "" then
        return nil, nil
    end

    local maxWindows = type(ns.GetMaxChatWindows) == "function" and ns.GetMaxChatWindows() or (NUM_CHAT_WINDOWS or 10)
    for i = 1, maxWindows do
        local frame = _G["ChatFrame" .. i]
        if frame then
            local name = GetFrameDisplayName(i, frame)
            if name == displayName then
                return frame, i
            end
        end
    end
    return nil, nil
end

local function SafeRemoveAllMessageGroups(frame)
    if not frame then return end
    if type(frame.RemoveAllMessageGroups) == "function" then pcall(frame.RemoveAllMessageGroups, frame); return end
    if type(ChatFrame_RemoveAllMessageGroups) == "function" then pcall(ChatFrame_RemoveAllMessageGroups, frame) end
end

local function SafeRemoveAllChannels(frame)
    if not frame then return end
    if type(frame.RemoveAllChannels) == "function" then pcall(frame.RemoveAllChannels, frame); return end
    if type(ChatFrame_RemoveAllChannels) == "function" then pcall(ChatFrame_RemoveAllChannels, frame) end
end

local function SafeAddMessageGroup(frame, group)
    if not frame or type(group) ~= "string" or group == "" then return end
    if type(frame.AddMessageGroup) == "function" then pcall(frame.AddMessageGroup, frame, group); return end
    if type(ChatFrame_AddMessageGroup) == "function" then pcall(ChatFrame_AddMessageGroup, frame, group) end
end

local function ConfigureTabFrame(frame, groups)
    if not frame then return false end
    SafeRemoveAllMessageGroups(frame)
    SafeRemoveAllChannels(frame)
    for _, group in ipairs(groups or {}) do
        SafeAddMessageGroup(frame, group)
    end
    return true
end

function Chatify:SetupDefaultTabs()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self:Print(T("Cannot modify chat tabs during combat."))
        return
    end
    if type(FCF_OpenNewWindow) ~= "function" then
        self:Print(T("Chat window creation is not available on this client."))
        return
    end

    local db = self.db and self.db.profile or {}
    local definitions = GetTabTemplateDefinitions()
    local template = definitions[db.chatTabsTemplate or "RAID"] or definitions.RAID
    local created, updated, failed = 0, 0, 0

    for _, tabInfo in ipairs(template.tabs) do
        local frame = ns.FindChatFrameByDisplayName and ns.FindChatFrameByDisplayName(tabInfo.name)
        local existed = frame and true or false
        if not frame then
            local okOpen, newFrame = pcall(FCF_OpenNewWindow, tabInfo.name)
            if okOpen then
                frame = newFrame
            end
        end

        if frame and ConfigureTabFrame(frame, tabInfo.groups) then
            if type(FCF_SelectDockFrame) == "function" then pcall(FCF_SelectDockFrame, frame) end
            if existed then updated = updated + 1 else created = created + 1 end
        else
            failed = failed + 1
        end
    end

    self:Print(string.format("Chat tabs: %d created, %d updated, %d failed.", created, updated, failed))
end

function Chatify:RestoreDefaultChatTabs()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        self:Print(T("Cannot modify chat tabs during combat."))
        return
    end

    local frame = _G.ChatFrame1 or DEFAULT_CHAT_FRAME
    if not frame then
        self:Print(T("Main chat frame is not available."))
        return
    end

    local groups = {
        "SAY", "YELL", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER",
        "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
        "WHISPER", "BN_WHISPER", "SYSTEM", "AFK", "DND", "LOOT",
    }
    ConfigureTabFrame(frame, groups)
    self:Print(T("Main chat groups restored. Custom windows were not deleted."))
end
