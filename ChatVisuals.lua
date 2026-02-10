local addonName, ns = ...
local Chatify = LibStub("AceAddon-3.0"):GetAddon("Chatify")

-- !!! ВИПРАВЛЕННЯ ТУТ: Додано "AceHook-3.0" !!!
local VisualsModule = Chatify:NewModule("Visuals", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- 1. ДОПОМІЖНІ ФУНКЦІЇ
-- =========================================================
local function NormalizeFontSize(size)
    if type(size) ~= "number" or size <= 0 then return 14 end
    local rounded = math.floor(size + 0.5)
    if rounded <= 0 or rounded > 64 then return 14 end
    return rounded
end

function ns.GetEditBox(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.editBox then return chatFrame.editBox end
    
    local name = chatFrame:GetName()
    if name then
        local suffixBox = _G[name .. "EditBox"]
        if suffixBox then return suffixBox end
    end
    
    local id = chatFrame:GetID()
    if id then
        local idBox = _G["ChatFrame" .. id .. "EditBox"]
        if idBox then return idBox end
    end
    
    return ChatFrame1EditBox
end

-- =========================================================
-- 2. СТИЛІЗАЦІЯ
-- =========================================================
local function StyleFrame(frame)
    if not frame then return end
    local db = ns.db or Chatify.db.profile
    if not db then return end 

    local fontPath, _, _ = ChatFontNormal:GetFont()
    
    if ns.Lists and ns.Lists.Fonts and db.fontID then
        local selectedFont = ns.Lists.Fonts[db.fontID]
        if selectedFont and selectedFont.path then
            fontPath = selectedFont.path
        end
    end
    
    local _, currentSize = frame:GetFont()
    local size = NormalizeFontSize(currentSize)
    local outline = db.fontOutline or "" 

    frame:SetFont(fontPath, size, outline)
    frame:SetShadowOffset(1, -1)

    local editBox = ns.GetEditBox(frame)
    if editBox and editBox.SetFont then
        editBox:SetFont(fontPath, size, outline)
    end
end

function ns.ApplyVisuals()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then StyleFrame(frame) end
    end
    
    if ns.db and ns.db.shortChannels then
        _G.CHAT_GUILD_GET             = "|Hchannel:GUILD|h[G]|h %s:\32"
        _G.CHAT_OFFICER_GET           = "|Hchannel:OFFICER|h[O]|h %s:\32"
        _G.CHAT_PARTY_GET             = "|Hchannel:PARTY|h[P]|h %s:\32"
        _G.CHAT_PARTY_LEADER_GET      = "|Hchannel:PARTY|h[PL]|h %s:\32"
        _G.CHAT_RAID_GET              = "|Hchannel:RAID|h[R]|h %s:\32"
        _G.CHAT_RAID_LEADER_GET       = "|Hchannel:RAID|h[RL]|h %s:\32"
        _G.CHAT_INSTANCE_CHAT_GET     = "|Hchannel:INSTANCE|h[I]|h %s:\32"
        _G.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE|h[IL]|h %s:\32"
        _G.CHAT_WHISPER_GET           = "[W] %s:\32"
        _G.CHAT_WHISPER_INFORM_GET    = "[TO] %s:\32"
    end
end

-- =========================================================
-- 3. ПОДІЇ ТА ХУКИ
-- =========================================================
function VisualsModule:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN")
    
    -- Тепер SecureHook працюватиме, бо ми підключили AceHook-3.0
    self:SecureHook("FCF_OpenTemporaryWindow", ns.ApplyVisuals)
    self:SecureHook("FCF_OpenNewWindow", ns.ApplyVisuals)
    
    if FCF_SetChatWindowFontSize then
        self:SecureHook("FCF_SetChatWindowFontSize", function(chatFrame)
            StyleFrame(chatFrame)
        end)
    end
    
    for _, info in pairs(ChatTypeInfo) do
        if type(info) == "table" then
            info.colorNameByClass = true
        end
    end
end

function VisualsModule:PLAYER_LOGIN()
    ns.ApplyVisuals()
end