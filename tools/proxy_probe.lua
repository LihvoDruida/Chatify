-- Proxy capture and parity harness.
--
--     lua5.1 tools/proxy_probe.lua                    (retail, secret values)
--     CHATIFY_STUB_MODE=classic lua5.1 tools/proxy_probe.lua
--
-- Step 1 and 2 of docs/own_handler_scope.md.
--
-- The proxy exists so Blizzard's message formatting can be run and its output captured
-- without writing frame.AddMessage on a real chat frame. Before anything is allowed to
-- depend on that, two things have to hold:
--
--   1. The proxy captures what the handler tried to display, and leaves the real frame
--      untouched while doing it.
--   2. A message routed through the proxy comes out the same as the same message
--      handled directly. This is the parity gate. Without it there is no way to tell
--      whether an own handler, when it is eventually written, is producing Blizzard's
--      output or something merely plausible.
--
-- WHAT THIS CANNOT TELL US. The stub is not the client. It cannot model taint, its
-- ChatFrameUtil is a handful of functions rather than the real one, and the handler
-- driven here is a test double, not Blizzard's 421-line original. So parity here means
-- "the proxy is a faithful stand-in for a frame", not "our output matches the game".
-- The second question is answerable only in-client, and the honest place to say so is
-- here rather than in a changelog.

package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
local mode = os.getenv("CHATIFY_STUB_MODE") or "retail"
env.install(mode)

