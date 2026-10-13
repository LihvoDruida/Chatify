-- R2-01/R2-02/R2-03 real SettingsWindow scripts on the API fixture.
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
addon:OpenConfig()
local checks = 0
local function check(name, condition)
    checks = checks + 1
    assert(condition, 'R2 settings: ' .. name)
end
local function row(page, key)
    ui.options = addon:GetOptions()
    for _, r in ipairs(ui:CollectRows(page, '')) do
        if r.info[#r.info] == key then return r end
    end
    error('missing setting ' .. page .. '/' .. key)
end
local function typeIn(input, value)
    input:SetFocus()
    input:SetText(value)
    input:GetScript('OnTextChanged')(input, true)
end
local function editRow(kind, r)
    local f = ui:CreateRow(kind)
    ui:BindRow(f, r)
    return f
end
addon.db.profile.language = 'enUS'
ui:Rebuild(false)
addon.db.profile.lineSpacing = 0
local spacing = row('appearance', 'lineSpacing')
local f = editRow('range', spacing)
typeIn(f.number, '9')
check('numeric draft remembered', ui:InputDrafts()[ui:FieldKey(spacing)].value == '9')
check('numeric draft has unsaved indicator', ui.fieldErrors[ui:FieldKey(spacing)] == nil and f.feedback:IsShown())
f.number:ClearFocus()
check('number commits on blur', addon.db.profile.lineSpacing == 9)
check('number successful commit clears draft', ui:InputDrafts()[ui:FieldKey(spacing)] == nil)
typeIn(f.number, '3')
f.number:GetScript('OnEnterPressed')(f.number)
check('number commits on Enter', addon.db.profile.lineSpacing == 3)
typeIn(f.number, 'nan-not-a-number')
f.number:ClearFocus()
check('invalid numeric does not touch profile', addon.db.profile.lineSpacing == 3)
check('invalid numeric preserves draft and error', ui:InputDrafts()[ui:FieldKey(spacing)].value == 'nan-not-a-number' and ui.fieldErrors[ui:FieldKey(spacing)] ~= nil)
ui:BindRow(f, spacing)
check('invalid numeric survives redraw', f.number:GetText() == 'nan-not-a-number' and f.feedback:IsShown())
f.number:GetScript('OnEscapePressed')(f.number)
check('Escape reverts invalid number', f.number:GetText() == '3' and not ui:InputDrafts()[ui:FieldKey(spacing)])
typeIn(f.number, '999')
f.number:ClearFocus()
check('range is clamped', addon.db.profile.lineSpacing == 10)
typeIn(f.number, '2,5')
f.number:GetScript('OnEnterPressed')(f.number)
check('comma decimal is supported', addon.db.profile.lineSpacing == 3)

local color = row('appearance', 'urlColor')
local originalColor = addon.db.profile.urlColor
local inp = editRow('input', color)
typeIn(inp.input, 'invalid-color')
inp.input:GetScript('OnEnterPressed')(inp.input)
check('invalid text does not apply', addon.db.profile.urlColor == originalColor)
ui:BindRow(inp, color)
check('invalid input preserved and inline feedback shown', inp.input:GetText() == 'invalid-color' and inp.feedback:IsShown())
inp.input:GetScript('OnEscapePressed')(inp.input)
check('Escape reverts text without saving', inp.input:GetText() == originalColor and not ui.fieldErrors[ui:FieldKey(color)])
typeIn(inp.input, 'ABCDEF')
inp.input:GetScript('OnEnterPressed')(inp.input)
check('valid text applied', addon.db.profile.urlColor == 'ABCDEF')

-- The permissive AceDB stub does not implement ResetProfile. Model its effects
-- explicitly so this probe can prove callback ordering and cancellation.
local resets = 0
local aceReset = addon.db.ResetProfile
addon.db.ResetProfile = function(db) resets = resets + 1; db.profile.lineSpacing = 0; return aceReset(db) end
-- Default must be an explicit confirmation, with Cancel leaving the profile unchanged.
local panel = ns.SettingsIntegration.panel
addon.db.profile.lineSpacing = 7
check('Blizzard Defaults callback implemented', panel.OnDefault(panel) == true and ui.confirm:IsShown())
ui.confirm.callback = nil
ui.confirm:Hide()
check('canceled default keeps profile', addon.db.profile.lineSpacing == 7)
check('second Defaults requests confirmation again', panel.OnDefault(panel) == true and ui.confirm:IsShown())
local apply = ui.confirm.callback
ui.confirm.callback = nil
ui.confirm:Hide()
apply()
check('confirmed default resets profile', addon.db.profile.lineSpacing == 0 and resets == 1)
-- Explicit reset remains the same shared operation.
addon.db.profile.lineSpacing = 8
local reset = row('profiles', 'btnReset')
ui:Apply(reset)
check('standalone reset still prompts', ui.confirm:IsShown() and addon.db.profile.lineSpacing == 8)
local doReset = ui.confirm.callback
ui.confirm.callback = nil; ui.confirm:Hide(); doReset()
check('standalone reset and Blizzard default share reset', addon.db.profile.lineSpacing == 0 and resets == 2)

-- Unavailable features must be explainable without pretending an unsupported API exists.
local capability = row('availability', 'capabilities')
local explanation = ui:Evaluate(capability.option, 'name', capability.info, '')
check('feature availability uses the same capability model', explanation:find('Whisper Auto Reply', 1, true) ~= nil)
local support = ns.GetFeatureSupport('autoReplyWhisper')
if support == 'unavailable' then
    check('unavailable whisper gets a visible reason', explanation:find('Disabled to respect protected chat values.', 1, true)
        or explanation:find('Required client capability is unavailable.', 1, true))
end
local originalPost, originalWrapper = ns.HasSecurePostRenderAPI, ns.CanReplaceChatFrameAddMessage
ns.HasSecurePostRenderAPI = function() return true end
ns.CanReplaceChatFrameAddMessage = function() return false end
if ns.IsFeatureAvailable('securityControls') then
    local safety = row('maintenance', 'retailSafeStatus')
    check('post-render capability not labeled unavailable because AddMessage wrapper is off',
        tostring(ui:Evaluate(safety.option, 'name', safety.info, '')):find('post-render path available', 1, true) ~= nil)
end
ns.HasSecurePostRenderAPI, ns.CanReplaceChatFrameAddMessage = originalPost, originalWrapper
print(('R2 settings editor: PASS (%s/%s, %d checks)'):format(client, api, checks))
