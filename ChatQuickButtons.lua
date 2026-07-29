local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local QuickButtonsModule = Chatify:NewModule("QuickButtons", "AceEvent-3.0")
local T = (ns.Locale and ns.Locale.Get and function(text) return ns.Locale:Get(text) end) or function(text) return text end
local ACD = LibStub("AceConfigDialog-3.0", true)

local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local unpack = unpack or table.unpack
local container
local settingsContainer
local settingsButton
local copyButton
local historyButton
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
local GetConfiguredChatFontPath
local GetAnchorFrame
local MixColor
local elvuiEngine
local elvuiChat
local gw2Engine
local UpdateButtonState
local RefreshCopyButtonLook
local RefreshHistoryButtonLook
local elvuiHooksInstalled = false
local gw2HooksInstalled = false
local generalHooksInstalled = false
local refreshQueued = false
local stateUpdateQueued = false
local lastLayoutSignature
local lastStateSignature
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

local function HomePartyCategory()
    return _G.LE_PARTY_CATEGORY_HOME or 1
end

local function InstancePartyCategory()
    return _G.LE_PARTY_CATEGORY_INSTANCE or 2
end

local GW2_TEXTURE_PATH = "Interface\\AddOns\\Chatify\\assets\\themes\\gw2\\"
local TRANSPARENT_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local GW2_BUTTON_NORMAL = GW2_TEXTURE_PATH .. "channel_button_normal.png"
local GW2_BUTTON_HIGHLIGHT = GW2_TEXTURE_PATH .. "channel_button_normal_highlight.png"
local GW2_BUTTON_ACTIVE = GW2_TEXTURE_PATH .. "channel_button_vc.png"
local GW2_BUTTON_ACTIVE_HIGHLIGHT = GW2_TEXTURE_PATH .. "channel_button_vc_highlight.png"
local GW2_CONTAINER_BG = GW2_TEXTURE_PATH .. "chatframebackground.png"
local GW2_CONTAINER_BORDER = GW2_TEXTURE_PATH .. "chatframeborder.png"
local DEFAULT_SIDEBAR_BUTTON_WIDTH = 26
local DEFAULT_SIDEBAR_BUTTON_HEIGHT = 28
local DEFAULT_SIDEBAR_BUTTON_RATIO = DEFAULT_SIDEBAR_BUTTON_HEIGHT / DEFAULT_SIDEBAR_BUTTON_WIDTH
local MIN_STABLE_CHAT_FRAME_WIDTH = 120
local MIN_STABLE_CHAT_FRAME_HEIGHT = 80
local SETTINGS_ICON = "Interface\\AddOns\\Chatify\\assets\\icons\\SettingsCog.png"
local COPY_CHAT_ICON = "Interface\\AddOns\\Chatify\\assets\\icons\\CopyChat.png"
local HISTORY_CHAT_ICON = "Interface\\AddOns\\Chatify\\assets\\icons\\HistoryChat.png"


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
    local loaded = type(ns.IsAddOnLoadedCompat) == "function" and ns.IsAddOnLoadedCompat("ElvUI") or (type(IsAddOnLoaded) == "function" and IsAddOnLoaded("ElvUI"))
    if not loaded or not _G.ElvUI then
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
    local loaded = type(ns.IsAddOnLoadedCompat) == "function" and ns.IsAddOnLoadedCompat("GW2_UI") or (type(IsAddOnLoaded) == "function" and IsAddOnLoaded("GW2_UI"))
    if not loaded or not _G.GW then
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


local function GetCompatState()
    if type(ns.GetChatAddonCompatibilityState) == "function" then
        return ns.GetChatAddonCompatibilityState()
    end
    return nil
end

local function ForceDetachedSidebarLayout()
    local state = GetCompatState()
    return state and state.safeQuickButtonMode == "detached" or false
end

local function InvalidateQuickButtonLayout(reason)
    lastLayoutSignature = nil
    lastStateSignature = nil
    if type(ns.IncrementRuntimeCounter) == "function" then
        ns.IncrementRuntimeCounter("quickbuttons:" .. tostring(reason or "invalidate"))
    end
end

local delayedRefreshToken = 0

local function SafeRun(label, func, ...)
    if type(ns.SafeCall) == "function" then
        return ns.SafeCall(label, func, ...)
    end
    if type(func) == "function" then
        return pcall(func, ...)
    end
    return false
end

local function ScheduleRefresh(delay)
    delay = tonumber(delay) or 0
    if delay < 0 then
        delay = 0
    end

    local after = ns.SafeAfter
    if type(after) ~= "function" and (not C_Timer or not C_Timer.After) then
        SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons)
        return
    end

    if delay > 0 then
        delayedRefreshToken = delayedRefreshToken + 1
        local token = delayedRefreshToken
        if type(after) == "function" then
            after(delay, function()
                if token ~= delayedRefreshToken then
                    return
                end
                SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons)
            end)
        else
            C_Timer.After(delay, function()
                if token ~= delayedRefreshToken then
                    return
                end
                SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons)
            end)
        end
        return
    end

    if refreshQueued then
        return
    end

    refreshQueued = true
    local function runRefresh()
        refreshQueued = false
        SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons)
    end
    if type(after) == "function" then
        after(0, runRefresh)
    else
        C_Timer.After(0, runRefresh)
    end
end

local function ScheduleButtonStateUpdate()
    local after = ns.SafeAfter
    if type(after) ~= "function" and (not C_Timer or not C_Timer.After) then
        SafeRun("QuickButtons.UpdateState", UpdateButtonState)
        return
    end

    if stateUpdateQueued then
        return
    end

    stateUpdateQueued = true
    local function runUpdate()
        stateUpdateQueued = false
        SafeRun("QuickButtons.UpdateState", UpdateButtonState)
    end
    if type(after) == "function" then
        after(0, runUpdate)
    else
        C_Timer.After(0, runUpdate)
    end
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

local function RestoreManagedTextureRegion(region, button, alpha, blendMode, visible)
    if not region or not button then
        return
    end

    region:ClearAllPoints()
    region:SetAllPoints(button)

    if type(region.SetBlendMode) == "function" and type(blendMode) == "string" then
        region:SetBlendMode(blendMode)
    end

    if type(region.SetVertexColor) == "function" then
        region:SetVertexColor(1, 1, 1, 1)
    end

    if type(region.SetAlpha) == "function" then
        region:SetAlpha(type(alpha) == "number" and alpha or 1)
    end

    if visible == true and type(region.Show) == "function" then
        region:Show()
    elseif visible == false and type(region.Hide) == "function" then
        region:Hide()
    end
end

local function ApplyStandardButtonTextures(button, enabled, selected, pressed, hovered)
    if not button then
        return
    end

    local normalTexture = (selected or pressed) and "chatframe-button-down" or "chatframe-button-up"
    local highlightAlpha = 0
    if enabled and hovered then
        highlightAlpha = selected and 0.8 or 1
    end

    pcall(button.SetNormalTexture, button, normalTexture)
    pcall(button.SetPushedTexture, button, "chatframe-button-down")
    pcall(button.SetDisabledTexture, button, "chatframe-button-up")
    pcall(button.SetHighlightTexture, button, "chatframe-button-highlight")

    RestoreManagedTextureRegion(type(button.GetNormalTexture) == "function" and button:GetNormalTexture() or nil, button, enabled and 1 or 0.92, "BLEND", true)
    RestoreManagedTextureRegion(type(button.GetPushedTexture) == "function" and button:GetPushedTexture() or nil, button, 1, "BLEND", pressed == true)
    RestoreManagedTextureRegion(type(button.GetDisabledTexture) == "function" and button:GetDisabledTexture() or nil, button, 0, "BLEND", false)
    RestoreManagedTextureRegion(type(button.GetHighlightTexture) == "function" and button:GetHighlightTexture() or nil, button, highlightAlpha, "ADD", hovered == true and enabled == true)
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

    local genericBg = container:CreateTexture(nil, "BACKGROUND")
    genericBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    genericBg:SetAllPoints(container)
    container.GenericBg = genericBg

    local genericLeft = container:CreateTexture(nil, "BORDER")
    genericLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    genericLeft:SetPoint("TOPLEFT", container, "TOPLEFT", -2, 0)
    genericLeft:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", -2, 0)
    genericLeft:SetWidth(2)
    container.GenericBorderLeft = genericLeft

    local genericRight = container:CreateTexture(nil, "BORDER")
    genericRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    genericRight:SetPoint("TOPRIGHT", container, "TOPRIGHT", 2, 0)
    genericRight:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 2, 0)
    genericRight:SetWidth(2)
    container.GenericBorderRight = genericRight

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
    if container.GenericBg then container.GenericBg:Hide() end
    if container.GenericBorderLeft then container.GenericBorderLeft:Hide() end
    if container.GenericBorderRight then container.GenericBorderRight:Hide() end
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
            text = { 0.62, 0.54, 0.20 },
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
            text = { 1.0, 0.92, 0.24 },
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
            text = { 1.0, 0.90, 0.20 },
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
        text = { 0.925, 0.804, 0.063 },
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
            button.Highlight:Show()
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
            button.Highlight:Show()
        end
    else
        ApplyStandardButtonTextures(button, enabled, selected, pressed, hovered)
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
            button.Highlight:SetVertexColor(1.0, 0.82, 0.18, 0.0)
            button.Highlight:Hide()
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
        local fontPath = GetConfiguredChatFontPath(theme)
        if type(ns.SafeSetFont) == "function" then
            ns.SafeSetFont(button.Label, fontPath, fontSize, "OUTLINE", STANDARD_TEXT_FONT)
        else
            pcall(button.Label.SetFont, button.Label, fontPath, fontSize, "OUTLINE")
        end
        button.Label:ClearAllPoints()
        button.Label:SetPoint("CENTER", button, "CENTER", pressed and 1 or 0, pressed and -1 or 0)

        local textColor = palette.text
        if theme == "STANDARD" then
            if not enabled then
                textColor = { 0.62, 0.54, 0.20 }
            elseif pressed then
                textColor = { 1.0, 0.94, 0.30 }
            elseif hovered then
                textColor = { 1.0, 0.90, 0.20 }
            elseif selected then
                textColor = { 1.0, 0.92, 0.24 }
            else
                textColor = { 0.925, 0.804, 0.063 }
            end
        end
        button.Label:SetTextColor(textColor[1], textColor[2], textColor[3], enabled and 1 or 0.90)
    end
