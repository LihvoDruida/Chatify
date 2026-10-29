-- UI interaction and viewport regressions on real addon + shipped AceGUI Lua.
-- Frame anchors/fonts/XML regions are fixtures: this does not render game pixels.
package.path = 'tools/stub/?.lua;' .. package.path
local env = require('wow_env')
local fixtures = require('client_fixtures')
local client = os.getenv('CHATIFY_SETTINGS_CLIENT') or 'forever'
local fixture = fixtures.install(env, client)
local ace = require('acegui_env').install(env)
UISpecialFrames = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
if os.getenv('CHATIFY_SETTINGS_API') == 'legacy' then
    Settings = nil
    InterfaceOptions_AddCategory = function() end
end
local ns = {}
for line in io.lines(fixture[4]) do
    if line:match('%.lua$') then assert(loadfile((line:gsub('\\', '/'))))('Chatify', ns) end
end
local addon, ui = ns.Chatify, ns.SettingsWindow
addon:OnInitialize()
addon.db.profile.language = os.getenv('CHATIFY_UI_LANGUAGE') or 'enUS'
local checks = 0
local function check(name, condition)
    checks = checks + 1
    assert(condition, 'UI/UX: ' .. name)
end
local function fits(f)
    return f:GetWidth() * f:GetScale() <= UIParent:GetWidth() - 31
        and f:GetHeight() * f:GetScale() <= UIParent:GetHeight() - 31
