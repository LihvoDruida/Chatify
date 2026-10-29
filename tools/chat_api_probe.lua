-- Real namespace signatures, late loading and no duplicate side effects.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local ns = {}
assert(loadfile("Config.lua"))("Chatify", ns)
local legacyCalls, modernCalls = 0, 0
_G.ChatFrameUtil = nil
_G.ChatFrame_OpenChat = function(text)
    legacyCalls = legacyCalls + 1
    assert(text == "hello")
    return "legacy"
end
local ok, result = ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello")
assert(ok and result == "legacy" and legacyCalls == 1)
_G.ChatFrameUtil = { OpenChat = function(text)
    modernCalls = modernCalls + 1
    assert(text == "hello", "namespace received an implicit self")
    return "modern", nil, "third"
end }
local third, fourth
ok, result, third, fourth = ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello")
assert(ok and result == "modern" and third == nil and fourth == "third")
assert(modernCalls == 1 and legacyCalls == 1, "late-loaded modern API was ignored")
_G.ChatFrameUtil.OpenChat = function()
    modernCalls = modernCalls + 1
    error("operation failed after a side effect")
end
assert(not ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello"))
assert(modernCalls == 2 and legacyCalls == 1, "failed operation was retried")
_G.ChatFrameUtil.OpenChat = nil
assert(ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello"))
assert(legacyCalls == 2, "absent namespace did not fall back")
_G.ChatFrame_OpenChat = nil
assert(not ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello"))
_G.ChatFrameUtil.OpenChat = function() return true end
assert(ns.CallChatAPI("ChatFrame_OpenChat", "OpenChat", "hello"), "missing route cached forever")
-- A valid negative modern result must not reach a deprecated global.
_G.IsAddOnLoaded = function() error("legacy addon query reached on modern client") end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
assert(ns.IsAddOnLoadedCompat("GW2_UI") == false)
print("modern chat API routing: PASS (late load, signatures, return tuples, no retry)")

local modernWrites, legacyWrites = 0, 0
_G.SetCVar = function() legacyWrites = legacyWrites + 1 end
_G.C_CVar = { SetCVar = function() modernWrites = modernWrites + 1; error("write rejected") end }
assert(not ns.SetCVarCompat("showTimestamps", "none"))
assert(modernWrites == 1 and legacyWrites == 0, "CVar write retried through deprecated API")
_G.C_CVar.AreCVarsLoaded = function() error("not ready") end
assert(not ns.SetCVarCompat("showTimestamps", "none"))
assert(modernWrites == 1, "unknown CVar readiness permitted a write")
