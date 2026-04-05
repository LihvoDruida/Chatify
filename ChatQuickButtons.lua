local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")
local QuickButtonsModule = Chatify:NewModule("QuickButtons", "AceEvent-3.0")

local C_Timer = C_Timer
local container
local buttons = {}
local hookedEditBox

local function GetDB()
    if Chatify and Chatify.db and Chatify.db.profile then
        return Chatify.db.profile
    end
    return nil
end

local BUTTON_DEFS = {
    {
        key = "GUILD",
        chatType = "GUILD",
        label = "G",
        tooltip = "Гільдійський чат",
        slash = "/g ",
        isAvailable = function()
            return type(IsInGuild) == "function" and IsInGuild() or false
        end,
    },
    {
        key = "RAID",
        chatType = "RAID",
        label = "R",
        tooltip = "Рейдовий чат",
        slash = "/ra ",
        isAvailable = function()
            return type(IsInRaid) == "function" and IsInRaid(LE_PARTY_CATEGORY_HOME) or false
        end,
    },
    {
        key = "PARTY",
        chatType = "PARTY",
        label = "P",
        tooltip = "Чат групи",
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
        tooltip = "Інстанс-чат",
        slash = "/i ",
        isAvailable = function()
            return type(IsInGroup) == "function" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false
        end,
    },
    {
        key = "SAY",
        chatType = "SAY",
        label = "S",
        tooltip = "Звичайний чат",
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
    if not frame then
        return UIParent
    end

    if frame.GetName then
        local buttonFrame = _G[frame:GetName() .. "ButtonFrame"]
        if buttonFrame then
            return buttonFrame
        end
    end

    return frame
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

            local normal = button:GetNormalTexture()
            if normal then
                if enabled then
                    normal:SetVertexColor(1, 1, 1, 1)
                else
                    normal:SetVertexColor(0.45, 0.45, 0.45, 0.75)
                end
            end

            if button.Label then
                if enabled then
                    button.Label:SetTextColor(1.0, 0.82, 0.18)
                else
                    button.Label:SetTextColor(0.55, 0.55, 0.55)
                end
            end

            if button.SelectionGlow then
                local selected = enabled and currentChatType == def.chatType
                button.SelectionGlow:SetShown(selected)
            end
        end
    end
end

local function ActivateChatType(def)
    if not def or not IsButtonEnabled(def) then
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
        pcall(editBox.SetAttribute, editBox, "chatType", def.chatType)
        pcall(editBox.SetAttribute, editBox, "tellTarget", nil)
        pcall(editBox.SetAttribute, editBox, "channelTarget", nil)
        if type(ChatEdit_UpdateHeader) == "function" then
            pcall(ChatEdit_UpdateHeader, editBox)
        end

        if editBox.GetAttribute and editBox:GetAttribute("chatType") == def.chatType then
            success = true
        end
    end

    if not success and type(ChatFrame_OpenChat) == "function" and type(def.slash) == "string" then
        pcall(ChatFrame_OpenChat, def.slash, frame)
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
    local size = 22
    if db and type(db.quickChatButtonSize) == "number" then
        size = math.max(16, math.min(32, math.floor(db.quickChatButtonSize + 0.5)))
    end
    local spacing = 4

    container:ClearAllPoints()
    local parent = GetAnchorParent()
    container:SetParent(parent)

    if parent and parent ~= UIParent and parent.GetName and parent:GetName() ~= "ChatFrame1" then
        container:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
    else
        local frame = GetAnchorFrame()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", -(size + 8), -2)
    end

    container:SetSize(size, (#BUTTON_DEFS * size) + ((#BUTTON_DEFS - 1) * spacing))

    local previous
    for _, def in ipairs(BUTTON_DEFS) do
        local button = buttons[def.key]
        if button then
            button:ClearAllPoints()
            button:SetSize(size, size)
            if previous then
                button:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
            else
                button:SetPoint("TOP", container, "TOP", 0, 0)
            end
            previous = button
        end
    end
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
    container = CreateFrame("Frame", "ChatifyQuickChatButtons", parent)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)

    for _, def in ipairs(BUTTON_DEFS) do
        local button = CreateFrame("Button", "ChatifyQuickChatButton" .. def.key, container)
        button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:RegisterForClicks("LeftButtonUp")

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(def.label)
        button.Label = label

        local glow = button:CreateTexture(nil, "ARTWORK")
        glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        glow:SetBlendMode("ADD")
        glow:SetAllPoints(button)
        glow:SetShown(false)
        button.SelectionGlow = glow

        button:SetScript("OnClick", function()
            ActivateChatType(def)
        end)

        button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(def.tooltip, 1, 0.82, 0.18)
                if IsButtonEnabled(def) then
                    GameTooltip:AddLine("ЛКМ: відкрити цей тип чату", 0.9, 0.9, 0.9, true)
                else
                    GameTooltip:AddLine("Зараз недоступно", 1.0, 0.2, 0.2, true)
                end
                GameTooltip:Show()
            end
        end)

        button:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
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
