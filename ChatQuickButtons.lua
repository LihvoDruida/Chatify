local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local QuickButtonsModule = Chatify:NewModule("QuickButtons", "AceEvent-3.0")

local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local unpack = unpack or table.unpack
local container
local settingsContainer
local settingsButton
local socialButton
local socialButtonHooked = false
local buttons = {}
local hookedEditBox
local hookedAnchorFrame
local GetConfiguredAlpha
local GetConfiguredPanelAlpha
local GetConfiguredTheme
local GetConfiguredButtonYOffset
local GetElvUIPanelColor
local GetGW2ChatFont
local GetAnchorFrame
local MixColor
local elvuiEngine
local elvuiChat
local gw2Engine
local UpdateButtonState
local elvuiHooksInstalled = false
local gw2HooksInstalled = false
local generalHooksInstalled = false
local refreshQueued = false
local stateUpdateQueued = false
local lastLayoutSignature
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

local GW2_TEXTURE_PATH = "Interface\\AddOns\\Chatify\\assets\\themes\\gw2\\"
local TRANSPARENT_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local GW2_BUTTON_NORMAL = GW2_TEXTURE_PATH .. "channel_button_normal.png"
local GW2_BUTTON_HIGHLIGHT = GW2_TEXTURE_PATH .. "channel_button_normal_highlight.png"
local GW2_BUTTON_ACTIVE = GW2_TEXTURE_PATH .. "channel_button_vc.png"
local GW2_BUTTON_ACTIVE_HIGHLIGHT = GW2_TEXTURE_PATH .. "channel_button_vc_highlight.png"
local GW2_CONTAINER_BG = GW2_TEXTURE_PATH .. "chatframebackground.png"
local GW2_CONTAINER_BORDER = GW2_TEXTURE_PATH .. "chatframeborder.png"
local SETTINGS_ICON = "Interface\\AddOns\\Chatify\\assets\\icons\\SettingsCog.png"


local function GetColorComponents(color, fallback)
    fallback = fallback or { 1, 1, 1 }
    if type(color) ~= "table" then
        return fallback[1], fallback[2], fallback[3]
    end

    local r = color.r or color[1] or fallback[1]
    local g = color.g or color[2] or fallback[2]
    local b = color.b or color[3] or fallback[3]
    return r, g, b
end

local function GetElvUI()
    if type(IsAddOnLoaded) ~= "function" or not IsAddOnLoaded("ElvUI") or not _G.ElvUI then
        elvuiEngine = nil
        elvuiChat = nil
        return nil, nil
    end

    if not elvuiEngine then
        local ok, engine = pcall(function()
            return unpack(_G.ElvUI)
        end)
        if ok then
            elvuiEngine = engine
        end
    end

    if elvuiEngine and not elvuiChat and type(elvuiEngine.GetModule) == "function" then
        local ok, chat = pcall(elvuiEngine.GetModule, elvuiEngine, "Chat", true)
        if ok then
            elvuiChat = chat
        end
    end

    return elvuiEngine, elvuiChat
end

local function HasElvUIChat()
    local E, CH = GetElvUI()
    return E ~= nil and CH ~= nil
end

local function GetGW2()
    if type(IsAddOnLoaded) ~= "function" or not IsAddOnLoaded("GW2_UI") or not _G.GW then
        gw2Engine = nil
        return nil
    end

    if not gw2Engine then
        gw2Engine = _G.GW
    end

    return gw2Engine
end

local function HasGW2Chat()
    local GW = GetGW2()
    if not GW then
        return false
    end

    local settings = GW.settings
    if type(settings) == "table" and settings.CHATFRAME_ENABLED == false then
        return false
    end

    if type(GW.ShouldBlockIncompatibleAddon) == "function" then
        local ok, blocked = pcall(GW.ShouldBlockIncompatibleAddon, "Chat")
        if ok and blocked then
            return false
        end
    end

    return true
end

local delayedRefreshToken = 0

local function ScheduleRefresh(delay)
    delay = tonumber(delay) or 0
    if delay < 0 then
        delay = 0
    end

    if not C_Timer or not C_Timer.After then
        ns.RefreshQuickChatButtons()
        return
    end

    if delay > 0 then
        delayedRefreshToken = delayedRefreshToken + 1
        local token = delayedRefreshToken
        C_Timer.After(delay, function()
            if token ~= delayedRefreshToken then
                return
            end
            ns.RefreshQuickChatButtons()
        end)
        return
    end

    if refreshQueued then
        return
    end

    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        ns.RefreshQuickChatButtons()
    end)
end

local function ScheduleButtonStateUpdate()
    if not C_Timer or not C_Timer.After then
        UpdateButtonState()
        return
    end

    if stateUpdateQueued then
        return
    end

    stateUpdateQueued = true
    C_Timer.After(0, function()
        stateUpdateQueued = false
        UpdateButtonState()
    end)
end

local function ApplyTextureToRegion(region, path)
    if not region or type(path) ~= "string" then
        return
    end

    region:SetTexture(path)
    region:SetAllPoints(region:GetParent() or region)
end

local function ResetManagedButtonTexture(button, getterName, setterName, layer)
    if not button then
        return
    end

    local getter = button[getterName]
    local setter = button[setterName]
    local region = type(getter) == "function" and getter(button) or nil

    if not region and type(setter) == "function" then
        pcall(setter, button, TRANSPARENT_TEXTURE, layer)
        region = type(getter) == "function" and getter(button) or nil
    end

    if region then
        region:SetTexture(TRANSPARENT_TEXTURE)
        region:SetAlpha(0)
        if type(region.SetVertexColor) == "function" then
            region:SetVertexColor(1, 1, 1, 0)
        end
        region:ClearAllPoints()
        region:SetAllPoints(button)
    end
end

local function ResetButtonThemeState(button)
    if not button then
        return
    end

    ResetManagedButtonTexture(button, "GetNormalTexture", "SetNormalTexture")
    ResetManagedButtonTexture(button, "GetPushedTexture", "SetPushedTexture")
    ResetManagedButtonTexture(button, "GetDisabledTexture", "SetDisabledTexture")
    ResetManagedButtonTexture(button, "GetHighlightTexture", "SetHighlightTexture", "ADD")
end

local function ApplyRegionToButton(region, button, alpha)
    if not region or not button then
        return
    end

    if type(region.SetAllPoints) == "function" then
        region:SetAllPoints(button)
    end
    if type(region.SetAlpha) == "function" and type(alpha) == "number" then
        region:SetAlpha(alpha)
    end
end

local function SafeSetManagedTexture(button, setterName, getterName, texturePath, layer, alpha)
    if not button or type(texturePath) ~= "string" or texturePath == "" then
        return nil
    end

    local setter = button[setterName]
    if type(setter) ~= "function" then
        return nil
    end

    local ok
    if layer ~= nil then
        ok = pcall(setter, button, texturePath, layer)
    else
        ok = pcall(setter, button, texturePath)
    end

    if not ok then
        return nil
    end

    local getter = button[getterName]
    local region = type(getter) == "function" and getter(button) or nil
    ApplyRegionToButton(region, button, alpha)
    return region
end

local function EnsureContainerArt()
    if not container or container.__chatifyArtReady then
        return
    end

    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(GW2_CONTAINER_BG)
    bg:SetAllPoints(container)
    container.GW2Bg = bg

    local left = container:CreateTexture(nil, "BORDER")
    left:SetTexture(GW2_CONTAINER_BORDER)
    left:SetPoint("TOPLEFT", container, "TOPLEFT", -3, 0)
    left:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", -3, 0)
    left:SetWidth(8)
    left:SetTexCoord(0, 0.5, 0, 1)
    container.GW2BorderLeft = left

    local right = container:CreateTexture(nil, "BORDER")
    right:SetTexture(GW2_CONTAINER_BORDER)
    right:SetPoint("TOPRIGHT", container, "TOPRIGHT", 3, 0)
    right:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 3, 0)
    right:SetWidth(8)
    right:SetTexCoord(0.5, 1, 0, 1)
    container.GW2BorderRight = right

    container.__chatifyArtReady = true
end

local function HideContainerThemeTextures()
    if not container then
        return
    end

    EnsureContainerArt()

    if container.GW2Bg then container.GW2Bg:Hide() end
    if container.GW2BorderLeft then container.GW2BorderLeft:Hide() end
    if container.GW2BorderRight then container.GW2BorderRight:Hide() end
end

local function EnsureButtonArt(button)
    if not button or button.__chatifyArtReady then
        return
    end

    local gloss = button:CreateTexture(nil, "ARTWORK")
    gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
    gloss:SetBlendMode("ADD")
    button.Gloss = gloss

    local accent = button:CreateTexture(nil, "BORDER")
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    button.Accent = accent

    local inner = button:CreateTexture(nil, "ARTWORK")
    inner:SetTexture("Interface\\Buttons\\WHITE8x8")
    button.Inner = inner

    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetBlendMode("ADD")
    button.Glow = glow

    local shade = button:CreateTexture(nil, "OVERLAY")
    shade:SetTexture("Interface\\Buttons\\WHITE8x8")
    shade:SetVertexColor(0, 0, 0, 0)
    shade:SetAllPoints(button)
    button.Shade = shade

    button.__chatifyArtReady = true
