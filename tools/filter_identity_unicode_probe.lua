-- R1-05 / R1-06: realm-correct friend cache and non-ASCII keyword matching.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
_G.Ambiguate = function(name) return name end
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))
local db = assert(addon.db.profile)
db.enableSpamFilter = true
db.enableThrottle = false
db.spamFilterMode = "block"
db.spamChannelRules.CHANNEL = true
db.spamWhitelist.friends = true
local function check(ok, reason) if not ok then error("identity/unicode: " .. reason) end end
local calls = {}
ns.IsFriendCompat = function(name)
    calls[name] = (calls[name] or 0) + 1
    return name == "Friend-Realm" or name == "Хтось-Перший"
end
-- The compatibility adapter must also reject a misleading modern API result.
_G.C_FriendList = {
    GetFriendInfo = function() return { name = "Friend-Other" } end,
}
check(ns.GetFriendInfoByNameCompat("Friend-Realm") == nil, "modern lookup trusted mismatched cross-realm response")
check(ns.GetFriendInfoByNameCompat("Friend") == nil, "local short lookup matched a remote friend")
_G.C_FriendList.GetFriendInfo = function() return { name = "Friend-Realm" } end
check(ns.GetFriendInfoByNameCompat("Friend") ~= nil, "local friend was not recognized via local realm")
check(ns.GetFriendInfoByNameCompat("Friend-Realm") ~= nil, "qualified friend was not recognized")
_G.C_FriendList = nil
db.spamKeywords = { "SPAM", "金币", "золото", "VIP" }
ns.UpdateSpamCache()
local function block(sender) return ns.ProcessSpamMessage("CHAT_MSG_CHANNEL", "SPAM", sender, "General") end
check(not block("Friend-Realm"), "real friend blocked")
check(block("Friend-Other"), "same-name cross-realm player whitelisted")
_G.Ambiguate = function(name) return (name:match("^[^-]+") or name) end
check(block("Friend-Third"), "abbreviating Ambiguate discarded explicit realm")
_G.Ambiguate = function(name) return name end
check(block("Other-Other"), "other player not blocked")
check(calls["Friend-Realm"] == 1 and calls["Friend-Other"] == 1, "identity lost realm or cached under short name")
check(not block("Хтось-Перший"), "Forever/two-part friend identity lost")
check(block("Хтось-Другий"), "Forever/two-part identity collision")
-- The friend list changes without a reload: the next query cannot reuse a stale entry.
ns.IsFriendCompat = function() return false end
addon.modules.Filters:FRIENDLIST_UPDATE()
check(block("Friend-Realm"), "friend cache not invalidated")
check(ns.GetSpamMatch("金币") == "金币", "CJK identical keyword missing")
check(ns.GetSpamMatch("出售金币交易") == "金币", "CJK keyword inside continuous text missing")
check(ns.GetSpamMatch("золото") == "золото", "Ukrainian exact keyword missing")
check(ns.GetSpamMatch("ЗОЛОТО") == "золото", "Cyrillic case folding missing")
check(not ns.GetSpamMatch("позолото"), "substring false positive on Ukrainian word")
check(not ns.GetSpamMatch("кіт і золотоволосий"), "substring false positive in non-spam text")
check(ns.GetSpamMatch("V.I.P") == "VIP", "ASCII obfuscation regression")
check(ns.GetSpamMatch("vіp") == "VIP", "homoglyph regression")
check(ns.GetSpamMatch("金\226\128\139币") == "金币", "zero-width Unicode split regression")
check(not ns.GetSpamMatch("добрий вечір, друзі"), "unrelated Ukrainian text blocked")
check(not ns.GetSpamMatch("遊戲冒險") , "unrelated CJK text blocked")
print("friend identity and Unicode keywords: PASS")
