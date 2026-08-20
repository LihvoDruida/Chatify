-- Minimal WoW / Ace3 stub so the addon can actually be loaded outside the game.
--
-- Static checks only see what the text says. This runs the files, which catches
-- the whole class of load-time faults they cannot: a nil call at file scope, a
-- table indexed before it is built, a bad upvalue, a metatable mistake, an
-- options table that errors while being constructed.
--
-- The stub is deliberately permissive: every unknown frame method returns a
-- chainable stub rather than erroring, so the harness reports the addon's own
-- mistakes rather than gaps in the stub. Anything the addon *requires* to exist
-- is modelled properly.
--
--     lua5.1 tools/stub/wow_env.lua

local M = {}

-- Records what the addon asked for that the stub did not model, so gaps are
-- visible rather than silently absorbed.
M.unknown = {}

local function noop() end

local frameMT
local function newFrame(kind, name)
    local f = {
        __kind = kind or "Frame",
        __name = name,
        __scripts = {},
        __events = {},
        __children = {},
        __points = {},
        __shown = true,
    }
    return setmetatable(f, frameMT)
end
M.newFrame = newFrame

local realFrameMethods = {
    RegisterEvent = function(self, e) self.__events[e] = true end,
    UnregisterEvent = function(self, e) self.__events[e] = nil end,
    UnregisterAllEvents = function(self) self.__events = {} end,
    IsEventRegistered = function(self, e) return self.__events[e] or false end,
    SetScript = function(self, k, fn) self.__scripts[k] = fn end,
    GetScript = function(self, k) return self.__scripts[k] end,
    HookScript = function(self, k, fn)
        local prev = self.__scripts[k]
        self.__scripts[k] = function(...)
            if prev then prev(...) end
            return fn(...)
        end
    end,
    Show = function(self) self.__shown = true end,
    Hide = function(self) self.__shown = false end,
    IsShown = function(self) return self.__shown end,
    IsVisible = function(self) return self.__shown end,
    GetName = function(self) return self.__name end,
    GetID = function(self) return self.__id or 1 end,
    SetID = function(self, id) self.__id = id end,
    GetParent = function(self) return self.__parent end,
    SetParent = function(self, p) self.__parent = p end,
    CreateTexture = function(self) return newFrame("Texture") end,
    CreateFontString = function(self) return newFrame("FontString") end,
    GetNumPoints = function() return 0 end,
    GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    GetWidth = function() return 400 end,
    GetHeight = function() return 200 end,
    GetText = function(self) return self.__text or "" end,
    SetText = function(self, t) self.__text = t end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
    GetMaxLines = function(self) return self.__maxLines or 128 end,
    SetMaxLines = function(self, n) self.__maxLines = n end,
    GetScrollOffset = function() return 0 end,
    AtBottom = function() return true end,
    AddMessage = function(self, text) self.__last = text end,
    GetNumMessages = function() return 0 end,
    GetMessageInfo = function() return nil end,
}

frameMT = {
    __index = function(t, k)
        local real = realFrameMethods[k]
        if real then return real end
        -- Unknown method: record it once and hand back a permissive stub.
        if type(k) == "string" and k:match("^%u") then
            M.unknown[t.__kind .. ":" .. k] = true
            return function() return nil end
        end
        return nil
    end,
}