local ns, addonName = {}, "Chatify"
for line in assert(io.open("Chatify.toc")):lines() do
    line = line:gsub("^\239\187\191", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then
        assert(loadfile((line:gsub("\\", "/"))))(addonName, ns)
    end
end

local failures = 0
local function check(label, ok, detail)
    print(string.format("%-58s %s%s", label, ok and "PASS" or "FAIL",
        detail and ("  " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
end

print("mode                       :", mode)

-- A stand-in for Blizzard's handler. It reads the routing fields off the frame the way
-- the real one does and assembles a line from them, so that a proxy which fails to
-- carry a field produces visibly different output rather than silently the same.
local function FakeHandler(frame, event, ...)
    local arg1, arg2 = ...
    local lang = frame.defaultLanguage or "?"
    local chatType = event:gsub("^CHAT_MSG_", "")
    local body

    if type(arg1) == "string" and issecretvalue and issecretvalue(arg1) then
        body = arg1
    else
        body = tostring(arg1)
    end

    local line = ("[%s][%s] %s: %s"):format(chatType, lang, tostring(arg2), body)
    return frame:AddMessage(line, 1, 1, 1, nil, 7, 3, event, { ... })
end

local realFrame = _G.ChatFrame1
assert(realFrame, "stub did not create ChatFrame1")
realFrame.defaultLanguage = "Common"
realFrame.channelList = { "General" }
realFrame.messageTypeList = { "SAY", "WHISPER" }
realFrame.chatType = "SAY"

-- 1. Capture works and reports the pieces the render hook cannot see at :667.
local cap, err = ns.CaptureThroughProxy(realFrame, FakeHandler, "CHAT_MSG_SAY", "hello", "Malivil")
check("capture returns a result", cap ~= nil, err)
if cap then
    check("captured text is the assembled line",
        cap.text == "[SAY][Common] Malivil: hello", cap.text)
    check("captured event is carried through", cap.event == "CHAT_MSG_SAY", cap.event)
    check("captured eventArgs are carried through",
        type(cap.eventArgs) == "table" and cap.eventArgs[1] == "hello")
    check("captured accessID and typeID survive", cap.accessID == 7 and cap.typeID == 3)
end

-- 2. The real frame is not written to. This is the whole reason the proxy exists: if a
--    capture leaves a mark on ChatFrame1 we have moved the taint, not removed it.
local before = realFrame.AddMessage
ns.CaptureThroughProxy(realFrame, FakeHandler, "CHAT_MSG_SAY", "again", "Malivil")
check("real frame AddMessage is untouched", realFrame.AddMessage == before)
check("proxy is not the real frame", ns.GetChatProxyFrame() ~= realFrame)

-- 3. Routing fields reach the proxy. A field that does not arrive makes the handler
--    take a different branch, which is how messages get silently dropped.
local proxyFrame = ns.GetChatProxyFrame()
local missing = {}
for _, key in ipairs(ns.GetChatProxyRoutingFields()) do
    if realFrame[key] ~= nil then
        -- Checked during a capture, since the fields are restored afterwards.
        missing[key] = true
    end
end
local seen = {}
ns.CaptureThroughProxy(realFrame, function(frame, event, ...)
    for _, key in ipairs(ns.GetChatProxyRoutingFields()) do
        seen[key] = frame[key]
    end
    return frame:AddMessage("x", 1, 1, 1)
end, "CHAT_MSG_SAY", "x", "Y")

local carried = true
local firstMissing
for key in pairs(missing) do
    if seen[key] ~= realFrame[key] then
        carried = false
        firstMissing = firstMissing or key
    end
end
check("routing fields are carried onto the proxy", carried, firstMissing)

-- 4. State does not leak between captures. The proxy is reused, so a value set by one
--    frame must not still be there for the next.
local other = _G.ChatFrame3
if other then
    other.defaultLanguage = "Orcish"
    other.chatType = "WHISPER"
    local capOther = ns.CaptureThroughProxy(other, FakeHandler, "CHAT_MSG_WHISPER", "hi", "Svampollon")
    check("a second frame gets its own routing state",
        capOther ~= nil and capOther.text == "[WHISPER][Orcish] Svampollon: hi",
        capOther and capOther.text)

    local capBack = ns.CaptureThroughProxy(realFrame, FakeHandler, "CHAT_MSG_SAY", "back", "Malivil")
    check("the first frame's state is not polluted by the second",
        capBack ~= nil and capBack.text == "[SAY][Common] Malivil: back",
        capBack and capBack.text)
end

-- 5. Display internals are never adopted. Copying a live pool or history buffer onto
--    the proxy hands it the real frame's rendering state to mutate.
local blacklist = ns.GetChatProxyBlacklist()
local adopted = {}
realFrame.historyBuffer = { STUB_MARKER = true }
realFrame.fontStringPool = { STUB_MARKER = true }
realFrame.scrollOffset = 42
ns.CaptureThroughProxy(realFrame, function(frame, event, ...)
    for key in pairs(blacklist) do
        if frame[key] ~= nil and realFrame[key] ~= nil and frame[key] == realFrame[key] then
            adopted[#adopted + 1] = key
        end
    end
    return frame:AddMessage("x", 1, 1, 1)
end, "CHAT_MSG_SAY", "x", "Y")
check("display internals are not adopted", #adopted == 0, table.concat(adopted, ", "))

-- 6. Parity. The same message handled directly and through the proxy must produce the
--    same line. This is the gate that a future own handler will be measured against.
local direct
local savedAdd = realFrame.AddMessage
realFrame.AddMessage = function(_, text) direct = text return true end
FakeHandler(realFrame, "CHAT_MSG_SAY", "parity", "Malivil")
realFrame.AddMessage = savedAdd

local viaProxy = ns.CaptureThroughProxy(realFrame, FakeHandler, "CHAT_MSG_SAY", "parity", "Malivil")
check("proxy output matches a direct run",
    viaProxy ~= nil and viaProxy.text == direct,
    viaProxy and ("proxy=" .. tostring(viaProxy.text) .. " direct=" .. tostring(direct)))

-- 7. A secret payload comes back byte-identical. The proxy must not be the place a
--    secret gets stringified.
if mode == "retail" and env.secretString then
    local capSecret = ns.CaptureThroughProxy(realFrame, function(frame, event, ...)
        local a1 = ...
        return frame:AddMessage(a1, 1, 1, 1, nil, 7, 3, event, { ... })
    end, "CHAT_MSG_SAY", env.secretString, "Malivil")
    check("a secret payload survives capture unchanged",
        capSecret ~= nil and capSecret.text == env.secretString)
    check("the captured secret is still secret",
        capSecret ~= nil and issecretvalue(capSecret.text) == true)
end

-- 8. The module is not wired to anything yet. Running Blizzard's handler on a proxy
--    while the real one also runs would double history IDs, whisper sounds and tab
--    flashes, so until an own handler REPLACES the real one this must stay inert.
-- rawget, not a plain index. The stub's frame metatable hands back a fresh closure
-- for any unknown capitalised key, so `frame.MessageEventHandler ~= baseline` is true
-- on an untouched frame and the check would fail for the wrong reason. The question
-- that actually matters is whether anything WROTE the field, which is what rawget asks.
local wired = {}
for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f and rawget(f, "MessageEventHandler") ~= nil then
        wired[#wired + 1] = "ChatFrame" .. i
    end
end
check("no chat frame MessageEventHandler is replaced", #wired == 0,
    #wired > 0 and table.concat(wired, ", ") or nil)

print(failures == 0 and "\nproxy probe: PASS"
    or ("\nproxy probe: " .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
