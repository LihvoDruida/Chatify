-- Drive real input scripts: typing, focus loss, redraw and Apply/Enter.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local fixtures = require("client_fixtures")
local client = os.getenv("CHATIFY_LABEL_CLIENT") or "retail"
local fixture = fixtures.install(env, client)
local view = os.getenv("CHATIFY_LABEL_VIEW") or "standalone"
Settings = {
    RegisterCanvasLayoutCategory = function() return { GetID = function() return 77 end } end,
    RegisterAddOnCategory = function() end,
}
local ns = {}
for line in io.lines(fixture[4]) do
    if line:match("%.lua$") then assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns) end
end
local addon, ui = ns.Chatify, ns.SettingsWindow
addon:OnInitialize()
if not ns.IsFeatureAvailable("channels") then
    print("channel label probe: SKIP (" .. client .. "; channel API unavailable)")
    return
end
addon.db.profile.shortChannels = true
addon.db.profile.channelModes.GUILD = "custom"
addon.db.profile.channelModes.GENERAL = "custom"
addon:OpenConfig("channels")
local checks = 0
local function check(label, condition)
    checks = checks + 1
    assert(condition, "channel label probe: " .. label)
end
if view == "embedded" then
    local panel = ns.SettingsIntegration.panel
    panel:GetScript("OnShow")(panel)
    ui:SelectPage("channels")
    check("same renderer embedded", ui.embeddedHost == panel)
