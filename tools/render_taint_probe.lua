-- Post-render safety contracts; the historical pre-postrender tests live in
-- tools/legacy. This models hook behavior and cannot certify live WoW taint.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install(os.getenv("CHATIFY_STUB_MODE") or "retail")
local hooks, originals = {}, {}
for i = 1, NUM_CHAT_WINDOWS do
    local frame = _G["ChatFrame" .. i]
    if frame then
        originals[frame] = frame.AddMessage
        frame.TransformMessages = function() return true end
        frame.RemoveMessagesByPredicate = function() return false end
    end
end
local originalTell = ChatFrameUtil and ChatFrameUtil.SetLastTellTarget
-- Model secure post-hook registration without an insecure write to the method.
_G.hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return end
    assert(type(target[method]) == "function" and type(callback) == "function")
    hooks[#hooks + 1] = { target, method, callback }
end
local ns = {}
for line in io.lines("Chatify.toc") do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(ns.Chatify)
addon:OnInitialize()
addon:OnEnable()
for _, module in pairs(addon.modules) do
    if module.OnInitialize then module:OnInitialize() end
    if module.OnEnable then module:OnEnable() end
end
assert(ns.HasSecurePostRenderAPI())
assert(not ns.CanReplaceChatFrameAddMessage(), "modern path permits insecure AddMessage replacement")
assert(not ns.IsLastTellTargetGuarded(), "clean modern stack installs a tell-target override")
if originalTell then assert(ChatFrameUtil.SetLastTellTarget == originalTell) end
for frame, original in pairs(originals) do
    assert(frame.AddMessage == original, "Blizzard AddMessage was replaced")
end
assert(#hooks > 0, "no post-hooks were exercised")
if env.secretString then
    assert(not ns.CanMutateChatPayload("CHAT_MSG_WHISPER", env.secretString, "Sender"))
    local history = addon.modules.History
    history:SaveHistory()
    local function noSecret(value)
        if type(value) ~= "table" then assert(value ~= env.secretString); return end
        for key, entry in pairs(value) do noSecret(key); noSecret(entry) end
    end
    noSecret(ChatifyHistoryDB)
end
for _, module in pairs(addon.modules) do
    if module.OnDisable then module:OnDisable() end
end
for frame, original in pairs(originals) do assert(frame.AddMessage == original) end
assert(not ns.Runtime.errors or #ns.Runtime.errors == 0, "runtime guard recorded errors")
print("post-render taint contracts: PASS (method identity, clean tell-target, protected payload rejection; offline model)")
