-- Integrate with the game's AddOns settings category without replacing any
-- Blizzard panels or shrinking the full Chatify editor to unreadable text.
-- The original complete editor (including its Overview) remains available.
local addonName, ns = ...
local Integration = {}
ns.SettingsIntegration = Integration

local function T(key)
    return ns.Locale and ns.Locale.Get and ns.Locale:Get(key) or key
end

local function MakeText(parent, font, offsetY, width, text)
    local label = parent:CreateFontString(nil, "ARTWORK", font)
    label:SetPoint("TOPLEFT", 24, offsetY)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

-- Close the parent settings panel before opening an independent editor.
-- It avoids placing a DIALOG window behind Blizzard's fullscreen settings.
local function CloseNativeSettings()
    local panel = _G.SettingsPanel or _G.InterfaceOptionsFrame
    if not panel then return end
    if type(HideUIPanel) == "function" then
        local ok = pcall(HideUIPanel, panel)
        if ok then return end
    end
    if type(panel.Hide) == "function" then pcall(panel.Hide, panel) end
end

local function MakeButton(parent, text, y, page)
    -- This is a Blizzard button where the template exists. The fallback uses
    -- the same game font and built-in textures on older/modified clients.
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(264, 29)
    b:SetPoint("TOPLEFT", 24, y)
    if type(b.SetText) == "function" then b:SetText(text) end
    -- Some clients and test stubs do not supply template-managed text.
    if not b.Text and type(b.GetFontString) == "function" and not b:GetFontString() then
        local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(text)
        if type(b.SetFontString) == "function" then b:SetFontString(label) end
    end
    b:SetScript("OnClick", function()
        if not ns.SettingsWindow or not ns.Chatify or not ns.Chatify.db then return end
        CloseNativeSettings()
        ns.SettingsWindow:Open()
        ns.SettingsWindow:SelectPage(page)
    end)
    return b
end

function Integration:CreateLanding()
    if self.landing then return self.landing end
    local landing = CreateFrame("Frame", nil, self.panel)
    landing:SetAllPoints(self.panel)
    local title = MakeText(landing, "GameFontNormalLarge", -28, 520, "Chatify")
    local description = MakeText(landing, "GameFontHighlight", -70, 570,
        T("Chatify keeps Blizzard's chat controls in place. Open the full settings window for every option, search and profile."))
    local guidance = MakeText(landing, "GameFontHighlightSmall", -118, 570,
        T("The full settings window opens at readable size, without changing your game chat layout."))
    local all = MakeButton(landing, T("Open Complete Chatify Settings"), -165, "overview")
    local windows = MakeButton(landing, T("Chat Windows & Tabs"), -205, "windows")
    local buttons = MakeButton(landing, T("Quick Chat Buttons"), -245, "quickButtons")
    local appearance = MakeButton(landing, T("Appearance"), -285, "appearance")
    local status = MakeText(landing, "GameFontDisableSmall", -338, 570, "")
    self.landing, self.landingDescription, self.landingGuidance = landing, description, guidance
    self.landingStatus = status
    self.landingControls = { all, windows, buttons, appearance }
    self.landingTitle = title
    return landing
end

function Integration:RefreshPanel()
    if not self.panel then return end
    local ui, panel = ns.SettingsWindow, self.panel
    if not ns.Chatify or not ns.Chatify.db or not ui then return end
    local width, height = panel:GetWidth(), panel:GetHeight()
    -- Full editor is designed for 790 UI units and needs enough height for its
    -- independent scrollable details panel without shrinking its fonts.
    -- Do not scale it below legible size in Blizzard's narrow Settings canvas.
    local full = type(width) == "number" and type(height) == "number"
        and width >= 810 and height >= 580
    if full then
        if self.landing then self.landing:Hide() end
        if ui.embeddedHost ~= panel or not ui.window or not ui.window:IsShown() then
            ui:OpenEmbedded(panel)
        else
            ui:FitScreen()
        end
    else
        -- Rehosting to the native landing must never close a standalone editor.
        if ui.embeddedHost == panel and ui.window then
            ui.rehosting = true
            ui.window:Hide()
            ui.rehosting = nil
            ui.embeddedHost = nil
        end
        local landing = self:CreateLanding()
        local usableWidth = math.max(180, (width or 620) - 48)
        self.landingTitle:SetWidth(math.min(520, usableWidth))
        self.landingDescription:SetText(T("Chatify keeps Blizzard's chat controls in place. Open the full settings window for every option, search and profile."))
        self.landingGuidance:SetText(T("The full settings window opens at readable size, without changing your game chat layout."))
        for i, control in ipairs(self.landingControls) do
            control:SetWidth(math.min(264, usableWidth))
            local keys = { "Open Complete Chatify Settings", "Chat Windows & Tabs", "Quick Chat Buttons", "Appearance" }
            control:SetText(T(keys[i]))
        end
        self.landingDescription:SetWidth(math.min(570, usableWidth))
        self.landingGuidance:SetWidth(math.min(570, usableWidth))
        self.landingStatus:SetWidth(math.min(570, usableWidth))
        local name = ns.Chatify.db:GetCurrentProfile()
        self.landingStatus:SetText(T("UI_CURRENT_PROFILE") .. ": " .. tostring(name))
        landing:Show()
    end
end

function Integration:Register()
    if self.registered then return true end
    local modern = type(Settings) == "table"
        and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
    local legacy = type(InterfaceOptions_AddCategory) == "function"
    if not modern and not legacy then return false end
    if not self.panel then
        local panel = CreateFrame("Frame", "ChatifyGameSettingsPanel", UIParent)
        panel.name = "Chatify"
        panel:Hide()
        panel:SetScript("OnShow", function() Integration:RefreshPanel() end)
        panel:SetScript("OnHide", function(self)
            local ui = ns.SettingsWindow
            if ui and ui.embeddedHost == self and ui.window then ui.window:Hide() end
        end)
        panel:SetScript("OnSizeChanged", function(self)
            if self:IsShown() then Integration:RefreshPanel() end
        end)
        panel.refresh = function() Integration:RefreshPanel() end
        panel.OnRefresh = panel.refresh
        panel.OnCommit = function() end
        panel.OnDefault = function()
            local ui = ns.SettingsWindow
            if ui and ns.Chatify and ns.Chatify.db then
                -- When a compact native category has no embedded editor, the
                -- confirmation must not appear behind Blizzard Settings.
                if ui.embeddedHost ~= panel then CloseNativeSettings() end
                return ui:ConfirmProfileReset()
            end
            return false
        end
        self.panel = panel
    end
    local registered = false
    if modern then
        if not self.category then
            local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, self.panel, self.panel.name)
            if ok and category then self.category = category end
        end
        if self.category and pcall(Settings.RegisterAddOnCategory, self.category) then
            self.api = "settings"
            registered = true
        end
    end
    if not registered and legacy then
        if not pcall(InterfaceOptions_AddCategory, self.panel) then return false end
        self.api = "interface-options"
        registered = true
    end
    if not registered then return false end
    self.registered = true
    self.events:UnregisterEvent("ADDON_LOADED")
    self.events:UnregisterEvent("PLAYER_LOGIN")
    return true
end

-- Some clients expose registration only after their settings addon loads.
Integration.events = CreateFrame("Frame")
Integration.events:RegisterEvent("ADDON_LOADED")
Integration.events:RegisterEvent("PLAYER_LOGIN")
Integration.events:SetScript("OnEvent", function() Integration:Register() end)
Integration:Register()
