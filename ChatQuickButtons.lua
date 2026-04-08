local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local QuickButtonsModule = Chatify:NewModule("QuickButtons", "AceEvent-3.0")

local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local unpack = unpack or table.unpack
local container
local buttons = {}
local hookedEditBox
local hookedAnchorFrame
local GetConfiguredAlpha
local GetConfiguredTheme
local GetElvUIPanelColor
local MixColor
local elvuiEngine
local elvuiChat
local elvuiHooksInstalled = false
local refreshQueued = false
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil


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

local function ScheduleRefresh(delay)
    delay = tonumber(delay) or 0

    if not C_Timer or not C_Timer.After then
        ns.RefreshQuickChatButtons()
        return
    end

    if delay > 0 then
        C_Timer.After(delay, ns.RefreshQuickChatButtons)
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

local function RefreshButtonLook(button)
    if not button then
        return
    end

    EnsureButtonArt(button)

    local palette = GetButtonPalette(button)
    ApplyButtonBackdrop(button, palette.bg, palette.border)

    if button.Label then
        button.Label:SetTextColor(palette.text[1], palette.text[2], palette.text[3])
    end

    if button.Accent then
        button.Accent:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], palette.accent[4])
    end

    if button.Inner then
        button.Inner:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], palette.inner or 0)
    end

    if button.Gloss then
        button.Gloss:SetVertexColor(1, 1, 1, palette.gloss)
    end

    if button.Glow then
        button.Glow:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], palette.glow or 0)
    end

    if button.Shade then
        button.Shade:SetVertexColor(0, 0, 0, palette.shade)
    end

    if button.Highlight then
        local highlightAlpha = 0
        if not button.__chatifyDisabled and button:IsMouseOver() then
            highlightAlpha = math.min(0.18, palette.accent[4] * 0.22)
        end
        button.Highlight:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3], highlightAlpha)
    end
end

local function ApplyContainerStyle()
    if not container then
        return
    end

    local theme = GetConfiguredTheme()

    if theme ~= "ELVUI" and container._chatifyElvTemplate then
        container._chatifyElvTemplate = nil
    end

    if theme == "ELVUI" then
        local E = GetElvUI()
        if E and type(container.SetTemplate) == "function" and not container._chatifyElvTemplate then
            pcall(container.SetTemplate, container, "Transparent")
            container._chatifyElvTemplate = true
        end

        if type(container.SetBackdropColor) == "function" and type(container.SetBackdropBorderColor) == "function" then
            local pr, pg, pb, pa = GetElvUIPanelColor()
            local br, bgc, bb = 0.12, 0.12, 0.12
            if E and E.media then
                br, bgc, bb = GetColorComponents(E.media.bordercolor, { 0.12, 0.12, 0.12 })
            end
            container:SetBackdropColor(pr, pg, pb, math.min(1, math.max(pa, GetConfiguredAlpha() * 0.90)))
            container:SetBackdropBorderColor(br, bgc, bb, 1.0)
        end
        return
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
        container:SetBackdropColor(0.02, 0.02, 0.03, math.min(0.22, GetConfiguredAlpha() * 0.22))
        container:SetBackdropBorderColor(0.38, 0.28, 0.10, math.min(0.45, GetConfiguredAlpha() * 0.55))
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

GetConfiguredTheme = function()
    local db = GetDB()
    local theme = db and db.quickChatButtonTheme or "AUTO"
    if theme ~= "AUTO" and theme ~= "STANDARD" and theme ~= "ELVUI" then
        theme = "AUTO"
    end

    if theme == "ELVUI" then
        return HasElvUIChat() and "ELVUI" or "STANDARD"
    end

    if theme == "AUTO" then
        return HasElvUIChat() and "ELVUI" or "STANDARD"
    end

    return "STANDARD"
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

local function GetConfiguredFontScale()
    local db = GetDB()
    local scale = db and db.quickChatButtonFontScale or 1
    if type(scale) ~= "number" then
        scale = 1
    end
    if scale < 0.8 then scale = 0.8 end
    if scale > 1.3 then scale = 1.3 end
    return scale
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

MixColor = function(fromColor, toColor, t)
    return {
        fromColor[1] + ((toColor[1] - fromColor[1]) * t),
        fromColor[2] + ((toColor[2] - fromColor[2]) * t),
        fromColor[3] + ((toColor[3] - fromColor[3]) * t),
        fromColor[4] + ((toColor[4] - fromColor[4]) * t),
    }
