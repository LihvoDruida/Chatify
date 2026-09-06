local addonName, ns = ...

-- A stand-in chat frame, so that Blizzard's message formatting can be run and its
-- output captured without writing to any field on a real chat frame.
--
-- Why this exists
--
-- Chatify's render hook writes frame.AddMessage, which taints Blizzard's dispatch from
-- ChatFrameOverrides.lua:667 down. That taint has exactly one victim (SetLastTellTarget
-- at :672) and 0.11.51 guards it, so the current arrangement is sound. What it cannot
-- do is give Chatify the message in pieces: by :667 the line is a finished string and
-- everything downstream is regular-expression surgery on Blizzard's phrasing.
--
-- Running the handler against a proxy gives back the formatted line without the write.
-- The proxy is Chatify's own frame, so replacing ITS AddMessage taints nothing that
-- Blizzard reads.
--
-- WHAT THIS IS NOT WIRED TO, AND WHY
--
-- Nothing. This module is built and exercised by tools/proxy_probe.lua and by nothing
-- else, deliberately.
--
-- Blizzard's handler is not a pure function of its arguments. Along the way it calls
-- ChatHistory_GetAccessID (which allocates history IDs), SetLastTellTarget, PlaySound,
-- FlashClientIcon and FlashTabIfNotShown. Running it a second time on a proxy while the
-- real handler is also running would double every one of those: two history IDs per
-- line, two whisper sounds, two tab flashes.
--
-- So a proxy can only ever REPLACE the real handler, never run alongside it. That is
-- step 3 of docs/own_handler_scope.md and it is not started. Until then this module
-- exists so the parity harness can be built against it, which is what makes step 3
-- checkable at all.

-- Fields that must not be copied onto the proxy.
--
-- Derived from Blizzard's own source: the assignments in ScrollingMessageFrame.lua that
-- create per-frame display state, plus the pools and containers built in its OnLoad.
-- Copying any of these hands the proxy a live reference to the real frame's rendering
-- state, and the proxy then mutates it.
--
-- historyBuffer is a CreateCircularBuffer, visibleLines and onDisplayRefreshedCallbacks
-- are tables rebuilt per layout, fontStringPool and highlightTexturePool own real
-- textures and font strings parented to the real frame.
local DISPLAY_INTERNALS = {
    historyBuffer = true,
    visibleLines = true,
    onDisplayRefreshedCallbacks = true,
    onDisplayRefreshedCallback = true,
    onScrollChangedCallback = true,
    onTextCopiedCallback = true,
    onLineRightClickedCallback = true,
    fontStringPool = true,
    highlightTexturePool = true,
    isLayoutDirty = true,
    isDisplayDirty = true,
    scrollOffset = true,
    selectingVisibleLineIndex = true,
    oldestFadingLineTimestamp = true,
    overrideFadeTimestamp = true,
    FontStringContainer = true,
    ScrollBar = true,
    ScrollToBottomButton = true,
}

-- Fields Blizzard's handler reads off the frame to decide routing and suppression.
-- These are the reason the proxy has to be a copy rather than a bare frame: get one
-- wrong and the handler takes a different branch than it would have on the real frame,
-- which is the failure mode that silently drops messages.
local ROUTING_FIELDS = {
    "channelList",
    "zoneChannelList",
    "messageTypeList",
    "privateMessageList",
    "excludePrivateMessageList",
    "bnConversationList",
    "excludeBNConversationList",
    "defaultLanguage",
    "alternativeDefaultLanguage",
    "chatType",
    "chatTarget",
    "tellTimer",
    "isTranscribing",
    "checkedGMOTD",
}

local proxy
local captured
local savedFields = {}

function ns.GetChatProxyBlacklist()
    return DISPLAY_INTERNALS
end

function ns.GetChatProxyRoutingFields()
    return ROUTING_FIELDS
end

local function BuildProxy()
    if proxy then
        return proxy
    end

    if type(CreateFrame) ~= "function" then
        return nil
    end

    local ok, frame = pcall(CreateFrame, "ScrollingMessageFrame")
    if not ok or not frame then
        return nil
    end

    -- ChatFrameMixin carries MessageEventHandler and the helpers it calls on self.
    -- Without it the proxy is a ScrollingMessageFrame that cannot answer the questions
    -- Blizzard's handler asks of it.
    if type(Mixin) == "function" and type(ChatFrameMixin) == "table" then
        pcall(Mixin, frame, ChatFrameMixin)
    end

    -- Capturing rather than displaying is the entire point, so this is set once and
    -- never restored. Writing it is safe: the frame belongs to Chatify.
    frame.AddMessage = function(_, text, r, g, b, id, accessID, typeID, event, eventArgs, formatter)
        captured = {
            text = text,
            r = r, g = g, b = b,
            id = id,
            accessID = accessID,
            typeID = typeID,
            event = event,
            eventArgs = eventArgs,
            formatter = formatter,
        }
        return true
    end

    -- The handler skips work for frames it believes are hidden.
    frame.IsShown = function() return true end

    proxy = frame
    return proxy
end

-- Copy the routing state of `frame` onto the proxy.
--
-- Only the named fields are copied, rather than everything that is not blacklisted.
-- A blacklist has to be complete to be safe and it silently degrades as Blizzard adds
-- fields; an allowlist fails the other way, by making the proxy behave unlike the real
-- frame in a way a parity probe can catch.
local function AdoptFrame(frame)
    local target = BuildProxy()
    if not target or type(frame) ~= "table" then
        return nil
    end

    wipe(savedFields)

    for i = 1, #ROUTING_FIELDS do
        local key = ROUTING_FIELDS[i]
        if not DISPLAY_INTERNALS[key] then
            savedFields[key] = target[key]
            target[key] = frame[key]
        end
    end

    return target
end

local function ReleaseFrame()
    if not proxy then
        return
    end

    for i = 1, #ROUTING_FIELDS do
        local key = ROUTING_FIELDS[i]
        proxy[key] = savedFields[key]
    end

    wipe(savedFields)
end

-- Run `handler` against a proxy of `frame` and return what it tried to display.
--
-- Returns the capture table, or nil plus a reason. The caller gets the formatted line
-- and the pieces Blizzard passed alongside it (event, eventArgs, accessID, typeID),
-- which is the structured access the render hook cannot get at :667.
--
-- The caller is responsible for the side effects described at the top of this file.
function ns.CaptureThroughProxy(frame, handler, event, ...)
    if type(handler) ~= "function" then
        return nil, "no handler"
    end

    local target = AdoptFrame(frame)
    if not target then
        return nil, "proxy unavailable"
    end

    captured = nil

    local ok, err = pcall(handler, target, event, ...)

    ReleaseFrame()

    if not ok then
        return nil, err
    end

    if not captured then
        return nil, "handler displayed nothing"
    end

    local result = captured
    captured = nil
    return result
end

function ns.GetChatProxyFrame()
    return proxy
end

-- Test seam. The proxy holds no state between captures, so dropping it is safe.
function ns.ResetChatProxy()
    proxy = nil
    captured = nil
    wipe(savedFields)
end
