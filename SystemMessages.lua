-- Match only Blizzard notice families, using the client's own localized formats.
-- Never interpret a party/raid/instance player's text as a system announcement.
local _, ns = ...
local channelEvents = {
    CHAT_MSG_CHANNEL_JOIN = true, CHAT_MSG_CHANNEL_LEAVE = true,
    CHAT_MSG_CHANNEL_NOTICE = true, CHAT_MSG_CHANNEL_NOTICE_USER = true,
}
local families = {
    hidePlayerStatusMessages = {
        "ERR_FRIEND_ONLINE_SS", "ERR_FRIEND_OFFLINE_S", "ERR_GUILD_MEMBER_LOGIN_S",
        "BN_INLINE_TOAST_FRIEND_ONLINE", "BN_INLINE_TOAST_FRIEND_OFFLINE",
    },
    hideGroupRosterMessages = {
        "ERR_JOINED_GROUP_S", "ERR_LEFT_GROUP_S", "ERR_RAID_MEMBER_ADDED_S",
        "ERR_RAID_MEMBER_REMOVED_S", "ERR_YOU_JOINED_GROUP_S", "ERR_YOU_LEFT_GROUP_S",
        "ERR_YOU_JOINED_RAID", "ERR_YOU_LEFT_RAID",
    },
    hideBattleRosterMessages = {
        "ERR_BG_PLAYER_JOINED_SS", "ERR_BG_PLAYER_LEFT_S",
        "ERR_PLAYER_JOINED_BATTLE_D", "ERR_PLAYER_LEFT_BATTLE_D",
        "ERR_PLAYERLIST_JOINED_BATTLE", "ERR_PLAYERLIST_LEFT_BATTLE",
        "ERR_PLAYERS_JOINED_BATTLE_D", "ERR_PLAYERS_LEFT_BATTLE_D",
    },
}
local cachedFormats = {}
local channelFormats = {
    "CHAT_YOU_JOINED_NOTICE", "CHAT_YOU_LEFT_NOTICE", "CHAT_YOU_CHANGED_NOTICE",
    "CHAT_JOINED_NOTICE", "CHAT_LEFT_NOTICE", "CHAT_CHANNEL_JOIN_GET", "CHAT_CHANNEL_LEAVE_GET",
    "CHAT_YOU_JOINED_NOTICE_BN", "CHAT_YOU_LEFT_NOTICE_BN", "CHAT_YOU_CHANGED_NOTICE_BN",
    "CHAT_JOINED_NOTICE_BN", "CHAT_LEFT_NOTICE_BN",
}
local function DB()
    return ns.Chatify and ns.Chatify.db and ns.Chatify.db.profile or ns.db
end
local function Readable(value)
    if ns.IsProtectedChatValue(value) or not ns.CanAccessChatValue(value) then return false end
    return type(value) == "string"
end
local function Plain(safeText)
    return (safeText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function Literal(safeText)
    return (safeText:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end
local function FormatPattern(safeFormat)
    local parts, i = { "^" }, 1
    while i <= #safeFormat do
        local tail = safeFormat:sub(i)
        local token, kind = tail:match("^(%%%d+%$([sdiu]))")
        if not token then token, kind = tail:match("^(%%[-+ #0]*%d*%.?%d*([sdiu]))") end
        if token then
            parts[#parts + 1] = kind == "s" and ".+" or "%d+"
            i = i + #token
        elseif tail:sub(1, 2) == "%%" then
            parts[#parts + 1] = "%%"
            i = i + 2
        else
            parts[#parts + 1] = Literal(safeFormat:sub(i, i))
            i = i + 1
        end
    end
    parts[#parts + 1] = "$"
    return table.concat(parts)
end
local function Matches(safeText, key)
    local format = _G[key]
    if not Readable(format) or format == "" then return false end
    local entry = cachedFormats[key]
    if not entry or entry.format ~= format then
        entry = { format = format, pattern = FormatPattern(Plain(format)) }
        cachedFormats[key] = entry
    end
    return safeText:match(entry.pattern) ~= nil
end

function ns.SystemNoticeFiltersEnabled()
    local db = DB()
    return db and (db.hideSystemSpam or db.hidePlayerStatusMessages
        or db.hideGroupRosterMessages or db.hideBattleRosterMessages) and true or false
end

function ns.ShouldHideSystemChatEvent(eventName, message)
    if not Readable(eventName) then return false end
    local db = DB()
    if not db then return false end
    if channelEvents[eventName] then return db.hideSystemSpam and true or false end
    if eventName ~= "CHAT_MSG_SYSTEM" and eventName ~= "CHAT_MSG_BN_INLINE_TOAST_ALERT" then return false end
    if ns.IsProtectedChatValue(message) or not ns.CanAccessChatValue(message) then return false end
    if type(message) ~= "string" then return false end
    if eventName == "CHAT_MSG_BN_INLINE_TOAST_ALERT" then
        return db.hidePlayerStatusMessages and (message == "FRIEND_ONLINE" or message == "FRIEND_OFFLINE") or false
    end
    local plain = Plain(message)
    for option, formats in pairs(families) do
        if db[option] then
            for _, key in ipairs(formats) do
                if Matches(plain, key) then return true end
            end
        end
    end
    return false
end

-- AddMessage(message, r, g, b, chatTypeID, ...) is also used directly by
-- BattlegroundChatFilters without an event/eventArgs pair. Require a known
-- system chat type so a player quoting the same sentence remains visible.
function ns.ShouldHideRenderedSystemMessage(message, chatTypeID, eventName)
    if type(eventName) ~= "nil" then
        if not Readable(eventName) then return false end
        if channelEvents[eventName] then return ns.ShouldHideSystemChatEvent(eventName, message) end
        if eventName ~= "CHAT_MSG_SYSTEM" and eventName ~= "CHAT_MSG_BN_INLINE_TOAST_ALERT" then return false end
    end
    if ns.HasSecretChatValue(chatTypeID) or not ns.CanAccessChatValue(chatTypeID) then return false end
    if type(chatTypeID) ~= "number" or type(ChatTypeInfo) ~= "table" then return false end
    for _, name in ipairs({ "SYSTEM", "BN_INLINE_TOAST_ALERT" }) do
        local info = ChatTypeInfo[name]
        if type(info) == "table" and not ns.HasSecretChatValue(info.id) and ns.CanAccessChatValue(info.id)
            and chatTypeID == info.id then
            return ns.ShouldHideSystemChatEvent("CHAT_MSG_SYSTEM", message)
        end
    end
    for event in pairs(channelEvents) do
        local info = ChatTypeInfo[event:sub(10)]
        if type(info) == "table" and not ns.HasSecretChatValue(info.id) and ns.CanAccessChatValue(info.id)
            and chatTypeID == info.id then return ns.ShouldHideSystemChatEvent(event, message) end
    end
    -- Some clients color both notices and player text with CHANNEL<n>'s id.
    -- For that shared type require the localized notice format as well.
    local db = DB()
    if db and db.hideSystemSpam and Readable(message) then
        local plain = Plain(message)
        for _, key in ipairs(channelFormats) do
            if Matches(plain, key) then
                for name, info in pairs(ChatTypeInfo) do
                    if type(name) == "string" and (name == "CHANNEL" or name:match("^CHANNEL%d+$"))
                        and type(info) == "table" and not ns.HasSecretChatValue(info.id)
                        and ns.CanAccessChatValue(info.id) and chatTypeID == info.id then return true end
                end
            end
        end
    end

    return false
end