end

local BUTTON_DEFS = {
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

local function GetAnchorFrame()
    local _, CH = GetElvUI()
    if CH and CH.LeftChatWindow then
        return CH.LeftChatWindow
    end

    return _G.ChatFrame1 or DEFAULT_CHAT_FRAME
end

local function GetAnchorParent()
    local frame = GetAnchorFrame()
    local _, CH = GetElvUI()

    if frame and CH then
        if CH.LeftChatWindow and frame == CH.LeftChatWindow and _G.LeftChatPanel then
            return _G.LeftChatPanel
        elseif CH.RightChatWindow and frame == CH.RightChatWindow and _G.RightChatPanel then
            return _G.RightChatPanel
        end
    end

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
    if editBox and editBox.IsShown and editBox:IsShown() and editBox.GetAttribute then
        local chatType = editBox:GetAttribute("chatType")
        if type(chatType) == "string" then
            return chatType
        end
    end
    return nil
end

local function UpdateButtonState()
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

    UpdateButtonState()
end

local function LayoutButtons()
    if not container then
        return
    end

    local E = GetElvUI()
    local db = GetDB()
    local configuredSize = 24
    local sideGap = 18
    if db and type(db.quickChatButtonSize) == "number" then
        configuredSize = math.max(16, math.min(40, math.floor(db.quickChatButtonSize + 0.5)))
    end
    if db and type(db.quickChatButtonGap) == "number" then
        sideGap = math.max(8, math.min(36, math.floor(db.quickChatButtonGap + 0.5)))
    end

    local frame = GetAnchorFrame()
    if not frame then
        return
    end

    local spacing = GetConfiguredSpacing()
    local outerPadding = GetConfiguredTheme() == "ELVUI" and 5 or 4
    local buttonCount = #BUTTON_DEFS
    local chatHeight = math.max(1, math.floor((frame.GetHeight and frame:GetHeight()) or 180))
    local fitHeight = math.max(chatHeight, math.floor(chatHeight * 1.35))
    local maxUsableSize = math.floor((fitHeight - ((buttonCount - 1) * spacing) - (outerPadding * 2)) / buttonCount)
    if maxUsableSize < 12 then
        maxUsableSize = 12
    end

    local size = math.max(12, math.min(configuredSize, 48))
    local desiredTotalHeight = (size * buttonCount) + (spacing * (buttonCount - 1))
    if desiredTotalHeight > fitHeight then
        size = math.max(12, math.min(size, maxUsableSize))
    end

    local totalHeight = (size * buttonCount) + (spacing * (buttonCount - 1))
    local holderHeight = totalHeight + (outerPadding * 2)

    container:ClearAllPoints()
    container:SetParent(GetAnchorParent())
    container:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", sideGap, 0)
    container:SetHeight(math.max(chatHeight, holderHeight))
    container:SetWidth(size + (GetConfiguredTheme() == "ELVUI" and 10 or 8))

    if container.SetFrameStrata then
        container:SetFrameStrata(E and "HIGH" or "MEDIUM")
    end
    if frame.GetFrameLevel and container.SetFrameLevel then
        container:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    end

    ApplyContainerStyle()

    local previous
    for _, def in ipairs(BUTTON_DEFS) do
        local button = buttons[def.key]
        if button then
            button:ClearAllPoints()
            button:SetSize(size, size)

            if previous then
                button:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
            else
                button:SetPoint("BOTTOM", container, "BOTTOM", 0, outerPadding)
            end

            if button.Label then
                local fontSize = math.max(10, math.floor(size * 0.48 * GetConfiguredFontScale()))
                if GetConfiguredTheme() == "ELVUI" and E and type(button.Label.FontTemplate) == "function" then
                    pcall(button.Label.FontTemplate, button.Label, nil, fontSize, "OUTLINE")
                else
                    local fontPath = STANDARD_TEXT_FONT
                    if ChatFontNormal and ChatFontNormal.GetFont then
                        fontPath = ChatFontNormal:GetFont() or fontPath
                    end
                    pcall(button.Label.SetFont, button.Label, fontPath, fontSize, "OUTLINE")
                end
                button.Label:ClearAllPoints()
                button.Label:SetPoint("CENTER", button, "CENTER", 0, 0)
            end

            if button.Highlight then
                button.Highlight:SetAllPoints(button)
            end

            if button.Accent then
                button.Accent:ClearAllPoints()
                button.Accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
                button.Accent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                button.Accent:SetHeight(math.max(2, math.floor(size * 0.12)))
            end

            if button.Inner then
                button.Inner:ClearAllPoints()
                button.Inner:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
                button.Inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
            end

            if button.Gloss then
                button.Gloss:ClearAllPoints()
                button.Gloss:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                button.Gloss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
                button.Gloss:SetHeight(math.max(4, math.floor(size * 0.34)))
            end

            if button.Glow then
                button.Glow:ClearAllPoints()
                button.Glow:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
                button.Glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
            end

            if button.Shade then
                button.Shade:SetAllPoints(button)
            end

            previous = button
            RefreshButtonLook(button)
        end
    end
end

local function HookAnchorFrameSignals()
    local frame = GetAnchorFrame()
    if not frame or frame == hookedAnchorFrame or not frame.HookScript then
        return
    end

    hookedAnchorFrame = frame
    frame:HookScript("OnSizeChanged", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ns.RefreshQuickChatButtons)
        else
            ns.RefreshQuickChatButtons()
        end
    end)
    frame:HookScript("OnShow", ns.RefreshQuickChatButtons)
    frame:HookScript("OnHide", ns.RefreshQuickChatButtons)
