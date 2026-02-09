local addonName, ns = ...

----------------------------------------------------------------------
-- 1. Create Window for COPYING LARGE TEXT (History/Msg)
----------------------------------------------------------------------
local f = CreateFrame("Frame", "MyChatCopyFrame", UIParent, "BackdropTemplate")

f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 }
})
f:SetBackdropColor(0, 0, 0, 0.9)
f:SetSize(500, 400)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:Hide()
f:EnableMouse(true)

-- Scroll Area
local scrollArea = CreateFrame("ScrollFrame", "MyChatCopyScroll", f, "UIPanelScrollFrameTemplate")
scrollArea:SetPoint("TOPLEFT", 10, -30)
scrollArea:SetPoint("BOTTOMRIGHT", -30, 10)

-- Main EditBox
local editBox = CreateFrame("EditBox", nil, scrollArea)
editBox:SetMultiLine(true)
editBox:SetMaxLetters(99999)
editBox:EnableMouse(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(460)
editBox:SetHeight(400) 
editBox:SetScript("OnEscapePressed", function() f:Hide() end)

scrollArea:SetScrollChild(editBox)

-- Close Button
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 0, 0)

-- Global function to show the window
function ns.ShowCopyWindow(text)
    f:Show()
    editBox:SetText(text)
    editBox:HighlightText()
    editBox:SetFocus()
end

----------------------------------------------------------------------
-- 2. Create Window for COPYING URL (Small Dialog)
----------------------------------------------------------------------
StaticPopupDialogs["CHATIFY_COPY_URL"] = {
    text = "Press Ctrl+C to copy the link:",
    button1 = "OK",
    hasEditBox = true,
    editBoxWidth = 350,
    
    OnShow = function(self, data)
        -- Modern WoW uses self.EditBox (Capitalized)
        local editBox = self.EditBox
        if editBox then
            editBox:SetText(data)
            editBox:SetFocus()
            editBox:HighlightText() -- Auto-highlight text
        end
    end,
    
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, 
}

----------------------------------------------------------------------
-- 3. Click Handler (SetItemRef Hook)
----------------------------------------------------------------------
local OldSetItemRef = SetItemRef
function SetItemRef(link, text, button, chatFrame)
    
    -- Click on TIMESTAMP
    if link == "chatcopy" then
        ns.ShowCopyWindow(text) 
        return
    end

    -- Click on URL
    if link:sub(1, 4) == "url:" then
        local currentLink = link:sub(5) -- Cut off "url:" prefix
        StaticPopup_Show("CHATIFY_COPY_URL", nil, nil, currentLink)
        return
    end

    OldSetItemRef(link, text, button, chatFrame)
end