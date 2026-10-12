-- Native, lazy-created settings window. Uses basic frame APIs shared by the
-- current Retail, Classic and Forever clients; no AceGUI/SettingsPanel internals.
local addonName, ns = ...
local UI = {}
ns.SettingsWindow = UI
local Compat = {
    IsSecret = function(value)
        return type(ns.HasSecretChatValue) == "function" and ns.HasSecretChatValue(value) or false
    end,
    GetAddonVersion = function()
        return type(ns.GetAddonMetadata) == "function" and ns.GetAddonMetadata(addonName, "Version") or "2.18.3"
    end,
}
local unpack = unpack or table.unpack
local floor, min, max = math.floor, math.min, math.max
local GOLD = { 0.86, 0.69, 0.40 }
local TEXT = { 0.88, 0.83, 0.72 }
local BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local L = setmetatable({}, { __index = function(_, key) return ns.Locale:Get(key) end })

local function frame(kind, name, parent)
    return CreateFrame(kind or "Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end
local function backdrop(f, color)
    if type(f.SetBackdrop) ~= "function" then
        local texture = f:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        if type(texture.SetColorTexture) == "function" then
            texture:SetColorTexture(unpack(color or { 0.07, 0.055, 0.045, 0.98 }))
        else
            texture:SetTexture("Interface\\Buttons\\WHITE8x8")
            texture:SetVertexColor(unpack(color or { 0.07, 0.055, 0.045, 0.98 }))
        end
        return
    end
    f:SetBackdrop({ bgFile = BG, edgeFile = EDGE, tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(unpack(color or { 0.07, 0.055, 0.045, 0.98 }))
    f:SetBackdropBorderColor(0.43, 0.34, 0.20, 1)
end
local function label(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- SetFont(file) discards the FontFamily alphabet fallbacks. Keep the
    -- inherited game font object so Cyrillic and Chinese work on English clients.
    if type(fs.SetFontHeight) == "function" then
        fs:SetFontHeight(size or 13)
    else
        fs:SetFontObject((size or 13) >= 16 and "GameFontNormalLarge" or
            ((size or 13) <= 12 and "GameFontNormalSmall" or "GameFontNormal"))
    end
    fs:SetTextColor(unpack(color or TEXT))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end
local function button(parent, text, width, height)
    local b = frame("Button", nil, parent)
    b:SetSize(width or 160, height or 28)
    backdrop(b, { 0.12, 0.10, 0.075, 1 })
    b.text = label(b, text)
    b.text:SetPoint("LEFT", 10, 0)
    b.text:SetPoint("RIGHT", -10, 0)
    b.text:SetJustifyH("CENTER")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return b
end
local function edit(parent, width)
    local e = frame("EditBox", nil, parent)
    e:SetSize(width, 28)
    backdrop(e, { 0.025, 0.02, 0.015, 1 })
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(9, 9, 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(0)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end
local function clean(text)
    return tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
local upper = { "А", "Б", "В", "Г", "Ґ", "Д", "Е", "Є", "Ж", "З", "И", "І", "Ї", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ь", "Ю", "Я" }
local lower = { "а", "б", "в", "г", "ґ", "д", "е", "є", "ж", "з", "и", "і", "ї", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ь", "ю", "я" }
local function fold(text)
    text = clean(text):lower()
    for i, value in ipairs(upper) do text = text:gsub(value, lower[i]) end
    return text
end

-- Every callback receives the option path just like the previous schema did.
-- A failed availability test hides/disables its setting rather than displaying
-- a clickable control that is unsupported on this client.
function UI:Evaluate(option, field, info, fallback, ...)
    local value = option[field]
    if type(value) ~= "function" then
        if value == nil then return fallback end
        return value
    end
    local ok, result = pcall(value, info, ...)
    if not ok or Compat.IsSecret(result) then
        if not ok then self.lastError = tostring(result) end
        if field == "hidden" or field == "disabled" then return true end
        return fallback
    end
    if result == nil then return fallback end
    return result
end

local function ordered(args)
    local result = {}
    for key, option in pairs(args or {}) do
        result[#result + 1] = { key = key, option = option }
    end
    table.sort(result, function(a, b)
        local x, y = tonumber(a.option.order) or 100, tonumber(b.option.order) or 100
        return x == y and tostring(a.key) < tostring(b.key) or x < y
    end)
    return result
end

function UI:GetPages()
    local root = self.options
    local pages = { { key = "overview", name = L.UI_OVERVIEW, option = root } }
    for _, item in ipairs(ordered(root.args)) do
        local o = item.option
        if o.type == "group" and not o.inline and not self:Evaluate(o, "hidden", { item.key }, false) then
            pages[#pages + 1] = { key = item.key, name = self:Evaluate(o, "name", { item.key }, ""), option = o }
        end
    end
    return pages
end

function UI:CollectRows(pageKey, query)
    local rows, root = {}, self.options
    query = fold(query)
    local searching = query ~= ""
    local function walk(group, path, inheritedDisabled, trail)
        for _, item in ipairs(ordered(group.args)) do
            local o, info = item.option, {}
            for i, key in ipairs(path) do info[i] = key end
            info[#info + 1] = item.key
            info.option, info.handler, info.arg = o, root.handler, o.arg
            if not UI:Evaluate(o, "hidden", info, false) then
                local disabled = inheritedDisabled or UI:Evaluate(o, "disabled", info, false)
                local name = UI:Evaluate(o, "name", info, "")
                local desc = UI:Evaluate(o, "desc", info, "")
                if o.type == "group" then
                    if searching or o.inline or pageKey == item.key then
                        local nextTrail = trail and (trail .. " / " .. clean(name)) or clean(name)
                        if not searching and clean(name):match("%S") then
                            rows[#rows + 1] = { option = { type = "header", name = name }, info = info, name = name, desc = desc, trail = trail }
                        end
                        walk(o, info, disabled, nextTrail)
                    end
                else
                    local match = not searching or fold(name .. " " .. desc .. " " .. (trail or "")):find(query, 1, true)
                    if (match or o.type == "multiselect") and name ~= "" then
                        if o.type == "multiselect" then
                            for _, choice in ipairs(ordered(UI:ChoiceOptions(o, info))) do
                                if match or fold(choice.option.name):find(query, 1, true) then
                                    rows[#rows + 1] = { option = o, info = info, name = choice.option.name,
                                        desc = desc, choice = choice.key, disabled = disabled, trail = trail }
                                end
                            end
                        elseif o.type ~= "header" or not searching then
                            rows[#rows + 1] = { option = o, info = info, name = name,
                                desc = desc, disabled = disabled, trail = trail }
                        end
                    end
                end
            end
        end
    end
    if searching or pageKey == "overview" then
        walk(root, {}, false, nil)
    else
        local group = root.args[pageKey]
        if group and not self:Evaluate(group, "hidden", { pageKey }, false) then
            walk(group, { pageKey }, self:Evaluate(group, "disabled", { pageKey }, false), self:Evaluate(group, "name", { pageKey }, ""))
        end
    end
    return rows
end

function UI:ChoiceOptions(option, info)
    local choices, result = self:Evaluate(option, "values", info, {}), {}
    for key, value in pairs(choices) do result[key] = { name = value } end
    return result
end

function UI:ClearInputFocus()
    for _, pool in pairs(self.pools or {}) do
        for _, row in ipairs(pool) do
            if row.number then row.number:ClearFocus() end
            if row.input then row.input:ClearFocus() end
        end
    end
    self.interacting = false
end

function UI:RequestRefresh()
    self.dirty = true
end

function UI:InputKey(row)
    return table.concat(row.info, "\031")
end

function UI:InputDrafts()
    local profile = ns.Chatify.db and ns.Chatify.db.profile
    if self.inputDraftProfile ~= profile then
        self.inputDraftProfile, self.inputDrafts = profile, {}
    end
    self.inputDrafts = self.inputDrafts or {}
    return self.inputDrafts
end

function UI:CommitInput(f, onlyChanged)
    -- A profile may be switched while an old control still owns keyboard focus.
    if f.inputProfile ~= (ns.Chatify.db and ns.Chatify.db.profile) then return false end
    local draft = self:InputDrafts()[self:InputKey(f.row)]
    if onlyChanged and not draft then return false end
    return self:Apply(f.row, draft and draft.value or f.input:GetText())
end

function UI:ShowDetails(row)
    if not self.window then return end
    self.detailTitle:SetText(row and clean(row.name) or L.UI_HELP_TITLE)
    local text = row and row.desc or L.UI_HELP_DESC
    if text == "" then text = L.UI_HELP_DESC end
    if row and row.disabled then text = text .. "\n\n|cffcda86c" .. L.UI_DISABLED .. "|r" end
    if row and row.trail then text = text .. "\n\n|cff9b8769" .. clean(row.trail) .. "|r" end
    self.detailText:SetText(text ~= "" and text or L.UI_HELP_DESC)
    self.detailChild:SetHeight(max(200, self.detailText:GetStringHeight() + self.detailTitle:GetStringHeight() + 25))
    self.detailScroll:SetVerticalScroll(0)
end

function UI:IsRowUnavailable(row)
    local node, path = self.options, {}
    for _, key in ipairs(row.info) do
        node = node.args and node.args[key]
        if not node then return true end
        path[#path + 1] = key
        if self:Evaluate(node, "hidden", path, false) or self:Evaluate(node, "disabled", path, false) then return true end
    end
    return false
end

function UI:Apply(row, ...)
    if self:IsRowUnavailable(row) then return false end
    if row.disabled or self:Evaluate(row.option, "disabled", row.info, false) then return false end
    local values = { ... }
    local handler = row.option.type == "execute" and row.option.func or row.option.set
    if type(handler) == "string" then
        local owner = self.options.handler
        local method = owner and owner[handler]
        if type(method) == "function" then
            handler = function(info, ...) return method(owner, info, ...) end
        end
    end
    if type(handler) ~= "function" then return false end
    if type(row.option.validate) == "function" then
        local ok, valid = pcall(row.option.validate, row.info, unpack(values))
        if not ok or valid ~= true then
            self:ShowDetails({ name = row.name, desc = type(valid) == "string" and valid or L.UI_INVALID })
            return false
        end
    end
    local function commit()
        local ok, err = pcall(handler, row.info, unpack(values))
        if not ok then
            UI.lastError = tostring(err)
            print("|cffff6060Chatify:|r " .. tostring(err))
            return false
        end
        if row.option.type == "input" then UI:InputDrafts()[UI:InputKey(row)] = nil end
        -- Rebuild the live schema after list edits, profile import or reset.
        UI:RequestRefresh()
        return true
    end
    if self:Evaluate(row.option, "confirm", row.info, false) then
        local text = self:Evaluate(row.option, "confirmText", row.info, row.name)
        if row.option.type == "select" then
            local choices = self:Evaluate(row.option, "values", row.info, {})
            if choices[values[1]] then text = text .. "\n" .. clean(choices[values[1]]) end
        end
        self:Confirm(text, commit)
    else
        return commit()
    end
end

function UI:Confirm(text, callback)
    self:ClearInputFocus()
    self:CloseChoices()
    if not self.confirm then
        local overlay = frame("Frame", nil, self.window)
        overlay:SetAllPoints()
        overlay:SetFrameLevel(self.window:GetFrameLevel() + 40)
        overlay:EnableMouse(true)
        local tint = overlay:CreateTexture(nil, "BACKGROUND")
        tint:SetAllPoints(); tint:SetColorTexture(0, 0, 0, 0.75)
        local panel = frame("Frame", nil, overlay)
        panel:SetSize(430, 155); panel:SetPoint("CENTER"); backdrop(panel)
        overlay.text = label(panel, "", 15, GOLD)
        overlay.text:SetPoint("TOPLEFT", 24, -23); overlay.text:SetWidth(382)
        local yes = button(panel, L.UI_CONFIRM, 180)
        yes:SetPoint("BOTTOMLEFT", 23, 22)
        yes:SetScript("OnClick", function() local fn = overlay.callback; overlay.callback = nil; overlay:Hide(); if fn then fn() end end)
        local no = button(panel, L.UI_CANCEL, 180)
        no:SetPoint("BOTTOMRIGHT", -23, 22)
        no:SetScript("OnClick", function() overlay.callback = nil; overlay:Hide() end)
        self.confirm = overlay
    end
    self.confirm.text:SetText(clean(text) .. "\n\n" .. L.UI_CONFIRM_DESC)
    self.confirm.callback = callback
    self.confirm:Show()
end

function UI:CloseChoices()
    if self.choices then self.choices:Hide() end
end

function UI:PreviewSound(row)
    if self:IsRowUnavailable(row) then return end
    local name = self:Evaluate(row.option, "get", row.info, nil)
    if type(name) ~= "string" or name == "None" then return end
    local path = type(ns.ResolveSoundPath) == "function" and ns.ResolveSoundPath(name)
    if path and type(PlaySoundFile) == "function" then
        local master = ns.Chatify.db.profile.sounds and ns.Chatify.db.profile.sounds.masterVolume
        pcall(PlaySoundFile, path, master and "Master" or "SFX")
    end
end

function UI:ShowChoices(row, anchor)
    self:ClearInputFocus()
    if self.choices and self.choices:IsShown() and self.choices.row == row then self:CloseChoices(); return end
    if not self.choices then
        local popup = frame("Frame", nil, self.window)
        popup:SetSize(250, 320); backdrop(popup)
        popup:SetFrameLevel(self.window:GetFrameLevel() + 30)
        popup:EnableMouse(true)
        local close = button(popup, "X", 25, 25); close:SetPoint("TOPRIGHT", -7, -7)
        close:SetScript("OnClick", function() self:CloseChoices() end)
        popup.title = label(popup, L.UI_SELECT, 14, GOLD)
        popup.title:SetPoint("TOPLEFT", 13, -14); popup.title:SetWidth(196)
        popup.scroll = CreateFrame("ScrollFrame", nil, popup)
        popup.scroll:SetPoint("TOPLEFT", 10, -45); popup.scroll:SetPoint("BOTTOMRIGHT", -10, 12)
        popup.child = CreateFrame("Frame", nil, popup.scroll)
        popup.child:SetWidth(230); popup.scroll:SetScrollChild(popup.child)
        popup.buttons = {}
        popup.scroll:SetScript("OnVerticalScroll", function()
            for _, b in ipairs(popup.buttons) do if b:IsShown() then UI:ClipControl(b, popup.scroll, true) end end
        end)
        popup.scroll:EnableMouseWheel(true)
        popup.scroll:SetScript("OnMouseWheel", function(f, delta)
            f:SetVerticalScroll(max(0, min(f:GetVerticalScrollRange(), f:GetVerticalScroll() - delta * 48)))
        end)
        self.choices = popup
    end
    local popup = self.choices
    popup.row = row
    popup:ClearAllPoints()
    -- Fixed in the inspector column: even a bottom-of-list control cannot put
    -- the choices below the screen, and the current control stays visible.
    popup:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", -16, -52)
    local values = self:Evaluate(row.option, "values", row.info, {})
    local keys, used, remainder = {}, {}, {}
    local sorting = self:Evaluate(row.option, "sorting", row.info, {})
    if type(sorting) == "table" then
        for _, key in ipairs(sorting) do
            if values[key] ~= nil and not used[key] then keys[#keys + 1] = key; used[key] = true end
        end
    end
    for key in pairs(values) do if not used[key] then remainder[#remainder + 1] = key end end
    table.sort(remainder, function(a, b)
        local x, y = fold(values[a]), fold(values[b])
        return x == y and tostring(a) < tostring(b) or x < y
    end)
    for _, key in ipairs(remainder) do keys[#keys + 1] = key end
    local choiceY = 0
    for i, key in ipairs(keys) do
        local selectedKey = key
        local b = popup.buttons[i]
        if not b then b = button(popup.child, "", 230, 29); popup.buttons[i] = b end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -choiceY)
        b.choiceKey = selectedKey
        b.text:SetText(values[selectedKey]); b.text:SetJustifyH("LEFT")
        self.choiceMeasure:SetText(values[selectedKey])
        local height = max(29, self.choiceMeasure:GetStringHeight() + 12)
        b:SetHeight(height); choiceY = choiceY + height + 2
        b:SetScript("OnClick", function() self:CloseChoices(); self:Apply(row, selectedKey) end)
        b:Show()
    end
    for i = #keys + 1, #popup.buttons do popup.buttons[i]:Hide() end
    popup.child:SetHeight(max(1, choiceY)); popup.scroll:SetVerticalScroll(0)
    popup:Show()
    for _, b in ipairs(popup.buttons) do if b:IsShown() then self:ClipControl(b, popup.scroll, true) end end
end

function UI:CreateRow(kind)
    local f = frame("Frame", nil, self.content)
    f.kind = kind
    f:EnableMouse(false)
    f.title = label(f, "", 13)
    f.title:SetPoint("TOPLEFT", 12, -11)
    f.title:SetWidth(485)
    f.title:SetJustifyV("TOP")
    if kind == "toggle" or kind == "multiselect" then
        local check = CreateFrame("CheckButton", nil, f)
        check:SetSize(25, 25); check:SetPoint("LEFT", 10, 0)
        check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        f.title:ClearAllPoints(); f.title:SetPoint("LEFT", 43, 0); f.title:SetWidth(451)
        f.check = check
        local function apply()
            local row = f.row
            local checked = not UI:Evaluate(row.option, "get", row.info, false, row.choice)
            if row.choice then UI:Apply(row, row.choice, checked) else UI:Apply(row, checked) end
        end
        check:SetScript("OnClick", apply)
        check:SetScript("OnEnter", function() UI:ShowDetails(f.row) end)
    elseif kind == "range" then
        local slider = frame("Slider", nil, f)
        slider:SetOrientation("HORIZONTAL"); slider:SetSize(376, 18)
        slider:SetPoint("BOTTOMLEFT", 13, 13)
        backdrop(slider, { 0.015, 0.012, 0.01, 1 })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetObeyStepOnDrag(true)
        slider.low = label(f, "", 10, GOLD); slider.low:SetPoint("BOTTOMLEFT", 14, 0)
        slider.high = label(f, "", 10, GOLD); slider.high:SetPoint("BOTTOMRIGHT", -130, 0)
        local number = edit(f, 91); number:SetPoint("BOTTOMRIGHT", -14, 9)
        number:SetScript("OnEditFocusGained", function() UI.interacting = true end)
        number:SetScript("OnEditFocusLost", function() UI.interacting = false; UI:RequestRefresh() end)
        f.slider, f.number = slider, number
        local function normal(value)
            local o = f.row.option
            local step = o.step or 1
            value = min(o.max, max(o.min, value))
            return min(o.max, max(o.min, o.min + floor((value - o.min) / step + 0.5) * step))
        end
        local function commit(value)
            if f.row.disabled then return end
            UI:Apply(f.row, normal(value))
        end
        slider:SetScript("OnValueChanged", function(_, value)
            if f.syncing then return end
            f.pendingValue = normal(value)
            number:SetText(string.format("%g", f.pendingValue))
        end)
        slider:SetScript("OnMouseDown", function() UI.interacting = true end)
        slider:SetScript("OnMouseUp", function()
            UI.interacting = false
            if f.pendingValue then commit(f.pendingValue); f.pendingValue = nil end
            UI:RequestRefresh()
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(_, delta) commit(slider:GetValue() + delta * (f.row.option.step or 1)) end)
        slider:SetScript("OnEnter", function() UI:ShowDetails(f.row) end)
        number:SetScript("OnEnterPressed", function(self)
            local value = tonumber((self:GetText() or ""):gsub(",", "."))
            self:ClearFocus()
            if value and value == value and value ~= math.huge and value ~= -math.huge then commit(value) end
            UI:RequestRefresh()
        end)
    elseif kind == "select" then
        f.control = button(f, "", 483, 29); f.control:SetPoint("BOTTOMLEFT", 12, 6)
        f.control.text:SetJustifyH("LEFT")
        f.control.text:ClearAllPoints()
        f.control.text:SetPoint("LEFT", 10, 0); f.control.text:SetPoint("RIGHT", -32, 0)
        local arrow = f.control:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(20, 20); arrow:SetPoint("RIGHT", -6, 0)
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        f.control:SetScript("OnClick", function(self) UI:ShowDetails(f.row); UI:ShowChoices(f.row, self) end)
        f.control:SetScript("OnEnter", function() UI:ShowDetails(f.row) end)
        f.soundPreview = button(f, L.UI_PREVIEW, 112, 29)
        f.soundPreview:SetPoint("BOTTOMRIGHT", -12, 6)
        f.soundPreview:SetScript("OnClick", function() UI:PreviewSound(f.row) end)
        f.soundPreview:SetScript("OnEnter", function() UI:ShowDetails(f.row) end)
    elseif kind == "input" then
        f.input = edit(f, 362); f.input:SetPoint("BOTTOMLEFT", 12, 6)
        f.input:SetScript("OnEditFocusGained", function() UI.interacting = true end)
        f.input:SetScript("OnTextChanged", function(self, userInput)
            if not userInput or f.syncing or not f.row then return end
            UI:InputDrafts()[UI:InputKey(f.row)] = { value = self:GetText() }
        end)
        f.input:SetScript("OnEditFocusLost", function()
            if not f.syncing and not f.canceling and f.row and f.row.option.chatifyCommitOnFocusLost then
                UI:CommitInput(f, true)
            end
            UI.interacting = false
            UI:RequestRefresh()
        end)
        f.input:SetScript("OnEscapePressed", function(self)
            f.canceling = true
            UI:InputDrafts()[UI:InputKey(f.row)] = nil
            f.syncing = true
            self:SetText(UI:Evaluate(f.row.option, "get", f.row.info, ""))
            f.syncing = false
            self:ClearFocus()
            f.canceling = false
            UI:RequestRefresh()
        end)
        f.control = button(f, L.UI_APPLY, 112, 28); f.control:SetPoint("BOTTOMRIGHT", -12, 6)
        local function commit() UI:CommitInput(f); f.input:ClearFocus() end
        f.control:SetScript("OnClick", commit); f.input:SetScript("OnEnterPressed", commit)
    elseif kind == "execute" then
        f.control = button(f, "", 483, 30); f.control:SetPoint("LEFT", 12, 0)
        f.control:SetScript("OnClick", function() UI:ShowDetails(f.row); UI:Apply(f.row) end)
        f.control:SetScript("OnEnter", function() UI:ShowDetails(f.row) end)
        f.title:Hide()
    elseif kind == "header" then
        f.title:SetTextColor(unpack(GOLD))
        local line = f:CreateTexture(nil, "BACKGROUND")
        line:SetHeight(1); line:SetPoint("BOTTOMLEFT", 12, 3); line:SetPoint("BOTTOMRIGHT", -12, 3)
        line:SetColorTexture(0.46, 0.34, 0.17, 0.65)
    end
    return f
end

function UI:BindRow(f, row)
    f.row, f.syncing, f.pendingValue = row, true, nil
    f.title:SetText(row.name)
    f:SetAlpha(row.disabled and 0.45 or 1)
    f:EnableMouse(false)
    local o = row.option
    if f.check then
        f.check:SetChecked(self:Evaluate(o, "get", row.info, false, row.choice))
        f.check:SetEnabled(not row.disabled)
    elseif f.slider then
        f.slider:SetMinMaxValues(o.min, o.max)
        f.slider:SetValueStep(o.step or 1)
        local value = self:Evaluate(o, "get", row.info, o.min)
        value = tonumber(value) or o.min
        f.slider:SetValue(value); f.slider:SetEnabled(not row.disabled)
        f.number:SetText(string.format("%g", value)); f.number:EnableMouse(not row.disabled)
        f.number:SetEnabled(not row.disabled)
        f.slider.low:SetText(string.format("%g", o.min)); f.slider.high:SetText(string.format("%g", o.max))
    elseif o.type == "select" then
        local values = self:Evaluate(o, "values", row.info, {})
        local selected = self:Evaluate(o, "get", row.info, nil)
        f.control.text:SetText(values[selected] or L.UI_SELECT)
        f.control:SetHeight(row.controlHeight or 29)
        f.control:SetWidth(o.chatifySound and 363 or 483)
        f.soundPreview:SetShown(o.chatifySound == true)
        f.soundPreview:SetHeight(row.controlHeight or 29)
        f.soundPreview:SetEnabled(not row.disabled and selected ~= nil and selected ~= "None")
        f.control:SetEnabled(not row.disabled and next(values) ~= nil)
    elseif o.type == "input" then
        local draft = self:InputDrafts()[self:InputKey(row)]
        f.inputProfile = ns.Chatify.db and ns.Chatify.db.profile
        f.input:SetText(draft and draft.value or self:Evaluate(o, "get", row.info, ""))
        f.input:SetEnabled(not row.disabled); f.control:SetEnabled(not row.disabled)
    elseif o.type == "execute" then
        f.control:SetHeight(max(30, row.height - 12))
        f.control.text:SetText(row.name); f.control:SetEnabled(not row.disabled)
    end
    f.syncing = false
end

-- ScrollFrame rendering clips its child, but input bounds must also be clipped.
function UI:ClipControl(control, scroll, enabled)
    if not control then return end
    local top, bottom = control:GetTop(), control:GetBottom()
    local viewTop, viewBottom = scroll:GetTop(), scroll:GetBottom()
    if top and bottom and viewTop and viewBottom then
        control:SetHitRectInsets(0, 0, max(0, top - viewTop), max(0, viewBottom - bottom))
        enabled = enabled and bottom < viewTop and top > viewBottom
    end
    if type(control.IsEnabled) == "function" then enabled = enabled and control:IsEnabled() end
    control:EnableMouse(enabled and true or false)
end

function UI:RenderVisible()
    if not self.rows or self.interacting then return end
    for _, pool in pairs(self.pools) do
        for _, f in ipairs(pool) do f:Hide() end
    end
    local counts, top = {}, self.scroll:GetVerticalScroll()
    local bottom = top + self.scroll:GetHeight()
    for _, row in ipairs(self.rows) do
        if row.y + row.height >= top and row.y <= bottom then
            local kind = row.option.type
            counts[kind] = (counts[kind] or 0) + 1
            local pool = self.pools[kind] or {}; self.pools[kind] = pool
            local f = pool[counts[kind]]
            if not f then f = self:CreateRow(kind); pool[counts[kind]] = f end
            f:ClearAllPoints(); f:SetPoint("TOPLEFT", 0, -row.y); f:SetSize(507, row.height - 3)
            self:BindRow(f, row); f:Show()
            for _, key in ipairs({ "check", "slider", "number", "control", "input", "soundPreview" }) do
                self:ClipControl(f[key], self.scroll, not row.disabled)
            end
        end
    end
end

function UI:Rebuild(resetScroll)
    self.options = ns.Chatify:GetOptions()
    self:CloseChoices()
    self.pages = self:GetPages()
    local selectedVisible = false
    for _, page in ipairs(self.pages) do if page.key == self.pageKey then selectedVisible = true end end
    if not selectedVisible then self.pageKey = "overview" end
    local navY = 0
    for i, page in ipairs(self.pages) do
        local b = self.navButtons[i]
        if not b then b = button(self.navChild, "", 191, 36); self.navButtons[i] = b end
        self.navMeasure:SetText(page.name)
        local height = max(36, self.navMeasure:GetStringHeight() + 16)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -navY); b:SetHeight(height)
        navY = navY + height + 4
        b.text:SetText(page.name)
        b.text:SetJustifyH("LEFT")
        b.text:SetTextColor(unpack(page.key == self.pageKey and GOLD or TEXT))
        local key = page.key
        b:SetScript("OnClick", function() self:SelectPage(key) end)
        b:Show(); self:ClipControl(b, self.nav, true)
    end
    for i = #self.pages + 1, #self.navButtons do self.navButtons[i]:Hide() end
    self.navChild:SetHeight(max(1, navY))
    self.rows = self:CollectRows(self.pageKey, self.search:GetText())
    local y = 0
    for _, row in ipairs(self.rows) do
        local kind = row.option.type
        local height = (kind == "range" and 88) or ((kind == "select" or kind == "input") and 80) or 46
        self.measure:SetWidth((kind == "toggle" or kind == "multiselect") and 451 or (kind == "execute" and 463 or 485))
        self.measure:SetText(row.name)
        local textHeight = self.measure:GetStringHeight()
        if kind == "range" then height = max(height, textHeight + 61)
        elseif kind == "select" or kind == "input" then height = max(height, textHeight + 54)
        else height = max(height, textHeight + 23) end
        if kind == "description" then
            height = max(38, textHeight + 23)
        end
        if kind == "select" then
            local choices = self:Evaluate(row.option, "values", row.info, {})
            local selected = self:Evaluate(row.option, "get", row.info, nil)
            self.measure:SetWidth(row.option.chatifySound and 321 or 441); self.measure:SetText(choices[selected] or L.UI_SELECT)
            row.controlHeight = max(29, self.measure:GetStringHeight() + 10)
            height = max(height, textHeight + row.controlHeight + 25)
        end
        row.y, row.height = y, height
        y = y + height
    end
    self.content:SetHeight(max(1, y))
    if resetScroll then self.scroll:SetVerticalScroll(0)
    else self.scroll:SetVerticalScroll(min(self.scroll:GetVerticalScroll(), max(0, y - self.scroll:GetHeight()))) end
    self.scrollbar:SetMinMaxValues(0, max(0, y - self.scroll:GetHeight()))
    self.scrollbar:SetValue(self.scroll:GetVerticalScroll())
    self.scrollbar:SetShown(y > self.scroll:GetHeight())
    local title = L.UI_SEARCH_RESULTS
    if self.search:GetText() == "" then
        for _, page in ipairs(self.pages) do if page.key == self.pageKey then title = page.name end end
    end
    self.pageTitle:SetText(title)
    self.empty:SetShown(#self.rows == 0)
    self.dirty = false
    self:RenderVisible()
end

function UI:SelectPage(key)
    self:ClearInputFocus()
    self.pageKey = key
    if self.search then self.search:SetText(""); self:Rebuild(true); self:ShowDetails(nil) end
end

function UI:UpdateStatus()
    local client = type(ns.GetClientDisplayName) == "function" and ns.GetClientDisplayName() or "World of Warcraft"
    local toc = type(ns.GetBuildInterface) == "function" and ns.GetBuildInterface() or 0
    self.status:SetText(client .. "  |  Interface " .. tostring(toc))
    self.profile:SetText(L.UI_CURRENT_PROFILE .. ": " .. ns.Chatify.db:GetCurrentProfile())
end

function UI:FitScreen()
    local host = self.embeddedHost or UIParent
    local width, height = host:GetWidth(), host:GetHeight()
    if width <= 0 or height <= 0 then return end
    local margin = self.embeddedHost and 0 or 24
    self.window:SetScale(max(0.1, min(1, (width - margin) / self.window:GetWidth(), (height - margin) / 670)))
end

function UI:SetStandaloneEscape(enabled)
    if not UISpecialFrames then return end
    local name = self.window:GetName()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
    if enabled then table.insert(UISpecialFrames, name) end
end

function UI:ConfigureLayout(embedded)
    self.window:SetSize(embedded and 790 or 1060, 670)
    self.body:SetHeight(embedded and 350 or 533)
    self.scroll:SetHeight(embedded and 284 or 467)
    self.scrollbar:SetHeight(embedded and 279 or 462)
    self.inspector:ClearAllPoints()
    if embedded then
        self.inspector:SetPoint("TOPLEFT", 225, -438)
        self.inspector:SetSize(538, 171)
    else
        self.inspector:SetPoint("TOPLEFT", 776, -76)
        self.inspector:SetSize(266, 533)
    end
    local width = embedded and 506 or 234
    self.detailScroll:SetSize(width, embedded and 135 or 496)
    self.detailChild:SetWidth(width - 2)
    self.detailTitle:SetWidth(width - 2); self.detailText:SetWidth(width - 2)
    self.profile:ClearAllPoints(); self.profile:SetPoint("TOPRIGHT", embedded and -20 or -60, -25)
    self.profile:SetWidth(embedded and 300 or 430)
    self.status:SetWidth(embedded and 740 or 810)
    self.closeButton:SetShown(not embedded); self.doneButton:SetShown(not embedded)
    self:ShowDetails(nil)
end

function UI:Create()
    local w = frame("Frame", "ChatifySettingsWindow", UIParent)
    self.window = w; w:SetSize(1060, 670); w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG"); backdrop(w)
    w:EnableMouse(true); w:SetMovable(true); w:SetClampedToScreen(true)
    local titleBar = CreateFrame("Frame", nil, w)
    titleBar:SetPoint("TOPLEFT", 0, 0); titleBar:SetPoint("TOPRIGHT", 0, 0); titleBar:SetHeight(68)
    titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() if not self.embeddedHost then w:StartMoving() end end)
    titleBar:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
    if UISpecialFrames then table.insert(UISpecialFrames, w:GetName()) end
    local icon = w:CreateTexture(nil, "ARTWORK"); icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 20, -17); icon:SetTexture("Interface\\AddOns\\" .. addonName .. "\\assets\\icon")
    local title = label(w, "Chatify", 21, GOLD); title:SetPoint("TOPLEFT", 62, -19)
    local version = label(w, Compat.GetAddonVersion(), 12); version:SetPoint("TOPLEFT", 63, -45)
    local close = button(w, "X", 28, 28); self.closeButton = close; close:SetPoint("TOPRIGHT", -15, -15)
    close:SetScript("OnClick", function() w:Hide() end)
    self.profile = label(w, "", 12); self.profile:SetPoint("TOPRIGHT", -60, -25); self.profile:SetWidth(430); self.profile:SetJustifyH("RIGHT")
    self.search = edit(w, 194); self.search:SetMaxLetters(200); self.search:SetPoint("TOPLEFT", 18, -76)
    self.search:SetScript("OnTextChanged", function() self.searchDelay = 0.14; self.dirty = true end)
    self.search:SetScript("OnEscapePressed", function(e) e:SetText(""); e:ClearFocus() end)
    self.search:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    self.searchHint = label(w, L.UI_SEARCH, 12, { 0.50, 0.46, 0.39 })
    self.searchHint:SetPoint("LEFT", self.search, "LEFT", 10, 0)
    self.nav = CreateFrame("ScrollFrame", nil, w)
    self.nav:SetPoint("TOPLEFT", 19, -117); self.nav:SetSize(194, 490)
    self.navChild = CreateFrame("Frame", nil, self.nav); self.navChild:SetSize(191, 1); self.nav:SetScrollChild(self.navChild)
    self.nav:EnableMouseWheel(true)
    self.nav:SetScript("OnVerticalScroll", function()
        for _, b in ipairs(self.navButtons) do if b:IsShown() then self:ClipControl(b, self.nav, true) end end
    end)
    self.nav:SetScript("OnMouseWheel", function(f, d) f:SetVerticalScroll(max(0, min(f:GetVerticalScrollRange(), f:GetVerticalScroll() - d * 40))) end)
    self.navButtons, self.pools = {}, {}
    local body = frame("Frame", nil, w); self.body = body; body:SetPoint("TOPLEFT", 225, -76); body:SetSize(538, 533); backdrop(body)
    self.pageTitle = label(body, "", 17, GOLD); self.pageTitle:SetPoint("TOPLEFT", 18, -16); self.pageTitle:SetWidth(496)
    self.scroll = CreateFrame("ScrollFrame", nil, body)
    self.scroll:SetPoint("TOPLEFT", 10, -52); self.scroll:SetSize(507, 467)
    self.content = CreateFrame("Frame", nil, self.scroll); self.content:SetSize(507, 1); self.scroll:SetScrollChild(self.content)
    self.measure = label(w, "", 13); self.measure:SetWidth(485); self.measure:Hide()
    self.navMeasure = label(w, "", 13); self.navMeasure:SetWidth(171); self.navMeasure:Hide()
    self.choiceMeasure = label(w, "", 13); self.choiceMeasure:SetWidth(210); self.choiceMeasure:Hide()
    self.scroll:EnableMouseWheel(true)
    self.scroll:SetScript("OnMouseWheel", function(f, d)
        self:ClearInputFocus(); self:CloseChoices(); f:SetVerticalScroll(max(0, min(f:GetVerticalScrollRange(), f:GetVerticalScroll() - d * 64)))
    end)
    self.scroll:SetScript("OnVerticalScroll", function(_, value)
        self.scrollbar:SetValue(value); self:RenderVisible()
    end)
    self.scrollbar = CreateFrame("Slider", nil, body)
    self.scrollbar:SetOrientation("VERTICAL"); self.scrollbar:SetSize(12, 462); self.scrollbar:SetPoint("TOPRIGHT", -8, -55)
    self.scrollbar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Vertical")
    self.scrollbar:SetValueStep(1)
    self.scrollbar:SetScript("OnMouseDown", function() self:ClearInputFocus(); self:CloseChoices() end)
    self.scrollbar:SetScript("OnValueChanged", function(_, value)
        if math.abs(self.scroll:GetVerticalScroll() - value) > 0.1 then self.scroll:SetVerticalScroll(value) end
    end)
    self.empty = label(body, L.UI_NO_RESULTS, 14); self.empty:SetPoint("TOPLEFT", 24, -73); self.empty:SetWidth(480)
    local inspector = frame("Frame", nil, w); self.inspector = inspector; inspector:SetPoint("TOPLEFT", 776, -76); inspector:SetSize(266, 533); backdrop(inspector)
    self.detailScroll = CreateFrame("ScrollFrame", nil, inspector); self.detailScroll:SetPoint("TOPLEFT", 16, -18); self.detailScroll:SetSize(234, 496)
    self.detailChild = CreateFrame("Frame", nil, self.detailScroll); self.detailChild:SetSize(232, 500); self.detailScroll:SetScrollChild(self.detailChild)
    self.detailTitle = label(self.detailChild, "", 16, GOLD); self.detailTitle:SetPoint("TOPLEFT", 0, 0); self.detailTitle:SetWidth(232)
    self.detailText = label(self.detailChild, "", 13); self.detailText:SetPoint("TOPLEFT", self.detailTitle, "BOTTOMLEFT", 0, -18); self.detailText:SetWidth(232)
    self.detailScroll:EnableMouseWheel(true)
    self.detailScroll:SetScript("OnMouseWheel", function(f, d) f:SetVerticalScroll(max(0, min(f:GetVerticalScrollRange(), f:GetVerticalScroll() - d * 50))) end)
    self.status = label(w, "", 11); self.status:SetPoint("BOTTOMLEFT", 22, 27); self.status:SetWidth(810)
    local done = button(w, L.UI_CLOSE, 172, 30); self.doneButton = done; done:SetPoint("BOTTOMRIGHT", -19, 18)
    done:SetScript("OnClick", function() w:Hide() end)
    w:SetScript("OnHide", function()
        self.interacting = false
        self:CloseChoices(); if self.confirm then self.confirm.callback = nil; self.confirm:Hide() end
        self.search:ClearFocus()
        for _, pool in pairs(self.pools) do
            for _, f in ipairs(pool) do
                if f.number then f.number:ClearFocus() end
                if f.input then f.input:ClearFocus() end
            end
        end
        self.inputDrafts = {}
    end)
    local tick, statusTick = 0, 0
    w:SetScript("OnUpdate", function(_, elapsed)
        tick, statusTick = tick + elapsed, statusTick + elapsed
        if tick < 0.05 then return end
        if self.searchDelay then self.searchDelay = self.searchDelay - tick end
        tick = 0
        if self.dirty and not self.interacting and (not self.searchDelay or self.searchDelay <= 0) then
            local reset = self.searchDelay ~= nil; self.searchDelay = nil; self:Rebuild(reset)
        end
        self.searchHint:SetShown(self.search:GetText() == "")
        if statusTick >= 1 then
            statusTick = 0; self:UpdateStatus()
            -- Diagnostic descriptions depend on runtime state. Rebuild only this page,
            -- through the normal interaction/debounce guard, while it is open.
            if self.pageKey == "maintenance" then self:RequestRefresh() end
        end
    end)
    w:RegisterEvent("DISPLAY_SIZE_CHANGED"); w:RegisterEvent("UI_SCALE_CHANGED")
    w:RegisterEvent("PLAYER_REGEN_DISABLED"); w:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, event in ipairs({ "CHANNEL_UI_UPDATE", "UPDATE_CHAT_WINDOWS", "CHAT_MSG_CHANNEL_NOTICE" }) do
        pcall(w.RegisterEvent, w, event)
    end
    w:SetScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then self:FitScreen() end
        self:RequestRefresh()
    end)
    self:FitScreen(); self:ShowDetails(nil)
    w:Hide()
end

function UI:OpenEmbedded(host)
    if not self.window then self:Create() end
    self.window:Hide()
    self.embeddedHost = host
    self.window:SetParent(host); self.window:ClearAllPoints(); self.window:SetPoint("CENTER", host, "CENTER")
    self.window:SetFrameStrata(host:GetFrameStrata())
    self.window:SetFrameLevel(host:GetFrameLevel() + 1)
    self:SetStandaloneEscape(false); self:ConfigureLayout(true)
    self.window:Show(); self:FitScreen()
    self.pageKey = self.pageKey or "overview"
    self:Rebuild(false); self:UpdateStatus()
    return true
end

function UI:Open()
    if not self.window then self:Create() end
    self.window:Hide()
    self.embeddedHost = nil
    self.window:SetParent(UIParent); self.window:ClearAllPoints(); self.window:SetPoint("CENTER")
    self.window:SetFrameStrata("DIALOG")
    self:SetStandaloneEscape(true); self:ConfigureLayout(false)
    self.window:Show(); self:FitScreen()
    self.pageKey = self.pageKey or "overview"
    self:Rebuild(false); self:UpdateStatus()
    return true
end

function UI:Toggle()
    if self.window and self.window:IsShown() and not self.embeddedHost then
        self.window:Hide()
        return true
    end
    return self:Open()
end