end

local function HookEditBoxSignals()
    local editBox = GetActiveEditBox()
    if not editBox or editBox == hookedEditBox or not editBox.HookScript then
        return
    end

    hookedEditBox = editBox
    editBox:HookScript("OnShow", UpdateButtonState)
    editBox:HookScript("OnHide", UpdateButtonState)
    editBox:HookScript("OnEditFocusGained", UpdateButtonState)
    editBox:HookScript("OnEditFocusLost", UpdateButtonState)
    editBox:HookScript("OnTextChanged", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, UpdateButtonState)
        else
            UpdateButtonState()
        end
    end)
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
                AddTooltipLine("Skin", GetConfiguredTheme() == "ELVUI" and "ElvUI" or "Standard", 0.72, 0.72, 0.72)
                GameTooltip:Show()
            end
        end)

        button:SetScript("OnLeave", function(self)
            RefreshButtonLook(self)
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        button:SetScript("OnMouseDown", function(self)
            if self.Label then
                self.Label:ClearAllPoints()
                self.Label:SetPoint("CENTER", self, "CENTER", 1, -1)
            end
        end)

        button:SetScript("OnMouseUp", function(self)
            if self.Label then
                self.Label:ClearAllPoints()
                self.Label:SetPoint("CENTER", self, "CENTER", 0, 0)
            end
        end)

        buttons[def.key] = button
    end
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
        _G.LeftChatPanel:HookScript("OnSizeChanged", function() ScheduleRefresh(0) end)
        _G.LeftChatPanel.__chatifyElvUIHooked = true
    end

    if _G.RightChatPanel and _G.RightChatPanel.HookScript and not _G.RightChatPanel.__chatifyElvUIHooked then
        _G.RightChatPanel:HookScript("OnShow", function() ScheduleRefresh(0) end)
        _G.RightChatPanel:HookScript("OnSizeChanged", function() ScheduleRefresh(0) end)
        _G.RightChatPanel.__chatifyElvUIHooked = true
    end

    elvuiHooksInstalled = true
end

function ns.RefreshQuickChatButtons()
    local db = GetDB()
    if not db or db.quickChatButtons == false then
        if container then
            container:Hide()
        end
        return
    end

    if HasElvUIChat() then
        HookElvUIRefreshSignals()
    end

    EnsureContainer()
    HookAnchorFrameSignals()
    HookEditBoxSignals()
    LayoutButtons()
    UpdateButtonState()
    container:Show()
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
    self:RegisterEvent("MODIFIER_STATE_CHANGED", function() UpdateButtonState() end)
    self:RegisterEvent("DISPLAY_SIZE_CHANGED", "Refresh")
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
        end
    end)

    ns.RefreshQuickChatButtons()

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.RefreshQuickChatButtons() end)
        C_Timer.After(1, function() ns.RefreshQuickChatButtons() end)
    end
end
