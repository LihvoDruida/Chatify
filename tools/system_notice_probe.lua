-- Localized system-notice contracts. Real addon code, modeled frame transport.
-- Optional pinned Blizzard source reproduces the reported aggregation without
-- Chatify, then exercises the same Lua producer with Chatify's post-hook active.
package.path = 'tools/stub/?.lua;' .. package.path
local env = require('wow_env')
local client = os.getenv('CHATIFY_SETTINGS_CLIENT') or 'retail'
local fixture = require('client_fixtures').install(env, client)
local unpack = unpack or table.unpack
local checks = 0
local function check(name, result)
    checks = checks + 1
    assert(result, 'system notices: ' .. name)
end
local formats = {
    ERR_PLAYER_JOINED_BATTLE_D = '%s has joined the battle.',
    ERR_PLAYER_LEFT_BATTLE_D = '%s has left the battle.',
    ERR_PLAYERLIST_JOINED_BATTLE = '%d players have joined the battle: %s.',
    ERR_PLAYERLIST_LEFT_BATTLE = '%d players have left the battle: %s.',
    ERR_PLAYERS_JOINED_BATTLE_D = '%d players have joined the battle.',
    ERR_PLAYERS_LEFT_BATTLE_D = '%d players have left the battle.',
    ERR_BG_PLAYER_JOINED_SS = '%s has joined the battle (%s).',
    ERR_BG_PLAYER_LEFT_S = '%s has left the battle.',
    ERR_FRIEND_ONLINE_SS = '|Hplayer:%s|h[%s]|h has come online.',
    ERR_FRIEND_OFFLINE_S = '%s has gone offline.',
    ERR_GUILD_MEMBER_LOGIN_S = '%s has come online.',
    BN_INLINE_TOAST_FRIEND_ONLINE = '%s has come online.',
    BN_INLINE_TOAST_FRIEND_OFFLINE = '%s has gone offline.',
    ERR_JOINED_GROUP_S = '%s joins the party.', ERR_LEFT_GROUP_S = '%s leaves the party.',
    ERR_RAID_MEMBER_ADDED_S = '%s has joined the raid group.',
    ERR_RAID_MEMBER_REMOVED_S = '%s has left the raid group.',
    CHAT_YOU_CHANGED_NOTICE = 'Changed Channel: [%d. %s]',
}
for key, value in pairs(formats) do _G[key] = value end
ChatTypeInfo = {SYSTEM = {id=1,r=1,g=1,b=0}, PARTY = {id=2}, INSTANCE_CHAT = {id=3},
    BN_INLINE_TOAST_ALERT = {id=4}, CHANNEL_JOIN = {id=5}, CHANNEL_LEAVE = {id=6},
    CHANNEL_NOTICE = {id=7}, CHANNEL_NOTICE_USER = {id=8}, CHANNEL1={id=9}}
local filters = {}
local function addFilter(event, fn)
    filters[event] = filters[event] or {}; filters[event][fn] = true
end
local function removeFilter(event, fn) if filters[event] then filters[event][fn] = nil end end
if ChatFrameUtil then
    ChatFrameUtil.AddMessageEventFilter, ChatFrameUtil.RemoveMessageEventFilter = addFilter, removeFilter
else
    ChatFrame_AddMessageEventFilter, ChatFrame_RemoveMessageEventFilter = addFilter, removeFilter