end

local function ApplyButtonBackdrop(button, bg, border)
    if not button then
        return
    end

    local theme = GetConfiguredTheme()

    if theme ~= "ELVUI" and button._chatifyElvTemplate then
        button._chatifyElvTemplate = nil
    end

    if theme == "GW2UI" then
        ResetButtonThemeState(button)
        if type(button.SetBackdrop) == "function" and not button._chatifyBackdropSet then
            button:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false,
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            button._chatifyBackdropSet = true
        end

        if type(button.SetBackdropColor) == "function" and type(button.SetBackdropBorderColor) == "function" then
            button:SetBackdropColor(0, 0, 0, 0)
            button:SetBackdropBorderColor(0, 0, 0, 0)
        end
        return
    end

    ResetButtonThemeState(button)

    if theme == "ELVUI" then
        local E = GetElvUI()
        if E and type(button.SetTemplate) == "function" and not button._chatifyElvTemplate then
            pcall(button.SetTemplate, button, "Transparent")
            button._chatifyElvTemplate = true
        end
    end

    if type(button.SetBackdrop) == "function" then
        if not button._chatifyBackdropSet then
            button:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false,
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            button._chatifyBackdropSet = true
        end

        button:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        button:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function GetButtonPalette(button)
    local enabled = not (button and button.__chatifyDisabled)
    local selected = button and button.__chatifySelected
    local hovered = button and button:IsMouseOver()
    local alpha = GetConfiguredAlpha()
    local theme = GetConfiguredTheme()

    if theme == "GW2UI" then
        if not enabled then
            return {
                bg = { 0.08, 0.08, 0.09, math.min(1, alpha * 0.75) },
                border = { 0.30, 0.30, 0.32, 0.85 },
                text = { 0.62, 0.64, 0.68 },
                accent = { 0.32, 0.32, 0.36, 0.0 },
                inner = 0.0,
                gloss = 0.0,
                glow = 0.0,
                shade = 0.22,
            }
        end

        if selected then
            return {
                bg = { 0.16, 0.24, 0.34, math.min(1, alpha) },
                border = { 0.42, 0.72, 1.0, 1.0 },
                text = { 1.0, 1.0, 1.0 },
                accent = { 0.42, 0.72, 1.0, 0.0 },
                inner = 0.0,
                gloss = 0.0,
                glow = 0.0,
                shade = 0.0,
            }
        end

        if hovered then
            return {
                bg = { 0.15, 0.16, 0.20, math.min(1, alpha) },
                border = { 0.70, 0.70, 0.76, 1.0 },
                text = { 1.0, 1.0, 1.0 },
                accent = { 0.70, 0.70, 0.76, 0.0 },
                inner = 0.0,
                gloss = 0.0,
                glow = 0.0,
                shade = 0.0,
            }
        end

        return {
            bg = { 0.10, 0.10, 0.12, alpha },
            border = { 0.46, 0.46, 0.50, 1.0 },
            text = { 0.92, 0.92, 0.94 },
            accent = { 0.46, 0.46, 0.50, 0.0 },
            inner = 0.0,
            gloss = 0.0,
            glow = 0.0,
            shade = 0.0,
        }
    end

    if theme == "ELVUI" then
        local E = GetElvUI()
        local vr, vg, vb = 0.20, 0.60, 1.00
        local br, bgc, bb = 0.12, 0.12, 0.12
        if E and E.media then
            vr, vg, vb = GetColorComponents(E.media.rgbvaluecolor, { 0.20, 0.60, 1.00 })
            br, bgc, bb = GetColorComponents(E.media.bordercolor, { 0.12, 0.12, 0.12 })
        end

        local pr, pg, pb, pa = GetElvUIPanelColor()
        local base = { pr, pg, pb, math.min(1, math.max(pa, alpha * 0.92)) }
        local text = { 0.92, 0.94, 0.98 }

        if not enabled then
            return {
                bg = { pr * 0.85, pg * 0.85, pb * 0.85, math.min(1, alpha * 0.78) },
                border = { br, bgc, bb, 0.85 },
                text = { 0.52, 0.55, 0.60 },
                accent = { br, bgc, bb, 0.45 },
                inner = 0.03,
                gloss = 0.00,
                glow = 0.00,
                shade = 0.18,
            }
        end

        if selected then
            return {
                bg = MixColor(base, { vr, vg, vb, math.min(1, alpha) }, 0.18),
                border = { vr, vg, vb, 1.0 },
                text = { 1.0, 1.0, 1.0 },
                accent = { vr, vg, vb, 1.0 },
                inner = 0.10,
                gloss = 0.16,
                glow = 0.12,
                shade = 0.00,
            }
        end

        if hovered then
            return {
                bg = MixColor(base, { vr, vg, vb, math.min(1, alpha) }, 0.08),
                border = { vr, vg, vb, 0.88 },
                text = { 1.0, 1.0, 1.0 },
                accent = { vr, vg, vb, 0.90 },
                inner = 0.07,
                gloss = 0.12,
                glow = 0.08,
                shade = 0.00,
            }
        end

        return {
            bg = base,
            border = { br, bgc, bb, 1.0 },
            text = text,
            accent = { vr, vg, vb, 0.78 },
            inner = 0.05,
            gloss = 0.05,
            glow = 0.04,
            shade = 0.00,
        }
    end

    if not enabled then
        return {
            bg = { 0.09, 0.09, 0.10, math.min(1, alpha * 0.76) },
            border = { 0.24, 0.24, 0.24, 0.92 },
            text = { 0.58, 0.58, 0.58 },
            accent = { 0.32, 0.32, 0.32, 0.55 },
            inner = 0.02,
            gloss = 0.00,
            glow = 0.00,
            shade = 0.22,
        }
    end

    if selected then
        return {
            bg = { 0.19, 0.14, 0.05, math.min(1, alpha + 0.04) },
            border = { 1.0, 0.82, 0.22, 1.0 },
            text = { 1.0, 0.94, 0.60 },
            accent = { 1.0, 0.82, 0.18, 1.0 },
            inner = 0.12,
            gloss = 0.18,
            glow = 0.14,
            shade = 0.00,
        }
    end

    if hovered then
        return {
            bg = { 0.10, 0.09, 0.08, math.min(1, alpha + 0.02) },
            border = { 0.86, 0.68, 0.22, 1.0 },
            text = { 1.0, 0.90, 0.35 },
            accent = { 1.0, 0.82, 0.18, 0.95 },
            inner = 0.08,
            gloss = 0.13,
            glow = 0.10,
            shade = 0.00,
        }
    end

    return {
        bg = { 0.07, 0.07, 0.08, alpha },
        border = { 0.58, 0.44, 0.16, 0.95 },
        text = { 1.0, 0.84, 0.22 },
        accent = { 1.0, 0.82, 0.18, 0.85 },
        inner = 0.05,
        gloss = 0.08,
        glow = 0.05,
        shade = 0.00,
    }
end

local GetConfiguredFontScale

