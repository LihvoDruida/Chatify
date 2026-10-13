-- Explicitly disable unknown-method autostubbing while checking capability gates.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("retail")
env.strictAPIs = true
local frame = assert(_G.ChatFrame1)
assert(frame.DefinitelyNotWoWAPI == nil, "fixture fabricated a missing method")
assert(frame.TransformMessages == nil, "fixture fabricated post-render API")
assert(frame.RemoveMessagesByPredicate == nil, "fixture fabricated removal API")
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
assert(ns.HasSecurePostRenderAPI() == false, "missing API reported available")
assert(ns.HasSecureSpamRemovalAPI() == false, "missing API reported available")
frame.TransformMessages = function() return true end
frame.RemoveMessagesByPredicate = function() return true end
assert(ns.HasSecurePostRenderAPI() == true, "post-render API not detected")
assert(ns.HasSecureSpamRemovalAPI() == true, "removal API not detected")
print("strict API fixture: PASS")
