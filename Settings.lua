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
    if type(ns.RegisterChatifyMedia) == "function" then
        pcall(ns.RegisterChatifyMedia)
    end

    local values = {}

    if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font then
        for _, name in ipairs(AceGUIWidgetLSMlists.font) do
            if type(name) == "string" and name ~= "" then
                values[name] = name
            end
        end
        for key, value in pairs(AceGUIWidgetLSMlists.font) do
            if type(key) == "string" and type(value) == "string" and value ~= "" then
                values[key] = value
            end
        end
    end

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
        local ok, hash = pcall(LSM.HashTable, LSM, "font")
        if ok and type(hash) == "table" then
            for name in pairs(hash) do
                values[name] = values[name] or name
            end
        end
    end

    if ns.Lists and ns.Lists.Fonts then
        for _, entry in ipairs(ns.Lists.Fonts) do
            local available = true
            if type(ns.IsFontEntryAvailable) == "function" then
                local ok, result = pcall(ns.IsFontEntryAvailable, entry)
                available = ok and result == true
            end
            if available and entry and not entry.hidden and entry.register ~= false and entry.name then
                values[entry.name] = values[entry.name] or entry.name
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

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if LSM then
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
local sessionLoadedFromDisk = false
local sessionPreviousCount = 0
local sessionPreviousStamp = nil
local sessionWarningShown = false

local function EnsureProfileTables(db)
    if not db then return end
    local defaults = ns.defaults and ns.defaults.profile or {}

    db.spamWhitelist = type(db.spamWhitelist) == "table" and db.spamWhitelist or {}
    db.spamChannelRules = type(db.spamChannelRules) == "table" and db.spamChannelRules or {}
    db.mentionRules = type(db.mentionRules) == "table" and db.mentionRules or {}
    db.sounds = type(db.sounds) == "table" and db.sounds or { events = {} }
    db.sounds.events = type(db.sounds.events) == "table" and db.sounds.events or {}
    db.autoReply = type(db.autoReply) == "table" and db.autoReply or {}
    db.copyTabMode = db.copyTabMode or "VISIBLE"
    db.copyTabFrames = type(db.copyTabFrames) == "table" and db.copyTabFrames or {}

    if type(defaults.autoReply) == "table" then
        for key, value in pairs(defaults.autoReply) do
            if db.autoReply[key] == nil then
                db.autoReply[key] = value
            end
        end
    end
    if type(defaults.sounds) == "table" and type(defaults.sounds.events) == "table" then
        for key, value in pairs(defaults.sounds.events) do
            if db.sounds.events[key] == nil then
                db.sounds.events[key] = value
            end
        end
    end

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

