-- Chatify compatibility layer for current/PTR WoW clients.
-- Loaded before bundled libraries so older AceGUI builds can safely run when
-- Blizzard removes or changes small global helpers.

local addonName = ...
_G.ChatifyCompat = _G.ChatifyCompat or {}
local compat = _G.ChatifyCompat
compat.version = "1.1.0"

-- Safe Addon Compartment entry point. It is declared in every TOC and must
-- survive even if the configuration module has not finished loading yet.
if type(_G.Chatify_ToggleOptionsWindow) ~= "function" then
    _G.Chatify_ToggleOptionsWindow = function()
        local addon
        if type(_G.LibStub) == "function" then
            local okAce, aceAddon = pcall(_G.LibStub, "AceAddon-3.0", true)
            if okAce and aceAddon and type(aceAddon.GetAddon) == "function" then
                local okAddon, loadedAddon = pcall(aceAddon.GetAddon, aceAddon, "Chatify", true)
                if okAddon then
                    addon = loadedAddon
                end
            end
        end

        if addon and type(addon.OpenConfig) == "function" then
            return addon:OpenConfig()
        end

        local acd
        if type(_G.LibStub) == "function" then
            local okACD, loadedACD = pcall(_G.LibStub, "AceConfigDialog-3.0", true)
            if okACD then
                acd = loadedACD
            end
        end
        if acd and type(acd.Open) == "function" then
            pcall(acd.Open, acd, "Chatify")
        end
    end
end


if type(_G.SetDesaturation) ~= "function" then
    _G.SetDesaturation = function(texture, desaturated)
        if not texture then
            return
        end

        if type(texture.SetDesaturated) == "function" then
            return texture:SetDesaturated(not not desaturated)
        end

        if type(texture.SetDesaturation) == "function" then
            return texture:SetDesaturation(desaturated and 1 or 0)
        end
    end
end

if type(_G.GetMouseFocus) ~= "function" and type(_G.GetMouseFoci) == "function" then
    _G.GetMouseFocus = function()
        local focus = _G.GetMouseFoci()
        if type(focus) == "table" then
            return focus[1]
        end
        return focus
    end
end

compat.loaded = true
