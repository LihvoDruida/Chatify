local addonName, ns = ...

-- Safety: Wait for variable initialization
ns.ApplyVisuals = ns.ApplyVisuals or function() end

-- =========================================================
-- 0. ЛОГІКА "KILLER FEATURE" (АВТО-ВКЛАДКИ)
-- =========================================================
local function SetupDefaultTabs()
    -- Перевірка, чи можна створювати вікна (в бою не можна)
    if InCombatLockdown() then 
        print("|cff33ff99Chatify:|r Неможливо налаштувати чат під час бою!") 
        return 
    end

    local tabs = {
        { 
            name = "Whisper", 
            groups = { "WHISPER", "BN_WHISPER" } 
        },
        { 
            name = "Guild",   
            groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } 
        },
        { 
            name = "Party",   
            groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } 
        }
    }

    local createdCount = 0

    for _, tabInfo in ipairs(tabs) do
        -- 1. Створюємо нове вікно
        -- FCF_OpenNewWindow існує у всіх версіях WoW (Vanilla -> Retail)
        local frame = FCF_OpenNewWindow(tabInfo.name)
        
        if frame then
            createdCount = createdCount + 1
            
            -- 2. Очищаємо всі стандартні канали та групи
            ChatFrame_RemoveAllMessageGroups(frame)
            ChatFrame_RemoveAllChannels(frame)
            
            -- 3. Додаємо лише потрібні групи
            for _, group in ipairs(tabInfo.groups) do
                ChatFrame_AddMessageGroup(frame, group)
            end
            
            -- 4. Активуємо вкладку (щоб вона засвітилася)
            if FCF_SelectDockFrame then
                FCF_SelectDockFrame(frame)
            end
        end
    end

    if createdCount > 0 then
        print("|cff33ff99Chatify:|r Успішно створено вкладок: " .. createdCount .. ". (Whisper, Guild, Party)")
    else
        print("|cff33ff99Chatify:|r Не вдалося створити вкладки (можливо, ліміт вікон досягнуто).")
    end
end

-- =========================================================
-- 1. MAIN PANEL (COMPATIBILITY MODE)
-- =========================================================
local panel = CreateFrame("Frame", "MyChatModsOptions", UIParent)
panel.name = "Chatify"

-- API Check: Retail/Modern Classic vs Old Classic/MIST
if Settings and Settings.RegisterCanvasLayoutCategory then
    -- Modern API (Dragonflight, War Within, Cata Classic)
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.SettingsCategoryID = category:GetID() -- Зберігаємо ID для слеш-команди
else
    -- Legacy API (TBC, WotLK, MoP, Vanilla)
    InterfaceOptions_AddCategory(panel)
end

-- Scroll frame for the entire panel
local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 5, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(600, 750) 
scrollFrame:SetScrollChild(content)

-- =========================================================
-- 2. UI HELPERS
-- =========================================================
local function AddTooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Helper for Backdrops across versions
local function ApplyBackdrop(frame)
    local backdropInfo = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    
    if frame.SetBackdrop then
        frame:SetBackdrop(backdropInfo)
    else
        -- Fallback for very specific client versions if mixin is missing
        Mixin(frame, BackdropTemplateMixin)
        frame:SetBackdrop(backdropInfo)
    end
end

local function CreateSection(parent, titleText, relativeTo, height, yOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if type(relativeTo) == "table" then
        header:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset or -25)
    else
        header:SetPoint("TOPLEFT", 10, yOffset or -10)
    end
    header:SetText(titleText)
    header:SetTextColor(1, 0.82, 0)

    -- "BackdropTemplate" is safe to use in CreateFrame for almost all versions.
    -- Older clients ignore it, newer clients require it.
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    container:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    container:SetHeight(height)
    
    ApplyBackdrop(container)
    container:SetBackdropColor(0.1, 0.1, 0.1, 0.4)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    return container
end

local function CreateDescription(parent, text, relativeTo, x, y, width)
    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", x, y)
    desc:SetText(text)
    desc:SetTextColor(0.6, 0.6, 0.6)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWidth(width or 250) 
    return desc
