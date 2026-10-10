-- Exercise the native settings renderer, preserved handlers and client gates.
-- CHATIFY_SETTINGS_CLIENT=classic|retail|forever
-- CHATIFY_SETTINGS_API=modern|legacy|late
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local client = os.getenv("CHATIFY_SETTINGS_CLIENT") or "retail"
local api = os.getenv("CHATIFY_SETTINGS_API") or "modern"
env.install(client == "classic" and "classic" or "retail")
if client == "classic" then
    GetBuildInfo = function() return "1.15.8", "12345", "fixture", 11508 end
end
if client == "forever" then
    GetBuildInfo = function() return "1.60.1", "70124", "Sep 29 2026", 16001 end
end
UISpecialFrames = {}
local registrations = 0
local function installAPI()
    if api == "legacy" then
        InterfaceOptions_AddCategory = function() registrations = registrations + 1 end
    else
        Settings = {
            RegisterCanvasLayoutCategory = function(panel, name)
                assert(name == "Chatify" and panel.name == name)
                return { GetID = function() return 55 end }
            end,
            RegisterAddOnCategory = function() registrations = registrations + 1 end,
        }
    end
end
if api ~= "late" then installAPI() end
local ns = {}
local toc = client == "forever" and "Chatify_Camelot.toc" or "Chatify.toc"
for line in io.lines(toc) do
    if line:match("%.lua$") then assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns) end
end
local addon, ui = ns.Chatify, ns.SettingsWindow
addon:OnInitialize()
if api == "late" then
    installAPI()
    ns.SettingsIntegration.events:GetScript("OnEvent")()
end
local checks = 0
local function check(name, condition)
    checks = checks + 1
    assert(condition, "settings probe: " .. name)
end
check("correct client", ns.GetProjectKey() == (client == "classic" and "vanilla" or client))
check("exactly one category", registrations == 1)
ns.SettingsIntegration:Register()
check("registration is idempotent", registrations == 1)

-- Check the actual existing option objects rather than a duplicated key list.
local layout = ns.OptionsLayout
ns.OptionsLayout = nil
local original = addon:GetOptions()
ns.OptionsLayout = layout
local leaves, callbacks = {}, {}
local function collect(node, target)
    for _, child in pairs(node.args or {}) do
        if child.type == "group" then collect(child, target)
        elseif child.type ~= "header" and child.type ~= "description" then
            target[child] = true
        end
    end
end
collect(original, leaves)
for node in pairs(leaves) do callbacks[node] = { node.get, node.set, node.func } end
layout:Apply(original)
local retained = {}; collect(original, retained)
local count = 0
for node in pairs(leaves) do
    count = count + 1
    check("original setting retained", retained[node])
    local prev = callbacks[node]
    check("original handlers preserved", node.get == prev[1] and node.set == prev[2] and node.func == prev[3])
