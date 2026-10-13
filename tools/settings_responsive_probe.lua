-- R2-04/05/06: responsive geometry, inline colour validation, picker draft,
-- breadcrumb search, and keyboard focus. This tests layout contracts, not pixels.
package.path = 'tools/stub/?.lua;' .. package.path
local env = require('wow_env')
local fixtures = require('client_fixtures')
local client = os.getenv('CHATIFY_SETTINGS_CLIENT') or 'retail'
local api = os.getenv('CHATIFY_SETTINGS_API') or 'modern'
local fixture = fixtures.install(env, client)
UISpecialFrames = {}
if api == 'legacy' then
    InterfaceOptions_AddCategory = function() end
else
    Settings = {
        RegisterCanvasLayoutCategory = function() return {} end,
        RegisterAddOnCategory = function() end,
    }
end
local ns = {}
for line in io.lines(fixture[4]) do
    if line:match('%.lua$') then assert(loadfile((line:gsub('\\', '/'))))('Chatify', ns) end
end
local addon, ui = ns.Chatify, ns.SettingsWindow
addon:OnInitialize()
addon.db.profile.language = 'enUS'
UIParent:SetSize(1280, 900)
addon:OpenConfig()
local checks = 0
local function check(name, truth)
    checks = checks + 1
    assert(truth, 'R2 responsive/picker: ' .. name)
