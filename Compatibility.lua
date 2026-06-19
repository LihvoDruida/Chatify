-- Chatify compatibility layer for current/PTR WoW clients.
-- Loaded before bundled libraries so older AceGUI builds can safely run when
-- Blizzard removes or changes small global helpers.

local addonName = ...
_G.ChatifyCompat = _G.ChatifyCompat or {}
local compat = _G.ChatifyCompat
compat.version = "1.0.0"

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