end

local function CreateCheckbox(parent, label, dbKey, x, y, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    -- Compatibility fix for CheckButton text access
    local textRegion = cb.Text or _G[cb:GetName().."Text"]
    if textRegion then textRegion:SetText(label) end
    
    local val = ns.db and ns.db[dbKey]
    cb:SetChecked(val == true)
    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db[dbKey] = self:GetChecked()
            ns.ApplyVisuals()
        end
    end)
    if tooltip then AddTooltip(cb, tooltip) end
    return cb
end

local function CreateDropdown(parent, label, listTable, dbKeyID, x, y, tooltip)
    local dropButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dropButton:SetSize(220, 25)
    dropButton:SetPoint("TOPLEFT", x, y)

    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("BOTTOMLEFT", dropButton, "TOPLEFT", 0, 5)
    lbl:SetText(label)

    local arrow = dropButton:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0)

    local listFrame = CreateFrame("Frame", nil, dropButton, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", dropButton, "BOTTOMLEFT", 0, -2)
    listFrame:SetSize(220, #listTable * 22 + 10)
    listFrame:SetFrameStrata("DIALOG")
    
    listFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16, 
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    listFrame:Hide()

    local function UpdateText()
        if not ns.db then return end
        local currentID = ns.db[dbKeyID] or 1
        local item = listTable[currentID]
        if not item then item = listTable[1] end
        dropButton:SetText(item.name)
    end
    if ns.db then UpdateText() end

    dropButton:SetScript("OnClick", function()
        if listFrame:IsShown() then listFrame:Hide() else listFrame:Show() end
    end)
    dropButton:SetScript("OnHide", function() listFrame:Hide() end)

    for i, item in ipairs(listTable) do
        local opt = CreateFrame("Button", nil, listFrame)
        opt:SetSize(200, 20)
        opt:SetPoint("TOPLEFT", 10, -5 - (i-1)*22)
        local optText = opt:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        optText:SetPoint("LEFT", 5, 0)
        optText:SetText(item.name)
        local hl = opt:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(opt)
        hl:SetColorTexture(1, 1, 1, 0.1)
        opt:SetScript("OnClick", function()
            ns.db[dbKeyID] = i
            UpdateText()
            ns.ApplyVisuals()
            listFrame:Hide()
        end)
    end
    
    if tooltip then AddTooltip(dropButton, tooltip) end
    dropButton.UpdateText = UpdateText
    return dropButton
end

-- =========================================================
-- 3. SPAM EDITOR
-- =========================================================
local function CreateSpamEditor(parent, x, y)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(200, 30)
    input:SetPoint("TOPLEFT", x, y)
    input:SetAutoFocus(false)
    input:SetTextInsets(8, 8, 0, 0)
    AddTooltip(input, "Type a word and press Enter")
    
    local inputLbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    inputLbl:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 0, 3)
    inputLbl:SetText("New keyword:")

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 5, -15)
    scrollFrame:SetSize(300, 140)
    
    local listBg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", scrollFrame, -5, 5)
    listBg:SetPoint("BOTTOMRIGHT", scrollFrame, 25, -5)
    
    ApplyBackdrop(listBg)
    listBg:SetBackdropColor(0, 0, 0, 0.3)
    listBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(280, 200)
    scrollFrame:SetScrollChild(contentFrame)

    local function RefreshList()
        if not ns.db or not ns.db.spamKeywords then return end
        if contentFrame.buttons then
            for _, btn in pairs(contentFrame.buttons) do btn:Hide() end
        end
        contentFrame.buttons = {}
        local keywords = ns.db.spamKeywords
        local height = 0
        
        for i, word in ipairs(keywords) do
            local row = CreateFrame("Button", nil, contentFrame)
            row:SetSize(280, 22)
            row:SetPoint("TOPLEFT", 0, -height)
            
            if i % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0.05)
            end
            
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            text:SetPoint("LEFT", 10, 0)
            text:SetText(word)
            
            local delBtn = CreateFrame("Button", nil, row)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("RIGHT", -5, 0)
            delBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            delBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
            delBtn:SetScript("OnClick", function()
                table.remove(ns.db.spamKeywords, i)
                RefreshList()
            end)
            AddTooltip(delBtn, "Delete")
            
            table.insert(contentFrame.buttons, row)
            height = height + 22
        end
        contentFrame:SetHeight(height)
    end

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 25)
    addBtn:SetPoint("LEFT", input, "RIGHT", 10, 0)
    addBtn:SetText("Add")
    
    local function AddWord()
        if not ns.db then return end
        local text = input:GetText()
        text = text:gsub("^%s*(.-)%s*$", "%1")
        if text and text ~= "" then
            local exists = false
            for _, w in ipairs(ns.db.spamKeywords) do
                if w:upper() == text:upper() then exists = true end
            end
            if not exists then
                table.insert(ns.db.spamKeywords, text)
                RefreshList()
                input:SetText("")
                input:ClearFocus()
            end
        end
    end
    
    addBtn:SetScript("OnClick", AddWord)
    input:SetScript("OnEnterPressed", AddWord)
    input.RefreshList = RefreshList
    return input
