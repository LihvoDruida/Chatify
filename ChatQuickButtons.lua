local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local QuickButtonsModule = Chatify:NewModule("QuickButtons", "AceEvent-3.0")

local C_Timer = C_Timer
local container
local buttons = {}
local hookedEditBox
local hookedAnchorFrame
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local GetConfiguredAlpha

local function ApplyButtonBackdrop(button, bg, border)
    if not button or type(button.SetBackdrop) ~= "function" then
        return
    end

    if not button._chatifyBackdropSet then
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        button._chatifyBackdropSet = true
    end

    button:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    button:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function GetButtonPalette(button)
    local enabled = not (button and button.__chatifyDisabled)
    local selected = button and button.__chatifySelected
    local alpha = GetConfiguredAlpha()

    if not enabled then
        return { 0.11, 0.11, 0.11, math.min(alpha, 0.78) }, { 0.32, 0.32, 0.32, math.min(1, alpha + 0.12) }, { 0.55, 0.55, 0.55 }
    end

    if selected then
        return { 0.17, 0.13, 0.05, math.min(1, alpha + 0.08) }, { 0.95, 0.78, 0.22, 1.0 }, { 1.0, 0.9, 0.45 }
    end

    return { 0.07, 0.07, 0.07, alpha }, { 0.72, 0.58, 0.18, math.min(1, alpha + 0.03) }, { 1.0, 0.82, 0.18 }
end

local function RefreshButtonLook(button)
    if not button then
        return
    end

    local bg, border, textColor = GetButtonPalette(button)
    ApplyButtonBackdrop(button, bg, border)

    if button.Label then
        button.Label:SetTextColor(textColor[1], textColor[2], textColor[3])
    end

    if button.Highlight then
        button.Highlight:SetShown(not button.__chatifyDisabled and button:IsMouseOver())
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

local BUTTON_DEFS = {
    {
        key = "GUILD",
        chatType = "GUILD",
        altChatType = "OFFICER",
        label = "G",
        tooltip = "Guild Chat",
        altTooltip = "Officer Chat",
        slash = "/g ",
        altSlash = "/o ",
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
        altSlash = "/rw ",
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
        slash = "/i ",
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
        isAvailable = function()
            return true
        end,
    },
}

local function GetAnchorFrame()
    return _G.ChatFrame1 or DEFAULT_CHAT_FRAME
end

local function GetAnchorParent()
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
            button:SetEnabled(enabled)
            button.__chatifyDisabled = not enabled
            button.__chatifySelected = enabled and (currentChatType == def.chatType or (def.altChatType and currentChatType == def.altChatType))

            if button.Label then
                if enabled then
                    button.Label:SetAlpha(1)
                else
                    button.Label:SetAlpha(0.9)
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

    if type(ChatEdit_SetLastActiveWindow) == "function" then
        pcall(ChatEdit_SetLastActiveWindow, frame)
    end

    if type(ChatFrame_OpenChat) == "function" then
        pcall(ChatFrame_OpenChat, "", frame)
    end

    local editBox = GetActiveEditBox()
    local success = false

    if editBox and editBox.SetAttribute then
        pcall(editBox.SetAttribute, editBox, "chatType", target.chatType)
        pcall(editBox.SetAttribute, editBox, "tellTarget", nil)
        pcall(editBox.SetAttribute, editBox, "channelTarget", nil)
        if type(ChatEdit_UpdateHeader) == "function" then
            pcall(ChatEdit_UpdateHeader, editBox)
        end

        if editBox.GetAttribute and editBox:GetAttribute("chatType") == target.chatType then
            success = true
        end
    end

    if not success and type(ChatFrame_OpenChat) == "function" and type(target.slash) == "string" then
        pcall(ChatFrame_OpenChat, target.slash, frame)
        editBox = GetActiveEditBox() or editBox
    end

    if editBox then
        if editBox.Show then
            pcall(editBox.Show, editBox)
        end
        if editBox.SetFocus then
            pcall(editBox.SetFocus, editBox)
        end
        if type(ChatEdit_UpdateHeader) == "function" then
            pcall(ChatEdit_UpdateHeader, editBox)
        end
    end

    UpdateButtonState()
end

local function LayoutButtons()
    if not container then
        return
    end

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

    local spacing = 4
    local buttonCount = #BUTTON_DEFS
    local chatHeight = math.max(1, math.floor((frame.GetHeight and frame:GetHeight()) or 180))
    local maxUsableSize = math.floor((chatHeight - ((buttonCount - 1) * spacing)) / buttonCount)
    if maxUsableSize < 12 then
        maxUsableSize = 12
    end

    local size = configuredSize
    if size * buttonCount + (spacing * (buttonCount - 1)) > chatHeight then
        size = math.max(12, math.min(configuredSize, maxUsableSize))
    end

    local totalHeight = (size * buttonCount) + (spacing * (buttonCount - 1))

    container:ClearAllPoints()
    container:SetParent(GetAnchorParent())
    container:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", sideGap, 0)
    container:SetHeight(math.max(chatHeight, totalHeight))
    container:SetWidth(size + 4)

    local previous
    for _, def in ipairs(BUTTON_DEFS) do
        local button = buttons[def.key]
        if button then
            button:ClearAllPoints()
            button:SetSize(size, size)

            if previous then
                button:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
            else
                button:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
            end

            if button.Label then
                local fontSize = math.max(10, math.floor(size * 0.48))
                pcall(button.Label.SetFont, button.Label, STANDARD_TEXT_FONT, fontSize, "OUTLINE")
                button.Label:ClearAllPoints()
                button.Label:SetPoint("CENTER", button, "CENTER", 0, 0)
            end

            if button.Highlight then
                button.Highlight:SetAllPoints(button)
                button.Highlight:SetVertexColor(1.0, 0.85, 0.25, math.min(0.18, GetConfiguredAlpha() * 0.18))
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
        highlight:SetVertexColor(1.0, 0.85, 0.25, 0.10)
        highlight:SetAllPoints(button)
        button.Highlight = highlight

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        label:SetText(def.label)
        button.Label = label

        button:SetScript("OnClick", function(_, mouseButton)
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
                AddTooltipLine("Primary", def.chatType, 0.82, 0.82, 0.82)

                if def.altChatType then
                    AddTooltipLine("Alt Action", def.altTooltip or def.altChatType, 0.72, 0.82, 1.00)
                end

                AddTooltipLine(" ")
                AddTooltipLine("Left Click", "Switch channel", 0.95, 0.95, 0.95)

                if def.altChatType then
                    if altEnabled then
                        AddTooltipLine("Alt + Left Click", "Use alternate channel", 0.72, 0.82, 1.00)
                    else
                        AddTooltipLine("Alt + Left Click", "Alternate channel unavailable", 0.62, 0.62, 0.62)
                    end
                end

                AddTooltipLine(" ")
                if enabled then
                    AddTooltipLine("Status", "Available", 0.35, 0.95, 0.55)
                else
                    AddTooltipLine("Status", "Unavailable", 1.00, 0.35, 0.35)
                end

                AddTooltipLine("Position", "Right side of the chat frame", 0.72, 0.72, 0.72)
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

function ns.RefreshQuickChatButtons()
    local db = GetDB()
    if not db or db.quickChatButtons == false then
        if container then
            container:Hide()
        end
        return
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

    ns.RefreshQuickChatButtons()

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.RefreshQuickChatButtons() end)
        C_Timer.After(1, function() ns.RefreshQuickChatButtons() end)
    end
end