end
local function setting(page, name)
    ui.options = addon:GetOptions()
    for _, row in ipairs(ui:CollectRows(page, '')) do
        if row.info[#row.info] == name then return row end
    end
    error(page .. '/' .. name .. ' not found')
end
local function typeIn(f, value)
    f.input:SetFocus()
    f.input:SetText(value)
    f.input:GetScript('OnTextChanged')(f.input, true)
end
check('wide layout has inspector column', ui.window:GetWidth() == 1060
    and ui.inspector:GetWidth() == 266 and ui.window:GetScale() == 1)
UIParent:SetSize(940, 760)
ui:FitScreen()
check('narrow desktop compacts before scaling', ui.window:GetWidth() == 790
    and ui.window:GetScale() == 1 and ui.inspector:GetWidth() == 538)
check('inspector positioned under body', ui.inspector.__points == nil or ui.inspector:GetHeight() >= 140)
UIParent:SetSize(940, 550)
ui:FitScreen()
check('short display reduces viewport not typography', ui.window:GetHeight() == 526
    and ui.scroll:GetHeight() < 300 and ui.window:GetScale() == 1)
check('short layout retains scrollable inspector', ui.detailScroll:GetHeight() > 90)
UIParent:SetSize(640, 480)
ui:FitScreen()
check('extremely small displays still fit', ui.window:GetWidth() == 790 and ui.window:GetScale() < 1)
UIParent:SetSize(1280, 900)
ui:FitScreen()
check('geometry recovers after resize', ui.window:GetWidth() == 1060 and ui.window:GetScale() == 1)

addon.db.profile.urlColor = '0099FF'
local color = setting('appearance', 'urlColor')
local f = ui:CreateRow('input')
ui:BindRow(f, color)
check('colour field exposes swatch button', f.colorButton:IsShown() and f.colorSwatch.__kind == 'Texture')
typeIn(f, 'BAD')
check('invalid hex immediately shows feedback', ui.fieldErrors[ui:FieldKey(color)] ~= nil and f.feedback:IsShown())
check('incomplete colour never commits', addon.db.profile.urlColor == '0099FF')
typeIn(f, '#ABCDEF')
check('valid hex shows live swatch', ui.fieldErrors[ui:FieldKey(color)] == nil and f.colorButton:IsShown())
check('draft remains unsaved', addon.db.profile.urlColor == '0099FF')
local picker = {}
function picker:SetupColorPickerAndShow(info) self.info = info; self.rgb = {info.r, info.g, info.b} end
function picker:GetColorRGB() return unpack(self.rgb) end
ColorPickerFrame = picker
check('modern colour picker opens', ui:OpenColorPicker(f) == true and picker.info ~= nil)
picker.rgb = {1, 0, 0}
picker.info.swatchFunc()
check('picker changes draft not profile', f.input:GetText() == 'FF0000'
    and addon.db.profile.urlColor == '0099FF')
picker.info.cancelFunc()
check('picker Cancel restores previous unsaved draft', f.input:GetText() == '#ABCDEF'
    and ui:InputDrafts()[ui:FieldKey(color)].value == '#ABCDEF')
check('picker Cancel leaves SavedVariables intact', addon.db.profile.urlColor == '0099FF')
ColorPickerFrame = {
    SetColorRGB = function(self, r, g, b)
        self.rgb = {r, g, b}
        if self.func then self.func() end -- some legacy APIs call on initial colour
    end,
    GetColorRGB = function(self) return unpack(self.rgb) end,
    Show = function(self) self.shown = true end,
}
check('legacy picker API opens without auto-mutating draft', ui:OpenColorPicker(f)
    and f.input:GetText() == '#ABCDEF')
ColorPickerFrame.rgb = {0, 1, 0}
ColorPickerFrame.func()
check('legacy picker remains draft-only', f.input:GetText() == '00FF00'
    and addon.db.profile.urlColor == '0099FF')
ColorPickerFrame.cancelFunc()
check('legacy picker Cancel restores edit', f.input:GetText() == '#ABCDEF')
ColorPickerFrame = nil
check('missing picker API safely declines', ui:OpenColorPicker(f) == false)
f.input:GetScript('OnEnterPressed')(f.input)
check('Apply persists selected colour', addon.db.profile.urlColor == 'ABCDEF')
ui:BindRow(f, color)
check('successful Apply shows inline saved feedback', f.feedback:IsShown()
    and f.feedback:GetText() == ns.Locale:Get('UI_SAVED'))

addon.db.profile.mentionRules = { {text='tester',color='ffd700',enabled=true,sound='None'} }
local mention = setting('mentions', 'mentionColor')
local oldMentionColor = addon.db.profile.mentionRules[1].color
check('mention colours share strict hex validation', ui:Apply(mention, 'GGHHII') == false
    and addon.db.profile.mentionRules[1].color == oldMentionColor)
check('valid mention hex accepted', ui:Apply(mention, '#68ccef') == true
    and addon.db.profile.mentionRules[1].color == '68ccef')

ui.search:SetText('spacing')
ui.search:GetScript('OnTextChanged')(ui.search, true)
ui:Rebuild(true)
check('search includes section breadcrumbs', #ui.rows > 0 and ui.rows[1].displayName
    and ui.rows[1].displayName:find(' / ', 1, true))
ui.search:GetScript('OnArrowPressed')(ui.search, 'DOWN')
check('Down chooses a result without changing settings', (ui.searchIndex or 0) > 0
    and ui.pageTitle:GetText():find('/', 1, true))
local selected = ui.searchIndex
ui.search:GetScript('OnArrowPressed')(ui.search, 'LEFT')
check('Left/Right only edit query, do not move results', ui.searchIndex == selected)
ui.search:GetScript('OnTabPressed')(ui.search)
check('Tab targets an editable matching result', (ui.searchIndex or 0) > 0
    and ui.rows[ui.searchIndex].option.type == 'range')
ui.search:GetScript('OnEscapePressed')(ui.search)
check('Esc clears search', ui.search:GetText() == '')
addon.db.profile.language = 'ukUA'
ui.search:SetText('ЧАСОВ')
ui.search:GetScript('OnTextChanged')(ui.search, true)
ui:Rebuild(true)
check('Ukrainian uppercase search remains functional', #ui.rows > 0)
ui.measure:SetWidth(485)
ui.measure:SetText(string.rep('Довгий заголовок 測試 ', 16))
check('long UA/CJK text is measured for row wrapping', ui.measure:GetStringHeight() > 30)
ui.search:SetText('')
ui.search:GetScript('OnTextChanged')(ui.search, true)
ui:Rebuild(true)

ns.SettingsIntegration.panel:SetSize(800, 650)
ns.SettingsIntegration.panel:GetScript('OnShow')(ns.SettingsIntegration.panel)
check('embedded mode stays compact', ui.embeddedHost ~= nil and ui.window:GetWidth() == 790)
ns.SettingsIntegration.panel:SetSize(730, 550)
ui:FitScreen()
check('embedded mode fits host', ui.window:GetScale() < 1 and ui.window:GetHeight() == 550)

print(string.format('R2 responsive/editor: PASS (%s/%s; %d checks)',client,api,checks))
