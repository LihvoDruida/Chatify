local addonName, ns = ...
local Chatify = ns.Chatify

-- =========================================================
-- MODULE
-- =========================================================
local History = Chatify:NewModule("History", "AceEvent-3.0", "AceHook-3.0")

-- =========================================================
-- LOCALS
-- =========================================================
local sessionHistory = {}
local isRestoring = false
local debugEnabled = false
local debugOverlays = {}

-- =========================================================
-- UTILS
-- =========================================================
local function GetChatID(frame)
    if not frame then return nil end
    local name = frame:GetName()
    if not name then return nil end
    return tonumber(name:match("ChatFrame(%d+)"))
end

-- =========================================================
-- DEBUG OVERLAY
-- =========================================================
local function UpdateDebugOverlay(frame, id)
    if not debugEnabled then return end
    if not frame or not id then return end

    if not debugOverlays[id] then
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
        fs:SetTextColor(0, 1, 0)
        debugOverlays[id] = fs
    end

    local count = sessionHistory[id] and #sessionHistory[id] or 0
    debugOverlays[id]:SetText(("ID:%d | %d msg"):format(id, count))
end

-- =========================================================
-- MESSAGE HOOK
-- =========================================================
function History:OnAddMessage(frame, text)
    local db = Chatify.db.profile
    if not db.enableHistory or isRestoring then return end
    if not text or text == "" then return end

    local id = GetChatID(frame)
    if not id or id == 2 then return end -- ignore combat log

    sessionHistory[id] = sessionHistory[id] or {}
    table.insert(sessionHistory[id], text)

    local limit = db.historyLimit or 50
    if #sessionHistory[id] > limit then
        table.remove(sessionHistory[id], 1)
    end

    UpdateDebugOverlay(frame, id)
end

-- =========================================================
-- RESTORE
-- =========================================================
function History:RestoreHistory()
    local db = Chatify.db.profile
    if not db.enableHistory then return end

    ChatifyHistoryDB = ChatifyHistoryDB or {}
    if not next(ChatifyHistoryDB) then return end

    isRestoring = true

    for id, messages in pairs(ChatifyHistoryDB) do
        local frame = _G["ChatFrame"..id]
        if frame and type(messages) == "table" and id ~= 2 then
            sessionHistory[id] = {}

            frame:AddMessage("------------------------------------------", 0.5, 0.5, 0.5)

            for _, msg in ipairs(messages) do
                if db.historyAlpha then
                    frame:AddMessage("|cff888888"..msg.."|r")
                else
                    frame:AddMessage(msg)
                end
                table.insert(sessionHistory[id], msg)
            end
            frame:AddMessage("-------------- Chat History --------------", 0.5, 0.5, 0.5)

            UpdateDebugOverlay(frame, id)
        end
    end

    isRestoring = false
end

-- =========================================================
-- SAVE
-- =========================================================
function History:SaveHistory()
    local db = Chatify.db.profile
    if not db.enableHistory then return end

    ChatifyHistoryDB = {}

    for id, messages in pairs(sessionHistory) do
        if #messages > 0 then
            ChatifyHistoryDB[id] = CopyTable(messages)
        end
    end
end

-- =========================================================
-- LIFECYCLE
-- =========================================================
function History:OnEnable()
    -- hook chat frames
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..i]
        if frame then
            self:SecureHook(frame, "AddMessage", "OnAddMessage")
            UpdateDebugOverlay(frame, i)
        end
    end

    self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")

    -- restore ONLY when everything is ready
    C_Timer.After(0, function()
        self:RestoreHistory()
    end)
end
