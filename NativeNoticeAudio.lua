-- Native (Blizzard-owned) Battle.net online/offline notifications.
-- The same UI_BNET_TOAST audio file is shared by OTHER alerts (friend requests,
-- broadcasts), so global MuteSoundFile would silence unrelated information.
-- Instead opt in to disabling just the two native toast event families using
-- their own Social CVars. This also hides their popup; explain it in Settings.
local _, ns = ...
local TOAST_CVARS = { "showToastOnline", "showToastOffline" }
local BACKUP_KEY = "chatifyStatusToastPrior"

local function Profile()
    return ns.Chatify and ns.Chatify.db and ns.Chatify.db.profile
end
local function Global()
    return ns.Chatify and ns.Chatify.db and ns.Chatify.db.global
end
local function ReadCVar(name)
    if type(ns.GetCVarCompat) ~= "function" then return nil end
    local value = ns.GetCVarCompat(name)
    if value == "0" or value == "1" then return value end
    return nil
end
local function WriteCVar(name, value)
    if type(ns.SetCVarCompat) ~= "function" then return false end
    if not ns.SetCVarCompat(name, value) then return false end
    -- Modern Blizzard_BNet caches subscriptions on BNToastFrame, which may be
    -- lazily loaded. Trigger its public update path only where present.
    local toast = _G.BNToastFrame
    if toast and type(toast.UpdateToastEvent) == "function" then
        pcall(toast.UpdateToastEvent, toast, name, value)
    elseif type(_G.BNet_UpdateToastEvent) == "function" then
        pcall(_G.BNet_UpdateToastEvent, name, value)
    end
    return true
end

function ns.NativeStatusToastControlAvailable()
    if type(ns.SetCVarCompat) ~= "function" then return false end
    for _, key in ipairs(TOAST_CVARS) do
        if not ReadCVar(key) then return false end
    end
    return true
end

function ns.SyncNativeStatusToastControl(forceRestore)
    local profile, global = Profile(), Global()
    if not profile or not global then return false end
    local requested = forceRestore ~= true and profile.hidePlayerStatusMessages == true and profile.mutePlayerStatusSounds == true
    local backup = rawget(global, BACKUP_KEY)

    if requested then
        if not ns.NativeStatusToastControlAvailable() then return false end
        if type(backup) ~= "table" then
            backup = {}
            for _, key in ipairs(TOAST_CVARS) do backup[key] = ReadCVar(key) end
            global[BACKUP_KEY] = backup
        end
        local ok = true
        for _, key in ipairs(TOAST_CVARS) do
            if ReadCVar(key) == "1" and not WriteCVar(key, "0") then ok = false end
        end
        return ok
    end

    if type(backup) ~= "table" then return true end
    local restored = true
    for _, key in ipairs(TOAST_CVARS) do
        local previous, current = backup[key], ReadCVar(key)
        if previous == "0" or previous == "1" then
            -- A new value other than 0 means the player or another addon has
            -- already changed it: preserve that choice rather than fight it.
            if current == "0" and previous ~= current then
                if not WriteCVar(key, previous) then restored = false end
            elseif current == nil then
                restored = false
            end
        end
    end
    if restored then global[BACKUP_KEY] = nil end
    return restored
end