end

-- =========================================================
-- 4. BUILD INTERFACE (ON SHOW)
-- =========================================================
panel:SetScript("OnShow", function()
    if not ns.db then return end
    if panel.initialized then return end
    panel.initialized = true
    
    -- === TOP INFO BLOCK ===
    local infoBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", 10, -10)
    infoBox:SetPoint("RIGHT", -10, 0)
    infoBox:SetHeight(65)
    
    ApplyBackdrop(infoBox)
    infoBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    infoBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Dynamic Version Fetch (Compatible API check)
    local version = "1.0"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(addonName, "Version") or version
    elseif GetAddOnMetadata then
        version = GetAddOnMetadata(addonName, "Version") or version
    end

    local title = infoBox:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("LEFT", 16, 5)
    title:SetText("Chatify")
    title:SetTextColor(1, 0.82, 0)

    local subTitle = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subTitle:SetText("v" .. version .. "  |cffaaaaaa•  Powerful Chat Manager|r")

    -- RELOAD BUTTON (Right side)
    local reloadBtn = CreateFrame("Button", nil, infoBox, "UIPanelButtonTemplate")
    reloadBtn:SetSize(120, 25)
    reloadBtn:SetPoint("RIGHT", -15, 0)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)

    -- [NEW] BUTTON: AUTO SETUP TABS (Left of Reload Button)
    local setupBtn = CreateFrame("Button", nil, infoBox, "UIPanelButtonTemplate")
    setupBtn:SetSize(140, 25)
    setupBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -10, 0) 
    setupBtn:SetText("Create Chat Tabs")
    
    -- Classic API Compatibility for FontObjects
    if setupBtn.SetNormalFontObject then
        setupBtn:SetNormalFontObject("GameFontNormal")
        setupBtn:SetHighlightFontObject("GameFontHighlight")
    end
    
    setupBtn:SetScript("OnClick", function()
        SetupDefaultTabs()
    end)
    AddTooltip(setupBtn, "Automatically creates Whisper, Guild, and Party tabs.")

    -- === SECTION 1: GENERAL (Height 90px) ===
    local s1 = CreateSection(content, "General Settings", infoBox, 90, -20)
    
    -- Checkbox 1: Short Channels
    local cb1 = CreateCheckbox(s1, "Shorten Channels [G]", "shortChannels", 20, -25, "Converts channel names to short versions")
    CreateDescription(s1, "Automatically shortens channel names.\nExample: |cff00ff00[Party]|r -> |cff00ff00[P]|r.", cb1, 0, -5, 250)

    -- Checkbox 2: Sound Alerts
    local cbSound = CreateCheckbox(s1, "Sound Alerts", "enableSoundAlerts", 300, -25, "Play sound on Whisper or name mention")
    CreateDescription(s1, "Plays a sound when you get a Whisper or your name is mentioned in raid.", cbSound, 0, -5, 250)
    
    -- === SECTION 2: VISUALS (Height 135px) ===
    local s2 = CreateSection(content, "Fonts & Time", s1, 135)
    
    local ddFont = CreateDropdown(s2, "Chat Font", ns.Lists.Fonts, "fontID", 20, -40, "Font Style")
    CreateDescription(s2, "Changes font style.\n*Font size is configured in game settings.", ddFont, 0, -5, 230)
    
    local ddTime = CreateDropdown(s2, "Time Format", ns.Lists.TimeFormats, "timestampID", 320, -40, "Time Format")
    CreateDescription(s2, "Adds a clickable timestamp before messages.", ddTime, 0, -5, 230)

    if ddFont.UpdateText then ddFont.UpdateText() end
    if ddTime.UpdateText then ddTime.UpdateText() end

    -- === SECTION 3: HISTORY (Height 130px) ===
    local s3 = CreateSection(content, "Chat History", s2, 130)

    local histCb = CreateCheckbox(s3, "Save History", "enableHistory", 20, -15, "Saves recent messages")
    CreateDescription(s3, "Restores chat after relogging or /reload.", histCb, 300, 2, 250)

    local grayCb = CreateCheckbox(s3, "Gray History Color", "historyAlpha", 20, -50, "Makes old messages darker")

    -- SLIDER (Line count)
    local slider = CreateFrame("Slider", "MyChatHistorySlider", s3, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 320, -60)
    slider:SetWidth(200)
    slider:SetMinMaxValues(10, 100)
    
    slider:SetValue(ns.db.historyLimit or 50)
    slider:SetObeyStepOnDrag(true)
    slider:SetValueStep(10)
    
    _G[slider:GetName() .. "Low"]:SetText("10")
    _G[slider:GetName() .. "High"]:SetText("100")
    _G[slider:GetName() .. "Text"]:SetText("Lines: " .. (ns.db.historyLimit or 50))
    
    slider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value)
        ns.db.historyLimit = val
        _G[self:GetName() .. "Text"]:SetText("Lines: " .. val)
    end)
    AddTooltip(slider, "How many recent messages to keep")

    -- === SECTION 4: SPAM FILTER (Height 285px) ===
    local s4 = CreateSection(content, "Spam Filter & Privacy", s3, 285)
    
    local spamCb = CreateCheckbox(s4, "Enable Spam Filter", "enableSpamFilter", 20, -15, "Turn on filter")
    CreateDescription(s4, "Hides messages containing unwanted words.", spamCb, 300, 2, 250)
    
    local editorInput = CreateSpamEditor(s4, 20, -65)
    if editorInput and editorInput.RefreshList then editorInput.RefreshList() end
    
    -- Instruction Text
    local helpTitle = s4:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    helpTitle:SetPoint("TOPRIGHT", -20, -65)
    helpTitle:SetText("How it works?")
    helpTitle:SetJustifyH("RIGHT")
    
    local helpText = s4:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPRIGHT", -20, -85)
    helpText:SetWidth(200)
    helpText:SetJustifyH("RIGHT")
    helpText:SetText(
        "Add words (e.g. 'WTS') to hide messages containing them.\n\n" ..
        "|cff00ff00• Case insensitive|r\n(WTS = wts)\n\n" ..
        "|cff00ff00• Partial match|r\n('boosting' is blocked by 'boost')"
    )
    helpText:SetTextColor(0.7, 0.7, 0.7)
end)

SLASH_MYCHATMODS1 = "/chatify"
SLASH_MYCHATMODS2 = "/mcm"
SlashCmdList["MYCHATMODS"] = function()
    -- Compatibility Check for opening the panel
    if Settings and Settings.OpenToCategory then
        -- Modern Retail
        if ns.SettingsCategoryID then
            Settings.OpenToCategory(ns.SettingsCategoryID)
        else
            -- Fallback attempt
            Settings.OpenToCategory(panel.name) 
        end
    else
        -- Classic / Legacy
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end