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
        self.panel = panel
    end
    if modern then
        if not self.category then
            local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, self.panel, self.panel.name)
            if not ok or not category then return false end
            self.category = category
        end
        if not pcall(Settings.RegisterAddOnCategory, self.category) then return false end
        self.api = "settings"
    else
        if not pcall(InterfaceOptions_AddCategory, self.panel) then return false end
        self.api = "interface-options"
    end
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