end
local frame = ChatFrame1
frame.buffer = {}
frame.AddMessage = function(self, text, r, g, b, ...)
    self.buffer[#self.buffer+1] = {text=text, meta={n=select('#',...),...}}
end
frame.TransformMessages = function() end
frame.RemoveMessagesByPredicate = function(self, predicate)
    for i=#self.buffer,1,-1 do
        local entry=self.buffer[i]
        if predicate(entry.text,1,1,0,unpack(entry.meta,1,entry.meta.n)) then table.remove(self.buffer,i) end
    end
    -- Blizzard's method has no success return value.
end
hooksecurefunc = function(target, method, callback)
    if type(target)=='string' then return end
    local original=target[method]
    target[method]=function(self,...)
        original(self,...)
        callback(self,...)
    end
end
local source = os.getenv('FOREVER_UI_SOURCE')
local controller
if source then
    tinsert, PLAYER_LIST_DELIMITER = table.insert, ', '
    GetBattlefieldWinner = function() return nil end
    ChatFrameUtil = ChatFrameUtil or {AddMessageEventFilter=addFilter,RemoveMessageEventFilter=removeFilter}
    assert(loadfile(source .. '/Interface/AddOns/Blizzard_ChatFrame/Mainline/BattlegroundChatFilters.lua'))()
    controller=env.newFrame('Frame')
    for key,value in pairs(BattlegroundChatFiltersMixin) do controller[key]=value end
    controller:OnLoad(); controller:StartBGChatFilter()
    controller:FilterChatMsgSystem('CHAT_MSG_SYSTEM', 'First has joined the raid group.')
    controller:FilterChatMsgSystem('CHAT_MSG_SYSTEM', 'Second has joined the raid group.')
    controller:OnUpdate(30)
    check('Blizzard creates reported summary without Chatify', #frame.buffer==1
        and frame.buffer[1].text:match('^2 players have joined the battle:'))
    controller:StopBGChatFilter()
    frame.buffer={}
end
local ns={}
for line in io.lines(fixture[4]) do
    if line:match('%.lua$') then assert(loadfile((line:gsub('\\','/'))))('Chatify',ns) end
end
local addon=ns.Chatify
addon:OnInitialize()
local db=addon.db.profile
db.enableSpamFilter,db.enableThrottle=false,false
db.enableHistory=true
addon.modules.History:OnEnable()
ns.RefreshSecureChatTransforms()
local function history() return ns.GetChatifyHistoryEntriesForFrame(frame,1000) or {} end
local function emit(text,id,event)
    if event then frame:AddMessage(text,1,1,0,id,nil,nil,event,{text,'Sender'})
    else frame:AddMessage(text,1,1,0,id) end
end
local function reset() frame.buffer={} end
local sample='2 players have joined the battle: First, Second.'
check('battle notices hidden by default',db.hideBattleRosterMessages==true)
check('new presence and group options are opt-in',db.hidePlayerStatusMessages==false and db.hideGroupRosterMessages==false)
for _,event in ipairs({'CHAT_MSG_CHANNEL_JOIN','CHAT_MSG_CHANNEL_LEAVE','CHAT_MSG_CHANNEL_NOTICE','CHAT_MSG_CHANNEL_NOTICE_USER'}) do
    check('channel event '..event,ns.ShouldHideSystemChatEvent(event,'YOU_CHANGED'))
end
check('channel setting is independent',not ns.ShouldHideSystemChatEvent('CHAT_MSG_CHANNEL',sample))
for _,key in ipairs({'ERR_PLAYER_JOINED_BATTLE_D','ERR_PLAYER_LEFT_BATTLE_D','ERR_PLAYERLIST_JOINED_BATTLE',
    'ERR_PLAYERLIST_LEFT_BATTLE','ERR_PLAYERS_JOINED_BATTLE_D','ERR_PLAYERS_LEFT_BATTLE_D'}) do
    local value=formats[key]:find('%%d') and string.format(formats[key],12,'First, Second') or string.format(formats[key],'First')
    check('localized template '..key,ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM',value))
end
check('non-notice system text stays',not ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','The battle begins in 30 seconds.'))
check('anchored match rejects quoted sentence',not ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','Please explain: '..sample))
for _,event in ipairs({'CHAT_MSG_PARTY','CHAT_MSG_RAID','CHAT_MSG_INSTANCE_CHAT','CHAT_MSG_SAY','CHAT_MSG_GUILD'}) do
    check('player chat retained '..event,not ns.ShouldHideSystemChatEvent(event,sample))
end
check('ordinary online status retained by default',not ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First has gone offline.'))
db.hidePlayerStatusMessages=true
check('friend online hyperlink',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM',string.format(ERR_FRIEND_ONLINE_SS,'First','First')))
check('friend offline',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First has gone offline.'))
check('guild login',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First has come online.'))
check('BNet online event',ns.ShouldHideSystemChatEvent('CHAT_MSG_BN_INLINE_TOAST_ALERT','FRIEND_ONLINE'))
check('BNet offline event',ns.ShouldHideSystemChatEvent('CHAT_MSG_BN_INLINE_TOAST_ALERT','FRIEND_OFFLINE'))
check('BNet friend request kept',not ns.ShouldHideSystemChatEvent('CHAT_MSG_BN_INLINE_TOAST_ALERT','FRIEND_REQUEST'))
db.hideGroupRosterMessages=true
check('party roster notice',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First joins the party.'))
check('raid roster notice',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First has left the raid group.'))
emit('First has come online.',4)
check('direct BNet status notice removed',#frame.buffer==0)
emit('You have a new friend request.',4)
check('BNet friend request retained',#frame.buffer==1)
reset()
local base=#history()
emit(sample,1)
check('direct Blizzard summary removed without event metadata',#frame.buffer==0)
check('removed direct summary absent from History',#history()==base)
emit(sample,2)
check('player quoting identical text retained',#frame.buffer==1)
emit(sample,nil)
check('untyped addon line is not guessed to be system',#frame.buffer==2)
emit(sample,1,'CHAT_MSG_INSTANCE_CHAT')
check('event context wins over misleading type id',#frame.buffer==3)
emit(sample,1,'CHAT_MSG_SYSTEM')
check('system with metadata removed',#frame.buffer==3)
emit('The battle begins in 30 seconds.',1)
check('battle countdown preserved',#frame.buffer==4)
db.hideBattleRosterMessages=false
emit(sample,1)
check('battle toggle restores immediately',#frame.buffer==5)
db.hideBattleRosterMessages=true
reset()
emit('Changed Channel: [1. General]',7)
check('direct channel notices removed by chat type',#frame.buffer==0)
emit('Changed Channel: [1. General]',9)
check('numbered channel shares type with player chat safely',#frame.buffer==0)
emit('[1. General] [First]: Changed Channel: [1. General]',9)
check('channel player quoting notice remains',#frame.buffer==1)
reset()
db.hideSystemSpam=false
emit('Changed Channel: [1. General]',7)
check('channel toggle restores notices',#frame.buffer==1)
db.hideSystemSpam=true
-- Existing identical player text must survive removing the system copy.
reset();emit(sample,2);emit(sample,1)
check('typed removal preserves same text in party chat',#frame.buffer==1)
-- Removal failure cannot discard the line from History.
local remove=frame.RemoveMessagesByPredicate
frame.RemoveMessagesByPredicate=function() return false end
base=#history();emit(sample,1)
check('failed removal preserves visible History parity',#history()==base+1 and #frame.buffer==2)
frame.RemoveMessagesByPredicate=remove
-- Live localized globals, positional placeholders and Lua pattern punctuation.
ERR_PLAYERLIST_JOINED_BATTLE='%1$d гравців увійшли в бій: %2$s!'
check('Ukrainian positional format',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','12 гравців увійшли в бій: Один, Два!'))
ERR_PLAYER_JOINED_BATTLE_D='[%s] joined (100%%)!'
check('format punctuation escaped',ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','[First] joined (100%)!'))
ERR_PLAYER_JOINED_BATTLE_D=nil
check('missing global is skipped',not ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM','First has joined the battle.'))
for key,value in pairs(formats) do _G[key]=value end
if env.secretString then
    check('secret message passed through',not ns.ShouldHideSystemChatEvent('CHAT_MSG_SYSTEM',env.secretString))
    check('secret type id passed through',not ns.ShouldHideRenderedSystemMessage(sample,env.secretString))
    check('secret event passed through',not ns.ShouldHideSystemChatEvent(env.secretString,sample))
end
-- Register all system event families on the existing guarded filter path.
ns.CanUseMessageEventFilters=function() return true end
addon.modules.Filters:OnEnable()
for _,event in ipairs({'CHAT_MSG_SYSTEM','CHAT_MSG_CHANNEL_JOIN','CHAT_MSG_CHANNEL_LEAVE',
    'CHAT_MSG_CHANNEL_NOTICE','CHAT_MSG_CHANNEL_NOTICE_USER','CHAT_MSG_BN_INLINE_TOAST_ALERT'}) do
    check('filter registered '..event,filters[event] and next(filters[event])~=nil)
end
local function isBlocked(event,message)
    for fn in pairs(filters[event] or {}) do if fn(nil,event,message,'Sender') then return true end end
    return false
end
check('installed system filter blocks summary',isBlocked('CHAT_MSG_SYSTEM',sample))
check('installed system filter preserves countdown',not isBlocked('CHAT_MSG_SYSTEM','The battle begins in 30 seconds.'))
check('installed channel filter blocks change',isBlocked('CHAT_MSG_CHANNEL_NOTICE','YOU_CHANGED'))
addon.modules.Filters:OnDisable()
check('disable removes own system filter',not filters.CHAT_MSG_SYSTEM or next(filters.CHAT_MSG_SYSTEM)==nil)
if controller then
    reset()
    controller:StartBGChatFilter()
    controller:FilterChatMsgSystem('CHAT_MSG_SYSTEM','First has joined the raid group.')
    controller:FilterChatMsgSystem('CHAT_MSG_SYSTEM','Second has joined the raid group.')
    controller:OnUpdate(30)
    check('actual Blizzard producer blocked by post-render path',#frame.buffer==0)
    controller:StopBGChatFilter()
end
-- Old clients without stored-message APIs still use the existing guarded
-- pre-render wrapper. No raw hook is introduced on protected modern frames.
if not ns.IsRetailSecretValueBuild() then
    for i=1,NUM_CHAT_WINDOWS do
        local chatFrame = _G['ChatFrame'..i]
        chatFrame.TransformMessages,chatFrame.RemoveMessagesByPredicate=false,false
    end
    db.shortChannels=false
    db.channelLabelModes={}
    db.enableMentionManager=false
    db.mentionRules={}
    db.hideSystemSpam,db.hidePlayerStatusMessages,db.hideGroupRosterMessages=false,false,false
    db.hideBattleRosterMessages=true
    ns.RefreshChannelLabelHook()
    reset();emit(sample,1)
    check('legacy pre-render fallback hides direct summary',#frame.buffer==0)
    emit(sample,2)
    check('legacy fallback retains party quote',#frame.buffer==1)
    local options=addon:GetOptions().args.filters.args.systemMessages.args
    options.hideBattleRosterMessages.set(nil,false)
    emit(sample,1)
    check('legacy toggle refreshes immediately',#frame.buffer==2)
    options.hideBattleRosterMessages.set(nil,true)
    emit(sample,1)
    check('legacy toggle re-enables without reload',#frame.buffer==2)
end
check('no post-render errors',ns.GetChatTransformStats().errors==0)
print(string.format('System notices: PASS (%s; %d contracts%s; modeled C/security)',client,checks,source and '; actual Blizzard battle aggregator' or ''))
