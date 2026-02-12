local addonName, ns = ...
local Chatify = ns.Chatify
local History = Chatify:NewModule("History", "AceEvent-3.0", "AceHook-3.0")

-- Локальні змінні
local sessionHistory = {}
local isRestoring = false
local debugEnabled = false -- Залиште false
local debugOverlays = {}

-- =========================================================
-- БЕЗПЕЧНА ОБРОБКА ТЕКСТУ (CRITICAL FIX)
-- =========================================================
-- Ця функція повертає рядок ТІЛЬКИ якщо він безпечний для читання.
-- Якщо рядок "секретний" або викликає помилку, повертає nil.
local function GetSanitizedText(rawText)
    if rawText == nil then return nil end

    -- КРОК 1: Безпечна конвертація в рядок
    local ok, str = pcall(tostring, rawText)
    if not ok or type(str) ~= "string" then return nil end

    -- КРОК 2: Безпечна перевірка на порожнечу
    -- Саме тут виникала помилка: порівняння (str == "") крашило гру.
    -- Ми робимо це всередині pcall.
    local checkOK, isNotEmpty = pcall(function() 
        return str ~= "" 
    end)

    -- Якщо перевірка впала (checkOK == false), значить рядок захищений -> ігноруємо його.
    -- Якщо рядок порожній (isNotEmpty == false) -> ігноруємо його.
    if not checkOK or not isNotEmpty then return nil end

    return str
end

-- Допоміжна функція для ID
local function GetChatID(frame)
    if not frame then return nil end
    local name = frame:GetName()
    if not name then return nil end
    return tonumber(name:match("ChatFrame(%d+)"))
end

-- Debug Overlay
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
-- MESSAGE HOOK (SECURE)
-- =========================================================
function History:OnAddMessage(frame, text, ...)
    local db = Chatify.db.profile
    
    -- Перевірки статусу
    if not db.enableHistory or isRestoring then return end

    -- Отримуємо ID чату
    local chatID = GetChatID(frame)
    if not chatID or chatID == 2 then return end -- Ігноруємо Combat Log

    -- === ГОЛОВНЕ ВИПРАВЛЕННЯ ===
    -- Ми отримуємо текст через нашу нову захищену функцію.
    -- Якщо текст "поганий" (tainted/secret), змінна safeText буде nil.
    local safeText = GetSanitizedText(text)

    -- Тепер safeText гарантовано безпечний або nil. Порівняння не потрібні.
    if not safeText then return end

    -- Ініціалізація та запис
    sessionHistory[chatID] = sessionHistory[chatID] or {}
    table.insert(sessionHistory[chatID], safeText)

    -- Ліміт історії
    local limit = db.historyLimit or 50
    if #sessionHistory[chatID] > limit then
        table.remove(sessionHistory[chatID], 1)
    end

    UpdateDebugOverlay(frame, chatID)
end

-- =========================================================
-- RESTORE HISTORY
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
            
            -- Додаємо розділювач (опціонально)
            pcall(function() frame:AddMessage("------------------------------------------", 0.5, 0.5, 0.5) end)

            for _, msg in ipairs(messages) do
                -- Навіть при відновленні перевіряємо безпеку
                local cleanMsg = GetSanitizedText(msg)
                
                if cleanMsg then
                    -- Використовуємо pcall для AddMessage, щоб уникнути будь-яких конфліктів UI
                    pcall(function()
                        if db.historyAlpha then
                            frame:AddMessage("|cff888888"..cleanMsg.."|r")
                        else
                            frame:AddMessage(cleanMsg)
                        end
                    end)
                    table.insert(sessionHistory[id], cleanMsg)
                end
            end
            
            pcall(function() frame:AddMessage("-------------- Chat History --------------", 0.5, 0.5, 0.5) end)
            UpdateDebugOverlay(frame, id)
        end
    end

    isRestoring = false
end

-- =========================================================
-- SAVE HISTORY
-- =========================================================
function History:SaveHistory()
    local db = Chatify.db.profile
    if not db.enableHistory then return end

    ChatifyHistoryDB = {}

    for id, messages in pairs(sessionHistory) do
        if #messages > 0 then
            -- Захищене копіювання таблиці
            local ok, copy = pcall(CopyTable, messages)
            if ok and copy then
                ChatifyHistoryDB[id] = copy
            end
        end
    end
end

-- =========================================================
-- INITIALIZATION
-- =========================================================
function History:OnEnable()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..i]
        if frame then
            -- SecureHook не блокує виконання оригінальної функції
            self:SecureHook(frame, "AddMessage", "OnAddMessage")
            UpdateDebugOverlay(frame, i)
        end
    end

    self:RegisterEvent("PLAYER_LOGOUT", "SaveHistory")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "SaveHistory")

    -- Відкладений запуск відновлення
    C_Timer.After(1, function() 
        local ok, err = pcall(function() self:RestoreHistory() end)
        if not ok then 
            -- Якщо виникла помилка, просто ігноруємо її, щоб не спамити
        end
    end)
end