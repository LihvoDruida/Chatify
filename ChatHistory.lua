local addonName, ns = ...

-- Тимчасова таблиця для зберігання повідомлень поточної сесії
-- Структура: sessionHistory[ChatID] = { "msg1", "msg2" }
local sessionHistory = {} 
local isRestoring = false 

-- 1. ФУНКЦІЯ ЗАПИСУ (Мульти-фрейм)
local function RecordMessage(self, text, ...)
    -- Не записуємо, якщо історія вимкнена, йде відновлення або текст порожній
    if not ns.db or not ns.db.enableHistory or isRestoring then return end
    if not text or text == "" then return end

    -- Отримуємо ID вікна (наприклад, 1 для General, 2 для CombatLog)
    local id = self:GetID()
    
    -- Ігноруємо Combat Log (зазвичай це 2), бо там забагато спаму
    if id == 2 then return end

    -- Ініціалізуємо таблицю для цього вікна, якщо її ще немає
    if not sessionHistory[id] then 
        sessionHistory[id] = {} 
    end

    table.insert(sessionHistory[id], text)

    -- Перевірка ліміту саме для ЦЬОГО вікна
    if #sessionHistory[id] > (ns.db.historyLimit or 50) then
        table.remove(sessionHistory[id], 1)
    end
end

-- Хук для ВСІХ вікон чату
-- Використовуємо захищений виклик, щоб переконатися, що фрейм існує
for i = 1, NUM_CHAT_WINDOWS do
    local frame = _G["ChatFrame"..i]
    if frame then
        hooksecurefunc(frame, "AddMessage", RecordMessage)
    end
end

-- 2. ОБРОБНИК ПОДІЙ
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")

f:SetScript("OnEvent", function(self, event)
    
    if event == "PLAYER_LOGIN" then
        -- Ініціалізація бази
        if not ChatifyHistoryDB then ChatifyHistoryDB = {} end
        
        -- === [ВИПРАВЛЕННЯ ПОМИЛКИ] ===
        -- Перевіряємо, чи база старого формату (список рядків).
        -- Якщо перший елемент - рядок, значить це старий формат -> Очищаємо базу.
        if #ChatifyHistoryDB > 0 and type(ChatifyHistoryDB[1]) == "string" then
            ChatifyHistoryDB = {} 
            -- print("Chatify: Історія чату була скинута через оновлення формату.")
        end
        -- =============================

        -- ВІДНОВЛЕННЯ
        if ns.db and ns.db.enableHistory and next(ChatifyHistoryDB) then
            isRestoring = true 
            
            -- Проходимо по всіх збережених ID вікон
            for id, messages in pairs(ChatifyHistoryDB) do
                -- Додаткова перевірка: messages має бути таблицею
                if type(messages) == "table" then
                    local chatFrame = _G["ChatFrame"..id]
                    
                    if chatFrame and id ~= 2 then
                        -- Створюємо сесію для цього вікна
                        sessionHistory[id] = {}
                        
                        -- Розділювач
                        chatFrame:AddMessage("------------------------------------------", 0.5, 0.5, 0.5)
                        
                        for _, msg in ipairs(messages) do
                            if ns.db.historyAlpha then
                                chatFrame:AddMessage("|cff888888" .. msg .. "|r")
                            else
                                chatFrame:AddMessage(msg)
                            end
                            
                            -- Відновлюємо в пам'ять
                            table.insert(sessionHistory[id], msg)
                        end
                        
                        chatFrame:AddMessage("-------------- Chat History --------------", 0.5, 0.5, 0.5)
                    end
                end
            end
            
            isRestoring = false
        end
        
    elseif event == "PLAYER_LOGOUT" then
        -- ЗБЕРЕЖЕННЯ
        if ns.db and ns.db.enableHistory then
            ChatifyHistoryDB = sessionHistory
        else
            ChatifyHistoryDB = {} 
        end
    end
end)