local function GetRuntimeDebugDescription()
    if type(ns.GetRuntimeDebugText) == "function" then
        return ns.GetRuntimeDebugText()
    end
    return "|cff888888Runtime debug log is not available yet.|r"
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
                name = T("General & Visual"),
                type = "group",
                order = 10,
                args = {
                    groupLanguage = {
                        name = T("Language"),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            languageOverride = {
                                order = 1,
                                type = "select",
                                name = T("Addon Language"),
                                desc = T("Choose the addon language. Client Default follows the game client language. The UI reloads immediately after changing this option."),
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
                        },
                    },

                    groupSafety = {
                        name = T("Compatibility & Safety"),
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                                groupSafetyNote = {
                                    order = 1,
                                    type = "description",
                                    name = T("How much Chatify is allowed to touch chat text. These only matter on Midnight (12.0+), where the game protects chat payloads."),
                                },
                            retailSafeStatus = {
                                order = 2,
                                type = "description",
                                name = GetRetailSafeDescription,
                                fontSize = "medium",
                            },
                            retailWhisperSafeMode = {
                                order = 3,
                                name = T("Never modify whispers (Retail)"),
                                desc = T("On modern Retail, leave whisper and Battle.net whisper lines completely untouched (no timestamps, links, or highlights), even outside of encounters. Chatify already leaves whispers alone during boss fights, Mythic+, and PvP; enable this only if you still see blank or duplicated whisper tabs."),
                                type = "toggle",
                                width = "full",
                                hidden = function()
                                    return not (type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild())
                                end,
                                set = function(info, val)
                                    self.db.profile.retailWhisperSafeMode = val
                                    if type(ns.ApplyVisuals) == "function" then ns.ApplyVisuals() end
                                end,
                                get = function(info) return self.db.profile.retailWhisperSafeMode end,
                            },
                            retailChatFilterMode = {
                                order = 4,
                                name = T("Chat filters on Midnight (12.0+)"),
                                desc = T("Controls how far Chatify goes when the game protects chat payloads with secret values. Safest is the default on 12.0+ because any chat filter can taint Blizzard's chat dispatch for the rest of the session, which shows up as player messages never appearing during a raid encounter or Mythic+ key. Balanced restores filtering during normal play and withdraws it for the whole time you are inside instanced content. Maximum filters everywhere. Requires /reload."),
                                type = "select",
                                width = "full",
                                values = function()
                                    return {
                                        full = T("Maximum features (can break chat in encounters)"),
                                        lockdown = T("Balanced - pause while inside instances"),
                                        off = T("Safest - never filter, use the game's timestamps (recommended)"),
                                    }
                                end,
                                sorting = function() return { "full", "lockdown", "off" } end,
                                hidden = function()
                                    return not (type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild())
                                end,
                                set = function(info, val)
                                    self.db.profile.retailChatFilterMode = val
                                    -- Marks the choice as deliberate, so GetRetailChatFilterMode
                                    -- stops downgrading "lockdown" to "off" on 12.0+ builds.
                                    self.db.profile.retailChatFilterModeUserSet = true
                                    self.db.profile.retailDisableChatFilters = nil
                                    if type(ns.RefreshMessageFilters) == "function" then ns.RefreshMessageFilters() end
                                    if type(ns.ApplyVisuals) == "function" then ns.ApplyVisuals() end
                                end,
                                get = function(info)
                                    -- Show the mode that is actually in force, not the raw
                                    -- stored value, or the dropdown would read "Balanced"
                                    -- while the addon is running in Safest.
                                    if type(ns.GetRetailChatFilterMode) == "function" then
                                        local ok, mode = pcall(ns.GetRetailChatFilterMode)
                                        if ok and mode then return mode end
                                    end
                                    return self.db.profile.retailChatFilterMode or "lockdown"
                                end,
                            },
                        },
                    },

                    groupText = {
                        name = T("Text & Appearance"),
                        type = "group",
                        inline = true,
                        order = 3,
                        args = {
                            fontID = {
                                order = 1,
                                name = T("Chat Font"),
                                desc = T("Select the typeface used for chat messages."),
                                type = "select",
                                width = "double",
                                dialogControl = GetLSMFontControl(),
                                values = GetLSMFontValues(),
                                set = function(info, val) self.db.profile.fontID = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.fontID end,
                            },
                            lineSpacing = {
                                order = 2,
                                name = T("Line Spacing"),
                                desc = T("Extra pixels between lines."),
                                type = "range",
                                min = 0, max = 10, step = 1,
                                set = function(info, val) self.db.profile.lineSpacing = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.lineSpacing or 0 end,
                            },
                            indentWrappedLines = {
                                order = 3,
                                name = T("Indent Wrapped Lines"),
                                desc = T("Indents the continuation of a long message so it lines up under the first line instead of starting at the left edge."),
                                type = "toggle",
                                hidden = function()
                                    local frame = _G.ChatFrame1
                                    return not (frame and type(frame.SetIndentedWordWrap) == "function")
                                end,
                                set = function(info, val) self.db.profile.indentWrappedLines = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.indentWrappedLines end,
                            },
                            urlColor = {
                                order = 5,
                                name = T("Link Colour"),
                                desc = T("Six hex digits used for the web links Chatify makes clickable, for example 0099FF."),
                                type = "input",
                                width = "half",
                                validate = function(info, val)
                                    val = tostring(val or ""):gsub("^#", "")
                                    if val:match("^%x%x%x%x%x%x$") then return true end
                                    return T("Enter six hex digits, for example 0099FF.")
                                end,
                                set = function(info, val)
                                    self.db.profile.urlColor = (tostring(val or ""):gsub("^#", ""))
                                end,
                                get = function(info) return self.db.profile.urlColor or "0099FF" end,
                            },

                            hoverHyperlinkTooltips = {
                                order = 6,
                                name = T("Show Link Tooltips on Hover"),
                                desc = T("When enabled, item/spell/achievement links in chat show their tooltip on mouseover.\nDisable this if hover-tooltips keep getting in your way."),
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
                        },
                    },

                    groupTimestamps = {
                        name = T("Timestamps"),
                        type = "group",
                        inline = true,
                        order = 4,
                        args = {
                            enableTimestamps = {
                                order = 1,
                                name = T("Show Timestamps"),
                                desc = T("Adds the time in front of each chat line.\n\nOn Midnight (12.0+) with filtering set to Safest this is handed to the game's own timestamp setting, so only the formats the game supports will take effect."),
                                type = "toggle",
                                width = "full",
                                set = function(info, val)
                                    self.db.profile.enableTimestamps = val
                                    ns.ApplyVisuals()
                                    if type(ns.RefreshTimestampFilterState) == "function" then
                                        ns.RefreshTimestampFilterState()
                                    end
                                end,
                                get = function(info) return self.db.profile.enableTimestamps end,
                            },

                            timestampColor = {
                                order = 2,
                                name = T("Timestamp Colour"),
                                desc = T("Six hex digits, for example 68ccef.\n\nOnly applies while Chatify draws the timestamps itself. Where the game's own timestamps are used, the game controls the colour."),
                                type = "input",
                                width = "half",
                                disabled = function() return not self.db.profile.enableTimestamps end,
                                validate = function(info, val)
                                    val = tostring(val or ""):gsub("^#", "")
                                    if val:match("^%x%x%x%x%x%x$") then return true end
                                    return T("Enter six hex digits, for example 68ccef.")
                                end,
                                set = function(info, val)
                                    self.db.profile.timestampColor = (tostring(val or ""):gsub("^#", ""))
                                    ns.ApplyVisuals()
                                end,
                                get = function(info) return self.db.profile.timestampColor or "68ccef" end,
                            },

                            timestampID = {
                                order = 3,
                                name = T("Time Format"),
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
                                order = 4,
                                name = T("Use Server Time"),
                                desc = T("If checked, uses Realm time.\nIf unchecked, uses Local Computer time."),
                                type = "toggle",
                                set = function(info, val) self.db.profile.useServerTime = val end,
                                get = function(info) return self.db.profile.useServerTime end,
                            },
                            timestampPost = {
                                order = 5,
                                name = T("Show at End"),
                                desc = T("Place timestamp at the end of the message.\n\n|cff999999Retail 12.x: applied only where Blizzard allows safe formatting.|r"),
                                type = "toggle",
                                set = function(info, val) self.db.profile.timestampPost = val end,
                                get = function(info) return self.db.profile.timestampPost end,
                            },
                        },
                    },

                    groupWindow = {
                        name = T("Chat Window"),
                        type = "group",
                        inline = true,
                        order = 5,
                        args = {
                                groupWindowNote = {
                                    order = 1,
                                    type = "description",
                                    name = T("These use only the chat window's own API, so they keep working on Midnight (12.0+) even when message filtering is switched off."),
                                },
                            scrollbackLines = {
                                order = 2,
                                name = T("Scrollback Depth"),
                                desc = T("How many lines each chat window keeps. The game keeps 128, which is usually why scrollback runs out during a busy fight.\n\nChanging this clears the affected window once, because the game reallocates the buffer."),
                                type = "select",
                                width = "double",
                                values = function()
                                    return {
                                        [0] = T("Game default"),
                                        [256] = "256",
                                        [500] = "500",
                                        [1000] = "1000",
                                        [2500] = "2500",
                                        [5000] = T("5000 (uses more memory)"),
                                    }
                                end,
                                set = function(info, val) self.db.profile.scrollbackLines = tonumber(val) or 0; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.scrollbackLines or 0 end,
                            },
                            disableChatFade = {
                                order = 3,
                                name = T("Never Fade Messages"),
                                desc = T("Keeps messages on screen instead of fading them out after a while."),
                                type = "toggle",
                                set = function(info, val) self.db.profile.disableChatFade = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.disableChatFade end,
                            },
                            chatFadeTime = {
                                order = 4,
                                name = T("Fade After (seconds)"),
                                desc = T("How long a message stays fully visible before it fades."),
                                type = "range",
                                min = 5, max = 600, step = 5, bigStep = 15,
                                disabled = function() return self.db.profile.disableChatFade end,
                                set = function(info, val) self.db.profile.chatFadeTime = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.chatFadeTime or 120 end,
                            },
                            enableScrollTweaks = {
                                order = 5,
                                name = T("Custom Scroll Speed"),
                                desc = T("Turn off to leave mouse wheel scrolling entirely to the game. Automatically inactive while a chat replacement addon such as ElvUI is loaded."),
                                type = "toggle",
                                set = function(info, val) self.db.profile.enableScrollTweaks = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.enableScrollTweaks ~= false end,
                            },
                            scrollLinesPerNotch = {
                                order = 6,
                                name = T("Scroll Speed (lines per notch)"),
                                desc = T("Lines moved per mouse wheel notch. Shift still jumps to the top or bottom, and Ctrl scrolls a full page."),
                                type = "range",
                                min = 1, max = 10, step = 1,
                                disabled = function() return self.db.profile.enableScrollTweaks == false end,
                                set = function(info, val) self.db.profile.scrollLinesPerNotch = val end,
                                get = function(info) return self.db.profile.scrollLinesPerNotch or 3 end,
                            },
                            hideBlizzardChatButtons = {
                                order = 7,
                                name = T("Hide Game Chat Buttons"),
                                desc = T("Hides the chat menu button and the Quick Join notification button."),
                                type = "toggle",
                                set = function(info, val) self.db.profile.hideBlizzardChatButtons = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.hideBlizzardChatButtons end,
                            },
                        },
                    },

                    groupQuickButtons = {
                        name = T("Quick Chat Buttons"),
                        type = "group",
                        inline = true,
                        order = 6,
                        args = {
                            quickChatButtons = {
                                order = 1,
                                name = T("Enable Quick Chat Buttons"),
                                desc = T("Show quick channel buttons on the right side of the chat frame, anchored from the bottom."),
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
                                order = 2,
                                name = T("Show Left Settings Button"),
                                desc = T("Show a dedicated settings button on the left side of the active chat frame. It opens Chatify settings without replacing the default chat behavior."),
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
                                order = 3,
                                name = T("Quick Button Theme"),
                                desc = T("Choose the appearance for the quick chat buttons. Automatic follows supported chat UI addons when they are loaded; Standard keeps the Blizzard-style text buttons and matches the Chatify settings button style."),
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
                                order = 4,
                                name = T("Quick Panel Background Opacity"),
                                desc = T("Adjust the background opacity of the quick chat panel container across all quick button themes. The default value is fully transparent."),
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
                                order = 5,
                                name = T("Quick Button Size"),
                                desc = T("Adjust the base width of the quick chat buttons. By default they match the standard Blizzard sidebar button proportions and still resize down automatically when the chat frame becomes smaller."),
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
                                order = 6,
                                name = T("Quick Button Spacing"),
                                desc = T("Adjust the vertical spacing between quick chat buttons."),
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
                                order = 7,
                                name = T("Quick Button Label Scale"),
                                desc = T("Adjust the text scale inside the quick chat buttons."),
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
                                order = 8,
                                name = T("Quick Button Offset"),
                                desc = T("Adjust how far the quick chat buttons sit from the right side of the chat frame."),
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
                                order = 9,
                                name = T("Quick Button Vertical Offset"),
                                desc = T("Move the quick chat stack a little higher or lower while keeping it anchored from the bottom edge of the chat frame."),
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
                                order = 10,
                                name = T("Quick Button Opacity"),
                                desc = T("Adjust the opacity of the quick chat buttons."),
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
                        },
                    },

                }
            },

            -- TAB 2: CHANNELS
            tabChannels = {
                name = T("Channels"),
                type = "group",
                order = 15,
                childGroups = "tab",
                args = {
                    groupChannelGeneral = {
                        name = T("General"),
                        type = "group",
                        order = 1,
                        args = {
                            shortChannels = {
                                order = 1,
                                name = T("Replace Channel Names"),
                                desc = T("Master switch. When off, every channel keeps the label the game gives it and the per-channel settings below are left untouched, so turning it back on restores them."),
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.shortChannels = val; ns.ApplyVisuals() end,
                                get = function(info) return self.db.profile.shortChannels end,
                            },

                            modesNote = {
                                order = 2,
                                type = "description",
                                name = T("Each channel can be set to:\n|cffffd100Game default|r - leave the label alone\n|cffffd100Short|r - the built-in abbreviation, or the number for a numbered channel\n|cffffd100Custom|r - your own text\n|cffffd100Hidden|r - drop the tag entirely"),
                            },

                            numberHint = {
                                order = 3,
                                type = "description",
                                name = T("For numbered channels, start a custom label with |cffffd100#|r to keep the number in front of it: |cffffd100#Trade|r shows as |cffaaaaaa[2. Trade]|r, and |cffffd100#|r on its own shows as |cffaaaaaa[2]|r."),
                            },
                        },
                    },

                    groupChannelBuiltin = {
                        name = T("Chat Types"),
                        type = "group",
                        order = 2,
                        args = (function()
                            local args = {
                                builtinNote = {
                                    order = 1,
                                    type = "description",
                                    name = T("Say, yell and whispers have no channel tag of their own, so Chatify has to introduce one and rewrite the wording around the sender's name. That is more invasive than swapping a label, which is why they start switched off."),
                                },
                            }

                            -- One inline group per chat type.
                            --
                            -- AceConfigDialog lays widgets out in a flow and packs
                            -- as many per row as will fit, so a flat list of
                            -- mode+text pairs desynchronised as soon as three fit:
                            -- the label above a control belonged to the previous
                            -- channel. An inline group always starts a new row and
                            -- owns its contents, so the pairing cannot drift, and
                            -- the group title carries the channel name.
                            for index, entry in ipairs(ns.Lists.ChannelLabels or {}) do
                                local token = entry.token

                                local function Mode()
                                    return ns.GetChannelMode(self.db.profile, token, entry)
                                end

                                args["row_" .. token] = {
                                    order = 10 + index,
                                    type = "group",
                                    inline = true,
                                    name = T(entry.name),
                                    args = {
                                        mode = {
                                            order = 1,
                                            type = "select",
                                            width = "normal",
                                            name = T("Mode"),
                                            disabled = function() return not self.db.profile.shortChannels end,
                                            values = function()
                                                return {
                                                    default = T("Game default"),
                                                    short = T("Short") .. " (" .. (entry.short or "") .. ")",
                                                    custom = T("Custom"),
                                                    hidden = T("Hidden"),
                                                }
                                            end,
                                            sorting = function() return ns.Lists.ChannelModes end,
                                            set = function(info, val)
                                                local profile = self.db.profile
                                                profile.channelModes = profile.channelModes or {}
                                                profile.channelModes[token] = val
                                                ns.ApplyVisuals()
                                            end,
                                            get = function(info) return Mode() end,
                                        },

                                        label = {
                                            order = 2,
                                            type = "input",
                                            width = "normal",
                                            name = T("Label"),
                                            desc = T("Text used for this chat type."),
                                            -- Hidden rather than greyed: an empty
                                            -- disabled box next to every channel was
                                            -- most of the clutter, and it only means
                                            -- anything in Custom mode anyway.
                                            hidden = function()
                                                return not self.db.profile.shortChannels or Mode() ~= "custom"
                                            end,
                                            validate = function(info, val)
                                                if type(val) == "string" and #val > 12 then
                                                    return T("Keep labels to 12 characters or fewer.")
                                                end
                                                return true
                                            end,
                                            set = function(info, val)
                                                local profile = self.db.profile
                                                profile.channelLabels = profile.channelLabels or {}
                                                val = TrimInput(val)
                                                profile.channelLabels[token] = (val ~= "") and val or nil
                                                ns.ApplyVisuals()
                                            end,
                                            get = function(info)
                                                local labels = self.db.profile.channelLabels
                                                local custom = labels and labels[token]
                                                if type(custom) == "string" and custom ~= "" then
                                                    return custom
                                                end
                                                return entry.short or ""
                                            end,
                                        },

                                        preview = {
                                            order = 3,
                                            type = "description",
                                            width = "normal",
                                            name = function()
                                                local mode = Mode()
                                                local shown
                                                if mode == "hidden" then
                                                    shown = "|cff999999" .. T("no tag") .. "|r"
                                                elseif mode == "short" then
                                                    shown = "[" .. (entry.short or "") .. "]"
                                                elseif mode == "custom" then
                                                    local labels = self.db.profile.channelLabels
                                                    local custom = labels and labels[token]
                                                    shown = "[" .. ((type(custom) == "string" and custom ~= "") and custom or (entry.short or "")) .. "]"
                                                else
                                                    shown = "[" .. ns.GetBuiltinChannelDefault(entry) .. "]"
                                                end
                                                return T("Shows as:") .. " |cffffd100" .. shown .. "|r"
                                            end,
                                        },
                                    },
                                }
                            end

                            return args
                        end)(),
                    },

                    groupChannelNamed = {
                        name = T("Numbered and Custom Channels"),
                        type = "group",
                        order = 3,
                        args = (function()
                            local profile = self.db.profile

                            -- Keeps the readable name of every joined channel, so a
                            -- channel you created with /join and later left is still
                            -- listed by name instead of by its uppercased key.
                            if type(ns.RememberChannelNames) == "function" then
                                pcall(ns.RememberChannelNames, profile)
                            end

                            local known = (type(ns.GetKnownChannelKeys) == "function")
                                and ns.GetKnownChannelKeys(profile) or {}

                            local args = {
                                namedNote = {
                                    order = 1,
                                    type = "description",
                                    name = T("Labels are remembered by channel name, not by the number in front of it, so they survive the numbers being reshuffled when you join, leave or change zone. Channels you made yourself with /join work the same way."),
                                },

                                addChannel = {
                                    order = 2,
                                    type = "input",
                                    width = "double",
                                    name = T("Add a Channel by Name"),
                                    desc = T("For a channel you are not in right now. Type the channel name exactly as it appears in chat, without the number."),
                                    set = function(info, val)
                                        val = TrimInput(val)
                                        if val == "" then return end

                                        local key = ns.ChannelNameKey and ns.ChannelNameKey(val)
                                        if not key then return end

                                        profile.channelLabelNames = profile.channelLabelNames or {}
                                        profile.channelLabelNames[key] =
                                            ns.NormalizeChannelName(val) or val

                                        local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
                                        if registry and type(registry.NotifyChange) == "function" then
                                            pcall(registry.NotifyChange, registry, "Chatify")
                                        end
                                    end,
                                    get = function(info) return "" end,
                                },
                            }

                            if #known == 0 then
                                args.namedEmpty = {
                                    order = 3,
                                    type = "description",
                                    name = T("|cff999999No numbered channels yet. This list fills in once you join one, or add it by name above.|r"),
                                }
                                return args
                            end

                            -- Same inline-group-per-row treatment as the chat types
                            -- above, for the same reason: a flat flow layout cannot
                            -- keep a control under its own label.
                            for index, entry in ipairs(known) do
                                local key = entry.key

                                local function Mode()
                                    return ns.GetChannelMode(profile, key, nil)
                                end

                                local function RowName()
                                    if entry.joined and entry.id then
                                        return entry.id .. ". " .. entry.name
                                    end
                                    return entry.name .. " |cff999999(" .. T("not joined") .. ")|r"
                                end

                                args["row_" .. key] = {
                                    order = 10 + index,
                                    type = "group",
                                    inline = true,
                                    name = RowName,
                                    args = {
                                        mode = {
                                            order = 1,
                                            type = "select",
                                            width = "normal",
                                            name = T("Mode"),
                                            disabled = function() return not profile.shortChannels end,
                                            values = function()
                                                local shortLabel = entry.joined and entry.id
                                                    and (T("Short") .. " (" .. entry.id .. ")")
                                                    or T("Short")
                                                return {
                                                    default = T("Game default"),
                                                    short = shortLabel,
                                                    custom = T("Custom"),
                                                    hidden = T("Hidden"),
                                                }
                                            end,
                                            sorting = function() return ns.Lists.ChannelModes end,
                                            set = function(info, val)
                                                profile.channelModes = profile.channelModes or {}
                                                profile.channelModes[key] = val
                                                ns.ApplyVisuals()
                                            end,
                                            get = function(info) return Mode() end,
                                        },

                                        label = {
                                            order = 2,
                                            type = "input",
                                            width = "normal",
                                            name = T("Label"),
                                            desc = T("Text used for this channel. Start with # to keep the number."),
                                            hidden = function()
                                                return not profile.shortChannels or Mode() ~= "custom"
                                            end,
                                            validate = function(info, val)
                                                if type(val) == "string" and #val > 12 then
                                                    return T("Keep labels to 12 characters or fewer.")
                                                end
                                                return true
                                            end,
                                            set = function(info, val)
                                                val = TrimInput(val)
                                                profile.channelLabelsNamed = profile.channelLabelsNamed or {}
                                                profile.channelLabelsNamed[key] = (val ~= "") and val or nil
                                                ns.ApplyVisuals()
                                            end,
                                            get = function(info)
                                                local labels = profile.channelLabelsNamed
                                                local custom = labels and labels[key]
                                                if type(custom) == "string" and custom ~= "" then
                                                    return custom
                                                end
                                                if entry.joined and entry.id then
                                                    return tostring(entry.id)
                                                end
                                                return entry.name or ""
                                            end,
                                        },

                                        preview = {
                                            order = 3,
                                            type = "description",
                                            width = "normal",
                                            name = function()
                                                local mode = Mode()
                                                local shown
                                                if mode == "hidden" then
                                                    shown = "|cff999999" .. T("no tag") .. "|r"
                                                elseif mode == "short" then
                                                    shown = "[" .. (entry.joined and entry.id or entry.name) .. "]"
                                                elseif mode == "custom" then
                                                    local labels = profile.channelLabelsNamed
                                                    local custom = labels and labels[key]
                                                    local text = (type(custom) == "string" and custom ~= "")
                                                        and custom or tostring(entry.id or entry.name)
                                                    -- Mirror the "#" expansion so the
                                                    -- preview matches what chat does.
                                                    local rest = text:match("^#(.*)$")
                                                    if rest ~= nil and entry.id then
                                                        text = (rest ~= "") and (entry.id .. ". " .. rest) or tostring(entry.id)
                                                    end
                                                    shown = "[" .. text .. "]"
                                                else
                                                    shown = "[" .. (entry.joined and entry.id and (entry.id .. ". " .. entry.name) or entry.name) .. "]"
                                                end
                                                return T("Shows as:") .. " |cffffd100" .. shown .. "|r"
                                            end,
                                        },
                                    },
                                }
                            end

                            args.forgetUnjoined = {
                                order = 800,
                                type = "execute",
                                name = T("Forget Channels You Left"),
                                desc = T("Removes the rows marked as not joined, along with their labels."),
                                hidden = function()
                                    for _, entry in ipairs(known) do
                                        if not entry.joined then return false end
                                    end
                                    return true
                                end,
                                func = function()
                                    for _, entry in ipairs(known) do
                                        if not entry.joined then
                                            if profile.channelLabelsNamed then
                                                profile.channelLabelsNamed[entry.key] = nil
                                            end
                                            if profile.channelLabelNames then
                                                profile.channelLabelNames[entry.key] = nil
                                            end
                                            if profile.channelModes then
                                                profile.channelModes[entry.key] = nil
                                            end
                                        end
                                    end
                                    ns.ApplyVisuals()
                                end,
                            }

                            args.clearLabels = {
                                order = 900,
                                type = "execute",
                                name = T("Reset All Channels"),
                                confirm = true,
                                confirmText = T("Put every chat type and channel back to the game's own labels?"),
                                func = function()
                                    profile.channelModes = {}
                                    profile.channelLabels = {}
                                    profile.channelLabelsNamed = {}
                                    -- channelLabelNames is left alone on purpose: it
                                    -- only holds readable names for the rows, so
                                    -- wiping it would also remove channels the user
                                    -- added by hand.
                                    ns.ApplyVisuals()
                                end,
                            }

                            return args
                        end)(),
                    },
                },
            },

            -- TAB 3: SOUNDS
            tabSounds = {
                name = T("Sounds"),
                type = "group",
                order = 20,
                args = {
                    groupSoundMaster = {
                        name = T("Master Settings"),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            enable = {
                                order = 1,
                                name = T("Enable Chat Sounds"),
                                desc = T("Toggle channel notification sounds."),
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.sounds.enable = val end,
                                get = function(info) return self.db.profile.sounds.enable end,
                            },
                            masterChannel = {
                                order = 2,
                                name = T("Use Master Channel"),
                                desc = T("Play channel notifications through Master. Mention alerts always use Master."),
                                type = "toggle",
                                width = "full",
                                disabled = function() return not self.db.profile.sounds.enable end,
                                set = function(info, val) self.db.profile.sounds.masterVolume = val end,
                                get = function(info) return self.db.profile.sounds.masterVolume end,
                            },
                        },
                    },

                    groupSoundChannels = {
                        name = T("Channel Notifications"),
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            mentionRoutingNotice = {
                                order = 1,
                                type = "description",
                                name = T("Channel notification sounds. Mention alerts are configured in Mention Manager."),
                            },
                            soundWhisper = {
                                order = 2,
                                type = "select",
                                dialogControl = GetLSMSoundControl(),
                                name = T("Whisper Received"),
                                values = GetLSMSoundValues(),
                                disabled = function() return not self.db.profile.sounds.enable end,
                                set = function(info, val) self.db.profile.sounds.events["WHISPER"] = val end,
                                get = function(info) return self.db.profile.sounds.events["WHISPER"] end,
                            },
                            soundGuild = {
                                order = 3,
                                type = "select",
                                dialogControl = GetLSMSoundControl(),
                                name = T("Guild Chat"),
                                values = GetLSMSoundValues(),
                                disabled = function() return not self.db.profile.sounds.enable end,
                                set = function(info, val) self.db.profile.sounds.events["GUILD"] = val end,
                                get = function(info) return self.db.profile.sounds.events["GUILD"] end,
                            },
                            soundParty = {
                                order = 4,
                                type = "select",
                                dialogControl = GetLSMSoundControl(),
                                name = T("Party Chat"),
                                values = GetLSMSoundValues(),
                                disabled = function() return not self.db.profile.sounds.enable end,
                                set = function(info, val) self.db.profile.sounds.events["PARTY"] = val end,
                                get = function(info) return self.db.profile.sounds.events["PARTY"] end,
                            },
                            soundRaid = {
                                order = 5,
                                type = "select",
                                dialogControl = GetLSMSoundControl(),
                                name = T("Raid Chat"),
                                values = GetLSMSoundValues(),
                                disabled = function() return not self.db.profile.sounds.enable end,
                                set = function(info, val) self.db.profile.sounds.events["RAID"] = val end,
                                get = function(info) return self.db.profile.sounds.events["RAID"] end,
                            },
                        },
                    },

                }
            },

            -- TAB 3: FILTERS & HISTORY
            tabTools = {
                name = T("Filters & History"),
                type = "group",
                order = 30,
                -- Three large, unrelated feature areas. As inline groups they made one
                -- very long scroll; as child tabs each one is a page of its own.
                childGroups = "tab",
                args = {
                    -- 1. SPAM FILTER GROUP
                    groupSpam = {
                        name = T("Spam & System Filters"),
                        type = "group",
                        order = 1,
                        args = {
                                spamCore = {
                                    name = T("Keyword Blocking"),
                                    type = "group",
                                    inline = true,
                                    order = 1,
                                    args = {
                                        enableSpamFilter = {
                                            order = 1,
                                            name = T("Enable Keyword Blocking"),
                                            type = "toggle",
                                            width = "full",
                                            set = function(info, val) self.db.profile.enableSpamFilter = val; if ns.UpdateSpamCache then ns.UpdateSpamCache() end end,
                                            get = function(info) return self.db.profile.enableSpamFilter end,
                                        },
                                        spamFilterMode = {
                                            order = 2,
                                            name = T("Spam Filter Mode"),
                                            desc = T("Block removes matched messages. Log Only keeps chat visible but records debug entries for tuning rules."),
                                            type = "select",
                                            values = { block = "Block", log = "Log Only" },
                                            set = function(info, val) self.db.profile.spamFilterMode = val end,
                                            get = function(info) return self.db.profile.spamFilterMode or "block" end,
                                        },
                                        hideSystemSpam = {
                                            order = 3,
                                            name = T("Hide Join/Leave Messages"),
                                            desc = T("Hides yellow system messages when players join or leave channels.\n\n|cff999999Retail 12.x: handled through the secure message filter path.|r"),
                                            type = "toggle",
                                            set = function(info, val) self.db.profile.hideSystemSpam = val end,
                                            get = function(info) return self.db.profile.hideSystemSpam end,
                                        },
                                    },
                                },

                                spamThrottle = {
                                    name = T("Anti-Flood"),
                                    type = "group",
                                    inline = true,
                                    order = 2,
                                    args = {
                                        enableThrottle = {
                                            order = 1,
                                            name = T("Block Repeated Messages (Anti-Flood)"),
                                            desc = T("Prevents the same author from repeating the same normalized message within the selected cooldown."),
                                            type = "toggle",
                                            set = function(info, val) self.db.profile.enableThrottle = val end,
                                            get = function(info) return self.db.profile.enableThrottle end,
                                        },
                                        throttleTime = {
                                            order = 2,
                                            name = T("Repeat Cooldown"),
                                            desc = T("Seconds before the same normalized message can appear again from the same sender/channel."),
                                            type = "range",
                                            min = 5, max = 300, step = 5,
                                            disabled = function() return not self.db.profile.enableThrottle end,
                                            set = function(info, val) self.db.profile.throttleTime = val end,
                                            get = function(info) return tonumber(self.db.profile.throttleTime) or 60 end,
                                        },
                                        throttleMinLength = {
                                            order = 3,
                                            name = T("Minimum Repeat Length"),
                                            desc = T("Short common messages are ignored by anti-flood to avoid false positives."),
                                            type = "range",
                                            min = 8, max = 80, step = 1,
                                            disabled = function() return not self.db.profile.enableThrottle end,
                                            set = function(info, val) self.db.profile.throttleMinLength = val end,
                                            get = function(info) return tonumber(self.db.profile.throttleMinLength) or 20 end,
                                        },
                                    },
                                },

                                spamWhitelist = {
                                    name = T("Whitelist"),
                                    type = "group",
                                    inline = true,
                                    order = 3,
                                    args = {
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
                                    },
                                },

                                spamChannels = {
                                    name = T("Channel Rules"),
                                    type = "group",
                                    inline = true,
                                    order = 4,
                                    args = {
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
                                    },
                                },

                                spamKeywordList = {
                                    name = T("Blocklist Management"),
                                    type = "group",
                                    inline = true,
                                    order = 5,
                                    args = {
                                        addKeyword = {
                                            order = 1,
                                            name = T("Add Keyword"),
                                            desc = T("Type a word to block (e.g., 'boost', 'WTS') and press Enter."),
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
                                            order = 2,
                                            name = T("Remove Keyword"),
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
                                            order = 3,
                                            type = "description",
                                            name = function() 
                                                local keywords = self.db.profile.spamKeywords or {}
                                                if #keywords == 0 then return "\n|cff888888" .. T("(Blocklist is empty)") .. "|r" end
                                                return "\n|cffff0000" .. T("Blocked Words:") .. "|r " .. table.concat(keywords, ", ") 
                                            end,
                                        },
                                    },
                                },

                                spamDebug = {
                                    name = T("Runtime Debug"),
                                    type = "group",
                                    inline = true,
                                    order = 6,
                                    args = {
                                        spamDebugLog = {
                                            order = 1,
                                            type = "description",
                                            name = GetSpamLogDescription,
                                            fontSize = "medium",
                                        },
                                        resetSpamDebug = {
                                            order = 2,
                                            type = "execute",
                                            name = T("Reset Spam Debug Counters"),
                                            func = function() if ns.ResetSpamFilterStats then ns.ResetSpamFilterStats() end end,
                                            width = "full",
                                        },
                                    },
                                },

                        }
                    },

                    -- 2. HISTORY GROUP
                    groupHistory = {
                        name = T("Chat History"),
                        type = "group",
                        order = 2,
                        args = {
                                enableHistory = {
                                    order = 1,
                                    name = T("Enable History"),
                                    desc = T("Saves messages for the Chatify History window only. History is never replayed into the live chat frame.\n\n|cff999999Retail 12.x: stores only messages captured through the safe event path.|r"),
                                    type = "toggle",
                                    set = function(info, val) self.db.profile.enableHistory = val end,
                                    get = function(info) return self.db.profile.enableHistory end,
                                },
                                historyLimit = {
                                    order = 2,
                                    name = T("History Size"),
                                    desc = T("Lines to keep per chat tab for the Chatify History window."),
                                    type = "range",
                                    min = 25, max = 500, step = 25,
                                    disabled = function() return not self.db.profile.enableHistory end,
                                    set = function(info, val) self.db.profile.historyLimit = val end,
                                    get = function(info) return self.db.profile.historyLimit end,
                                }
                        }
                    },

                    -- 3. COPY CHAT GROUP
                    groupCopy = {
                        name = T("Copy Chat"),
                        type = "group",
                        order = 3,
                        args = {
                                copyNativeSelection = {
                                    order = 1,
                                    name = T("Enable Direct Chat Selection"),
                                    desc = T("Shift + Left Click the Copy Chat button toggles Blizzard direct selection inside the chat frame. Select text in chat, then press Ctrl+C. WoW addons cannot write to the system clipboard automatically."),
                                    type = "toggle",
                                    width = "full",
                                    set = function(info, val) self.db.profile.copyNativeSelection = val end,
                                    get = function(info) return self.db.profile.copyNativeSelection ~= false end,
                                },
                                copyNativeUseVisibleFrames = {
                                    order = 2,
                                    name = T("Compatibility Mode for Custom Chat Layouts"),
                                    desc = T("Enable direct selection on all visible chat frames instead of only the best detected frame. Use this only if ElvUI/Prat/custom chat layouts prevent Shift + Left Click from selecting text. Keeping this off is safer."),
                                    type = "toggle",
                                    width = "full",
                                    disabled = function() return self.db.profile.copyNativeSelection == false end,
                                    set = function(info, val) self.db.profile.copyNativeUseVisibleFrames = val end,
                                    get = function(info) return self.db.profile.copyNativeUseVisibleFrames == true end,
                                },
                                copyNativeTimeout = {
                                    order = 3,
                                    name = T("Auto-disable Direct Selection"),
                                    desc = T("Seconds before Chatify turns direct selection off automatically. Use 0 only if you want to turn it off manually with Shift + Left Click."),
                                    type = "range",
                                    min = 0, max = 120, step = 5,
                                    width = "full",
                                    disabled = function() return self.db.profile.copyNativeSelection == false end,
                                    set = function(info, val) self.db.profile.copyNativeTimeout = val end,
                                    get = function(info) return tonumber(self.db.profile.copyNativeTimeout) or 30 end,
                                },
                                copyNativeAnnounce = {
                                    order = 4,
                                    name = T("Show Direct Selection Hint"),
                                    desc = T("Print a short Chatify message when Shift + Left Click toggles direct chat selection."),
                                    type = "toggle",
                                    width = "full",
                                    disabled = function() return self.db.profile.copyNativeSelection == false end,
                                    set = function(info, val) self.db.profile.copyNativeAnnounce = val end,
                                    get = function(info) return self.db.profile.copyNativeAnnounce ~= false end,
                                },
                                copyNativeHelp = {
                                    order = 5,
                                    type = "description",
                                    name = T("\n|cffffd200How it works:|r Left Click opens the normal copy window. Shift + Left Click toggles direct selection inside the chat frame only. Select text, then press Ctrl+C. Repeat Shift + Left Click to turn it off.\n|cff999999Direct OS clipboard writes are blocked by the WoW client, so selected chat text still needs Ctrl+C.|r"),
                                },
                                copyTabsHeader = {
                                    order = 10,
                                    type = "header",
                                    name = T("Copy Window Tabs"),
                                },
                                copyTabMode = {
                                    order = 11,
                                    name = T("Tabs shown in copy window"),
                                    desc = T("Controls which Blizzard chat windows appear as tabs in the ChatCopy 2.0 popup. Combat Log and Voice are always excluded. Hidden windows are disabled by default."),
                                    type = "select",
                                    width = "full",
                                    values = {
                                        ALL = T("All usable chat tabs"),
                                        VISIBLE = T("Visible or docked tabs only"),
                                        PINNED = T("Manual selection only"),
                                        SELECTED = T("Selected chat only"),
                                    },
                                    set = function(info, val)
                                        EnsureProfileTables(self.db.profile)
                                        self.db.profile.copyTabMode = val or "VISIBLE"
                                        if type(ns.RefreshCopyChatTabs) == "function" then ns.RefreshCopyChatTabs() end
                                    end,
                                    get = function(info)
                                        EnsureProfileTables(self.db.profile)
                                        return self.db.profile.copyTabMode or "VISIBLE"
                                    end,
                                },
                                copyTabFrames = {
                                    order = 12,
                                    name = T("Chat tabs available for copy"),
                                    desc = T("Enable or disable individual chat windows in the ChatCopy tab strip. Names are read from the current Blizzard chat windows, so renamed tabs are supported. Combat Log and Voice are intentionally not listed."),
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
                name = T("Mention Manager"),
                type = "group",
                order = 35,
                args = {
                    groupMentionRules = {
                        name = T("Rules"),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            headerMentions = {
                                order = 1,
                                type = "description",
                                name = T("Create rules for names, words, or phrases. Each rule can highlight text, play a sound, limit channels, and use its own cooldown."),
                                fontSize = "medium",
                            },
                            enableMentionManager = {
                                order = 2,
                                name = T("Enable Mention Manager"),
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.enableMentionManager = val end,
                                get = function(info) return self.db.profile.enableMentionManager ~= false end,
                            },
                            addMentionRule = {
                                order = 3,
                                name = T("Add Word / Phrase"),
                                desc = T("Example: Sebas, RL, Ключ"),
                                type = "input",
                                width = "full",
                                set = function(info, val) AddMentionRule(self.db.profile, val) end,
                                get = function(info) return "" end,
                            },
                            selectedMentionRule = {
                                order = 4,
                                name = T("Selected Rule"),
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
                                name = T("Remove Selected Rule"),
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
                        },
                    },

                    groupMentionEdit = {
                        name = T("Edit Selected Rule"),
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            mentionEnabled = {
                                order = 1,
                                name = T("Enabled"),
                                type = "toggle",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.enabled = val end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.enabled ~= false or false end,
                            },
                            mentionText = {
                                order = 2,
                                name = T("Word / Phrase"),
                                type = "input",
                                width = "full",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.text = TrimInput(val) end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.text or "" end,
                            },
                            mentionColor = {
                                order = 3,
                                name = T("Color Hex"),
                                desc = T("Use 6-digit RGB hex without #. Example: ffd700, ff4040, 68ccef."),
                                type = "input",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.color = TrimInput(val):gsub("#", "") end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.color or "ffd700" end,
                            },
                            mentionSound = {
                                order = 4,
                                type = "select",
                                dialogControl = GetLSMSoundControl(),
                                name = T("Sound"),
                                desc = T("Sound for this mention rule. Choose None for highlight only."),
                                values = GetLSMSoundValues(),
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.sound = val end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.sound or "None" end,
                            },
                            testMentionSound = {
                                order = 5,
                                name = T("Test Selected Sound"),
                                type = "execute",
                                func = function() PlaySelectedMentionRuleSound(self.db.profile) end,
                            },
                            mentionChannels = {
                                order = 6,
                                name = T("Channels"),
                                desc = T("Comma-separated. Supported: GUILD, PARTY, RAID, INSTANCE, WHISPER, CHANNEL, TRADE, SERVICES, GENERAL, COMMUNITY, SAY, YELL, ALL."),
                                type = "input",
                                width = "full",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.channels = TrimInput(val) end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.channels or "ALL" end,
                            },
                            mentionIgnoreCase = {
                                order = 7,
                                name = T("Ignore Case"),
                                type = "toggle",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.ignoreCase = val end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.ignoreCase ~= false or false end,
                            },
                            mentionWholeWord = {
                                order = 8,
                                name = T("Whole Word Only"),
                                desc = T("Match the whole word instead of a part of another word. For non-Latin text, Chatify uses safe phrase matching."),
                                type = "toggle",
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.wholeWord = val end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and rule.wholeWord ~= false or false end,
                            },
                            mentionCooldown = {
                                order = 9,
                                name = T("Sound Cooldown"),
                                type = "range",
                                min = 0, max = 60, step = 1,
                                set = function(info, val) local rule = GetSelectedMentionRule(self.db.profile); if rule then rule.cooldown = val end end,
                                get = function(info) local rule = GetSelectedMentionRule(self.db.profile); return rule and tonumber(rule.cooldown) or 2 end,
                            },
                        },
                    },

                },
            },

            -- TAB 5: AUTO REPLY
            tabAutoReply = {
                name = T("Auto Reply"),
                type = "group",
                order = 40,
                args = {
                    groupReplyBehaviour = {
                        name = T("Behaviour"),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            headerAutoReply = {
                                order = 1,
                                type = "description",
                                name = T("Automatically reply when you are AFK, in queue, inside an instance, or manually marked as busy.\n\n|cff999999Retail Safe Mode: whisper / BN whisper auto-replies are disabled on modern Retail; guild mention replies can still work when available.|r"),
                                fontSize = "medium",
                            },
                            enableAutoReply = {
                                order = 2,
                                name = T("Enable Auto Reply"),
                                type = "toggle",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.enabled = val end,
                                get = function(info) return self.db.profile.autoReply.enabled end,
                            },
                            busyMode = {
                                order = 3,
                                name = T("Busy Mode"),
                                desc = T("Force the busy message even when you are not AFK or inside an activity."),
                                type = "toggle",
                                width = "full",
                                disabled = function() return not self.db.profile.autoReply.enabled end,
                                set = function(info, val) self.db.profile.autoReply.busyMode = val end,
                                get = function(info) return self.db.profile.autoReply.busyMode end,
                            },
                            onlyFriends = {
                                order = 4,
                                name = T("Only Friends / Guild"),
                                desc = T("Reply only to Battle.net friends, regular friends, or guild members."),
                                type = "toggle",
                                width = "full",
                                disabled = function() return not self.db.profile.autoReply.enabled end,
                                set = function(info, val) self.db.profile.autoReply.onlyFriends = val end,
                                get = function(info) return self.db.profile.autoReply.onlyFriends end,
                            },
                            autoNotify = {
                                order = 5,
                                name = T("Send Return Message"),
                                desc = T("When you are back, whisper everyone who contacted you while you were busy."),
                                type = "toggle",
                                width = "full",
                                disabled = function() return not self.db.profile.autoReply.enabled end,
                                set = function(info, val) self.db.profile.autoReply.autoNotify = val end,
                                get = function(info) return self.db.profile.autoReply.autoNotify end,
                            },
                            guildReplyEnabled = {
                                order = 6,
                                name = T("Reply to Guild Mentions"),
                                desc = T("When your name is mentioned in guild chat during activity, send one throttled guild response and remember that player for the return whisper."),
                                type = "toggle",
                                width = "full",
                                disabled = function() return not self.db.profile.autoReply.enabled end,
                                set = function(info, val) self.db.profile.autoReply.guildReplyEnabled = val end,
                                get = function(info) return self.db.profile.autoReply.guildReplyEnabled end,
                            },
                            cooldown = {
                                order = 7,
                                name = T("Reply Cooldown (minutes)"),
                                desc = T("How often Chatify may auto-reply to the same player."),
                                type = "range",
                                min = 1, max = 60, step = 1,
                                disabled = function() return not self.db.profile.autoReply.enabled end,
                                set = function(info, val) self.db.profile.autoReply.cooldown = val end,
                                get = function(info) return self.db.profile.autoReply.cooldown end,
                            },
                        },
                    },

                    groupReplyMessages = {
                        name = T("Messages"),
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            afkMessage = {
                                order = 1,
                                name = T("AFK Message"),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.afkMessage = val end,
                                get = function(info) return self.db.profile.autoReply.afkMessage end,
                            },
                            queueMessage = {
                                order = 2,
                                name = T("Queue Message"),
                                desc = T("Use %s to inject the wait time in minutes."),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.queueMessage = val end,
                                get = function(info) return self.db.profile.autoReply.queueMessage end,
                            },
                            dungeonMessage = {
                                order = 3,
                                name = T("Dungeon Message"),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.dungeonMessage = val end,
                                get = function(info) return self.db.profile.autoReply.dungeonMessage end,
                            },
                            raidMessage = {
                                order = 4,
                                name = T("Raid Message"),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.raidMessage = val end,
                                get = function(info) return self.db.profile.autoReply.raidMessage end,
                            },
                            pvpMessage = {
                                order = 5,
                                name = T("PvP Message"),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.pvpMessage = val end,
                                get = function(info) return self.db.profile.autoReply.pvpMessage end,
                            },
                            busyMessage = {
                                order = 6,
                                name = T("Busy Message"),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.busyMessage = val end,
                                get = function(info) return self.db.profile.autoReply.busyMessage end,
                            },
                            returnMessage = {
                                order = 7,
                                name = T("Return Message"),
                                desc = T("Sent automatically when you become available again."),
                                type = "input",
                                width = "full",
                                set = function(info, val) self.db.profile.autoReply.returnMessage = val end,
                                get = function(info) return self.db.profile.autoReply.returnMessage end,
                            },
                        },
                    },

                }
            },

            -- TAB 5: SETUP / MAINTENANCE
            tabSetup = {
                name = T("Setup & Reset"),
                type = "group",
                order = 99, 
                args = {
                    groupTabSetup = {
                        name = T("Chat Tabs Setup"),
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            descSetup = {
                                order = 1,
                                type = "description",
                                name = T("Safely create or update chat tabs without duplicates. The selected template controls which tabs are created.\n|cffffcc00Warning: Modifies chat window layout, but does not run in combat.|r"),
                                fontSize = "medium",
                            },
                            chatTabsTemplate = {
                                order = 2,
                                name = T("Template"),
                                type = "select",
                                values = { PM = "PM", GUILD = "Guild", RAID = "Raid / Guild / PM" },
                                set = function(info, val) self.db.profile.chatTabsTemplate = val end,
                                get = function(info) return self.db.profile.chatTabsTemplate or "RAID" end,
                            },
                            chatTabsPreview = {
                                order = 3,
                                type = "description",
                                name = GetChatTabsPreview,
                                fontSize = "medium",
                            },
                            btnSetup = {
                                order = 4,
                                name = T("Apply Safe Tab Setup"),
                                type = "execute",
                                func = "SetupDefaultTabs", 
                                width = "full",
                                confirm = true,
                                confirmText = "Create or update chat tabs for the selected template?",
                            },
                            btnRestoreDefaultTabs = {
                                order = 5,
                                name = T("Restore Main Chat Groups"),
                                desc = T("Restores common message groups on the main General chat frame. It does not delete custom windows."),
                                type = "execute",
                                func = "RestoreDefaultChatTabs",
                                width = "full",
                                confirm = true,
                                confirmText = "Restore common message groups on the main chat frame?",
                            },
                        },
                    },

                    groupMaintenance = {
                        name = T("Maintenance"),
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            runtimeDebug = {
                                order = 1,
                                type = "description",
                                name = GetRuntimeDebugDescription,
                                fontSize = "medium",
                            },
                            btnReset = {
                                order = 2,
                                name = T("Reset All Settings"),
                                desc = T("|cffff0000Cannot be undone!|r"),
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
                                order = 3,
                                name = T("Reload UI"),
                                type = "execute",
                                func = function() ReloadUI() end,
                                width = "full",
                                confirm = true,
                                confirmText = "Reload UI now?",
                            },
                        },
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
-- /chatifydb - what the SavedVariables actually did this session.
--
-- Settings resetting at logout is almost never the addon clearing them: it is
-- the SavedVariables file failing to be written or failing to parse on the way
-- back in, after which the client discards it and the addon starts from
-- defaults. That is invisible from inside the game, so this reports the few
-- facts that distinguish the causes.
--
-- Read it at the START of a session, before changing anything: "loaded from
-- disk" being false on a character that has used Chatify before is the finding.
function Chatify:PrintSavedVariablesReport()
    local function say(line)
        local frame = DEFAULT_CHAT_FRAME
        if frame and type(frame.AddMessage) == "function" then
            pcall(frame.AddMessage, frame, "|cffffd200Chatify:|r " .. tostring(line))
        end
    end

    say("SavedVariables report")

    if not self.db then
        say("  database was never created - settings cannot persist at all")
        return
    end

    -- Guarded individually: AceDB's profile API is not present on every version,
    -- and a diagnostic that errors is worse than one that says less.
    if type(self.db.GetCurrentProfile) == "function" then
        local ok, current = pcall(self.db.GetCurrentProfile, self.db)
        say("  profile in use: " .. tostring(ok and current or "unknown"))
    end

    if type(self.db.GetProfiles) == "function" then
        local ok, profiles = pcall(self.db.GetProfiles, self.db)
        if ok and type(profiles) == "table" then
            say("  profiles stored: " .. #profiles)
        end
    end

    -- ChatifyDB exists as a global only if the client read a file back in. On a
    -- first-ever login it is absent, which is expected; on a character that has
    -- used the addon before, absent means the file did not survive.
    say("  loaded from disk: " .. tostring(sessionLoadedFromDisk))
    say("  previous sessions recorded: " .. tostring(sessionPreviousCount))
    if sessionPreviousStamp then
        say("  last saved: " .. tostring(sessionPreviousStamp))
    end

    if sessionPreviousCount == 0 then
        say("|cffff6060  Nothing came back from disk this session.|r")
        say("  If you have used Chatify before, the file is not being written at")
        say("  logout. That is outside the addon: check that WoW is not installed")
        say("  under Program Files, that the WTF folder is not synced by OneDrive")
        say("  or Dropbox, and that the game is exited normally rather than being")
        say("  force-closed or crashing, since the file is only written on a clean exit.")
    else
        say("  Persistence is working: your settings did survive earlier logouts.")
    end

    if type(ChatifyHistoryDB) == "table" then
        local frames, lines = 0, 0
        for _, messages in pairs(ChatifyHistoryDB.frames or {}) do
            frames = frames + 1
            if type(messages) == "table" then
                lines = lines + #messages
            end
        end

        local size = type(ns.EstimateHistorySize) == "function" and ns.EstimateHistorySize() or 0
        say(string.format("  history: %d windows, %d lines, about %.1f MB",
            frames, lines, size / 1048576))

        -- The client refuses to write an oversized file and then saves nothing at
        -- all, settings included, so a large history is worth calling out even
        -- before SAVED_VARIABLES_TOO_LARGE fires.
        if size > 2 * 1048576 then
            say("  |cffff4444history is large enough to risk the save being refused|r")
            say("  lower History Limit, or press Clear History, then /reload")
        end
    else
        say("  history: none stored")
    end

    say("  addon folder: " .. tostring(addonName))
    say("If 'loaded from disk' is false at the start of a session, the file is")
    say("being lost at logout rather than the settings being reset.")
end

function Chatify:OnInitialize()
    -- Initialize DB
    if not ns.defaults then ns.defaults = { profile = { spamKeywords = {} } } end

    -- Recorded before AceDB runs, because AceDB creates the table when it is
    -- missing and afterwards there is no way to tell a restored file from a
    -- fresh one. This is the single fact that separates "settings were reset"
    -- from "the file never came back".
    sessionLoadedFromDisk = type(ChatifyDB) == "table" and next(ChatifyDB) ~= nil

    self.db = LibStub("AceDB-3.0"):New("ChatifyDB", ns.defaults, true)

    -- Session marker.
    --
    -- "My settings reset every logout" has two completely different causes and
    -- no way to tell them apart from inside the game: either something is
    -- clearing the profile, or the SavedVariables file is not surviving the
    -- logout at all. The counter answers that outright - it lives in the global
    -- section, has no default, and is therefore never touched by AceDB's
    -- removeDefaults. If it reads 1 on a character that has used Chatify for
    -- days, nothing was ever written back.
    local marker = self.db.global
    sessionPreviousCount = tonumber(marker.sessionCount) or 0
    sessionPreviousStamp = marker.lastSavedAt
    marker.sessionCount = sessionPreviousCount + 1
    marker.lastSavedAt = (type(date) == "function") and date("%Y-%m-%d %H:%M") or nil
    
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

    -- Setup Config GUI. PTR clients may expose small API differences that break
    -- older AceGUI widgets, so never let the configuration UI stop Chatify from
    -- loading or refreshing chat.
    local aceConfig = LibStub("AceConfig-3.0", true)
    if aceConfig and type(aceConfig.RegisterOptionsTable) == "function" then
        -- Registered as a function rather than a built table. The Channels tab
        -- lists the channels you are actually in, and that list changes at
        -- runtime; a table built once at load would show whatever was joined
        -- during login and never update.
        pcall(aceConfig.RegisterOptionsTable, aceConfig, "Chatify", function()
            local ok, options = pcall(self.GetOptions, self)
            if ok and type(options) == "table" then
                return options
            end
            -- Never let a build error take the whole options panel away.
            return { name = "Chatify", type = "group", args = {} }
        end)
    end

    if ACD and type(ACD.AddToBlizOptions) == "function" then
        local ok, frame = pcall(ACD.AddToBlizOptions, ACD, "Chatify", "Chatify")
        if ok then
            self.optionsFrame = frame
        else
            self.optionsFrame = nil
            ns.configRegistrationError = frame
        end
    end

    -- Chat Commands. Keep the primary /chatify plus a short, addon-scoped alias.
    -- /mcm is intentionally NOT registered: it is a de-facto generic "Mod
    -- Configuration Menu" command that several addons claim, and AceConsole's
    -- last-writer-wins registration would silently hijack it from them.
    self:RegisterChatCommand("chatify", "OpenConfig")
    self:RegisterChatCommand("cfy", "OpenConfig")
    self:RegisterChatCommand("chatifydb", "PrintSavedVariablesReport")
    
    -- Runtime modules refresh themselves on enable. Avoid doing a second full
    -- style/filter pass here because Ace will immediately enable modules after
    -- initialization.
end

local refreshQueued = false
local function RefreshRuntimeModulesNow()
    local safeCall = type(ns.SafeCall) == "function" and ns.SafeCall or function(_, func, ...) return pcall(func, ...) end

    if type(ns.UpdateSpamCache) == "function" then
        safeCall("UpdateSpamCache", ns.UpdateSpamCache)
    end

    -- One visual pass is enough. Calling both ns.ApplyVisuals() and the module
    -- method caused duplicate style/filter work during profile changes.
    if type(ns.ApplyVisuals) == "function" then
        safeCall("ApplyVisuals", ns.ApplyVisuals)
    end

    if type(ns.NotifyQuickChatSettingsChanged) == "function" then
        safeCall("QuickChatSettingsChanged", ns.NotifyQuickChatSettingsChanged)
    end

    local router = Chatify.GetModule and Chatify:GetModule("Router", true)
    if router then
        if type(router.ApplyToAllFrames) == "function" then
            safeCall("Router.ApplyToAllFrames", router.ApplyToAllFrames, router)
        end
        if type(router.RefreshProxies) == "function" then
            safeCall("Router.RefreshProxies", router.RefreshProxies, router)
        end
    end

    local quickButtons = Chatify.GetModule and Chatify:GetModule("QuickButtons", true)
    if quickButtons and type(quickButtons.Refresh) == "function" then
        safeCall("QuickButtons.Refresh", quickButtons.Refresh, quickButtons)
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
    self:WarnIfSettingsWereLost()
end

-- Tells the user once, in chat, when their configuration did not come back.
--
-- Without this they only notice that things look wrong and have to guess why.
-- The condition is deliberately narrow: the session counter is stored in the
-- global section with no default, so AceDB never strips it, and the only way it
-- reads zero while a profile has customised values is that the last write did
-- not reach disk. A genuine first run has no customised values either, so it
-- stays quiet.
function Chatify:WarnIfSettingsWereLost()
    if sessionWarningShown or sessionPreviousCount > 0 then
        return
    end

    if not self.db or not self.db.profile then
        return
    end

    -- rawget through the AceDB proxy: reading normally would fall through to the
    -- defaults and report customisation that is not there.
    local sv = rawget(self.db, "sv")
    local profiles = sv and rawget(sv, "profiles")
    local stored = profiles and profiles[self.db:GetCurrentProfile()]
    if type(stored) ~= "table" or next(stored) == nil then
        -- Nothing customised, so this is a first run and there is nothing to warn about.
        return
    end

    sessionWarningShown = true

    local frame = DEFAULT_CHAT_FRAME
    if not frame or type(frame.AddMessage) ~= "function" then
        return
    end

    pcall(frame.AddMessage, frame,
        "|cffffd200Chatify:|r |cffff6060" ..
        T("Your saved settings did not load this session.") .. "|r " ..
        T("Type /chatifydb for details."))
end

function Chatify:OpenConfig()
    if ACD and type(ACD.Open) == "function" then
        local ok, err = pcall(ACD.Open, ACD, "Chatify")
        if ok then
            return
        end
        ns.configOpenError = err
    end

    local frame = self.optionsFrame
    if not frame then
        return
    end

    local category = frame.name or frame

    if Settings and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, category)
        if ok then
            return
        end
    end

    if InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, frame)
        pcall(InterfaceOptionsFrame_OpenToCategory, frame)
    end
end


function _G.Chatify_ToggleOptionsWindow()
    if Chatify and type(Chatify.OpenConfig) == "function" then
        return Chatify:OpenConfig()
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