function M.install(mode)
    M.mode = mode or "classic"
    local G = _G

    G.UIParent = newFrame("Frame", "UIParent")
    G.WorldFrame = newFrame("Frame", "WorldFrame")
    G.NUM_CHAT_WINDOWS = 10

    for i = 1, 10 do
        local f = newFrame("ScrollingMessageFrame", "ChatFrame" .. i)
        f.__id = i
        G["ChatFrame" .. i] = f
        G["ChatFrame" .. i .. "Tab"] = newFrame("Button", "ChatFrame" .. i .. "Tab")
        G["ChatFrame" .. i .. "EditBox"] = newFrame("EditBox", "ChatFrame" .. i .. "EditBox")
    end
    G.DEFAULT_CHAT_FRAME = G.ChatFrame1
    G.SELECTED_CHAT_FRAME = G.ChatFrame1
    G.ChatFrameMenuButton = newFrame("Button", "ChatFrameMenuButton")
    G.QuickJoinToastButton = newFrame("Button", "QuickJoinToastButton")

    -- Every frame is kept so events can actually be delivered. Libraries such as
    -- AceDB do real work from PLAYER_LOGOUT, and a test that cannot fire that
    -- event cannot tell whether settings survive a logout.
    M.frames = {}

    G.CreateFrame = function(kind, name, parent, template)
        local f = newFrame(kind, name)
        f.__parent = parent
        f.__template = template
        if name then G[name] = f end
        M.frames[#M.frames + 1] = f
        return f
    end

    G.GetTime = function() return 1000.0 end
    G.time = os.time
    G.date = os.date
    G.GetServerTime = os.time
    G.InCombatLockdown = function() return false end
    G.IsInInstance = function() return false, "none" end
    G.IsInGroup = function() return false end
    G.IsInRaid = function() return false end
    G.UnitName = function() return "Tester", "Realm" end
    G.UnitGUID = function() return "Player-1-00000001" end
    G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    G.GetRealmName = function() return "Realm" end
    G.GetLocale = function() return "enUS" end
    G.GetBuildInfo = function() return "12.1.0", "68914", "Aug 05 2026", 120100 end
    G.Ambiguate = function(n) return n end
    G.IsShiftKeyDown = function() return false end
    G.IsControlKeyDown = function() return false end
    G.IsAltKeyDown = function() return false end
    G.PlaySoundFile = noop
    G.PlaySound = noop
    G.GetChannelList = function() return 1, "General - Elwynn Forest", false,
                                        2, "Trade - City", false end
    G.GetChannelName = function() return 1, "General", 0 end
    G.JoinChannelByName = noop
    G.SendChatMessage = noop
    G.LoggingChat = function() return false end
    G.hooksecurefunc = function(a, b, c)
        if type(a) == "string" then return end
        return true
    end
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.tContains = function(t, v)
        for _, x in ipairs(t) do if x == v then return true end end
        return false
    end
    G.strsplit = function(sep, str)
        local out = {}
        for piece in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = piece end
        return unpack(out)
    end
    G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
    G.format = string.format
    G.gsub = string.gsub
    G.strfind = string.find
    G.strsub = string.sub
    G.strlower = string.lower
    G.strupper = string.upper
    G.max = math.max
    G.min = math.min
    G.floor = math.floor
    G.abs = math.abs
    G.tinsert = table.insert
    G.tremove = table.remove
    G.sort = table.sort
    G.unpack = unpack

    -- C_Timer used to swallow the callback entirely, which meant every piece of
    -- deferred login work - the channel label migration, the timestamp retry, the
    -- delayed visual passes - was never exercised by any test. Callbacks are now
    -- queued with their delay so a test can run them explicitly.
    M.pendingTimers = {}
    G.C_Timer = {
        After = function(delay, fn)
            if type(fn) == "function" then
                M.pendingTimers[#M.pendingTimers + 1] = { delay = tonumber(delay) or 0, fn = fn }
            end
            return fn
        end,
        NewTicker = function() return { Cancel = noop } end,
    }
    G.C_CVar = {
        AreCVarsLoaded = function() return true end,
        GetCVar = function() return "none" end,
        SetCVar = function() return true end,
    }
    G.GetCVar = G.C_CVar.GetCVar
    G.SetCVar = G.C_CVar.SetCVar
    G.C_AddOns = {
        GetAddOnMetadata = function(_, key) return key == "Version" and "0.0.0" or nil end,
        IsAddOnLoaded = function() return false end,
        LoadAddOn = function() return true end,
    }
    G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = noop,
        GetChannelShortcutForChannelID = function() return nil end,
    }
    G.C_FriendList = {
        IsFriend = function() return false end,
        GetFriendInfoByName = function() return nil end,
        GetNumFriends = function() return 0 end,
    }
    G.C_BattleNet = { GetAccountInfoByID = function() return nil end }
    G.C_Container = {}
    G.C_Sound = { PlaySound = noop, PlaySoundWithOptions = noop }

    -- Chat GlobalStrings that the template rewrite derives its patterns from.
    G.CHAT_SAY_GET = "%s says: "
    G.CHAT_YELL_GET = "%s yells: "
    G.CHAT_WHISPER_GET = "%s whispers: "
    G.CHAT_WHISPER_INFORM_GET = "To %s: "
    G.CHAT_BN_WHISPER_GET = "%s whispers: "
    G.CHAT_BN_WHISPER_INFORM_GET = "To %s: "
    G.CHAT_RAID_WARNING_GET = "[Raid Warning] %s: "
    G.GUILD, G.OFFICER, G.PARTY, G.RAID = "Guild", "Officer", "Party", "Raid"
    G.PARTY_LEADER, G.RAID_LEADER = "Party Leader", "Raid Leader"
    G.RAID_WARNING = "Raid Warning"
    G.INSTANCE_CHAT, G.INSTANCE_CHAT_LEADER = "Instance", "Instance Leader"
    G.CHAT_MSG_SAY = "Say"
    G.OKAY, G.CANCEL, G.CLOSE, G.NONE = "Okay", "Cancel", "Close", "None"

    G.ChatFrameUtil = nil          -- pre-namespace client; the resolver must cope
    G.ChatFrame_AddMessageEventFilter = function() return true end
    G.ChatFrame_RemoveMessageEventFilter = function() return true end
    G.ChatFrame_OpenChat = noop
    G.FCF_GetCurrentChatFrame = function() return G.ChatFrame1 end
    G.FCF_GetChatWindowInfo = function() return "General" end
    G.FCF_IsWindowIDCombatLog = function(id) return id == 2 end
    G.ChatEdit_GetLastActiveWindow = function() return G.ChatFrame1EditBox end
    G.ChatEdit_SetLastActiveWindow = noop
    G.ChatEdit_ParseText = noop
    G.ChatEdit_ChooseBoxForSend = function() return G.ChatFrame1EditBox end
    G.ScrollingEdit_OnUpdate = noop
    G.ScrollingEdit_OnCursorChanged = noop
    G.StaticPopupDialogs = {}
    G.StaticPopup_Show = noop
    G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
    G.SlashCmdList = {}

    -- Two shapes, because the addon branches hard on this.
    --
    -- classic: no secret-value API at all. Most likely to expose an unguarded
    --   Retail-only call.
    -- retail: the API exists and marked values are reported as secret.
    --
    -- IMPORTANT, and this stub used to claim otherwise: reading or comparing a
    -- marked value here does NOT error the way it does in game. The sentinel is an
    -- ordinary Lua string, so `msg == ""`, `#msg` and `msg:sub()` all succeed. In
    -- game those operations raise "attempt to compare/index a secret string value"
    -- once execution is tainted, and Lua 5.1 offers no way to build a value that
    -- both reports type() == "string" and errors on comparison.
    --
    -- So what is testable here is the outcome - a secret payload must be rejected,
    -- and must come back byte-identical rather than rewritten - not the error. Guard
    -- *ordering* (the guard running before anything touches the payload) cannot be
    -- caught by this harness at all and has to be held by review.
    if M.mode == "retail" then
        local secrets = setmetatable({}, { __mode = "k" })
        M.markSecret = function(value)
            secrets[value] = true
            return value
        end

        -- The sentinel is a real string, because that is what a secret value is
        -- in game: type() reports "string", which is precisely why a type check is
        -- not a guard. A table would have been filtered out by every
        -- `type(text) == "string"` branch and proved nothing.
        local secretString = "\1CHATIFY_SECRET_PAYLOAD\1"
        secrets[secretString] = true
        M.secretString = secretString

        G.issecretvalue = function(v) return secrets[v] == true end
        G.hasanysecretvalues = function(...)
            for i = 1, select("#", ...) do
                if secrets[select(i, ...)] then return true end
            end
            return false
        end
        G.canaccessvalue = function(v) return not secrets[v] end
        G.canaccessallvalues = function(...)
            for i = 1, select("#", ...) do
                if secrets[select(i, ...)] then return false end
            end
            return true
        end
        G.GetBuildInfo = function() return "12.1.0", "68914", "Aug 05 2026", 120100 end
        G.WOW_PROJECT_ID = 1
        G.WOW_PROJECT_MAINLINE = 1
        G.ChatFrameUtil = {
            AddMessageEventFilter = function() return true end,
            RemoveMessageEventFilter = function() return true end,
            OpenChat = noop,
            GetCurrentChatFrame = function() return G.ChatFrame1 end,
            GetChatWindowInfo = function() return "General" end,
            IsWindowIDCombatLog = function(id) return id == 2 end,
            GetLastActiveWindow = function() return G.ChatFrame1EditBox end,
            SetLastActiveWindow = noop,
        }
    else
        G.issecretvalue = nil
        G.hasanysecretvalues = nil
        G.canaccessvalue = nil
        G.canaccessallvalues = nil
    end

    M.installLibStub()
end

-- Ace3 is not vendored into this harness, so LibStub hands back small stand-ins
-- that satisfy the calls the addon makes.
-- Dispatches an event to every frame registered for it, the way the client does.
-- Runs everything scheduled through C_Timer.After with a delay at or below
-- `upTo`, in schedule order. Callbacks that schedule more work are picked up on
-- the next pass, with a cap so a self-rescheduling timer cannot hang the test.
function M.runPendingTimers(upTo)
    upTo = tonumber(upTo) or math.huge
    local ran = 0

    for _ = 1, 8 do
        local queue = M.pendingTimers or {}
        if #queue == 0 then
            break
        end
        M.pendingTimers = {}

        local deferred = {}
        for _, entry in ipairs(queue) do
            if entry.delay <= upTo then
                ran = ran + 1
                local ok, err = pcall(entry.fn)
                if not ok then
                    print("  note: deferred timer failed: " .. tostring(err))
                end
            else
                deferred[#deferred + 1] = entry
            end
        end

        for _, entry in ipairs(deferred) do
            M.pendingTimers[#M.pendingTimers + 1] = entry
        end
    end

    return ran
end

function M.fireEvent(event, ...)
    local delivered = 0
    for _, frame in ipairs(M.frames or {}) do
        if frame.__events and frame.__events[event] then
            local handler = frame.__scripts and frame.__scripts.OnEvent
            if handler then
                delivered = delivered + 1
                local ok, err = pcall(handler, frame, event, ...)
                if not ok then
                    M.eventErrors = M.eventErrors or {}
                    M.eventErrors[#M.eventErrors + 1] = event .. ": " .. tostring(err)
                end
            end
        end
    end
    return delivered
end

function M.installLibStub()
    local libs = {}

    -- Embeds are honoured rather than assumed. Handing every module the same
    -- fixed method set hid a real difference: only modules that ask for
    -- AceConsole-3.0 get RegisterChatCommand, and a module calling it without
    -- the embed errors in game exactly as it does here.
    local embedMethods = {
        ["AceEvent-3.0"] = { "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents",
                             "RegisterMessage", "UnregisterMessage", "SendMessage" },
        ["AceConsole-3.0"] = { "RegisterChatCommand", "UnregisterChatCommand",
                               "Print", "Printf" },
        ["AceHook-3.0"] = { "Hook", "HookScript", "SecureHook", "SecureHookScript",
                            "Unhook", "UnhookAll", "IsHooked", "RawHook", "RawHookScript" },
        ["AceTimer-3.0"] = { "ScheduleTimer", "ScheduleRepeatingTimer",
                             "CancelTimer", "CancelAllTimers" },
    }

    -- AceHook:RawHook on a global is modelled for real rather than stubbed to a
    -- no-op. Replacing a Blizzard global is a taint vector, so a test that cannot
    -- observe the replacement cannot catch the mistake - which is exactly how a raw
    -- hook on SetItemRef survived every check until a user reported
    -- ADDON_ACTION_FORBIDDEN on GetDiscordUserName.
    local aceHookMethods = {
        RawHook = function(self, target, handler)
            if type(target) ~= "string" then
                return
            end

            local original = _G[target]
            if type(original) ~= "function" then
                return
            end

            self.hooks = self.hooks or {}
            self.hooks[target] = original

            local methodName = type(handler) == "string" and handler or target
            _G[target] = function(...)
                local fn = self[methodName]
                if type(fn) == "function" then
                    return fn(self, ...)
                end
                return original(...)
            end
        end,
        IsHooked = function(self, target)
            return self.hooks ~= nil and self.hooks[target] ~= nil
        end,
        Unhook = function(self, target)
            if self.hooks and self.hooks[target] then
                _G[target] = self.hooks[target]
                self.hooks[target] = nil
            end
        end,
    }

    local function applyEmbeds(target, ...)
        for i = 1, select("#", ...) do
            local libName = select(i, ...)
            local methods = embedMethods[libName]
            if methods then
                for _, m in ipairs(methods) do
                    target[m] = target[m] or aceHookMethods[m] or noop
                end
            else
                M.unknown["embed:" .. tostring(libName)] = true
            end
        end
        return target
    end

    local AceAddon = {}
    local createdAddons = {}

    AceAddon.NewAddon = function(_, name, ...)
        local addon = { name = name, modules = {}, orderedModules = {} }
        applyEmbeds(addon, ...)

        addon.NewModule = function(self, modName, ...)
            local m = { name = modName, moduleName = modName }
            applyEmbeds(m, ...)
            self.modules[modName] = m
            self.orderedModules[#self.orderedModules + 1] = m
            return m
        end
        addon.GetModule = function(self, modName) return self.modules[modName] end
        addon.SetDefaultModuleLibraries = noop
        addon.IterateModules = function(self) return pairs(self.modules) end

        createdAddons[name] = addon
        return addon
    end

    -- Must return the addon created above: files after the first fetch the same
    -- object with GetAddon, and returning nil made every one of them fail at
    -- load with "attempt to index local 'Chatify'".
    AceAddon.GetAddon = function(_, name) return createdAddons[name] end

    libs["AceAddon-3.0"] = AceAddon

    libs["AceDB-3.0"] = {
        New = function(_, _, defaults)
            local db = {
                profile = {},
                char = {},
                global = {},
                RegisterCallback = noop,
                ResetProfile = noop,
                GetCurrentProfile = function() return "Default" end,
            }
            if defaults then
                for scope, values in pairs(defaults) do
                    if type(values) == "table" and db[scope] then
                        for k, v in pairs(values) do
                            if type(v) == "table" then
                                local copy = {}
                                for k2, v2 in pairs(v) do copy[k2] = v2 end
                                db[scope][k] = copy
                            else
                                db[scope][k] = v
                            end
                        end
                    end
                end
            end
            return db
        end,
    }

    local registered = {}
    libs["AceConfig-3.0"] = {
        RegisterOptionsTable = function(_, name, tbl)
            registered[name] = tbl
            return true
        end,
    }
    libs["AceConfigDialog-3.0"] = {
        AddToBlizOptions = function() return newFrame("Frame") end,
        Open = noop, Close = noop, SetDefaultSize = noop,
    }
    libs["AceConfigRegistry-3.0"] = { NotifyChange = noop }
    libs["AceDBOptions-3.0"] = { GetOptionsTable = function() return { name = "Profiles", type = "group", args = {} } end }
    libs["AceLocale-3.0"] = {
        NewLocale = function() return setmetatable({}, { __newindex = rawset }) end,
        GetLocale = function()
            return setmetatable({}, { __index = function(_, k) return k end })
        end,
    }
    libs["LibSharedMedia-3.0"] = {
        Register = noop,
        Fetch = function() return "Fonts\\FRIZQT__.TTF" end,
        List = function() return { "Default" } end,
        HashTable = function() return { Default = "Fonts\\FRIZQT__.TTF" } end,
        MediaType = { FONT = "font", SOUND = "sound", STATUSBAR = "statusbar" },
        RegisterCallback = noop,
    }

    _G.LibStub = setmetatable({
        GetLibrary = function(_, name, silent)
            local lib = libs[name]
            if not lib and not silent then
                M.unknown["LibStub:" .. name] = true
            end
            return lib
        end,
        NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end,
    }, {
        __call = function(self, name, silent) return self:GetLibrary(name, silent) end,
    })

    M.registeredOptions = registered
end

return M
