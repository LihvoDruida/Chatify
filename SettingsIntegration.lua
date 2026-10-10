-- Register the same native renderer inside the game's AddOns settings list.
-- Feature detection covers both Settings canvas pages and InterfaceOptions.
local addonName, ns = ...
local Integration = {}
ns.SettingsIntegration = Integration

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
        panel:SetScript("OnShow", function(self)
            if ns.Chatify and ns.Chatify.db then ns.SettingsWindow:OpenEmbedded(self) end
        end)
        panel:SetScript("OnHide", function(self)
            local ui = ns.SettingsWindow
            if ui.embeddedHost == self and ui.window then ui.window:Hide() end
        end)
        panel:SetScript("OnSizeChanged", function(self)
            local ui = ns.SettingsWindow
            if ui.embeddedHost == self then ui:FitScreen() end
        end)
        -- Edits apply immediately, just as in the standalone window.
        panel.refresh = function() ns.SettingsWindow:RequestRefresh() end
        panel.OnRefresh = panel.refresh
        panel.OnCommit = function() end
        panel.OnDefault = function() end
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