end
local function row(page, key)
    ui.options = addon:GetOptions()
    for _, r in ipairs(ui:CollectRows(page, '')) do
        if r.info[#r.info] == key then return r end
    end
    error('setting missing: ' .. key)
end

-- Real AceGUI Frame/ScrollFrame/Flow and all real Composer controls.
UIParent:SetSize(1280, 720)
addon.db.profile.composer.enabled = true
local composer = addon:GetModule('Composer')
composer:OnEnable()
check('Composer opens', composer:Open({text = 'A retained draft', autoSplit = false}) == true)
local window = composer.window
local body = window.children[1]
check('Composer uses scrollable body', #window.children == 1 and body.type == 'ScrollFrame' and #body.children > 25)
check('720p retains text scale and fits', fits(window.frame) and window.frame:GetScale() == 1 and window.frame:GetHeight() == 688)
check('Flow computes scrollable content taller than viewport', body.content:GetHeight() > window.frame:GetHeight())
composer:OpenHelp()
check('help fits at native scale', fits(composer.helpWindow.frame) and composer.helpWindow.frame:GetScale() == 1)
UIParent:SetSize(520, 360)
env.fireEvent('DISPLAY_SIZE_CHANGED')
check('small Composer and help fit', fits(window.frame) and fits(composer.helpWindow.frame) and window.frame:GetScale() < 1)
check('resize retains draft', composer.inputWidget:GetText() == 'A retained draft')
UIParent:SetSize(1440, 1080)
env.fireEvent('UI_SCALE_CHANGED')
check('scale and preferred sizes recover', window.frame:GetScale() == 1 and window.frame:GetHeight() == 880)
check('existing Composer reopens and rebuilds', composer:Open({text = 'Reopened draft', autoSplit = true}) == true
    and #composer.sessionState.chunks > 0)
check('method wrapper preserves message argument', composer:RebuildPreview('Preview rebuilt') == true
    and type(composer.ui.status.label:GetText()) == 'string')
local old = window.frame
UIParent:SetSize(520, 360)
env.fireEvent('DISPLAY_SIZE_CHANGED')
composer:OnDisable()
check('released AceGUI frame scale restored', old:GetScale() == 1)
old:SetSize(777, 333)
if old:GetScript('OnShow') then old:GetScript('OnShow')(old) end
env.fireEvent('UI_SCALE_CHANGED')
check('released widget no longer fitted', old:GetWidth() == 777 and old:GetHeight() == 333)
local recycled = ace.gui:Create('Frame')
check('pool restores resize handles', recycled.sizer_se:IsShown() and recycled.frame:GetScale() == 1)
ace.gui:Release(recycled)
composer:OnEnable()
check('Composer reopens after disable', composer:Open({autoSplit = false}) == true and fits(composer.window.frame))
check('no swallowed AceGUI errors', #ace.errors == 0)
composer:OnDisable()

-- Copy text must be sized by wrapped font height, including long single lines.
UIParent:SetSize(1280, 720)
ChatFrame1.GetNumMessages = function() return 1 end
ChatFrame1.GetMessageInfo = function() return string.rep('довгий chat message ', 60) end
ns.OpenChatCopyWindow(ChatFrame1, 50)
local copy, text, scroll = ChatifyCopyFrame, ChatifyCopySelectableEditBox, ChatifyCopyPreviewScroll
check('Copy fits', fits(copy))
local wideHeight = text:GetHeight()
check('single wrapped line gets multiple rows', wideHeight > 100)
scroll:SetWidth(280) -- the frame fixture does not resolve native anchors
ns.WindowLayout:Fit(copy)
check('narrow copy remeasures wrapped text', text:GetHeight() > wideHeight)
ChatFrame1.GetMessageInfo = function() return 'https://example.invalid/' .. string.rep('abcdef', 200) end
ns.OpenChatCopyWindow(ChatFrame1, 50)
check('long unbroken URL retains scroll height', text:GetHeight() > 100)
UIParent:SetSize(520, 360)
env.fireEvent('DISPLAY_SIZE_CHANGED')
check('Copy fits small viewport', fits(copy) and copy:GetScale() < 1)
UIParent:SetSize(1280, 720)
env.fireEvent('UI_SCALE_CHANGED')
check('Copy restores native scale', copy:GetScale() == 1)
ns.OpenChatHistoryWindow(ChatFrame1, 50)
local search = ChatifyHistorySearchBox
check('History search anchors to window rather than translated label', search.testPoints[1][2] == copy
    and search.testPoints[2][2] == copy and search.testPoints[1][5] == -103)
search:SetFocus()
env.runPendingTimers(0)
check('deferred Copy focus preserves History search', search:HasFocus() and not text:HasFocus())
search:ClearFocus()

-- Disabled settings keep hover help while their controls cannot mutate state.
ui:Open()
local spacing = row('appearance', 'lineSpacing')
spacing.disabled = true
local f = ui:CreateRow('range')
ui:BindRow(f, spacing)
ui:ClipControl(f, ui.scroll, true)
f:GetScript('OnEnter')(f)
check('disabled row remains hoverable', f.__mouse == true and not f.slider:IsEnabled())
check('disabled row exposes explanation', ui.detailText:GetText():find(ns.Locale:Get('UI_DISABLED'), 1, true) ~= nil)
spacing.disabled = false
ui:BindRow(f, spacing)
ui.pools.range = ui.pools.range or {}
table.insert(ui.pools.range, f)
addon.db.profile.lineSpacing = 0
f.number:SetFocus(); f.number:SetText('2')
f.number:GetScript('OnTextChanged')(f.number, true)
-- Deliver OnHide as the real client does, including edit-focus loss ordering.
local hide = ui.window.Hide
ui.window.Hide = function(w)
    local shown = w:IsShown(); hide(w)
    if shown then w:GetScript('OnHide')(w) end
end
local host = CreateFrame('Frame', nil, UIParent)
host:SetSize(800, 650); host:SetFrameLevel(100)
ui:OpenEmbedded(host)
local draft = ui:InputDrafts()[ui:FieldKey(spacing)]
check('rehosting preserves numeric draft without saving', draft and draft.value == '2' and addon.db.profile.lineSpacing == 0)
ui:Open()
check('standalone preserves draft too', ui:InputDrafts()[ui:FieldKey(spacing)].value == '2')
ui:Confirm('Test confirmation', function() end)
check('confirmation follows current host frame level', ui.confirm:GetFrameLevel() == ui.window:GetFrameLevel() + 40)
check('confirmation text fits panel', ui.confirm.panel:GetHeight() >= ui.confirm.text:GetStringHeight() + 100)
ui.confirm.callback = nil; ui.confirm:Hide()

-- A delayed confirmation must re-check the current schema and active profile.
local originalOptions = ui.options
local allowed, calls = true, 0
local option = {type = 'execute', confirm = true, disabled = function() return not allowed end,
    func = function() calls = calls + 1 end}
local action = {name = 'Action', option = option, info = {'action'}}
ui.options = {args = {action = option}}
ui:Apply(action)
local confirm = ui.confirm.callback
allowed = false
check('confirmation rechecks runtime restriction', confirm() == false and calls == 0)
allowed = true
ui:Apply(action)
confirm = ui.confirm.callback
local profile = addon.db.profile
addon.db.profile = {}
check('confirmation rejects different profile', confirm() == false and calls == 0)
addon.db.profile = profile
ui:Apply(action)
check('unchanged confirmation applies once', ui.confirm.callback() == true and calls == 1)
ui.options = originalOptions
local resets = 0
addon.ResetChatifyProfile = function() resets = resets + 1 end
ui:ConfirmProfileReset()
confirm = ui.confirm.callback
addon.db.profile = {}
confirm()
check('profile reset confirmation cannot reset a switched profile', resets == 0)
addon.db.profile = profile
ui:OpenEmbedded(host)
ui:Confirm('Embedded', function() end)
check('embedded confirmation level refreshed', ui.confirm:GetFrameLevel() == 141)
ui.confirm.callback = nil; ui.confirm:Hide()
ui.window:Hide()
check('real close clears drafts', next(ui.inputDrafts) == nil)

-- Navigation remains available when channel routing is unavailable or late.
local feature = ns.IsFeatureAvailable
local route = false
ns.IsFeatureAvailable = function(name) if name == 'quickButtons' then return route end return feature(name) end
local quick = addon:GetModule('QuickButtons')
local registrations = 0
quick.RegisterEvent = function() registrations = registrations + 1 end
quick:OnEnable()
ns.RefreshQuickChatButtons()
check('no routing still registers lifecycle listeners', registrations > 0)
check('no routing keeps Settings/Copy/History sidebar', ChatifyChatMenuSettingsContainer:IsShown()
    and ChatifyChatMenuSettingsButton:IsShown() and ChatifyChatMenuCopyButton:IsShown() and ChatifyChatMenuHistoryButton:IsShown())
check('unavailable routing hides channel strip', not ChatifyQuickChatButtons:IsShown())
route = true
ns.RefreshQuickChatButtons()
check('late routing enables channel strip', ChatifyQuickChatButtons:IsShown())
ns.IsFeatureAvailable = feature
check('no event-handler errors', not env.eventErrors or #env.eventErrors == 0)
check('no AceGUI safecall failures', #ace.errors == 0)
print(string.format('UI/UX: PASS (%s; %d viewport/interaction/pool regressions, real AceGUI Lua; no pixel/taint certification)', client .. '/' .. addon.db.profile.language, checks))