end

local function ApplyContainerStyle()
    if not container then
        return
    end

    local panelAlpha = GetConfiguredPanelAlpha()
    local theme = GetConfiguredTheme()
    local bgR, bgG, bgB, bgA = 0.02, 0.02, 0.03, panelAlpha
    local borderR, borderG, borderB, borderA = 0.38, 0.28, 0.10, math.min(1, panelAlpha * 1.8)

    if theme == "ELVUI" then
        local pr, pg, pb, pa = GetElvUIPanelColor()
        local E = GetElvUI()
        bgR, bgG, bgB, bgA = pr, pg, pb, math.min(1, math.max(panelAlpha, pa * 0.92))
        if E and E.media then
            borderR, borderG, borderB = GetColorComponents(E.media.bordercolor, { 0.12, 0.12, 0.12 })
        else
            borderR, borderG, borderB = 0.12, 0.12, 0.12
        end
        borderA = math.min(1, 0.88 + (panelAlpha * 0.12))
    end

    local styleSignature = string.format("%s|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", theme, panelAlpha, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    if container.__chatifyStyleSignature == styleSignature then
        return
    end
    container.__chatifyStyleSignature = styleSignature

    HideContainerThemeTextures()

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

    EnsureContainerArt()
    if panelAlpha > 0.01 and container.GenericBg then
        container.GenericBg:Show()
        container.GenericBg:SetVertexColor(bgR, bgG, bgB, bgA)
    end
    if panelAlpha > 0.01 and container.GenericBorderLeft then
        container.GenericBorderLeft:Show()
        container.GenericBorderLeft:SetVertexColor(borderR, borderG, borderB, borderA)
    end
    if panelAlpha > 0.01 and container.GenericBorderRight then
        container.GenericBorderRight:Show()
        container.GenericBorderRight:SetVertexColor(borderR, borderG, borderB, borderA)
    end

    if type(container.SetBackdrop) == "function" then
        if not container._chatifyBackdropSet then
            container:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
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

        container:SetBackdropColor(bgR, bgG, bgB, math.min(bgA, panelAlpha * 0.85))
        container:SetBackdropBorderColor(borderR, borderG, borderB, math.min(borderA, math.max(0.18, panelAlpha)))
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
    -- Classic-era clients already own the chat menu/scroll stack. Do not
    -- steal the global social/micro button into the chat button frame there;
    -- it breaks BCC/Vanilla/Wrath/Titan/Mists layouts where the native stack
    -- contains scroll buttons instead of the Retail social/channel pair.
    if type(ns.IsClassicClient) == "function" then
        local ok, classic = pcall(ns.IsClassicClient)
        if ok and classic then
            return nil
        end
    end

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
    InvalidateQuickButtonLayout("settings")
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

GetConfiguredChatFontPath = function(theme)
    local db = GetDB()
    if db and type(ns.ResolveFontPath) == "function" then
        local ok, fontPath = pcall(ns.ResolveFontPath, db.fontID)
        if ok and type(fontPath) == "string" and fontPath ~= "" then
            return fontPath
        end
    end

    if theme == "GW2UI" then
        local gw2Font = GetGW2ChatFont()
        if type(gw2Font) == "string" and gw2Font ~= "" then
            return gw2Font
        end
    end

    if ChatFontNormal and ChatFontNormal.GetFont then
        local fontPath = ChatFontNormal:GetFont()
        if type(fontPath) == "string" and fontPath ~= "" then
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
        altLabel = "O",
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
        altLabel = "RW",
        tooltip = "Raid Chat",
        altTooltip = "Raid Warning",
        slash = "/ra ",
        slashAlias = "/raid",
        altSlash = "/rw ",
        altSlashAlias = "/raidwarning",
        isAvailable = function()
            return type(IsInRaid) == "function" and IsInRaid(HomePartyCategory()) or false
        end,
        altIsAvailable = function()
            if type(IsInRaid) ~= "function" or not IsInRaid(HomePartyCategory()) then
                return false
            end

            local isLeader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player", HomePartyCategory())
            local isAssistant = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player", HomePartyCategory())
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
            return IsInGroup(HomePartyCategory()) and not IsInRaid(HomePartyCategory())
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
            return type(IsInGroup) == "function" and IsInGroup(InstancePartyCategory()) or false
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
            -- Plain call: the namespace is a function table, not a mixin.
            local ok, result = pcall(util.GetLastActiveWindow)
            if ok then
                result = NormalizeChatFrame(result)
                if result then
                    return result
                end
            end
        end

        if type(util.GetActiveChatFrame) == "function" then
            -- Plain call: the namespace is a function table, not a mixin.
            local ok, result = pcall(util.GetActiveChatFrame)
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

    if frame.buttonFrame then
        return frame.buttonFrame, frame
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
    local width = DEFAULT_SIDEBAR_BUTTON_WIDTH
    local height = DEFAULT_SIDEBAR_BUTTON_HEIGHT

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

local function IsDetachedClassicSidebarLayout()
    if ForceDetachedSidebarLayout() then
        return true
    end

    if type(ns.IsClassicClient) == "function" then
        local ok, classic = pcall(ns.IsClassicClient)
        if ok and classic then
            return true
        end
    end

    if type(ns.GetProjectKey) == "function" then
        local ok, key = pcall(ns.GetProjectKey)
        if ok then
            return key == "vanilla"
                or key == "tbc"
                or key == "bcc"
                or key == "wrath"
                or key == "titan"
                or key == "mists"
                or key == "cata"
        end
    end

    local project = _G.WOW_PROJECT_ID
    return project ~= nil and _G.WOW_PROJECT_MAINLINE ~= nil and project ~= _G.WOW_PROJECT_MAINLINE
end

local function SafeFrameCenterX(frame)
    if not frame then
        return nil
    end

    if frame.GetCenter then
        local ok, x = pcall(frame.GetCenter, frame)
        if ok and type(x) == "number" then
            return x
        end
    end

    if frame.GetLeft and frame.GetRight then
        local okLeft, left = pcall(frame.GetLeft, frame)
        local okRight, right = pcall(frame.GetRight, frame)
        if okLeft and okRight and type(left) == "number" and type(right) == "number" then
            return (left + right) * 0.5
        end
    end

    return nil
end

local function GetClassicSidebarSide(sidebarFrame, hostFrame)
    local side
    if hostFrame then
        if type(hostFrame.buttonSide) == "string" then
            side = hostFrame.buttonSide
        elseif hostFrame.GetAttribute then
            local ok, value = pcall(hostFrame.GetAttribute, hostFrame, "buttonSide")
            if ok and type(value) == "string" then
                side = value
            end
        end
    end

    if type(side) == "string" then
        side = string.lower(side)
        if string.find(side, "left", 1, true) then
            return "LEFT"
        elseif string.find(side, "right", 1, true) then
            return "RIGHT"
        end
    end

    local sidebarCenter = SafeFrameCenterX(sidebarFrame)
    local hostCenter = SafeFrameCenterX(hostFrame)
    if sidebarCenter and hostCenter and sidebarCenter < hostCenter then
        return "LEFT"
    end

    return "RIGHT"
end

local function GetConfiguredButtonMetrics()
    local db = GetDB()
    local configuredWidth = DEFAULT_SIDEBAR_BUTTON_WIDTH
    if db and type(db.quickChatButtonSize) == "number" then
        configuredWidth = math.max(16, math.min(40, math.floor(db.quickChatButtonSize + 0.5)))
    end

    local ratio = DEFAULT_SIDEBAR_BUTTON_RATIO
    local sidebarWidth, sidebarHeight = GetSidebarButtonMetrics()
    if type(sidebarWidth) == "number" and type(sidebarHeight) == "number" and sidebarWidth > 0 and sidebarHeight > 0 then
        ratio = sidebarHeight / sidebarWidth
        if ratio < 0.85 or ratio > 1.35 then
            ratio = DEFAULT_SIDEBAR_BUTTON_RATIO
        end
    end

    local configuredHeight = math.max(18, math.floor((configuredWidth * ratio) + 0.5))
    return math.floor(configuredWidth + 0.5), math.floor(configuredHeight + 0.5), ratio
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
    local size = type(db.quickChatButtonSize) == "number" and math.floor(db.quickChatButtonSize + 0.5) or DEFAULT_SIDEBAR_BUTTON_WIDTH
    local _, buttonHeight, buttonRatio = GetConfiguredButtonMetrics()
    local ratio = string.format("%.3f", buttonRatio or DEFAULT_SIDEBAR_BUTTON_RATIO)
    local buttonHeightSignature = tostring(buttonHeight or DEFAULT_SIDEBAR_BUTTON_HEIGHT)
    local gap = type(db.quickChatButtonGap) == "number" and math.floor(db.quickChatButtonGap + 0.5) or 18
    local yOffset = GetConfiguredButtonYOffset()
    local panelAlpha = string.format("%.2f", GetConfiguredPanelAlpha())
    local showQuickButtons = db.quickChatButtons ~= false
    local showSettingsButton = ShouldShowSettingsButton()
    local sidebarFrame, sidebarHostFrame = GetMainSidebarButtonFrame()
    local sidebarMode = IsDetachedClassicSidebarLayout() and "classic-detached" or "native-stack"
    local sidebarSide = sidebarFrame and GetClassicSidebarSide(sidebarFrame, sidebarHostFrame) or "none"
    local compatSignature = type(ns.GetAddonCompatibilitySignature) == "function" and ns.GetAddonCompatibilitySignature() or "none"

    return table.concat({
        GetConfiguredTheme(),
        compatSignature,
        sidebarMode,
        sidebarSide,
        GetFrameIdentity(frame),
        GetFrameIdentity(visualFrame),
        tostring(width),
        tostring(height),
        tostring(strata),
        tostring(size),
        buttonHeightSignature,
        ratio,
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

-- Holding Alt previews the alternate channel on buttons that have one
-- (Guild -> Officer, Raid -> Raid Warning), matching what Alt + Left Click does.
local function IsAltModifierDown()
    if type(IsAltKeyDown) ~= "function" then
        return false
    end
    local ok, down = pcall(IsAltKeyDown)
    return ok and down or false
end

local function BuildButtonStateSignature()
    -- The Alt state must be part of the signature: MODIFIER_STATE_CHANGED queues an
    -- update when Alt is pressed or released, and UpdateButtonState bails out early
    -- when the signature is unchanged. Without this the preview never redraws.
    local signature = { GetCurrentChatType() or "nil", IsAltModifierDown() and "alt" or "noalt" }

    for _, def in ipairs(BUTTON_DEFS) do
        local enabled = IsButtonEnabled(def) and "1" or "0"
        local altEnabled = def.altChatType and (IsAltButtonEnabled(def) and "1" or "0") or "-"
        signature[#signature + 1] = def.key
        signature[#signature + 1] = enabled
        signature[#signature + 1] = altEnabled
    end

    return table.concat(signature, "|")
end

UpdateButtonState = function()
    if not container then
        return
    end

    local stateSignature = BuildButtonStateSignature()
    if stateSignature == lastStateSignature then
        return
    end
    lastStateSignature = stateSignature

    local currentChatType = GetCurrentChatType()
    local altDown = IsAltModifierDown()
    for _, def in ipairs(BUTTON_DEFS) do
        local button = buttons[def.key]
        if button then
            local enabled = IsButtonEnabled(def)
            -- Alt only previews the alternate channel when it is actually usable;
            -- a non-officer holding Alt should still see the plain Guild button.
            local altActive = altDown and def.altChatType and IsAltButtonEnabled(def) or false

            button:SetEnabled(true)
            if button.EnableMouse then
                button:EnableMouse(true)
            end
            button.__chatifyDisabled = not enabled
            button.__chatifySelected = enabled and (currentChatType == def.chatType or (def.altChatType and currentChatType == def.altChatType)) or false
            button.__chatifyAltActive = altActive

            if button.Label then
                button.Label:SetText(altActive and (def.altLabel or def.label) or def.label)
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

    if copyButton then
        copyButton:SetEnabled(true)
        if copyButton.EnableMouse then
            copyButton:EnableMouse(true)
        end
        copyButton.__chatifyDisabled = false
        copyButton.__chatifySelected = false
        RefreshCopyButtonLook()
    end

    if historyButton then
        local db = GetDB()
        local enabled = type(ns.OpenChatHistoryWindow) == "function" and not (db and db.enableHistory == false)
        historyButton:SetEnabled(true)
        if historyButton.EnableMouse then
            historyButton:EnableMouse(true)
        end
        historyButton.__chatifyDisabled = not enabled
        historyButton.__chatifySelected = false
        if RefreshHistoryButtonLook then
            RefreshHistoryButtonLook()
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

    -- Both of these used to build their own ChatFrameUtil fallback and pass the
    -- namespace table through as the first argument. Blizzard's util namespaces
    -- take no implicit self, so `text` became the table and the fallback would
    -- have broken the moment the flat globals are removed. ns.CallChatAPI picks
    -- the right spelling and calling convention for the running client.
    if type(ns.CallChatAPI) == "function" then
        ns.CallChatAPI("ChatEdit_SetLastActiveWindow", "SetLastActiveWindow", frame)
    elseif type(_G.ChatEdit_SetLastActiveWindow) == "function" then
        pcall(_G.ChatEdit_SetLastActiveWindow, frame)
    end

    local openChat = _G.ChatFrame_OpenChat
    if type(openChat) ~= "function" and type(ns.CallChatAPI) == "function" then
        openChat = function(text, chatFrame)
            return ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", text, chatFrame)
        end
    end

    local parseText = _G.ChatEdit_ParseText
    if type(parseText) ~= "function" then
        if _G.ChatFrameEditBoxMixin and type(_G.ChatFrameEditBoxMixin.ParseText) == "function" then
            parseText = function(editBox, send)
                return _G.ChatFrameEditBoxMixin.ParseText(editBox, send)
            end
        elseif _G.ChatFrameEditBoxMixinBase and type(_G.ChatFrameEditBoxMixinBase.ParseText) == "function" then
            parseText = function(editBox, send)
                return _G.ChatFrameEditBoxMixinBase.ParseText(editBox, send)
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

    -- Preserve a half-typed message, but only if the edit box is actually open.
    -- A hidden box can still hold stale text from a previous session, and
    -- resurrecting that would be worse than starting empty.
    local existingText = ""
    if editBox and type(editBox.GetText) == "function" then
        local shown = true
        if type(editBox.IsShown) == "function" then
            local okShown, visible = pcall(editBox.IsShown, editBox)
            shown = okShown and visible or false
        end

        if shown then
            local ok, text = pcall(editBox.GetText, editBox)
            if ok and type(text) == "string" then
                existingText = text
            end
        end
    end

    local slash = type(target.slash) == "string" and target.slash or ""

    -- Guard against re-prefixing when the box already holds the slash, which
    -- happens if the same button is clicked twice before anything is typed.
    if slash ~= "" and existingText:sub(1, #slash) == slash then
        existingText = existingText:sub(#slash + 1)
    end

    -- If the edit box is already on the requested channel there is nothing to
    -- parse: injecting the slash would only overwrite the draft with a literal
    -- "/g " and drop whatever was typed. Just reopen with the draft intact.
    if GetCurrentChatType() == target.chatType then
        if type(openChat) == "function" then
            pcall(openChat, existingText, frame)
            editBox = GetActiveEditBox() or editBox
        end
    else
        local parseBuffer = slash .. existingText

        if type(openChat) == "function" then
            pcall(openChat, parseBuffer, frame)
            editBox = GetActiveEditBox() or editBox
        end

        -- OpenChat only fills the box; ChatEdit_ParseText is what consumes the
        -- slash and flips the edit box over to the new chat type.
        if editBox and type(parseText) == "function" and slash ~= "" then
            if editBox.SetText then
                pcall(editBox.SetText, editBox, parseBuffer)
            end
            pcall(parseText, editBox, 0)
            editBox = GetActiveEditBox() or editBox
        end
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


local function GetVisibleSidebarLayoutHost()
    if settingsContainer and settingsContainer:IsShown() then
        return settingsContainer
    end
    return GetMainSidebarButtonFrame()
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

    button:SetParent(GetVisibleSidebarLayoutHost() or sidebarFrame)
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
        pcall(hooksecurefunc, button, "SetPoint", function(_, _, frame)
            local currentSidebar = GetVisibleSidebarLayoutHost()
            if currentSidebar and frame ~= currentSidebar then
                button:SetParent(currentSidebar)
                button:ClearAllPoints()
                originalSetPoint(button, "TOP", currentSidebar, "TOP", 0, 0)
            end
        end)
    end

    return button
end

local function EnsureSidebarIconButtonVisual(self, iconPath, iconSize)
    if not self then
        return
    end

    if self._chatifyVisualReady then
        if self.Icon and iconPath then
            self.Icon:SetTexture(iconPath)
        end
        return
    end

    self._chatifyVisualReady = true
    self._chatifyIconSize = iconSize or 12
    self:SetNormalTexture("chatframe-button-up")
    self:SetPushedTexture("chatframe-button-down")
    self:SetHighlightTexture("chatframe-button-highlight")

    local icon = self:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(iconPath)
    icon:SetPoint("CENTER")
    icon:SetSize(self._chatifyIconSize, self._chatifyIconSize)
    icon:SetVertexColor(0.925, 0.804, 0.063)
    self.Icon = icon

    self:HookScript("OnMouseDown", function(button)
        if button.Icon then
            if button.Icon.AdjustPointsOffset then
                button.Icon:AdjustPointsOffset(2, -2)
            else
                button.Icon:ClearAllPoints()
                button.Icon:SetPoint("CENTER", button, "CENTER", 2, -2)
            end
        end
    end)

    self:HookScript("OnMouseUp", function(button)
        if button.Icon then
            if button.Icon.AdjustPointsOffset then
                button.Icon:AdjustPointsOffset(-2, 2)
            else
                button.Icon:ClearAllPoints()
                button.Icon:SetPoint("CENTER", button, "CENTER", 0, 0)
            end
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

local function RefreshSidebarIconButtonLook(button, iconPath, iconSize)
    if not button then
        return
    end

    EnsureSidebarIconButtonVisual(button, iconPath, iconSize)

    -- Size is controlled by LayoutSidebarButtonStack(). Do not hardcode it here,
    -- otherwise settings/copy buttons drift from Blizzard sidebar metrics.
    button:SetNormalTexture("chatframe-button-up")
    button:SetPushedTexture("chatframe-button-down")
    button:SetHighlightTexture("chatframe-button-highlight")

    if button.Icon then
        button.Icon:SetTexture(iconPath)
        button.Icon:SetSize(iconSize or button._chatifyIconSize or 12, iconSize or button._chatifyIconSize or 12)
        if button:IsMouseOver() then
            button.Icon:SetVertexColor(1.0, 0.90, 0.20)
        else
            button.Icon:SetVertexColor(0.925, 0.804, 0.063)
        end
        button.Icon:ClearAllPoints()
        button.Icon:SetPoint("CENTER")
    end
end

local function EnsureSettingsButtonVisual(self)
    EnsureSidebarIconButtonVisual(self, SETTINGS_ICON, 12)
end

local function RefreshSettingsButtonLook()
    RefreshSidebarIconButtonLook(settingsButton, SETTINGS_ICON, 12)
end

RefreshCopyButtonLook = function()
    RefreshSidebarIconButtonLook(copyButton, COPY_CHAT_ICON, 14)
end

RefreshHistoryButtonLook = function()
    RefreshSidebarIconButtonLook(historyButton, HISTORY_CHAT_ICON, 14)
end

-- Table-driven sidebar layout manager: one compact stack controls
-- social/channel/settings/copy buttons and keeps spacing consistent.
local SIDEBAR_LAYOUT = {
    paddingTop = 0,
    spacing = 1,
    x = 0,
}

local function GetSidebarLayoutSpacing()
    local db = GetDB()
    local spacing = SIDEBAR_LAYOUT.spacing
    if db and type(db.quickChatButtonSpacing) == "number" then
        spacing = math.max(1, math.min(2, math.floor(db.quickChatButtonSpacing + 0.5)))
    end
    return spacing
end

local function AddSidebarLayoutItem(items, key, button, refreshFunc)
    if not button then
        return
    end
    items[#items + 1] = { key = key, frame = button, refresh = refreshFunc }
end

local function ApplySidebarButtonLayout(button, layoutHost, buttonWidth, buttonHeight, strata, frameLevel)
    if not button or not layoutHost then
        return
    end
    button:SetParent(layoutHost)
    button:ClearAllPoints()
    button:SetSize(buttonWidth, buttonHeight)
    button:SetFrameStrata(strata)
    if button.SetFrameLevel then
        button:SetFrameLevel(frameLevel + 2)
    end
    if button.SetClipsChildren then
        button:SetClipsChildren(false)
    end
    button:Show()
end

local function GetSidebarAvailableHeight(sidebarFrame, hostFrame)
    local sidebarHeight = 0
    local hostHeight = 0

    if sidebarFrame and sidebarFrame.GetHeight then
        local ok, value = pcall(sidebarFrame.GetHeight, sidebarFrame)
        if ok and type(value) == "number" then
            sidebarHeight = value
        end
    end
    if hostFrame and hostFrame.GetHeight then
        local ok, value = pcall(hostFrame.GetHeight, hostFrame)
        if ok and type(value) == "number" then
            hostHeight = value
        end
    end

    -- The default Blizzard button frame is often sized for only the native
    -- social/channel buttons. Use the real chat frame height as the available
    -- budget so extra Chatify buttons fit instead of being clipped.
    return math.max(64, math.floor(math.max(sidebarHeight, hostHeight) + 0.5))
end

local function FitSidebarButtonMetrics(sidebarFrame, hostFrame, itemCount, buttonWidth, buttonHeight, ratio, spacing)
    itemCount = tonumber(itemCount) or 0
    if itemCount <= 0 then
        return buttonWidth, buttonHeight, spacing, 0
    end

    local availableHeight = GetSidebarAvailableHeight(sidebarFrame, hostFrame)
    local naturalHeight = (buttonHeight * itemCount) + (spacing * math.max(0, itemCount - 1))
    if naturalHeight <= availableHeight then
        return buttonWidth, buttonHeight, spacing, naturalHeight
    end

    spacing = math.max(0, math.min(spacing, 1))
    local fittedHeight = math.floor((availableHeight - (spacing * math.max(0, itemCount - 1))) / itemCount)
    fittedHeight = math.max(18, math.min(buttonHeight, fittedHeight))
    local fittedWidth = math.max(18, math.floor((fittedHeight / math.max(ratio or DEFAULT_SIDEBAR_BUTTON_RATIO, 0.1)) + 0.5))
    local totalHeight = (fittedHeight * itemCount) + (spacing * math.max(0, itemCount - 1))

    return fittedWidth, fittedHeight, spacing, totalHeight
end

local function PrepareSidebarLayoutHost(sidebarFrame, hostFrame, buttonWidth, totalHeight, strata, frameLevel)
    local layoutHost = settingsContainer or sidebarFrame
    if not layoutHost then
        return nil
    end

    local parent = (hostFrame and hostFrame.GetParent and hostFrame:GetParent()) or (sidebarFrame and sidebarFrame.GetParent and sidebarFrame:GetParent()) or UIParent
    layoutHost:SetParent(parent)
    layoutHost:ClearAllPoints()
    if sidebarFrame then
        layoutHost:SetPoint("TOP", sidebarFrame, "TOP", 0, 0)
    elseif hostFrame then
        layoutHost:SetPoint("TOPLEFT", hostFrame, "TOPRIGHT", 0, 0)
    end
    layoutHost:SetSize(buttonWidth + 4, math.max(1, totalHeight))
    layoutHost:SetFrameStrata(strata)
    if layoutHost.SetFrameLevel then
        layoutHost:SetFrameLevel(frameLevel + 1)
    end
    if layoutHost.SetClipsChildren then
        layoutHost:SetClipsChildren(false)
    end
    layoutHost:Show()

    if sidebarFrame and sidebarFrame.SetClipsChildren then
        sidebarFrame:SetClipsChildren(false)
    end

    return layoutHost
end

local function LayoutSidebarButtonStack(layoutHost, items, buttonWidth, buttonHeight, spacing, strata, frameLevel)
    local previous
    for _, item in ipairs(items) do
        local button = item.frame
        ApplySidebarButtonLayout(button, layoutHost, buttonWidth, buttonHeight, strata, frameLevel)
        if previous then
            button:SetPoint("TOP", previous, "BOTTOM", SIDEBAR_LAYOUT.x, -spacing)
        else
            button:SetPoint("TOP", layoutHost, "TOP", SIDEBAR_LAYOUT.x, -SIDEBAR_LAYOUT.paddingTop)
        end
        if type(item.refresh) == "function" then
            item.refresh()
        end
        previous = button
    end
end

local function LayoutSidebarButtonRow(layoutHost, items, buttonWidth, buttonHeight, spacing, strata, frameLevel)
    local previous
    for _, item in ipairs(items) do
        local button = item.frame
        ApplySidebarButtonLayout(button, layoutHost, buttonWidth, buttonHeight, strata, frameLevel)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
        else
            button:SetPoint("LEFT", layoutHost, "LEFT", 0, 0)
        end
        if type(item.refresh) == "function" then
            item.refresh()
        end
        previous = button
    end
end

local function GetFrameRect(frame)
    if not frame then
        return nil
    end

    local left, right, top, bottom
    if frame.GetLeft then
        local ok, value = pcall(frame.GetLeft, frame)
        if ok and type(value) == "number" then left = value end
    end
    if frame.GetRight then
        local ok, value = pcall(frame.GetRight, frame)
        if ok and type(value) == "number" then right = value end
    end
    if frame.GetTop then
        local ok, value = pcall(frame.GetTop, frame)
        if ok and type(value) == "number" then top = value end
    end
    if frame.GetBottom then
        local ok, value = pcall(frame.GetBottom, frame)
        if ok and type(value) == "number" then bottom = value end
    end

    return left, right, top, bottom
end

local function GetUIParentWidth()
    if UIParent and UIParent.GetWidth then
        local ok, value = pcall(UIParent.GetWidth, UIParent)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    return nil
end

local function ResolveClassicToolbarPlacement(sidebarFrame, hostFrame, buttonWidth, buttonHeight, itemCount, spacing)
    local gap = 6
    local rowWidth = (buttonWidth * itemCount) + (spacing * math.max(0, itemCount - 1))
    local left, right, top = GetFrameRect(sidebarFrame)
    local uiWidth = GetUIParentWidth()
    local side = GetClassicSidebarSide(sidebarFrame, hostFrame)

    if side == "LEFT" then
        if left and left >= (buttonWidth + gap) then
            return "vertical-left", buttonWidth + 4, (buttonHeight * itemCount) + (spacing * math.max(0, itemCount - 1)), gap
        end
        return "row-above-left", rowWidth, buttonHeight, gap
    end

    if right and uiWidth and (uiWidth - right) >= (buttonWidth + gap) then
        return "vertical-right", buttonWidth + 4, (buttonHeight * itemCount) + (spacing * math.max(0, itemCount - 1)), gap
    end

    return "row-above-right", rowWidth, buttonHeight, gap
end

local function HideUnusedSidebarButtons(activeItems, ...)
    local active = {}
    for _, item in ipairs(activeItems or {}) do
        active[item.frame] = true
    end
    for i = 1, select("#", ...) do
        local button = select(i, ...)
        if button and not active[button] then
            button:Hide()
        end
    end
end

local function AddClassicNativeButtonCandidate(candidates, button)
    if not button or candidates[button] then
        return
    end
    if button == settingsButton or button == copyButton or button == historyButton then
        return
    end
    if button.IsShown and not button:IsShown() then
        return
    end
    if not button.GetTop or not button.GetBottom then
        return
    end

    local okTop, top = pcall(button.GetTop, button)
    local okBottom, bottom = pcall(button.GetBottom, button)
    if okTop and okBottom and type(top) == "number" and type(bottom) == "number" then
        candidates[button] = { frame = button, top = top, bottom = bottom }
    end
end

local function GetClassicNativeButtonBounds(sidebarFrame, hostFrame)
    local candidates = {}
    local hostName
    if hostFrame and hostFrame.GetName then
        local ok, name = pcall(hostFrame.GetName, hostFrame)
        if ok and type(name) == "string" then
            hostName = name
        end
    end

    if hostName then
        AddClassicNativeButtonCandidate(candidates, _G[hostName .. "ButtonFrameUpButton"])
        AddClassicNativeButtonCandidate(candidates, _G[hostName .. "ButtonFrameDownButton"])
        AddClassicNativeButtonCandidate(candidates, _G[hostName .. "ButtonFrameBottomButton"])
        AddClassicNativeButtonCandidate(candidates, _G[hostName .. "ButtonFrameMinimizeButton"])
        AddClassicNativeButtonCandidate(candidates, _G[hostName .. "MinimizeButton"])
    end

    AddClassicNativeButtonCandidate(candidates, _G.ChatFrameMenuButton)
    AddClassicNativeButtonCandidate(candidates, _G.ChatFrameChannelButton)

    if sidebarFrame and sidebarFrame.GetChildren then
        local children = { sidebarFrame:GetChildren() }
        for i = 1, #children do
            AddClassicNativeButtonCandidate(candidates, children[i])
        end
    end

    local topButton, bottomButton
    local highestTop, lowestBottom
    for button, data in pairs(candidates) do
        if not highestTop or data.top > highestTop then
            highestTop = data.top
            topButton = button
        end
        if not lowestBottom or data.bottom < lowestBottom then
            lowestBottom = data.bottom
            bottomButton = button
        end
    end

    return topButton, highestTop, bottomButton, lowestBottom
end

local function PrepareDetachedClassicSidebarHost(sidebarFrame, hostFrame, buttonWidth, buttonHeight, itemCount, spacing, strata, frameLevel)
    local layoutHost = settingsContainer
    if not layoutHost then
        return nil, nil
    end

    local parent = (hostFrame and hostFrame.GetParent and hostFrame:GetParent())
        or (sidebarFrame and sidebarFrame.GetParent and sidebarFrame:GetParent())
        or UIParent

    itemCount = math.max(1, tonumber(itemCount) or 1)
    local placement, width, height, gap = ResolveClassicToolbarPlacement(sidebarFrame, hostFrame, buttonWidth, buttonHeight, itemCount, spacing)

    -- Classic chat button frames are not stable across Vanilla/BCC/Wrath/Titan/Mists.
    -- Do not insert Chatify into Blizzard's ButtonFrame at all; keep a separate
    -- toolbar beside/above the native stack so scroll/menu buttons remain untouched.
    layoutHost:SetParent(parent)
    layoutHost:ClearAllPoints()
    layoutHost:SetSize(math.max(1, width or buttonWidth), math.max(1, height or buttonHeight))

    if placement == "vertical-left" and sidebarFrame then
        layoutHost:SetPoint("TOPRIGHT", sidebarFrame, "TOPLEFT", -gap, 0)
    elseif placement == "vertical-right" and sidebarFrame then
        layoutHost:SetPoint("TOPLEFT", sidebarFrame, "TOPRIGHT", gap, 0)
    elseif placement == "row-above-right" and sidebarFrame then
        layoutHost:SetPoint("BOTTOMRIGHT", sidebarFrame, "TOPRIGHT", 0, gap)
    elseif sidebarFrame then
        layoutHost:SetPoint("BOTTOMLEFT", sidebarFrame, "TOPLEFT", 0, gap)
    elseif hostFrame then
        layoutHost:SetPoint("BOTTOMLEFT", hostFrame, "TOPLEFT", 0, gap)
    else
        layoutHost:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    layoutHost.__chatifyClassicPlacement = placement
    layoutHost:SetFrameStrata(strata)
    if layoutHost.SetFrameLevel then
        layoutHost:SetFrameLevel(frameLevel + 20)
    end
    if layoutHost.SetClipsChildren then
        layoutHost:SetClipsChildren(false)
    end
    -- Do not clamp this toolbar: clamping can push it back on top of Blizzard's
    -- native chat buttons at screen edges, which is exactly the BCC overlap bug.
    if layoutHost.SetClampedToScreen then
        layoutHost:SetClampedToScreen(false)
    end
    layoutHost:Show()

    return layoutHost, placement
end

local function LayoutDetachedClassicSidebarButtons(sidebarFrame, hostFrame)
    if not settingsButton then
        return false
    end

    local showSettings = ShouldShowSettingsButton()
    local showCopy = showSettings and copyButton ~= nil
    local showHistory = showSettings and historyButton ~= nil

    local layoutItems = {}
    if showSettings then
        AddSidebarLayoutItem(layoutItems, "settings", settingsButton, RefreshSettingsButtonLook)
    end
    if showCopy then
        AddSidebarLayoutItem(layoutItems, "copy", copyButton, RefreshCopyButtonLook)
    end
    if showHistory then
        AddSidebarLayoutItem(layoutItems, "history", historyButton, RefreshHistoryButtonLook)
    end

    if #layoutItems == 0 then
        if settingsContainer then
            settingsContainer:Hide()
        end
        HideUnusedSidebarButtons(layoutItems, settingsButton, copyButton, historyButton)
        return true
    end

    local buttonWidth, buttonHeight, ratio = GetConfiguredButtonMetrics()
    local spacing = GetSidebarLayoutSpacing()
    local strata = (sidebarFrame and sidebarFrame.GetFrameStrata and sidebarFrame:GetFrameStrata())
        or (hostFrame and hostFrame.GetFrameStrata and hostFrame:GetFrameStrata())
        or "HIGH"
    local frameLevel = (sidebarFrame and sidebarFrame.GetFrameLevel and sidebarFrame:GetFrameLevel())
        or (hostFrame and hostFrame.GetFrameLevel and hostFrame:GetFrameLevel())
        or 1

    -- Classic keeps Chatify controls detached from Blizzard's native button
    -- column. Use the native button size, but do not fit against the native
    -- ButtonFrame height because that reintroduces overlap on BCC.
    spacing = math.max(2, spacing)

    local layoutHost, placement = PrepareDetachedClassicSidebarHost(sidebarFrame, hostFrame, buttonWidth, buttonHeight, #layoutItems, spacing, strata, frameLevel)
    if not layoutHost then
        return false
    end

    if placement == "row-above-left" or placement == "row-above-right" then
        LayoutSidebarButtonRow(layoutHost, layoutItems, buttonWidth, buttonHeight, spacing, strata, frameLevel + 18)
    else
        LayoutSidebarButtonStack(layoutHost, layoutItems, buttonWidth, buttonHeight, spacing, strata, frameLevel + 18)
    end
    HideUnusedSidebarButtons(layoutItems, settingsButton, copyButton, historyButton)

    -- Never hide or reparent Blizzard's Classic chat buttons here. BCC,
    -- Vanilla, Wrath/Titan and MoP Classic use different native children
    -- (Up/Down/Bottom/Minimize/Menu), and changing their parent/order is what
    -- causes the broken vertical stack shown in game.
    if socialButton and socialButton.Hide then
        socialButton:Hide()
    end

    return true
end


local function LayoutFallbackSidebarButtons(anchorFrame)
    if not settingsContainer or not settingsButton then
        return false
    end

    anchorFrame = anchorFrame or GetAnchorVisualFrame() or GetAnchorFrame()
    if not anchorFrame then
        return false
    end

    local showSettings = ShouldShowSettingsButton()
    local showCopy = showSettings and copyButton ~= nil
    local showHistory = showSettings and historyButton ~= nil
    local layoutItems = {}

    if showSettings then
        AddSidebarLayoutItem(layoutItems, "settings", settingsButton, RefreshSettingsButtonLook)
    end
    if showCopy then
        AddSidebarLayoutItem(layoutItems, "copy", copyButton, RefreshCopyButtonLook)
    end
    if showHistory then
        AddSidebarLayoutItem(layoutItems, "history", historyButton, RefreshHistoryButtonLook)
    end

    if #layoutItems == 0 then
        settingsContainer:Hide()
        HideUnusedSidebarButtons(layoutItems, settingsButton, copyButton, historyButton)
        return true
    end

    local parent = (anchorFrame.GetParent and anchorFrame:GetParent()) or UIParent
    local buttonWidth, buttonHeight = GetConfiguredButtonMetrics()
    local spacing = math.max(2, GetSidebarLayoutSpacing())
    local width = (#layoutItems * buttonWidth) + ((#layoutItems - 1) * spacing)
    local height = buttonHeight
    local strata = (anchorFrame.GetFrameStrata and anchorFrame:GetFrameStrata()) or "HIGH"
    local frameLevel = (anchorFrame.GetFrameLevel and anchorFrame:GetFrameLevel()) or 1

    settingsContainer:SetParent(parent)
    settingsContainer:ClearAllPoints()
    settingsContainer:SetSize(width, height)
    settingsContainer:SetFrameStrata(strata)
    if settingsContainer.SetFrameLevel then
        settingsContainer:SetFrameLevel(frameLevel + 20)
    end
    if settingsContainer.SetClampedToScreen then
        settingsContainer:SetClampedToScreen(false)
    end
    if settingsContainer.SetClipsChildren then
        settingsContainer:SetClipsChildren(false)
    end

    -- Last-resort mode for custom/replacement chat layouts that expose no
    -- Blizzard ButtonFrame yet. Put the small row above the chat instead of
    -- hiding Settings/Copy/History forever after /reload.
    settingsContainer:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, spacing)
    settingsContainer.__chatifyClassicPlacement = "fallback-row-above"
    settingsContainer:Show()

    LayoutSidebarButtonRow(settingsContainer, layoutItems, buttonWidth, buttonHeight, spacing, strata, frameLevel + 18)
    HideUnusedSidebarButtons(layoutItems, settingsButton, copyButton, historyButton)
    if socialButton and socialButton.Hide then
        socialButton:Hide()
    end
    return true
end

local function LayoutSettingsButton()
    if not settingsButton then
        return
    end

    local sidebarFrame, hostFrame = GetMainSidebarButtonFrame()
    if not sidebarFrame or not hostFrame then
        if LayoutFallbackSidebarButtons(GetAnchorVisualFrame() or GetAnchorFrame()) then
            return
        end
        if settingsContainer then
            settingsContainer:Hide()
        end
        settingsButton:Hide()
        if copyButton then
            copyButton:Hide()
        end
        if historyButton then
            historyButton:Hide()
        end
        if socialButton then
            socialButton:Hide()
        end
        return
    end

    if IsDetachedClassicSidebarLayout() then
        LayoutDetachedClassicSidebarButtons(sidebarFrame, hostFrame)
        return
    end

    local social = EnsureSocialSidebarButton()
    local channelButton = _G.ChatFrameChannelButton
    local showSettings = ShouldShowSettingsButton()
    local showCopy = showSettings and copyButton ~= nil
    local showHistory = showSettings and historyButton ~= nil

    local layoutItems = {}
    AddSidebarLayoutItem(layoutItems, "social", social)
    AddSidebarLayoutItem(layoutItems, "channel", channelButton)
    if showSettings then
        AddSidebarLayoutItem(layoutItems, "settings", settingsButton, RefreshSettingsButtonLook)
    end
    if showCopy then
        AddSidebarLayoutItem(layoutItems, "copy", copyButton, RefreshCopyButtonLook)
    end
    if showHistory then
        AddSidebarLayoutItem(layoutItems, "history", historyButton, RefreshHistoryButtonLook)
    end

    if #layoutItems == 0 then
        if settingsContainer then
            settingsContainer:Hide()
        end
        HideUnusedSidebarButtons(layoutItems, socialButton, channelButton, settingsButton, copyButton, historyButton)
        return
    end

    local buttonWidth, buttonHeight, ratio = GetConfiguredButtonMetrics()
    local spacing = GetSidebarLayoutSpacing()
    local strata = (sidebarFrame.GetFrameStrata and sidebarFrame:GetFrameStrata()) or "HIGH"
    local frameLevel = (sidebarFrame.GetFrameLevel and sidebarFrame:GetFrameLevel()) or 1

    local totalHeight
    buttonWidth, buttonHeight, spacing, totalHeight = FitSidebarButtonMetrics(sidebarFrame, hostFrame, #layoutItems, buttonWidth, buttonHeight, ratio, spacing)
    local layoutHost = PrepareSidebarLayoutHost(sidebarFrame, hostFrame, buttonWidth, totalHeight, strata, frameLevel)
    if not layoutHost then
        return
    end

    LayoutSidebarButtonStack(layoutHost, layoutItems, buttonWidth, buttonHeight, spacing, strata, frameLevel)
    HideUnusedSidebarButtons(layoutItems, socialButton, channelButton, settingsButton, copyButton, historyButton)
end

local function LayoutButtons()
    if not container then
        return false
    end

    local db = GetDB()
    local sideGap = 18
    if db and type(db.quickChatButtonGap) == "number" then
        sideGap = math.max(8, math.min(36, math.floor(db.quickChatButtonGap + 0.5)))
    end

    local frame = GetAnchorFrame()
    local visualFrame = GetAnchorVisualFrame()
    if not frame or not visualFrame then
        return false
    end

    local visualWidth = math.floor((visualFrame.GetWidth and visualFrame:GetWidth()) or (frame.GetWidth and frame:GetWidth()) or 0)
    local visualHeight = math.floor((visualFrame.GetHeight and visualFrame:GetHeight()) or (frame.GetHeight and frame:GetHeight()) or 0)
    if visualWidth < MIN_STABLE_CHAT_FRAME_WIDTH or visualHeight < MIN_STABLE_CHAT_FRAME_HEIGHT then
        ScheduleRefresh(0.10)
        ScheduleRefresh(0.50)
        return false
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
        return true
    end

    local buttonWidth, buttonHeight, ratio = GetConfiguredButtonMetrics()

    local chatHeight = math.max(MIN_STABLE_CHAT_FRAME_HEIGHT, visualHeight, math.floor((frame.GetHeight and frame:GetHeight()) or MIN_STABLE_CHAT_FRAME_HEIGHT))
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

    local theme = GetConfiguredTheme()
    local fontScale = GetConfiguredFontScale()
    local fontPath = GetConfiguredChatFontPath(theme)
    local fontSize = math.max(10, math.floor(math.min(buttonWidth, buttonHeight) * 0.56 * fontScale))

    local previous
    for _, button in ipairs(orderedButtons) do
        button:ClearAllPoints()
        if button.__chatifyWidth ~= buttonWidth or button.__chatifyHeight ~= buttonHeight then
            button:SetSize(buttonWidth, buttonHeight)
            button.__chatifyWidth = buttonWidth
            button.__chatifyHeight = buttonHeight
        end

        if previous then
            button:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
        else
            button:SetPoint("BOTTOM", container, "BOTTOM", 0, outerPadding)
        end

        if button.Label then
            if button.__chatifyFontPath ~= fontPath or button.__chatifyFontSize ~= fontSize then
                if type(ns.SafeSetFont) == "function" then
                    ns.SafeSetFont(button.Label, fontPath, fontSize, "OUTLINE", STANDARD_TEXT_FONT)
                else
                    pcall(button.Label.SetFont, button.Label, fontPath, fontSize, "OUTLINE")
                end
                button.__chatifyFontPath = fontPath
                button.__chatifyFontSize = fontSize
            end
            if not button.__chatifyLabelAnchored then
                button.Label:ClearAllPoints()
                button.Label:SetPoint("CENTER", button, "CENTER", 0, 0)
                button.__chatifyLabelAnchored = true
            end
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

    return true
end

local function HookAnchorFrameSignals()
    local frame = GetAnchorVisualFrame() or GetAnchorFrame()
    if not frame or frame == hookedAnchorFrame or not frame.HookScript then
        return
    end

    hookedAnchorFrame = frame
    local hook = ns.SafeHookScript
    if type(hook) == "function" then
        hook(frame, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyQuickAnchorSize")
        hook(frame, "OnShow", function() ScheduleRefresh(0) end, "__chatifyQuickAnchorShow")
        hook(frame, "OnHide", function() ScheduleRefresh(0) end, "__chatifyQuickAnchorHide")
    else
        frame:HookScript("OnSizeChanged", function() ScheduleRefresh(0.05) end)
        frame:HookScript("OnShow", function() ScheduleRefresh(0) end)
        frame:HookScript("OnHide", function() ScheduleRefresh(0) end)
    end
end

local function HookEditBoxSignals()
    local editBox = GetActiveEditBox()
    if not editBox or editBox == hookedEditBox or not editBox.HookScript then
        return
    end

    hookedEditBox = editBox
    local hook = ns.SafeHookScript
    if type(hook) == "function" then
        hook(editBox, "OnShow", ScheduleButtonStateUpdate, "__chatifyQuickEditShow")
        hook(editBox, "OnHide", ScheduleButtonStateUpdate, "__chatifyQuickEditHide")
        hook(editBox, "OnEditFocusGained", ScheduleButtonStateUpdate, "__chatifyQuickEditFocusGained")
        hook(editBox, "OnEditFocusLost", ScheduleButtonStateUpdate, "__chatifyQuickEditFocusLost")
        hook(editBox, "OnTextChanged", ScheduleButtonStateUpdate, "__chatifyQuickEditTextChanged")
    else
        editBox:HookScript("OnShow", ScheduleButtonStateUpdate)
        editBox:HookScript("OnHide", ScheduleButtonStateUpdate)
        editBox:HookScript("OnEditFocusGained", ScheduleButtonStateUpdate)
        editBox:HookScript("OnEditFocusLost", ScheduleButtonStateUpdate)
        editBox:HookScript("OnTextChanged", ScheduleButtonStateUpdate)
    end
end


local function IsNativeCopyEnabled()
    local db = GetDB()
    return not (db and db.copyNativeSelection == false)
end

local function IsHistoryWindowEnabled()
    local db = GetDB()
    return type(ns.OpenChatHistoryWindow) == "function" and not (db and db.enableHistory == false)
end

local function ShouldUseNativeCopy(mouseButton)
    if not IsNativeCopyEnabled() then
        return false
    end

    return mouseButton == "LeftButton"
        and type(IsShiftKeyDown) == "function"
        and IsShiftKeyDown()
end

local function GetNativeCopyTooltipMode()
    if not IsNativeCopyEnabled() then
        return T("disabled in settings")
    end

    return T("Shift + Left Click")
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
                GameTooltip:AddLine(T(def.tooltip), 1.00, 0.82, 0.18, true)
                AddTooltipLine(T("Command"), string.format("%s  |cff8f8f8f%s|r", def.slash:gsub("%s+$", ""), def.slashAlias or ""), 0.90, 0.90, 0.90)

                if def.tooltipNote then
                    AddTooltipLine(T(def.tooltipNote), nil, 0.72, 0.82, 1.00, true)
                end

                AddTooltipLine(" ")
                AddTooltipLine(T("Left Click"), T("Switch to this channel"), 0.95, 0.95, 0.95)

                if def.altChatType then
                    AddTooltipLine(T("Alt Command"), string.format("%s  |cff8f8f8f%s|r", (def.altSlash or ""):gsub("%s+$", ""), def.altSlashAlias or ""), 0.72, 0.82, 1.00)
                    if altEnabled then
                        AddTooltipLine(T("Alt + Left Click"), string.format(T("Switch to %s"), T(def.altTooltip or def.altChatType)), 0.72, 0.82, 1.00)
                    else
                        AddTooltipLine(T("Alt + Left Click"), string.format(T("%s unavailable"), T(def.altTooltip or "Alternate channel")), 0.62, 0.62, 0.62)
                    end
                end

                AddTooltipLine(" ")
                if enabled then
                    AddTooltipLine(T("Status"), T("Available"), 0.35, 0.95, 0.55)
                else
                    AddTooltipLine(T("Status"), T("Unavailable"), 1.00, 0.35, 0.35)
                end

                AddTooltipLine(T("Position"), T("Right side of the chat frame"), 0.72, 0.72, 0.72)
                local skinLabel = "Standard"
                if GetConfiguredTheme() == "ELVUI" then
                    skinLabel = "ElvUI"
                elseif GetConfiguredTheme() == "GW2UI" then
                    skinLabel = "GW2 UI"
                end
                AddTooltipLine(T("Skin"), skinLabel, 0.72, 0.72, 0.72)
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
            return
        end
        if ACD and type(ACD.Open) == "function" then
            pcall(ACD.Open, ACD, "Chatify")
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
            GameTooltip:AddLine(T("Chatify Settings"), 1.00, 0.82, 0.18, true)
            AddTooltipLine(T("Left Click"), T("Open Chatify configuration"), 0.95, 0.95, 0.95)
            AddTooltipLine(T("Position"), T("Main chat button panel"), 0.72, 0.72, 0.72)
            AddTooltipLine(T("Skin"), skinLabel, 0.72, 0.72, 0.72)
            GameTooltip:Show()
        end
    end)

    settingsButton:SetScript("OnLeave", function()
        RefreshSettingsButtonLook()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)


    copyButton = CreateFrame("Button", "ChatifyChatMenuCopyButton", settingsContainer, backdropTemplate)
    copyButton:RegisterForClicks("LeftButtonUp")
    copyButton:SetHitRectInsets(0, 0, 0, 0)
    copyButton.RefreshVisual = RefreshCopyButtonLook
    EnsureSidebarIconButtonVisual(copyButton, COPY_CHAT_ICON, 14)

    copyButton:SetScript("OnClick", function(_, mouseButton)
        -- The sidebar button belongs to the main chat host. Do not blindly use
        -- SELECTED_CHAT_FRAME here: a whisper/temporary tab can remain selected
        -- while the visible main chat still has readable lines, which made the
        -- custom copy window open with the native-selection fallback only.
        local frame = GetMainSidebarHostFrame() or GetAnchorFrame() or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if ShouldUseNativeCopy(mouseButton) then
            if type(ns.ToggleNativeChatCopyMode) == "function" then
                ns.ToggleNativeChatCopyMode(frame)
                return
            elseif type(ns.EnterNativeChatCopyMode) == "function" then
                ns.EnterNativeChatCopyMode(frame)
                return
            end
        end

        if type(ns.OpenChatCopyWindow) == "function" then
            ns.OpenChatCopyWindow(frame, 250)
        end
    end)

    copyButton:SetScript("OnEnter", function(self)
        RefreshCopyButtonLook()
        if GameTooltip then
            local skinLabel = "Standard"
            if GetConfiguredTheme() == "ELVUI" then
                skinLabel = "ElvUI"
            elseif GetConfiguredTheme() == "GW2UI" then
                skinLabel = "GW2 UI"
            end

            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(T("Copy Chat"), 1.00, 0.82, 0.18, true)
            AddTooltipLine(T("Left Click"), T("Open recent chat in a copy window"), 0.95, 0.95, 0.95)
            if IsNativeCopyEnabled() then
                AddTooltipLine(T("Shift + Left Click"), T("Toggle direct selection inside the chat frame. Press Ctrl+C after selecting text."), 0.80, 0.80, 0.80)
            else
                AddTooltipLine(T("Shift + Left Click"), T("Direct chat selection is disabled in settings"), 0.62, 0.62, 0.62)
            end
            AddTooltipLine(T("Limit"), T("Optimized recent messages only"), 0.72, 0.82, 1.00)
            AddTooltipLine(T("Position"), T("Below Chatify settings"), 0.72, 0.72, 0.72)
            AddTooltipLine(T("Skin"), skinLabel, 0.72, 0.72, 0.72)
            GameTooltip:Show()
        end
    end)

    copyButton:SetScript("OnLeave", function(self)
        RefreshCopyButtonLook()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    historyButton = CreateFrame("Button", "ChatifyChatMenuHistoryButton", settingsContainer, backdropTemplate)
    historyButton:RegisterForClicks("LeftButtonUp")
    historyButton:SetHitRectInsets(0, 0, 0, 0)
    historyButton.RefreshVisual = RefreshHistoryButtonLook
    EnsureSidebarIconButtonVisual(historyButton, HISTORY_CHAT_ICON, 14)

    historyButton:SetScript("OnClick", function()
        if not IsHistoryWindowEnabled() then
            return
        end
        local frame = GetMainSidebarHostFrame() or GetAnchorFrame() or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if type(ns.OpenChatHistoryWindow) == "function" then
            ns.OpenChatHistoryWindow(frame)
        end
    end)

    historyButton:SetScript("OnEnter", function(self)
        RefreshHistoryButtonLook()
        if GameTooltip then
            local skinLabel = "Standard"
            if GetConfiguredTheme() == "ELVUI" then
                skinLabel = "ElvUI"
            elseif GetConfiguredTheme() == "GW2UI" then
                skinLabel = "GW2 UI"
            end

            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(T("Chat History"), 1.00, 0.82, 0.18, true)
            if IsHistoryWindowEnabled() then
                AddTooltipLine(T("Left Click"), T("Open saved chat history with the same tabs as Copy Chat"), 0.95, 0.95, 0.95)
                AddTooltipLine(T("Filter"), T("Uses the same included chat tabs as Copy Chat"), 0.72, 0.82, 1.00)
            else
                AddTooltipLine(T("Status"), T("Chat History is disabled in settings"), 1.00, 0.45, 0.35)
            end
            AddTooltipLine(T("Position"), T("Below Copy Chat"), 0.72, 0.72, 0.72)
            AddTooltipLine(T("Skin"), skinLabel, 0.72, 0.72, 0.72)
            GameTooltip:Show()
        end
    end)

    historyButton:SetScript("OnLeave", function(self)
        RefreshHistoryButtonLook()
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
        pcall(hooksecurefunc, "FCF_DockUpdate", function()
            ScheduleRefresh(0)
        end)
    end

    if type(_G.FCFDock_SelectWindow) == "function" then
        pcall(hooksecurefunc, "FCFDock_SelectWindow", function()
            ScheduleRefresh(0)
            ScheduleButtonStateUpdate()
        end)
    end

    if type(_G.FCF_SelectDockFrame) == "function" then
        pcall(hooksecurefunc, "FCF_SelectDockFrame", function()
            ScheduleRefresh(0)
            ScheduleButtonStateUpdate()
        end)
    end

    if type(_G.FloatingChatFrame_Update) == "function" then
        pcall(hooksecurefunc, "FloatingChatFrame_Update", function()
            ScheduleRefresh(0)
        end)
    end

    if type(_G.ChatEdit_UpdateHeader) == "function" then
        pcall(hooksecurefunc, "ChatEdit_UpdateHeader", function()
            ScheduleButtonStateUpdate()
        end)
    end

    if _G.ChatFrameUtil then
        if type(_G.ChatFrameUtil.ActivateChat) == "function" then
            pcall(hooksecurefunc, _G.ChatFrameUtil, "ActivateChat", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatFrameUtil.DeactivateChat) == "function" then
            pcall(hooksecurefunc, _G.ChatFrameUtil, "DeactivateChat", function()
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatFrameUtil.SetLastActiveWindow) == "function" then
            pcall(hooksecurefunc, _G.ChatFrameUtil, "SetLastActiveWindow", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end
    else
        if type(_G.ChatEdit_ActivateChat) == "function" then
            pcall(hooksecurefunc, "ChatEdit_ActivateChat", function()
                ScheduleRefresh(0)
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatEdit_DeactivateChat) == "function" then
            pcall(hooksecurefunc, "ChatEdit_DeactivateChat", function()
                ScheduleButtonStateUpdate()
            end)
        end

        if type(_G.ChatEdit_SetLastActiveWindow) == "function" then
            pcall(hooksecurefunc, "ChatEdit_SetLastActiveWindow", function()
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
        pcall(hooksecurefunc, GW, "UpdateChatSettings", function()
            ScheduleRefresh(0)
        end)
    end

    local frame = GetAnchorFrame()
    if frame and frame.Container and frame.Container.HookScript and not frame.Container.__chatifyGW2Hooked then
        ns.SafeHookScript(frame.Container, "OnShow", function() ScheduleRefresh(0) end, "__chatifyGW2OnShow")
        ns.SafeHookScript(frame.Container, "OnHide", function() ScheduleRefresh(0) end, "__chatifyGW2OnHide")
        ns.SafeHookScript(frame.Container, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyGW2OnSizeChanged")
        frame.Container.__chatifyGW2Hooked = true
    end

    local background = frame and frame.GetName and _G[frame:GetName() .. "Background"]
    if background and background.HookScript and not background.__chatifyGW2Hooked then
        ns.SafeHookScript(background, "OnShow", function() ScheduleRefresh(0) end, "__chatifyGW2BackgroundShow")
        ns.SafeHookScript(background, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyGW2BackgroundSize")
        background.__chatifyGW2Hooked = true
    end

    if _G.GeneralDockManager and _G.GeneralDockManager.HookScript and not _G.GeneralDockManager.__chatifyGW2Hooked then
        ns.SafeHookScript(_G.GeneralDockManager, "OnShow", function() ScheduleRefresh(0) end, "__chatifyGW2DockShow")
        ns.SafeHookScript(_G.GeneralDockManager, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyGW2DockSize")
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
            pcall(hooksecurefunc, CH, name, function()
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
        ns.SafeHookScript(_G.LeftChatToggleButton, "OnClick", function() ScheduleRefresh(0) end, "__chatifyElvUIToggleLeftClick")
        _G.LeftChatToggleButton.__chatifyElvUIHooked = true
    end

    if _G.RightChatToggleButton and _G.RightChatToggleButton.HookScript and not _G.RightChatToggleButton.__chatifyElvUIHooked then
        ns.SafeHookScript(_G.RightChatToggleButton, "OnClick", function() ScheduleRefresh(0) end, "__chatifyElvUIToggleRightClick")
        _G.RightChatToggleButton.__chatifyElvUIHooked = true
    end

    if _G.LeftChatPanel and _G.LeftChatPanel.HookScript and not _G.LeftChatPanel.__chatifyElvUIHooked then
        ns.SafeHookScript(_G.LeftChatPanel, "OnShow", function() ScheduleRefresh(0) end, "__chatifyElvUIPanelLeftShow")
        ns.SafeHookScript(_G.LeftChatPanel, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyElvUIPanelLeftSize")
        _G.LeftChatPanel.__chatifyElvUIHooked = true
    end

    if _G.RightChatPanel and _G.RightChatPanel.HookScript and not _G.RightChatPanel.__chatifyElvUIHooked then
        ns.SafeHookScript(_G.RightChatPanel, "OnShow", function() ScheduleRefresh(0) end, "__chatifyElvUIPanelRightShow")
        ns.SafeHookScript(_G.RightChatPanel, "OnSizeChanged", function() ScheduleRefresh(0.05) end, "__chatifyElvUIPanelRightSize")
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
        lastStateSignature = nil
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
    local didLayout = false
    if layoutSignature ~= lastLayoutSignature or not container:IsShown() or (showSidebarMenu and settingsContainer and not settingsContainer:IsShown()) then
        local layoutApplied = LayoutButtons()
        if layoutApplied then
            LayoutSettingsButton()
            lastLayoutSignature = layoutSignature
            lastStateSignature = nil
            didLayout = true
        end
    end

    SafeRun("QuickButtons.UpdateState", UpdateButtonState)

    if showQuickButtons then
        container:Show()
    elseif container then
        container:Hide()
    end

    if showSidebarMenu then
        if not didLayout then
            LayoutSettingsButton()
        end
    elseif settingsContainer then
        settingsContainer:Hide()
    end
end

function QuickButtonsModule:Refresh()
    ScheduleRefresh(0)
end

function QuickButtonsModule:OnEnable()
    local function register(eventName, method)
        if type(ns.RegisterEventIfSupported) == "function" then
            return ns.RegisterEventIfSupported(self, eventName, method)
        end
        return pcall(self.RegisterEvent, self, eventName, method)
    end

    register("PLAYER_LOGIN", "Refresh")
    register("PLAYER_ENTERING_WORLD", "Refresh")
    register("GROUP_ROSTER_UPDATE", "Refresh")
    register("PLAYER_GUILD_UPDATE", "Refresh")
    -- Raid Warning depends on being leader or assistant, and Officer chat on the
    -- guild rank's permissions. Both can change without the roster size changing,
    -- so refresh the enabled/disabled state on those events too. These only queue
    -- a coalesced state update, not a full layout pass.
    register("PARTY_LEADER_CHANGED", function() ScheduleButtonStateUpdate() end)
    register("GUILD_RANKS_UPDATE", function() ScheduleButtonStateUpdate() end)
    register("UPDATE_CHAT_WINDOWS", "Refresh")
    register("UPDATE_FLOATING_CHAT_WINDOWS", "Refresh")
    register("CHANNEL_UI_UPDATE", "Refresh")
    register("MODIFIER_STATE_CHANGED", function() ScheduleButtonStateUpdate() end)
    register("DISPLAY_SIZE_CHANGED", "Refresh")
    register("UI_SCALE_CHANGED", "Refresh")
    register("CVAR_UPDATE", function(_, cvar)
        if cvar == "useUiScale" or cvar == "uiScale" then
            ScheduleRefresh(0)
        end
    end)
    register("ADDON_LOADED", function(_, addon)
        if type(ns.ResetAddonCompatibilityCache) == "function" then
            ns.ResetAddonCompatibilityCache()
        end

        if addon == "ElvUI" then
            elvuiEngine = nil
            elvuiChat = nil
            elvuiHooksInstalled = false
            InvalidateQuickButtonLayout("elvui-loaded")
            ScheduleRefresh(0)
            ScheduleRefresh(1)
        elseif addon == "GW2_UI" then
            gw2Engine = nil
            gw2HooksInstalled = false
            InvalidateQuickButtonLayout("gw2-loaded")
            ScheduleRefresh(0)
            ScheduleRefresh(1)
        elseif addon == "Chattynator" or addon == "Prat-3.0" or addon == "Prat" or addon == "Glass" or addon == "Chatter" or addon == "BasicChatMods" then
            InvalidateQuickButtonLayout("chat-addon-loaded")
            ScheduleRefresh(0)
            ScheduleRefresh(1)
        end
    end)

    SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons)

    if type(ns.SafeAfter) == "function" then
        ns.SafeAfter(0, function() SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons) end)
        ns.SafeAfter(1, function() SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons) end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, function() SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons) end)
        C_Timer.After(1, function() SafeRun("QuickButtons.Refresh", ns.RefreshQuickChatButtons) end)
    end
end