local function RefreshButtonLook(button)
    if not button then
        return
    end

    local enabled = not button.__chatifyDisabled
    local selected = button.__chatifySelected
    local hovered = button:IsMouseOver()
    local pressed = button.__chatifyPressed
    local alpha = enabled and GetConfiguredAlpha() or math.max(0.45, GetConfiguredAlpha() * 0.75)
    local theme = GetConfiguredTheme()
    local palette = GetButtonPalette(button)

    EnsureButtonArt(button)

    if theme == "GW2UI" then
        local normalTexture = (selected or pressed) and GW2_BUTTON_ACTIVE or GW2_BUTTON_NORMAL
        local highlightTexture = (selected or pressed) and GW2_BUTTON_ACTIVE_HIGHLIGHT or GW2_BUTTON_HIGHLIGHT
        SafeSetManagedTexture(button, "SetNormalTexture", "GetNormalTexture", normalTexture, nil, alpha)
        SafeSetManagedTexture(button, "SetPushedTexture", "GetPushedTexture", GW2_BUTTON_ACTIVE, nil, alpha)
        SafeSetManagedTexture(button, "SetHighlightTexture", "GetHighlightTexture", highlightTexture, "ADD", hovered and 0.92 or 0.72)
        if button.Highlight then
            button.Highlight:SetVertexColor(1, 1, 1, 0)
        end
        ApplyButtonBackdrop(button, palette.bg, palette.border)
    elseif theme == "ELVUI" then
        ResetButtonThemeState(button)
        ApplyButtonBackdrop(button, palette.bg, palette.border)
        if button.Highlight then
            button.Highlight:SetTexture(TRANSPARENT_TEXTURE)
            button.Highlight:SetAllPoints(button)
            button.Highlight:SetBlendMode("ADD")
            button.Highlight:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], hovered and 0.10 or 0.0)
        end
    else
        button:SetNormalTexture((selected or pressed) and "chatframe-button-down" or "chatframe-button-up")
        button:SetPushedTexture("chatframe-button-down")
        button:SetHighlightTexture("chatframe-button-highlight")
        if type(button.SetBackdropColor) == "function" then
            button:SetBackdropColor(0, 0, 0, 0)
        end
        if type(button.SetBackdropBorderColor) == "function" then
            button:SetBackdropBorderColor(0, 0, 0, 0)
        end
        if button.Highlight then
            button.Highlight:SetTexture(TRANSPARENT_TEXTURE)
            button.Highlight:SetAllPoints(button)
            button.Highlight:SetBlendMode("ADD")
            button.Highlight:SetVertexColor(1.0, 0.82, 0.18, hovered and 0.08 or 0.0)
        end
    end

    button:SetAlpha(alpha)

    if button.Icon then
        button.Icon:Hide()
    end

    if button.Inner then
        button.Inner:ClearAllPoints()
        button.Inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.Inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.Inner:SetVertexColor(palette.bg[1], palette.bg[2], palette.bg[3], math.max(0, palette.inner or 0))
        button.Inner:SetShown((palette.inner or 0) > 0.001 and theme ~= "STANDARD")
    end

    if button.Accent then
        button.Accent:ClearAllPoints()
        button.Accent:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.Accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
        button.Accent:SetWidth(1)
        button.Accent:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], palette.accent[4] or 0)
        button.Accent:SetShown((palette.accent[4] or 0) > 0.001 and theme ~= "STANDARD")
    end

    if button.Gloss then
        button.Gloss:ClearAllPoints()
        button.Gloss:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.Gloss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
        button.Gloss:SetHeight(math.max(2, math.floor((button:GetHeight() or 18) * 0.42)))
        button.Gloss:SetVertexColor(1, 1, 1, math.max(0, palette.gloss or 0))
        button.Gloss:SetShown((palette.gloss or 0) > 0.001 and theme ~= "STANDARD")
    end

    if button.Glow then
        button.Glow:ClearAllPoints()
        button.Glow:SetAllPoints(button)
        button.Glow:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], math.max(0, palette.glow or 0))
        button.Glow:SetShown((palette.glow or 0) > 0.001 and theme ~= "STANDARD")
    end

    if button.Shade then
        button.Shade:ClearAllPoints()
        button.Shade:SetAllPoints(button)
        local shadeAlpha = math.max(0, palette.shade or 0)
        if pressed and enabled then
            shadeAlpha = math.min(0.24, shadeAlpha + 0.10)
        end
        button.Shade:SetVertexColor(0, 0, 0, shadeAlpha)
        button.Shade:SetShown(shadeAlpha > 0.001)
    end

    if button.Label then
        local width = math.max(1, button:GetWidth() or 26)
        local height = math.max(1, button:GetHeight() or 28)
        local fontSize = math.max(10, math.floor(math.min(width, height) * 0.56 * GetConfiguredFontScale()))
        local fontPath = STANDARD_TEXT_FONT
        if theme == "GW2UI" then
            fontPath = GetGW2ChatFont() or fontPath
        elseif ChatFontNormal and ChatFontNormal.GetFont then
            fontPath = ChatFontNormal:GetFont() or fontPath
        end
        pcall(button.Label.SetFont, button.Label, fontPath, fontSize, "OUTLINE")
        button.Label:ClearAllPoints()
        button.Label:SetPoint("CENTER", button, "CENTER", pressed and 1 or 0, pressed and -1 or 0)

        local textColor = palette.text
        if hovered and theme == "STANDARD" then
            textColor = { 1.0, 0.90, 0.35 }
        elseif selected and theme == "STANDARD" then
            textColor = { 1.0, 0.94, 0.50 }
        end
        button.Label:SetTextColor(textColor[1], textColor[2], textColor[3], enabled and 1 or 0.92)
    end
end