end
check("non-empty preservation check", count >= 150)
check("window created lazily", ui.window == nil)
addon:OpenConfig()
check("standalone opens", ui.window:IsShown() and ui.embeddedHost == nil)
check("escape registered once", #UISpecialFrames == 1)
local function rows(page, query)
    ui.options = addon:GetOptions()
    return ui:CollectRows(page, query or "")
end
local function find(page, key)
    for _, row in ipairs(rows(page)) do if row.info[#row.info] == key then return row end end
    error("setting not found: " .. page .. "." .. key)
end
for _, language in ipairs({ "enUS", "ukUA" }) do
    addon.db.profile.language = language
    ui:Rebuild(true)
    for _, page in ipairs(ui.pages) do
        ui:SelectPage(page.key)
        local all = rows(page.key)
        for _, row in ipairs(all) do
            check("supported widget", ({ toggle=true, range=true, select=true, input=true, execute=true, multiselect=true, header=true, description=true })[row.option.type])
            if row.option.get then ui:Evaluate(row.option, "get", row.info, nil, row.choice) end
            if row.option.values then ui:Evaluate(row.option, "values", row.info, {}) end
        end
        -- Exercise pooling and clipping at both ends of every section.
        ui.scroll:SetVerticalScroll(ui.scroll:GetVerticalScrollRange())
        ui:RenderVisible()
        ui.scroll:SetVerticalScroll(0)
    end
end
check("no callback errors", ui.lastError == nil)
addon.db.profile.language = "enUS"
ui.options = addon:GetOptions()
local results = rows("overview", "Repeated Messages")
check("search across all pages", #results >= 1 and results[1].info[1] == "filters")
check("search includes parent section", #rows("overview", "Player Names") >= 1)
addon.db.profile.language = "ukUA"
check("case insensitive Ukrainian search", #rows("overview", "ЧАСОВ") >= 1)
check("unmatched search", #rows("overview", "___no_settings_match___") == 0)

addon.db.profile.enableTimestamps = false
check("timestamp dependencies", find("appearance", "timestampID").disabled)
addon.db.profile.enableTimestamps = true
check("timestamp dependencies restored", not find("appearance", "timestampID").disabled)
local disabled = find("appearance", "timestampID")
addon.db.profile.enableTimestamps = false
local oldFormat = addon.db.profile.timestampID
ui:Apply(disabled, "HH:MM")
check("stale control respects current ancestor/option gates", addon.db.profile.timestampID == oldFormat)
check("whitelist bypass is reflected", find("filters", "scanGuild").disabled)
addon.db.profile.spamWhitelist.guild = false
check("guild scanning becomes editable", not find("filters", "scanGuild").disabled)
addon.db.profile.mentionRules = {}
check("empty rule list disables editor", find("mentions", "mentionColor").disabled)
local spam = find("filters", "addKeyword")
ui:Apply(spam, "  TEST-SETTINGS  ")
check("keyword input calls existing setter", addon.db.profile.spamKeywords[#addon.db.profile.spamKeywords] == "TEST-SETTINGS")
local filter = find("filters", "enableThrottle")
local before = addon.db.profile.enableThrottle
ui:Apply(filter, not before)
check("toggle persists", addon.db.profile.enableThrottle == not before)
local link = find("appearance", "urlColor")
local color = addon.db.profile.urlColor
ui:Apply(link, "bad")
check("invalid input rejected", addon.db.profile.urlColor == color)
ui:Apply(link, "#ABCDEF")
check("valid input applied", addon.db.profile.urlColor == "ABCDEF")

-- Drive the layout handlers on an API-capable fixture even when the protected
-- client intentionally hides manual tab setup in normal use.
local featureAvailable = ns.IsFeatureAvailable
ns.IsFeatureAvailable = function(feature)
    if feature == "chatTabs" then return true end
    return featureAvailable(feature)
end
local combat = false
InCombatLockdown = function() return combat end
combat = true
check("tab layout blocked in combat", find("windows", "btnSetup").disabled)
combat = false
check("tab layout restored after combat", not find("windows", "btnSetup").disabled)
local setupCalled = 0
addon.SetupDefaultTabs = function(self) check("string handler receives addon", self == addon); setupCalled = setupCalled + 1 end
local setup = find("windows", "btnSetup")
ui:Apply(setup)
check("confirmation defers action", setupCalled == 0 and ui.confirm:IsShown())
local commit = ui.confirm.callback
ui.confirm.callback = nil; ui.confirm:Hide(); commit()
check("confirmed string handler executed", setupCalled == 1)
ns.IsFeatureAvailable = featureAvailable

-- Numbered channel rows are rebuilt from current runtime membership.
GetChannelList = function() return 1, "General - Elwynn Forest", false, 7, "SettingsProbe", false end
if ns.InvalidateChannelListCache then ns.InvalidateChannelListCache() end
ui.options = addon:GetOptions()
local found = false
for _, row in ipairs(rows("channels")) do
    if table.concat(row.info, "."):find("SETTINGSPROBE", 1, true) then found = true end
end
check("joined channels refresh", found)
local selection = find("copy", "copyTabFrames")
check("multiselect expanded per frame", type(selection.choice) == "string" and selection.choice ~= "__none")
ui:Apply(selection, selection.choice, false)
check("multiselect writes selected frame", addon.db.profile.copyTabFrames[selection.choice] == false)
ui:SelectPage("appearance")
local choice = find("appearance", "fontID")
ui:ShowChoices(choice)
check("scrollable dropdown opens", ui.choices:IsShown())
ui:CloseChoices()
check("dropdown closes", not ui.choices:IsShown())
local f = ui:CreateRow("input")
link.height = 80
ui:BindRow(f, link)
ui.pools.input = ui.pools.input or {}; table.insert(ui.pools.input, f)
f.input:SetFocus()
check("editing delays refresh", ui.interacting)
ui:SelectPage("filters")
check("navigation releases input focus", not ui.interacting and not f.input:HasFocus())
local resolver, soundAPI = ns.ResolveSoundPath, PlaySoundFile
local heard
ns.ResolveSoundPath = function(name) return "probe/" .. name end
PlaySoundFile = function(path) heard = path end
local sound = find("sounds", "soundGuild")
addon.db.profile.sounds.enable = true
sound = find("sounds", "soundGuild")
addon.db.profile.sounds.events.GUILD = "Chatify Default"
ui:PreviewSound(sound)
check("selected sound can be previewed", heard == "probe/Chatify Default")
addon.db.profile.sounds.events.GUILD = "None"
heard = nil
ui:PreviewSound(sound)
check("None sound is silent", heard == nil)
ns.ResolveSoundPath, PlaySoundFile = resolver, soundAPI
local mouse
local fake = {
    GetTop = function() return 120 end, GetBottom = function() return 80 end,
    SetHitRectInsets = function(_, _, _, top, bottom) check("partial bounds clipped", top == 20 and bottom == 0) end,
    EnableMouse = function(_, enabled) mouse = enabled end,
    IsEnabled = function() return true end,
}
local scroll = { GetTop = function() return 100 end, GetBottom = function() return 0 end }
ui:ClipControl(fake, scroll, true)
check("partially visible control interactive", mouse)
fake.GetBottom = function() return 110 end
ui:ClipControl(fake, scroll, true)
check("fully offscreen control not interactive", not mouse)
local panel = ns.SettingsIntegration.panel
panel:GetScript("OnShow")(panel)
check("same window embeds in game settings", ui.embeddedHost == panel and ui.window:GetParent() == panel)
check("embedded layout", ui.window:GetWidth() == 790 and ui.inspector:GetHeight() == 171)
check("embedded escape released", #UISpecialFrames == 0)
panel:GetScript("OnHide")(panel)
check("embedded closes with category", not ui.window:IsShown())
addon:OpenConfig("composer")
check("composer shortcut selects correct page", ui.pageKey == "composer" and ui.embeddedHost == nil)
addon:OpenConfig("autoReply")
check("auto-reply shortcut selects correct page", ui.pageKey == "autoReply")
Chatify_ToggleOptionsWindow()
check("compartment toggles closed", not ui.window:IsShown())
Chatify_ToggleOptionsWindow()
check("compartment toggles open", ui.window:IsShown())
check("escape no duplicates", #UISpecialFrames == 1)
UIParent:SetSize(640, 480)
ui:FitScreen()
check("small screen scales to fit", ui.window:GetScale() < 1)
check("renderer has no swallowed errors", ui.lastError == nil)
print(string.format("settings probe: PASS (%s / %s; %d checks; %d original controls retained)", client, api, checks, count))
