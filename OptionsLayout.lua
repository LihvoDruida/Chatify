-- Arrange the existing option objects by task. Profile keys and runtime handlers
-- stay with their original objects; no SavedVariables migration is needed.
local _, ns = ...
local Layout = {}
ns.OptionsLayout = Layout
local function T(text) return ns.Locale:Get(text) end

function Layout:Apply(options)
    local old = options.args
    local general, tools, setup = old.tabGeneral.args, old.tabTools.args, old.tabSetup.args
    local root = { headerInfo = old.headerInfo, groupLanguage = general.groupLanguage }
    options.args, options.childGroups = root, "tree"
    local function page(key, name, order, node)
        node = node or { type = "group", args = {} }
        node.name, node.order, node.inline = T(name), order, false
        root[key] = node
        return node.args
    end
    local function group(parent, key, name, order)
        local node = { type = "group", inline = true, name = T(name), order = order, args = {} }
        parent[key] = node
        return node.args
    end
    local function move(source, target, keys)
        for i, key in ipairs(keys) do
            local node = source[key]
            if node then target[key], source[key], node.order = node, nil, i end
        end
    end
    root.settingsHelp = { type = "description", order = 1,
        name = T("Choose a section or search settings. Use Apply/Enter for text; number fields save with Enter or when you leave them. Channel labels also save on blur. Esc cancels edits. Reset requires confirmation.") }
    root.groupLanguage.order = 2
    root.groupLanguage.args.languageOverride.sorting = ns.Locale.order

    local appearance = page("appearance", "Appearance", 10)
    appearance.groupText, appearance.groupTimestamps = general.groupText, general.groupTimestamps
    appearance.groupText.order, appearance.groupTimestamps.order = 1, 4
    local text = appearance.groupText.args
    move(text, group(appearance, "senders", "Player Names & Icons", 2),
        { "shortPlayerNames", "senderRaceIcon", "senderClassIcon", "senderIconScale", "senderIconOffset" })
    move(text, group(appearance, "links", "Links & Tooltips", 3), { "urlColor", "hoverHyperlinkTooltips" })
    local stamp = appearance.groupTimestamps.args
    for _, key in ipairs({ "timestampID", "useServerTime", "timestampPost" }) do
        local original = stamp[key].disabled
        stamp[key].disabled = function(info)
            return not ns.Chatify.db.profile.enableTimestamps
                or (type(original) == "function" and original(info)) or original == true
        end
    end

    local windows = page("windows", "Chat Windows & Tabs", 20)
    windows.groupWindow, windows.groupTabSetup = general.groupWindow, setup.groupTabSetup
    windows.groupWindow.order, windows.groupTabSetup.order = 1, 4
    for _, key in ipairs({ "btnSetup", "btnRestoreDefaultTabs" }) do
        windows.groupTabSetup.args[key].disabled = function()
            return type(InCombatLockdown) == "function" and InCombatLockdown()
        end
    end
    move(windows.groupWindow.args, group(windows, "fading", "Message Fading", 2), { "disableChatFade", "chatFadeTime" })
    move(windows.groupWindow.args, group(windows, "buttons", "Blizzard Chat Buttons", 3), { "hideBlizzardChatButtons" })

    page("quickButtons", "Quick Chat Buttons", 30, general.groupQuickButtons)
    local quick = root.quickButtons.args
    move(quick, group(quick, "quickAppearance", "Button Appearance", 20),
        { "quickChatButtonTheme", "quickChatPanelAlpha", "quickChatButtonAlpha", "quickChatButtonSize", "quickChatButtonFontScale" })
    move(quick, group(quick, "quickPosition", "Button Position & Spacing", 30),
        { "quickChatButtonSpacing", "quickChatButtonGap", "quickChatButtonYOffset" })

    page("channels", "Channel Names", 40, old.tabChannels)
    page("composer", "Message Composer", 50, old.tabComposer)
    local composer = root.composer.args.groupComposer.args
    move(composer, group(root.composer.args, "composerFormat", "Message Format", 2),
        { "chunkLimit", "continuation", "showCounter", "spellcheckIntegration", "perLineHelp" })
    move(composer, group(root.composer.args, "composerFlow", "Sending & Drafts", 3),
        { "defaultChannel", "importCurrentDraft", "autoPreview", "autoAdvance", "lockFinalChunk", "rememberWhisperTarget" })
    root.composer.args.groupComposerAutomation.order = 4

    page("filters", "Spam & System Filters", 60, tools.groupSpam)
    local spam = root.filters.args
    spam.spamCore.order, spam.spamKeywordList.order, spam.spamThrottle.order = 1, 2, 3
    spam.spamWhitelist.order, spam.spamChannels.order = 4, 5
    move(spam.spamCore.args, group(spam, "systemMessages", "System Messages", 6), { "hideSystemSpam" })
    spam.spamCore.args.spamFilterMode.disabled = function() return not ns.Chatify.db.profile.enableSpamFilter end
    -- Scan choices remain editable before enabling the filter. Guild scanning,
    -- however, is bypassed by the whitelist and must not look active then.
    spam.spamChannels.args.scanGuild.disabled = function()
        return ns.Chatify.db.profile.spamWhitelist.guild ~= false
    end
    spam.spamChannels.args.scanGuild.desc = T("Disable the Guild / Officer whitelist to filter guild messages.")

    page("mentions", "Mention Manager", 70, old.tabMentions)
    local edit = root.mentions.args.groupMentionEdit
    edit.disabled = function()
        local rules = ns.Chatify.db.profile.mentionRules
        return type(rules) ~= "table" or #rules == 0
    end
    for _, key in ipairs({ "selectedMentionRule", "removeMentionRule" }) do
        root.mentions.args.groupMentionRules.args[key].disabled = edit.disabled
    end
    page("sounds", "Sounds", 80, old.tabSounds)
    for _, option in pairs(root.sounds.args.groupSoundChannels.args) do
        if option.type == "select" then option.chatifySound = true end
    end
    edit.args.mentionSound.chatifySound = true
    page("autoReply", "Auto Reply", 90, old.tabAutoReply)
    local reply = root.autoReply.args.groupReplyBehaviour.args
    move(reply, group(root.autoReply.args, "replyDelivery", "Recipients & Cooldown", 2),
        { "onlyFriends", "guildReplyEnabled", "autoNotify", "cooldown" })
    root.autoReply.args.groupReplyMessages.order = 3

    page("copy", "Copy Chat", 100, tools.groupCopy)
    local copy = root.copy.args
    move(copy, group(copy, "copyTabs", "Copy Window Tabs", 20),
        { "copyTabsHeader", "copyTabMode", "copyTabFrames", "resetCopyTabFrames" })
    -- The group heading already identifies the tab selection controls.
    copy.copyTabs.args.copyTabsHeader.hidden = true
    page("history", "Chat History", 110, tools.groupHistory)
    local profiles = page("profiles", "Profiles & Backup", 120)
    profiles.groupProfileBackup = tools.groupProfileBackup
    profiles.groupProfileBackup.order = 1
    move(setup.groupMaintenance.args, group(profiles, "resetProfile", "Reset Profile", 2), { "btnReset" })

    -- Explain unavailable controls using the very same capability result that
    -- powers runtime diagnostics and protected-client shortcut routing.
    local availability = page("availability", "Feature Availability", 125)
    local features = {
        { "autoReplyWhisper", "Whisper Auto Reply" },
        { "autoReplyBNet", "Battle.net Auto Reply" },
        { "autoReplyGuild", "Guild Auto Reply" },
        { "virtualChat", "Virtual Chat" },
        { "nativeCopy", "Native Copy" },
        { "mentions", "Mentions" },
        { "composer", "Message Composer" },
    }
    availability.capabilities = {
        type = "description", order = 1,
        name = function()
            local lines = { T("Unavailable features are listed here rather than silently disappearing from Settings.") }
            for _, entry in ipairs(features) do
                local support = type(ns.GetFeatureSupport) == "function" and ns.GetFeatureSupport(entry[1]) or "unavailable"
                local status = support == "supported" and T("Available")
                    or (support == "warning" and T("Limited") or T("Unavailable"))
                lines[#lines + 1] = "• " .. T(entry[2]) .. ": " .. status
                if support == "warning" and type(ns.GetFeatureWarningText) == "function" then
                    local warning = ns.GetFeatureWarningText(entry[1])
                    if type(warning) == "string" and warning ~= "" then
                        lines[#lines + 1] = "   " .. T(warning)
                    end
                elseif support == "unavailable" then
                    if type(ns.IsRetailSecretValueBuild) == "function" and ns.IsRetailSecretValueBuild()
                        and (entry[1] == "autoReplyWhisper" or entry[1] == "autoReplyBNet" or entry[1] == "virtualChat") then
                        lines[#lines + 1] = "   " .. T("Disabled to respect protected chat values.")
                    else
                        lines[#lines + 1] = "   " .. T("Required client capability is unavailable.")
                    end
                end
            end
            return table.concat(lines, "\n")
        end,
    }

    local maintenance = page("maintenance", "Compatibility & Diagnostics", 130)
    maintenance.groupSafety, maintenance.groupMaintenance = general.groupSafety, setup.groupMaintenance
    maintenance.groupSafety.order, maintenance.groupMaintenance.order = 1, 3
    maintenance.spamDebug = spam.spamDebug
    spam.spamDebug = nil
    maintenance.spamDebug.order = 2
    -- Preserve the feature gate when moving this group outside the filters page.
    maintenance.spamDebug.hidden = root.filters.hidden
    local reports = group(maintenance, "reports", "Diagnostic Reports", 4)
    for i, entry in ipairs({ { "PrintClientCompatibilityReport", "Print Client Compatibility Report" },
        { "PrintChatTaintReport", "Print Chat Compatibility Report" },
        { "PrintSavedVariablesReport", "Print Saved Settings Report" },
        { "PrintChatEntryTrace", "Print Chat Entry Trace" } }) do
        reports[entry[1]] = { type = "execute", order = i, name = T(entry[2]), func = entry[1] }
    end

    -- Descendants form sections in one scrollable page, including dynamic
    -- per-channel rows previously hidden behind another level of tabs.
    local function inline(node)
        for _, child in pairs(node.args or {}) do
            if child.type == "group" then child.inline = true; inline(child) end
        end
    end
    for _, node in pairs(root) do inline(node) end
end