end
local function rowFor(token)
    ui.options = addon:GetOptions()
    for _, row in ipairs(ui:CollectRows("channels", "")) do
        if row.info[#row.info] == "label" and row.info[#row.info - 1] == "row_" .. token then return row end
    end
    error("label missing: " .. token)
end
local function control(token)
    local row = rowFor(token)
    local f = ui:CreateRow("input")
    ui:BindRow(f, row)
    return f
end
local function typeText(f, text)
    f.input:SetFocus()
    f.input:SetText(text)
    local changed = f.input:GetScript("OnTextChanged")
    if changed then changed(f.input, true) end
end

local guild = control("GUILD")
typeText(guild, "MyGuild")
guild.input:ClearFocus()
-- A UI update can occur between the edit box losing focus and the button click.
ui:BindRow(guild, rowFor("GUILD"))
guild.control:GetScript("OnClick")(guild.control)
check("Apply survives focus loss and redraw", addon.db.profile.channelLabels.GUILD == "MyGuild")

local general = control("GENERAL")
typeText(general, "#MyGeneral")
general.input:GetScript("OnEnterPressed")(general.input)
check("Enter stores numbered channel label", addon.db.profile.channelLabelsNamed.GENERAL == "#MyGeneral")

typeText(guild, "MyGuild2")
guild.input:ClearFocus()
check("valid label saves when leaving the field", addon.db.profile.channelLabels.GUILD == "MyGuild2")

typeText(guild, "ГільдіяДруїд")
guild.input:GetScript("OnEnterPressed")(guild.input)
check("12 Ukrainian characters are accepted", addon.db.profile.channelLabels.GUILD == "ГільдіяДруїд")
typeText(general, "#世界频道")
general.input:ClearFocus()
check("CJK numbered label accepted", addon.db.profile.channelLabelsNamed.GENERAL == "#世界频道")
check("number prefix renders", ns.ApplyChannelLabels("|Hchannel:CHANNEL:1|h[1. General - Elwynn Forest]|h hi"):find("[1. 世界频道]", 1, true))

typeText(guild, "1234567890123")
guild.input:ClearFocus()
ui:BindRow(guild, rowFor("GUILD"))
check("invalid label does not change saved value", addon.db.profile.channelLabels.GUILD == "ГільдіяДруїд")
check("invalid draft survives redraw for correction", guild.input:GetText() == "1234567890123")
typeText(guild, "Corrected")
guild.control:GetScript("OnClick")(guild.control)
check("corrected draft applies", addon.db.profile.channelLabels.GUILD == "Corrected")

typeText(guild, "Cancelled")
guild.input:GetScript("OnEscapePressed")(guild.input)
check("Escape cancels without saving", addon.db.profile.channelLabels.GUILD == "Corrected")
check("Escape restores the saved text", guild.input:GetText() == "Corrected")

-- A pooled frame can be rebound to a different option; drafts belong to paths.
typeText(guild, "TooLongDraftValue")
guild.input:ClearFocus()
ui:BindRow(guild, rowFor("GENERAL"))
check("draft does not leak into another channel", guild.input:GetText() == "#世界频道")
ui:BindRow(guild, rowFor("GUILD"))
check("pooled row recovers its own draft", guild.input:GetText() == "TooLongDraftValue")
guild.input:GetScript("OnEscapePressed")(guild.input)

-- Action inputs keep explicit submission; a redraw must not lose their draft or
-- invoke an add action a second time when focus is cleared.
local action
for _, row in ipairs(ui:CollectRows("channels", "")) do
    if row.info[#row.info] == "addChannel" then action = row end
end
local add = ui:CreateRow("input")
ui:BindRow(add, action)
typeText(add, "DraftChannel")
add.input:ClearFocus()
ui:BindRow(add, action)
check("action draft survives redraw", add.input:GetText() == "DraftChannel")
check("action is not submitted on blur", addon.db.profile.channelLabelNames.DRAFTCHANNEL == nil)
add.control:GetScript("OnClick")(add.control)
check("action submits on Apply", addon.db.profile.channelLabelNames.DRAFTCHANNEL == "DraftChannel")
ui:BindRow(add, action)
check("successful action clears draft", add.input:GetText() == "")

-- Clear restores the existing default, including the literal '#' convention.
ui:BindRow(general, rowFor("GENERAL"))
typeText(general, "#")
general.input:GetScript("OnEnterPressed")(general.input)
check("bare number prefix persists", addon.db.profile.channelLabelsNamed.GENERAL == "#")
check("bare number prefix renders", ns.ApplyChannelLabels("|Hchannel:CHANNEL:1|h[1. General - Elwynn Forest]|h hi"):find("[1]", 1, true))
typeText(general, "")
general.input:ClearFocus()
check("empty label clears override", addon.db.profile.channelLabelsNamed.GENERAL == nil)

-- Fresh schemas and profile switches must not inherit another profile's draft.
local saved = { channelModes = { GUILD = "custom" }, channelLabels = { GUILD = "Reloaded" },
    channelLabelsNamed = {}, channelLabelNames = {}, shortChannels = true }
local oldProfile = addon.db.profile
typeText(guild, "OldDraft")
addon.db.profile = saved
guild.input:ClearFocus()
check("old control cannot write after profile switch", saved.channelLabels.GUILD == "Reloaded" and oldProfile.channelLabels.GUILD == "Corrected")
ui:BindRow(guild, rowFor("GUILD"))
check("profile switch clears old draft", guild.input:GetText() == "Reloaded")
addon.db.profile = oldProfile
ui:BindRow(guild, rowFor("GUILD"))
typeText(guild, "FinalGuild")
ui.pools.input = ui.pools.input or {}
ui.pools.input[#ui.pools.input + 1] = guild
ui.window:Hide()
-- The frame stub does not dispatch OnHide automatically; deliver Blizzard's
-- event explicitly, as the native settings probe does for category panels.
ui.window:GetScript("OnHide")(ui.window)
check("closing window commits valid channel label", oldProfile.channelLabels.GUILD == "FinalGuild")
addon:OpenConfig("channels")
check("reopening reads saved label", rowFor("GUILD").option.get() == "FinalGuild")
check("built-in chat renders saved label", ns.ApplyChannelLabels("|Hchannel:GUILD|h[Guild]|h hi"):find("[FinalGuild]", 1, true))
local backup = assert(ns.ExportProfileText())
oldProfile.channelLabels.GUILD = "Changed"
check("profile backup imports", ns.ImportProfileText(backup))
check("applied label survives profile backup roundtrip", oldProfile.channelLabels.GUILD == "FinalGuild")
check("input handling has no swallowed errors", ui.lastError == nil)

print(string.format("channel label probe: PASS (%s / %s; %d checks)", client, view, checks))