local function ApplyContainerStyle()
    if not container then
        return
    end

    HideContainerThemeTextures()

    local panelAlpha = GetConfiguredPanelAlpha()
    local theme = GetConfiguredTheme()

    if theme == "GW2UI" then
        EnsureContainerArt()
        if container.GW2Bg then
            container.GW2Bg:Show()
            container.GW2Bg:SetVertexColor(1, 1, 1, panelAlpha)
        end
        if container.GW2BorderLeft then
            container.GW2BorderLeft:Show()
            container.GW2BorderLeft:SetAlpha(math.min(1, panelAlpha * 1.8))
        end
        if container.GW2BorderRight then
            container.GW2BorderRight:Show()
            container.GW2BorderRight:SetAlpha(math.min(1, panelAlpha * 1.8))
        end
        if type(container.SetBackdropColor) == "function" then
            container:SetBackdropColor(0, 0, 0, 0)
        end
        if type(container.SetBackdropBorderColor) == "function" then
            container:SetBackdropBorderColor(0, 0, 0, 0)
        end
        return
    end

    if type(container.SetBackdrop) == "function" then
        if not container._chatifyBackdropSet then
            container:SetBackdrop({
                bgFile = "Interface\Buttons\WHITE8x8",
                edgeFile = "Interface\Buttons\WHITE8x8",
                tile = false,
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            container._chatifyBackdropSet = true
        end

        if panelAlpha <= 0.01 then
            container:SetBackdropColor(0, 0, 0, 0)
            container:SetBackdropBorderColor(0, 0, 0, 0)
            return
        end

        if theme == "ELVUI" then
            local pr, pg, pb, pa = GetElvUIPanelColor()
            local E = GetElvUI()
            local br, bgc, bb = 0.12, 0.12, 0.12
            if E and E.media then
                br, bgc, bb = GetColorComponents(E.media.bordercolor, { 0.12, 0.12, 0.12 })
            end
            container:SetBackdropColor(pr, pg, pb, math.min(1, math.max(panelAlpha, pa * 0.92)))
            container:SetBackdropBorderColor(br, bgc, bb, math.min(1, 0.88 + (panelAlpha * 0.12)))
        else
            container:SetBackdropColor(0.02, 0.02, 0.03, panelAlpha)
            container:SetBackdropBorderColor(0.38, 0.28, 0.10, math.min(1, panelAlpha * 1.8))
        end
    end
end

local function AddTooltipLine(leftText, rightText, r, g, b, wrap)
    if not GameTooltip or type(leftText) ~= "string" then
        return
    end

    if rightText then
        GameTooltip:AddDoubleLine(leftText, rightText, r or 0.90, g or 0.90, b or 0.90, 0.78, 0.78, 0.78)
    else
        GameTooltip:AddLine(leftText, r or 0.90, g or 0.90, b or 0.90, wrap ~= false)
    end
end

local function GetDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return nil
end

GetConfiguredAlpha = function()
    local db = GetDB()
    local alpha = db and db.quickChatButtonAlpha or 0.92
    if type(alpha) ~= "number" then
        alpha = 0.92
    end
    if alpha < 0.25 then alpha = 0.25 end
    if alpha > 1 then alpha = 1 end
    return alpha
end

GetConfiguredPanelAlpha = function()
    local db = GetDB()
    local alpha = db and db.quickChatPanelAlpha or 0
    if type(alpha) ~= "number" then
        alpha = 0
    end
    if alpha < 0 then alpha = 0 end
    if alpha > 1 then alpha = 1 end
    return alpha
end

GetConfiguredTheme = function()
    local db = GetDB()
    local theme = db and db.quickChatButtonTheme or "AUTO"
    if theme ~= "AUTO" and theme ~= "STANDARD" and theme ~= "ELVUI" and theme ~= "GW2UI" then
        theme = "AUTO"
    end

    if theme == "AUTO" then
        if HasGW2Chat() then
            return "GW2UI"
        end

        if HasElvUIChat() then
            return "ELVUI"
        end

        return "STANDARD"
    end

    return theme
end

local function GetConfiguredSpacing()
    local db = GetDB()
    local spacing = db and db.quickChatButtonSpacing or 4
    if type(spacing) ~= "number" then
        spacing = 4
    end
    if spacing < 2 then spacing = 2 end
    if spacing > 10 then spacing = 10 end
    return math.floor(spacing + 0.5)
end

GetConfiguredFontScale = function()
    local db = GetDB()
    local scale = db and db.quickChatButtonFontScale or 1
    if type(scale) ~= "number" then
        scale = 1
    end
    if scale < 0.8 then scale = 0.8 end
    if scale > 1.3 then scale = 1.3 end
    return scale
end

GetConfiguredButtonYOffset = function()
    local db = GetDB()
    local offset = db and db.quickChatButtonYOffset or -4
    if type(offset) ~= "number" then
        offset = -4
    end
    if offset < -24 then offset = -24 end
    if offset > 16 then offset = 16 end
    return math.floor(offset + 0.5)
end

local function ShouldShowSettingsButton()
    local db = GetDB()
    if not db then
        return false
    end
    if db.quickChatSettingsButton == nil then
        return true
    end
    return db.quickChatSettingsButton == true
end

local function GetSocialSidebarButton()
    if QuickJoinToastButton then
        return QuickJoinToastButton
    end
    if FriendsMicroButton then
        return FriendsMicroButton
    end
    return nil
end

local function ShouldShowSidebarMenu()
    return GetSocialSidebarButton() ~= nil or ShouldShowSettingsButton()
end

local BUTTON_DEFS

local function GetOrderedButtons()
    local ordered = {}
    local db = GetDB() or {}

    if db.quickChatButtons ~= false then
        for _, def in ipairs(BUTTON_DEFS) do
            local button = buttons[def.key]
            if button then
                table.insert(ordered, button)
            end
        end
    end

    return ordered
end


function ns.NotifyQuickChatSettingsChanged()
    ScheduleRefresh(0)
end

GetElvUIPanelColor = function()
    local _, CH = GetElvUI()
    local panelColor = CH and CH.db and CH.db.panelColor
    if type(panelColor) == "table" then
        return panelColor.r or panelColor[1] or 0.06,
               panelColor.g or panelColor[2] or 0.06,
               panelColor.b or panelColor[3] or 0.06,
               panelColor.a or panelColor[4] or GetConfiguredAlpha()
    end

    return 0.06, 0.06, 0.06, GetConfiguredAlpha()
end

GetGW2ChatFont = function()
    local GW = GetGW2()
    if GW and GW.Libs and GW.Libs.LSM and type(GW.Libs.LSM.Fetch) == "function" then
        local ok, fontPath = pcall(GW.Libs.LSM.Fetch, GW.Libs.LSM, "font", "GW2_UI_Chat")
        if ok and type(fontPath) == "string" and fontPath ~= "" then
            return fontPath
        end
    end

    return STANDARD_TEXT_FONT
end

MixColor = function(fromColor, toColor, t)
    return {
        fromColor[1] + ((toColor[1] - fromColor[1]) * t),
        fromColor[2] + ((toColor[2] - fromColor[2]) * t),
        fromColor[3] + ((toColor[3] - fromColor[3]) * t),
        fromColor[4] + ((toColor[4] - fromColor[4]) * t),
    }
end

BUTTON_DEFS = {
    {
        key = "GUILD",
        chatType = "GUILD",
        altChatType = "OFFICER",
        label = "G",
        tooltip = "Guild Chat",
        altTooltip = "Officer Chat",
        slash = "/g ",
        slashAlias = "/guild",
        altSlash = "/o ",
        altSlashAlias = "/officer",
        isAvailable = function()
            return type(IsInGuild) == "function" and IsInGuild() or false
        end,
        altIsAvailable = function()
            if type(IsInGuild) == "function" and not IsInGuild() then
                return false
            end

            if C_GuildInfo and type(C_GuildInfo.CanEditOfficerNote) == "function" then
                local ok, canSpeak = pcall(C_GuildInfo.CanEditOfficerNote)
                return ok and canSpeak or false
            end

            if type(CanEditOfficerNote) == "function" then
                local ok, canSpeak = pcall(CanEditOfficerNote)
                return ok and canSpeak or false
            end

            return false
        end,
    },
    {
        key = "RAID",
        chatType = "RAID",
        altChatType = "RAID_WARNING",
        label = "R",
        tooltip = "Raid Chat",
        altTooltip = "Raid Warning",
        slash = "/ra ",
        slashAlias = "/raid",
        altSlash = "/rw ",
        altSlashAlias = "/raidwarning",
        isAvailable = function()
            return type(IsInRaid) == "function" and IsInRaid(LE_PARTY_CATEGORY_HOME) or false
        end,
        altIsAvailable = function()
            if type(IsInRaid) ~= "function" or not IsInRaid(LE_PARTY_CATEGORY_HOME) then
                return false
            end

            local isLeader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
            local isAssistant = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player", LE_PARTY_CATEGORY_HOME)
            return isLeader or isAssistant or false
        end,
    },
    {
        key = "PARTY",
        chatType = "PARTY",
        label = "P",
        tooltip = "Party Chat",
        slash = "/p ",
        slashAlias = "/party",
        isAvailable = function()
            if type(IsInGroup) ~= "function" or type(IsInRaid) ~= "function" then
                return false
            end
            return IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid(LE_PARTY_CATEGORY_HOME)
        end,
    },
    {
        key = "INSTANCE_CHAT",
        chatType = "INSTANCE_CHAT",
        label = "I",
        tooltip = "Instance Chat",
        tooltipNote = "Available only in instance groups formed through the group finder.",
        slash = "/i ",
        slashAlias = "/instance",
        isAvailable = function()
            return type(IsInGroup) == "function" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false
        end,
    },
    {
        key = "SAY",
        chatType = "SAY",
        label = "S",
        tooltip = "Say Chat",
        slash = "/s ",
        slashAlias = "/say",
        isAvailable = function()
            return true
        end,
    },
}

local function GetElvUIAnchorPanel(frame)
    local _, CH = GetElvUI()
    if not CH or not frame then
        return nil
    end

    if CH.LeftChatWindow and frame == CH.LeftChatWindow and _G.LeftChatPanel then
        return _G.LeftChatPanel
    elseif CH.RightChatWindow and frame == CH.RightChatWindow and _G.RightChatPanel then
        return _G.RightChatPanel
    end

    return nil
end

local function GetAnchorVisualFrame()
    local frame = GetAnchorFrame()
    if not frame then
        return nil
    end

    local theme = GetConfiguredTheme()
    if theme == "GW2UI" and HasGW2Chat() and frame.Container then
        return frame.Container
    end

    if theme == "ELVUI" and HasElvUIChat() then
        return GetElvUIAnchorPanel(frame) or frame
    end

    return frame
end

local function NormalizeChatFrame(candidate)
    if not candidate then
        return nil
    end

    if type(candidate) == "table" and candidate.chatFrame then
        candidate = candidate.chatFrame
    end

    if type(candidate) ~= "table" then
        return nil
    end

    if type(candidate.GetObjectType) == "function" then
        local ok, objectType = pcall(candidate.GetObjectType, candidate)
        if ok and (objectType == "ScrollingMessageFrame" or objectType == "Frame") then
            return candidate
        end
    end

    if candidate.editBox and type(candidate.editBox) == "table" and candidate.editBox.chatFrame then
        return candidate.editBox.chatFrame
    end

    return nil
end

local function GetSelectedDockFrame()
    if type(_G.FCFDock_GetSelectedWindow) == "function" and _G.GeneralDockManager then
        local ok, selected = pcall(_G.FCFDock_GetSelectedWindow, _G.GeneralDockManager)
        if ok then
            selected = NormalizeChatFrame(selected)
            if selected then
                return selected
            end
        end
    end

    if _G.GeneralDockManager then
        local selected = NormalizeChatFrame(_G.GeneralDockManager.selected)
        if selected then
            return selected
        end

        local primary = NormalizeChatFrame(_G.GeneralDockManager.primary)
        if primary then
            return primary
        end
    end

    return nil
end

local function GetLastActiveChatFrame()
    if type(_G.ChatEdit_GetLastActiveWindow) == "function" then
        local ok, result = pcall(_G.ChatEdit_GetLastActiveWindow)
        if ok then
            result = NormalizeChatFrame(result)
            if result then
                return result
            end
        end
    end

    if _G.ChatFrameUtil then
        local util = _G.ChatFrameUtil
        if type(util.GetLastActiveWindow) == "function" then
            local ok, result = pcall(util.GetLastActiveWindow, util)
            if ok then
                result = NormalizeChatFrame(result)
                if result then
                    return result
                end
            end
        end

        if type(util.GetActiveChatFrame) == "function" then
            local ok, result = pcall(util.GetActiveChatFrame, util)
            if ok then
                result = NormalizeChatFrame(result)
                if result then
                    return result
                end
            end
        end
    end

    return nil
end

GetAnchorFrame = function()
    local activeFrame = GetLastActiveChatFrame() or GetSelectedDockFrame()
    if activeFrame then
        return activeFrame
    end

    local _, CH = GetElvUI()
    if CH then
        local left = NormalizeChatFrame(CH.LeftChatWindow)
        if left then
            return left
        end

        local right = NormalizeChatFrame(CH.RightChatWindow)
        if right then
            return right
        end
    end

    return NormalizeChatFrame(_G.DEFAULT_CHAT_FRAME) or NormalizeChatFrame(_G.ChatFrame1) or _G.ChatFrame1 or DEFAULT_CHAT_FRAME
end

local function GetMainSidebarHostFrame()
    return NormalizeChatFrame(_G.DEFAULT_CHAT_FRAME) or NormalizeChatFrame(_G.ChatFrame1) or _G.ChatFrame1 or DEFAULT_CHAT_FRAME
end

local function GetMainSidebarButtonFrame()
    local frame = GetMainSidebarHostFrame()
    if not frame then
        return nil, nil
    end

    if frame.ButtonFrame then
        return frame.ButtonFrame, frame
    end

    if type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then
            local buttonFrame = _G[name .. "ButtonFrame"]
            if buttonFrame then
                return buttonFrame, frame
            end
        end
    end

    return nil, frame
end

local function GetSidebarButtonMetrics()
    local button = _G.ChatFrameChannelButton or _G.ChatFrameMenuButton
    local width = 26
    local height = 28

    if button then
        if type(button.GetWidth) == "function" then
            local ok, value = pcall(button.GetWidth, button)
            if ok and type(value) == "number" and value > 0 then
                width = math.floor(value + 0.5)
            end
        end
        if type(button.GetHeight) == "function" then
            local ok, value = pcall(button.GetHeight, button)
            if ok and type(value) == "number" and value > 0 then
                height = math.floor(value + 0.5)
            end
        end
    end

    return width, height
end

local function GetFrameIdentity(frame)
    if not frame then
        return "nil"
    end

    if type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return tostring(frame)
end

local function GetLayoutSignature()
    local db = GetDB() or {}
    local frame = GetAnchorFrame()
    local visualFrame = GetAnchorVisualFrame() or frame
    if not frame or not visualFrame then
        return nil
    end

    local width = visualFrame.GetWidth and math.floor((visualFrame:GetWidth() or 0) + 0.5) or 0
    local height = visualFrame.GetHeight and math.floor((visualFrame:GetHeight() or 0) + 0.5) or 0
    local strata = visualFrame.GetFrameStrata and visualFrame:GetFrameStrata() or "MEDIUM"
    local alpha = string.format("%.2f", GetConfiguredAlpha())
    local spacing = GetConfiguredSpacing()
    local scale = string.format("%.2f", GetConfiguredFontScale())
    local size = type(db.quickChatButtonSize) == "number" and math.floor(db.quickChatButtonSize + 0.5) or 24
    local gap = type(db.quickChatButtonGap) == "number" and math.floor(db.quickChatButtonGap + 0.5) or 18
    local yOffset = GetConfiguredButtonYOffset()
    local panelAlpha = string.format("%.2f", GetConfiguredPanelAlpha())
    local showQuickButtons = db.quickChatButtons ~= false
    local showSettingsButton = ShouldShowSettingsButton()

    return table.concat({
        GetConfiguredTheme(),
        GetFrameIdentity(frame),
        GetFrameIdentity(visualFrame),
        tostring(width),
        tostring(height),
        tostring(strata),
        tostring(size),
        tostring(gap),
        tostring(yOffset),
        tostring(spacing),
        tostring(scale),
        tostring(alpha),
        tostring(panelAlpha),
        tostring(showQuickButtons),
        tostring(showSettingsButton),
    }, "|")
end

local function GetAnchorParent()
    local visualFrame = GetAnchorVisualFrame()
    if visualFrame and visualFrame.GetParent then
        return visualFrame:GetParent() or UIParent
    end

    local frame = GetAnchorFrame()
    if frame and frame.GetParent then
        return frame:GetParent() or UIParent
    end
    return UIParent
end

local function GetActiveEditBox()
    local frame = GetAnchorFrame()
    if not frame or type(ns.GetEditBox) ~= "function" then
        return nil
    end
    return ns.GetEditBox(frame)
end

local function IsButtonEnabled(def)
    if type(def.isAvailable) ~= "function" then
        return true
    end
    local ok, enabled = pcall(def.isAvailable)
    return ok and enabled or false
end

local function IsAltButtonEnabled(def)
    if type(def.altIsAvailable) ~= "function" then
        return false
    end
    local ok, enabled = pcall(def.altIsAvailable)
    return ok and enabled or false
end

local function ResolveChatTarget(def, useAlt)
    if not def then
        return nil
    end

    if useAlt and def.altChatType and IsAltButtonEnabled(def) then
        return {
            chatType = def.altChatType,
            slash = def.altSlash or def.slash,
            isAlt = true,
        }
    end

    if not IsButtonEnabled(def) then
        return nil
    end

    return {
        chatType = def.chatType,
        slash = def.slash,
        isAlt = false,
    }
end

local function GetCurrentChatType()
    local editBox = GetActiveEditBox()
    if editBox then
        local chatType
        if editBox.GetAttribute then
            local ok, value = pcall(editBox.GetAttribute, editBox, "chatType")
            if ok and type(value) == "string" then
                chatType = value
            end
        end

        if type(chatType) ~= "string" and type(editBox.chatType) == "string" then
            chatType = editBox.chatType
        end

        if type(chatType) == "string" then
            return chatType
        end
    end
    return nil
end

UpdateButtonState = function()
    if not container then
        return
    end

    local currentChatType = GetCurrentChatType()
    for _, def in ipairs(BUTTON_DEFS) do
        local button = buttons[def.key]
        if button then
            local enabled = IsButtonEnabled(def)
            button:SetEnabled(true)
            if button.EnableMouse then
                button:EnableMouse(true)
            end
            button.__chatifyDisabled = not enabled
            button.__chatifySelected = enabled and (currentChatType == def.chatType or (def.altChatType and currentChatType == def.altChatType))

            if button.Label then
                if enabled then
                    button.Label:SetAlpha(1)
                else
                    button.Label:SetAlpha(0.88)
                end
            end

            RefreshButtonLook(button)
        end
    end

    if settingsButton then
        settingsButton:SetEnabled(true)
        if settingsButton.EnableMouse then
            settingsButton:EnableMouse(true)
        end
        settingsButton.__chatifyDisabled = false
        settingsButton.__chatifySelected = false
        if settingsButton.RefreshVisual then
            settingsButton:RefreshVisual()
        else
            RefreshButtonLook(settingsButton)
        end
    end
end

local function ActivateChatType(def, useAlt)
    local target = ResolveChatTarget(def, useAlt)
    if not target then
        return
    end

    local frame = GetAnchorFrame()
    if not frame then
        return
    end

    local setLastActiveWindow = _G.ChatEdit_SetLastActiveWindow
    if type(setLastActiveWindow) ~= "function" and _G.ChatFrameUtil and type(_G.ChatFrameUtil.SetLastActiveWindow) == "function" then
        setLastActiveWindow = function(chatFrame)
            return _G.ChatFrameUtil.SetLastActiveWindow(_G.ChatFrameUtil, chatFrame)
        end
    end

    if type(setLastActiveWindow) == "function" then
        pcall(setLastActiveWindow, frame)
    end

    local openChat = _G.ChatFrame_OpenChat
    if type(openChat) ~= "function" and _G.ChatFrameUtil and type(_G.ChatFrameUtil.OpenChat) == "function" then
        openChat = function(text, chatFrame)
            return _G.ChatFrameUtil.OpenChat(_G.ChatFrameUtil, text, chatFrame)
        end
    end

    local parseText = _G.ChatEdit_ParseText
    if type(parseText) ~= "function" then
        if _G.ChatFrameEditBoxMixin and type(_G.ChatFrameEditBoxMixin.ParseText) == "function" then
            parseText = function(editBox, send)
                return _G.ChatFrameEditBoxMixin.ParseText(editBox, send)
            end
        elseif _G.ChatFrameEditBoxBaseMixin and type(_G.ChatFrameEditBoxBaseMixin.ParseText) == "function" then
            parseText = function(editBox, send)
                return _G.ChatFrameEditBoxBaseMixin.ParseText(editBox, send)
            end
        end
    end

    local chooseBoxForSend = _G.ChatEdit_ChooseBoxForSend
    local editBox = GetActiveEditBox()
    if not editBox and type(chooseBoxForSend) == "function" then
        local ok, chosen = pcall(chooseBoxForSend, frame)
        if ok then
            editBox = chosen
        end
    end

    local existingText = ""
    if editBox and type(editBox.GetText) == "function" then
        local ok, text = pcall(editBox.GetText, editBox)
        if ok and type(text) == "string" then
            existingText = text
        end
    end

    local opened = false
    if type(openChat) == "function" and type(target.slash) == "string" then
        local ok = pcall(openChat, target.slash, frame)
        opened = ok and true or false
        editBox = GetActiveEditBox() or editBox
    end

    if not opened and type(openChat) == "function" then
        pcall(openChat, "", frame)
        editBox = GetActiveEditBox() or editBox
    end

    local switched = false
    local currentChatType = GetCurrentChatType()
    if currentChatType == target.chatType then
        switched = true
    end

    if not switched and editBox and type(parseText) == "function" and type(target.slash) == "string" then
        local parseBuffer = target.slash
        if existingText and existingText ~= "" then
            parseBuffer = target.slash .. existingText
        end

        if editBox.SetText then
            pcall(editBox.SetText, editBox, parseBuffer)
        end
        pcall(parseText, editBox, 0)
        editBox = GetActiveEditBox() or editBox
        currentChatType = GetCurrentChatType()
        switched = currentChatType == target.chatType
    end

    if editBox then
        if editBox.Show then
            pcall(editBox.Show, editBox)
        end
        if editBox.SetFocus then
            pcall(editBox.SetFocus, editBox)
        end
        if editBox.HighlightText then
            pcall(editBox.HighlightText, editBox, 0, 0)
        end
        if editBox.SetCursorPosition and type(editBox.GetText) == "function" then
            local ok, text = pcall(editBox.GetText, editBox)
            if ok and type(text) == "string" then
                pcall(editBox.SetCursorPosition, editBox, #text)
            end
        end
    end

    ScheduleButtonStateUpdate()
end


local function EnsureSocialSidebarButton()
    local sidebarFrame = GetMainSidebarButtonFrame()
    if not sidebarFrame then
        socialButton = nil
        return nil
    end

    local button = GetSocialSidebarButton()
    socialButton = button
    if not button then
        return nil
    end

    button:SetParent(sidebarFrame)
    button:SetScript("OnMouseDown", nil)
    button:SetScript("OnMouseUp", nil)
    button:ClearAllPoints()
    button:SetFrameStrata((sidebarFrame.GetFrameStrata and sidebarFrame:GetFrameStrata()) or "HIGH")
    if sidebarFrame.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((sidebarFrame:GetFrameLevel() or 1) + 2)
    end

    if not socialButtonHooked and type(hooksecurefunc) == "function" then
        socialButtonHooked = true
        local originalSetPoint = button.SetPoint
        hooksecurefunc(button, "SetPoint", function(_, _, frame)
            local currentSidebar = GetMainSidebarButtonFrame()
            if currentSidebar and frame ~= currentSidebar then
                button:SetParent(currentSidebar)
                button:ClearAllPoints()
                originalSetPoint(button, "TOP", currentSidebar, "TOP", 0, 0)
            end
        end)
    end

    return button
end

local function EnsureSettingsButtonVisual(self)
    if not self then
        return
    end

    if self._chatifyVisualReady then
        return
    end

    self._chatifyVisualReady = true
    self:SetNormalTexture("chatframe-button-up")
    self:SetPushedTexture("chatframe-button-down")
    self:SetHighlightTexture("chatframe-button-highlight")

    local icon = self:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(SETTINGS_ICON)
    icon:SetPoint("CENTER")
    icon:SetSize(12, 12)
    icon:SetVertexColor(0.925, 0.804, 0.063)
    self.Icon = icon

    self:HookScript("OnMouseDown", function(button)
        if button.Icon then
            button.Icon:AdjustPointsOffset(2, -2)
        end
    end)

    self:HookScript("OnMouseUp", function(button)
        if button.Icon then
            button.Icon:AdjustPointsOffset(-2, 2)
        end
    end)

    self:HookScript("OnEnter", function(button)
        if button.Icon then
            button.Icon:SetVertexColor(1.0, 0.90, 0.20)
        end
    end)

    self:HookScript("OnLeave", function(button)
        if button.Icon then
            button.Icon:SetVertexColor(0.925, 0.804, 0.063)
        end
    end)
end

local function RefreshSettingsButtonLook()
    if not settingsButton then
        return
    end

    EnsureSettingsButtonVisual(settingsButton)

    settingsButton:SetSize(26, 28)
    settingsButton:SetNormalTexture("chatframe-button-up")
    settingsButton:SetPushedTexture("chatframe-button-down")
    settingsButton:SetHighlightTexture("chatframe-button-highlight")

    if settingsButton.Icon then
        settingsButton.Icon:SetSize(12, 12)
        if settingsButton:IsMouseOver() then
            settingsButton.Icon:SetVertexColor(1.0, 0.90, 0.20)
        else
            settingsButton.Icon:SetVertexColor(0.925, 0.804, 0.063)
        end
        settingsButton.Icon:ClearAllPoints()
        settingsButton.Icon:SetPoint("CENTER")
    end
end

local function LayoutSettingsButton()
    if not settingsButton then
        return
    end

    local sidebarFrame, hostFrame = GetMainSidebarButtonFrame()
    if not sidebarFrame or not hostFrame then
        if settingsContainer then
            settingsContainer:Hide()
        end
        settingsButton:Hide()
        if socialButton then
            socialButton:Hide()
        end
        return
    end

    local social = EnsureSocialSidebarButton()
    local channelButton = _G.ChatFrameChannelButton
    local showSettings = ShouldShowSettingsButton()
    local showSidebar = social ~= nil or showSettings
    if not showSidebar then
        if settingsContainer then
            settingsContainer:Hide()
        end
        settingsButton:Hide()
        return
    end

    local buttonWidth = 26
    local buttonHeight = 28
    local spacing = 2
    local strata = (sidebarFrame.GetFrameStrata and sidebarFrame:GetFrameStrata()) or "HIGH"
    local frameLevel = (sidebarFrame.GetFrameLevel and sidebarFrame:GetFrameLevel()) or 1

    if settingsContainer then
        settingsContainer:SetParent(sidebarFrame)
        settingsContainer:ClearAllPoints()
        settingsContainer:SetAllPoints(sidebarFrame)
        settingsContainer:SetFrameStrata(strata)
        settingsContainer:SetFrameLevel(frameLevel + 1)
        settingsContainer:Show()
    end

    if channelButton then
        channelButton:SetParent(sidebarFrame)
        channelButton:ClearAllPoints()
        channelButton:SetFrameStrata(strata)
        if channelButton.SetFrameLevel then
            channelButton:SetFrameLevel(frameLevel + 2)
        end
        channelButton:SetSize(buttonWidth, buttonHeight)
    end

    local previousButton = nil

    if social then
        social:ClearAllPoints()
        social:SetPoint("TOP", sidebarFrame, "TOP", 0, 0)
        social:SetSize(buttonWidth, buttonHeight)
        social:SetFrameStrata(strata)
        if social.SetFrameLevel then
            social:SetFrameLevel(frameLevel + 2)
        end
        social:Show()
        previousButton = social
    end

    if channelButton then
        if previousButton then
            channelButton:SetPoint("TOP", previousButton, "BOTTOM", 0, -spacing)
        else
            channelButton:SetPoint("TOP", sidebarFrame, "TOP", 0, 0)
        end
        previousButton = channelButton
    end

    if showSettings then
        settingsButton:SetParent(sidebarFrame)
        settingsButton:ClearAllPoints()
        if previousButton then
            settingsButton:SetPoint("TOP", previousButton, "BOTTOM", 0, -spacing)
        else
            settingsButton:SetPoint("TOP", sidebarFrame, "TOP", 0, 0)
        end
        settingsButton:SetSize(buttonWidth, buttonHeight)
        settingsButton:SetFrameStrata(strata)
        if settingsButton.SetFrameLevel then
            settingsButton:SetFrameLevel(frameLevel + 2)
        end
        RefreshSettingsButtonLook()
        settingsButton:Show()
    else
        settingsButton:Hide()
    end
end

local function LayoutButtons()
    if not container then
        return
    end

    local db = GetDB()
    local configuredWidth = 26
    local sideGap = 18
    if db and type(db.quickChatButtonSize) == "number" then
        configuredWidth = math.max(16, math.min(40, math.floor(db.quickChatButtonSize + 0.5)))
    end
    if db and type(db.quickChatButtonGap) == "number" then
        sideGap = math.max(8, math.min(36, math.floor(db.quickChatButtonGap + 0.5)))
    end

    local frame = GetAnchorFrame()
    local visualFrame = GetAnchorVisualFrame()
    if not frame or not visualFrame then
        return
    end

    local spacing = GetConfiguredSpacing()
    local outerPadding = 0
    local orderedButtons = GetOrderedButtons()
    local buttonCount = #orderedButtons
    if buttonCount == 0 then
        container:SetSize(1, 1)
        for _, button in pairs(buttons) do
            if button then
                button:Hide()
            end
        end
        return
    end

    local sidebarWidth, sidebarHeight = GetSidebarButtonMetrics()
    local ratio = sidebarHeight / math.max(1, sidebarWidth)

    local buttonWidth = math.max(16, math.min(configuredWidth, 40))
    local buttonHeight = math.max(18, math.floor((buttonWidth * ratio) + 0.5))

    local chatHeight = math.max(1, math.floor((visualFrame.GetHeight and visualFrame:GetHeight()) or (frame.GetHeight and frame:GetHeight()) or 180))
    local fitHeight = math.max(chatHeight, math.floor(chatHeight * 1.35))
    local desiredTotalHeight = (buttonHeight * buttonCount) + (spacing * (buttonCount - 1))

    if desiredTotalHeight > fitHeight then
        local maxButtonHeight = math.floor((fitHeight - ((buttonCount - 1) * spacing) - (outerPadding * 2)) / buttonCount)
        if maxButtonHeight < 18 then
            maxButtonHeight = 18
        end
        buttonHeight = math.max(18, math.min(buttonHeight, maxButtonHeight))
        buttonWidth = math.max(16, math.floor((buttonHeight / math.max(ratio, 0.1)) + 0.5))
        desiredTotalHeight = (buttonHeight * buttonCount) + (spacing * (buttonCount - 1))
    end

    local totalHeight = desiredTotalHeight
    local holderHeight = totalHeight + (outerPadding * 2)

    container:ClearAllPoints()
    container:SetParent(GetAnchorParent())
    container:SetPoint("BOTTOMLEFT", visualFrame, "BOTTOMRIGHT", sideGap, GetConfiguredButtonYOffset())
    container:SetHeight(math.max(chatHeight, holderHeight))
    container:SetWidth(buttonWidth + 4)

    if container.SetFrameStrata then
        local strata = (visualFrame.GetFrameStrata and visualFrame:GetFrameStrata()) or (frame.GetFrameStrata and frame:GetFrameStrata()) or "MEDIUM"
        container:SetFrameStrata(strata)
    end
    if frame.GetFrameLevel and container.SetFrameLevel then
        container:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    end

    ApplyContainerStyle()

    local activeButtons = {}
    for _, button in ipairs(orderedButtons) do
        activeButtons[button] = true
    end

    for _, button in pairs(buttons) do
        if button then
            if activeButtons[button] then
                button:Show()
            else
                button:Hide()
            end
        end
    end

    local previous
    for _, button in ipairs(orderedButtons) do
        button:ClearAllPoints()
        button:SetSize(buttonWidth, buttonHeight)

        if previous then
            button:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
        else
            button:SetPoint("BOTTOM", container, "BOTTOM", 0, outerPadding)
        end

        if button.Label then
            local fontSize = math.max(10, math.floor(math.min(buttonWidth, buttonHeight) * 0.56 * GetConfiguredFontScale()))
            local fontPath = STANDARD_TEXT_FONT
            if GetConfiguredTheme() == "GW2UI" then
                fontPath = GetGW2ChatFont() or fontPath
            elseif ChatFontNormal and ChatFontNormal.GetFont then
                fontPath = ChatFontNormal:GetFont() or fontPath
            end
            pcall(button.Label.SetFont, button.Label, fontPath, fontSize, "OUTLINE")
            button.Label:ClearAllPoints()
            button.Label:SetPoint("CENTER", button, "CENTER", 0, 0)
        end

        if button.Icon then
            button.Icon:Hide()
        end

        if button.Highlight then
            button.Highlight:SetAllPoints(button)
        end

        previous = button
        RefreshButtonLook(button)
    end
end

local function HookAnchorFrameSignals()
    local frame = GetAnchorVisualFrame() or GetAnchorFrame()
    if not frame or frame == hookedAnchorFrame or not frame.HookScript then
        return
    end

    hookedAnchorFrame = frame
    frame:HookScript("OnSizeChanged", function()
        ScheduleRefresh(0.05)
    end)
    frame:HookScript("OnShow", function() ScheduleRefresh(0) end)
    frame:HookScript("OnHide", function() ScheduleRefresh(0) end)
end

local function HookEditBoxSignals()
    local editBox = GetActiveEditBox()
    if not editBox or editBox == hookedEditBox or not editBox.HookScript then
        return
    end

    hookedEditBox = editBox
    editBox:HookScript("OnShow", ScheduleButtonStateUpdate)
    editBox:HookScript("OnHide", ScheduleButtonStateUpdate)
    editBox:HookScript("OnEditFocusGained", ScheduleButtonStateUpdate)
    editBox:HookScript("OnEditFocusLost", ScheduleButtonStateUpdate)
    editBox:HookScript("OnTextChanged", ScheduleButtonStateUpdate)
end

local function EnsureContainer()
    if container then
        return
    end

    local parent = GetAnchorParent()
    container = CreateFrame("Frame", "ChatifyQuickChatButtons", parent, backdropTemplate)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)

    for _, def in ipairs(BUTTON_DEFS) do
        local button = CreateFrame("Button", "ChatifyQuickChatButton" .. def.key, container, backdropTemplate)
        button:RegisterForClicks("LeftButtonUp")
        button:SetHitRectInsets(0, 0, 0, 0)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:SetBlendMode("ADD")
        highlight:SetVertexColor(1.0, 0.85, 0.25, 0.00)
        highlight:SetAllPoints(button)
        button.Highlight = highlight

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        label:SetText(def.label)
        button.Label = label

        button:SetScript("OnClick", function(self, mouseButton)
            if self.__chatifyDisabled then
                return
            end
            local useAlt = mouseButton == "LeftButton" and IsAltKeyDown()
            ActivateChatType(def, useAlt)
        end)

        button:SetScript("OnEnter", function(self)
            RefreshButtonLook(self)
            if GameTooltip then
                local enabled = IsButtonEnabled(def)
                local altEnabled = def.altChatType and IsAltButtonEnabled(def) or false

                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(def.tooltip, 1.00, 0.82, 0.18, true)
                AddTooltipLine("Command", string.format("%s  |cff8f8f8f%s|r", def.slash:gsub("%s+$", ""), def.slashAlias or ""), 0.90, 0.90, 0.90)

                if def.tooltipNote then
                    AddTooltipLine(def.tooltipNote, nil, 0.72, 0.82, 1.00, true)
                end

                AddTooltipLine(" ")
                AddTooltipLine("Left Click", "Switch to this channel", 0.95, 0.95, 0.95)

                if def.altChatType then
                    AddTooltipLine("Alt Command", string.format("%s  |cff8f8f8f%s|r", (def.altSlash or ""):gsub("%s+$", ""), def.altSlashAlias or ""), 0.72, 0.82, 1.00)
                    if altEnabled then
                        AddTooltipLine("Alt + Left Click", string.format("Switch to %s", def.altTooltip or def.altChatType), 0.72, 0.82, 1.00)
                    else
                        AddTooltipLine("Alt + Left Click", string.format("%s unavailable", def.altTooltip or "Alternate channel"), 0.62, 0.62, 0.62)
                    end
                end

                AddTooltipLine(" ")
                if enabled then
                    AddTooltipLine("Status", "Available", 0.35, 0.95, 0.55)
                else
                    AddTooltipLine("Status", "Unavailable", 1.00, 0.35, 0.35)
                end

                AddTooltipLine("Position", "Right side of the chat frame", 0.72, 0.72, 0.72)
                local skinLabel = "Standard"
                if GetConfiguredTheme() == "ELVUI" then
                    skinLabel = "ElvUI"
                elseif GetConfiguredTheme() == "GW2UI" then
                    skinLabel = "GW2 UI"
                end
                AddTooltipLine("Skin", skinLabel, 0.72, 0.72, 0.72)
                GameTooltip:Show()
            end
        end)

        button:SetScript("OnLeave", function(self)
            self.__chatifyPressed = false
            RefreshButtonLook(self)
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        button:SetScript("OnMouseDown", function(self)
            self.__chatifyPressed = true
            if self.Label then
                self.Label:ClearAllPoints()
                self.Label:SetPoint("CENTER", self, "CENTER", 1, -1)
            end
            RefreshButtonLook(self)
        end)

        button:SetScript("OnMouseUp", function(self)
            self.__chatifyPressed = false
            if self.Label then
                self.Label:ClearAllPoints()
                self.Label:SetPoint("CENTER", self, "CENTER", 0, 0)
            end
            RefreshButtonLook(self)
        end)

        buttons[def.key] = button
    end

    settingsContainer = CreateFrame("Frame", "ChatifyChatMenuSettingsContainer", GetAnchorParent(), backdropTemplate)
    settingsContainer:SetFrameStrata("MEDIUM")
    settingsContainer:SetClampedToScreen(true)

    settingsButton = CreateFrame("Button", "ChatifyChatMenuSettingsButton", settingsContainer, backdropTemplate)
    settingsButton:RegisterForClicks("LeftButtonUp")
    settingsButton:SetHitRectInsets(0, 0, 0, 0)
    settingsButton.RefreshVisual = RefreshSettingsButtonLook

    settingsButton:SetScript("OnClick", function()
        if Chatify and type(Chatify.OpenConfig) == "function" then
            Chatify:OpenConfig()
        end
    end)

    settingsButton:SetScript("OnEnter", function(self)
        RefreshSettingsButtonLook()
        if GameTooltip then
            local skinLabel = "Standard"
            if GetConfiguredTheme() == "ELVUI" then
                skinLabel = "ElvUI"
            elseif GetConfiguredTheme() == "GW2UI" then
                skinLabel = "GW2 UI"
            end

            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Chatify Settings", 1.00, 0.82, 0.18, true)
            AddTooltipLine("Left Click", "Open Chatify configuration", 0.95, 0.95, 0.95)
            AddTooltipLine("Position", "Main chat button panel", 0.72, 0.72, 0.72)
            AddTooltipLine("Skin", skinLabel, 0.72, 0.72, 0.72)
            GameTooltip:Show()
        end
    end)

    settingsButton:SetScript("OnLeave", function()
        RefreshSettingsButtonLook()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end


local function HookGeneralRefreshSignals()
    if generalHooksInstalled or type(hooksecurefunc) ~= "function" then
        return
    end

    if type(_G.FCF_DockUpdate) == "function" then
        hooksecurefunc("FCF_DockUpdate", function()
            ScheduleRefresh(0)
        end)
    end

    if type(_G.FCFDock_SelectWindow) == "function" then
        hooksecurefunc("FCFDock_SelectWindow", function()
            ScheduleRefresh(0)
            ScheduleButtonStateUpdate()
        end)
    end

    if type(_G.FCF_SelectDockFrame) == "function" then
        hooksecurefunc("FCF_SelectDockFrame", function()
            ScheduleRefresh(0)
            ScheduleButtonStateUpdate()
        end)
    end

    if type(_G.FloatingChatFrame_Update) == "function" then
        hooksecurefunc("FloatingChatFrame_Update", function()
            ScheduleRefresh(0)
        end)
    end

    if type(_G.ChatEdit_UpdateHeader) == "function" then
        hooksecurefunc("ChatEdit_UpdateHeader", function()
            ScheduleButtonStateUpdate()
        end)
    end

    if _G.ChatFrameUtil then
        if type(_G.ChatFrameUtil.ActivateChat) == "function" then
            hooksecurefunc(_G.ChatFrameUtil, "ActivateChat", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatFrameUtil.DeactivateChat) == "function" then
            hooksecurefunc(_G.ChatFrameUtil, "DeactivateChat", function()
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatFrameUtil.SetLastActiveWindow) == "function" then
            hooksecurefunc(_G.ChatFrameUtil, "SetLastActiveWindow", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end
    else
        if type(_G.ChatEdit_ActivateChat) == "function" then
            hooksecurefunc("ChatEdit_ActivateChat", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatEdit_DeactivateChat) == "function" then
            hooksecurefunc("ChatEdit_DeactivateChat", function()
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatEdit_SetLastActiveWindow) == "function" then
            hooksecurefunc("ChatEdit_SetLastActiveWindow", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end
    end

    generalHooksInstalled = true
end

local function HookGW2RefreshSignals()
    if type(hooksecurefunc) ~= "function" then
        return
    end

    local GW = GetGW2()
    if not GW then
        return
    end

    if not gw2HooksInstalled and type(GW.UpdateChatSettings) == "function" then
        hooksecurefunc(GW, "UpdateChatSettings", function()
            ScheduleRefresh(0)
        end)
    end

    local frame = GetAnchorFrame()
    if frame and frame.Container and frame.Container.HookScript and not frame.Container.__chatifyGW2Hooked then
        frame.Container:HookScript("OnShow", function() ScheduleRefresh(0) end)
        frame.Container:HookScript("OnHide", function() ScheduleRefresh(0) end)
        frame.Container:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        frame.Container.__chatifyGW2Hooked = true
    end

    local background = frame and frame.GetName and _G[frame:GetName() .. "Background"]
    if background and background.HookScript and not background.__chatifyGW2Hooked then
        background:HookScript("OnShow", function() ScheduleRefresh(0) end)
        background:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        background.__chatifyGW2Hooked = true
    end

    if _G.GeneralDockManager and _G.GeneralDockManager.HookScript and not _G.GeneralDockManager.__chatifyGW2Hooked then
        _G.GeneralDockManager:HookScript("OnShow", function() ScheduleRefresh(0) end)
        _G.GeneralDockManager:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        _G.GeneralDockManager.__chatifyGW2Hooked = true
    end

    gw2HooksInstalled = true
end

local function HookElvUIRefreshSignals()
    if elvuiHooksInstalled or type(hooksecurefunc) ~= "function" then
        return
    end

    local _, CH = GetElvUI()
    if not CH then
        return
    end

    local function hookMethod(name)
        if type(CH[name]) == "function" then
            hooksecurefunc(CH, name, function()
                ScheduleRefresh(0)
            end)
        end
    end

    hookMethod("SetupChat")
    hookMethod("PositionChat")
    hookMethod("PositionChats")
    hookMethod("UpdateSettings")
    hookMethod("UpdateEditboxAnchors")
    hookMethod("UpdateChatTabs")
    hookMethod("Panel_ColorUpdate")
    hookMethod("Panels_ColorUpdate")
    hookMethod("UpdateChatTabColors")
    hookMethod("StyleChat")
    hookMethod("FCF_SetWindowAlpha")

    if _G.LeftChatToggleButton and _G.LeftChatToggleButton.HookScript and not _G.LeftChatToggleButton.__chatifyElvUIHooked then
        _G.LeftChatToggleButton:HookScript("OnClick", function() ScheduleRefresh(0) end)
        _G.LeftChatToggleButton.__chatifyElvUIHooked = true
    end

    if _G.RightChatToggleButton and _G.RightChatToggleButton.HookScript and not _G.RightChatToggleButton.__chatifyElvUIHooked then
        _G.RightChatToggleButton:HookScript("OnClick", function() ScheduleRefresh(0) end)
        _G.RightChatToggleButton.__chatifyElvUIHooked = true
    end

    if _G.LeftChatPanel and _G.LeftChatPanel.HookScript and not _G.LeftChatPanel.__chatifyElvUIHooked then
        _G.LeftChatPanel:HookScript("OnShow", function() ScheduleRefresh(0) end)
        _G.LeftChatPanel:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        _G.LeftChatPanel.__chatifyElvUIHooked = true
    end

    if _G.RightChatPanel and _G.RightChatPanel.HookScript and not _G.RightChatPanel.__chatifyElvUIHooked then
        _G.RightChatPanel:HookScript("OnShow", function() ScheduleRefresh(0) end)
        _G.RightChatPanel:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        _G.RightChatPanel.__chatifyElvUIHooked = true
    end

    elvuiHooksInstalled = true
end

function ns.RefreshQuickChatButtons()
    local db = GetDB()
    local showQuickButtons = db and db.quickChatButtons ~= false
    local showSettingsButton = ShouldShowSettingsButton()
    local showSidebarMenu = ShouldShowSidebarMenu()

    if not db or (not showQuickButtons and not showSidebarMenu) then
        lastLayoutSignature = nil
        if container then
            container:Hide()
        end
        if settingsContainer then
            settingsContainer:Hide()
        end
        return
    end

    HookGeneralRefreshSignals()

    if HasGW2Chat() then
        HookGW2RefreshSignals()
    end

    if HasElvUIChat() then
        HookElvUIRefreshSignals()
    end

    HookAnchorFrameSignals()
    HookEditBoxSignals()

    EnsureContainer()
    local layoutSignature = GetLayoutSignature()
    if layoutSignature ~= lastLayoutSignature or not container:IsShown() or (showSidebarMenu and settingsContainer and not settingsContainer:IsShown()) then
        LayoutButtons()
        LayoutSettingsButton()
        lastLayoutSignature = layoutSignature
    end

    UpdateButtonState()

    if showQuickButtons then
        container:Show()
    elseif container then
        container:Hide()
    end

    if showSidebarMenu then
        LayoutSettingsButton()
    elseif settingsContainer then
        settingsContainer:Hide()
    end
end

function QuickButtonsModule:Refresh()
    ns.RefreshQuickChatButtons()
end

function QuickButtonsModule:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "Refresh")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "Refresh")
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "Refresh")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "Refresh")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "Refresh")
    self:RegisterEvent("CHANNEL_UI_UPDATE", "Refresh")
    self:RegisterEvent("MODIFIER_STATE_CHANGED", function() ScheduleButtonStateUpdate() end)
    self:RegisterEvent("DISPLAY_SIZE_CHANGED", "Refresh")
    self:RegisterEvent("UI_SCALE_CHANGED", "Refresh")
    self:RegisterEvent("CVAR_UPDATE", function(_, cvar)
        if cvar == "useUiScale" or cvar == "uiScale" then
            self:Refresh()
        end
    end)
    self:RegisterEvent("ADDON_LOADED", function(_, addon)
        if addon == "ElvUI" then
            elvuiEngine = nil
            elvuiChat = nil
            elvuiHooksInstalled = false
            ScheduleRefresh(0)
            ScheduleRefresh(1)
        elseif addon == "GW2_UI" then
            gw2Engine = nil
            gw2HooksInstalled = false
            ScheduleRefresh(0)
            ScheduleRefresh(1)
        end
    end)

    ns.RefreshQuickChatButtons()

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.RefreshQuickChatButtons() end)
        C_Timer.After(1, function() ns.RefreshQuickChatButtons() end)
    end
end
