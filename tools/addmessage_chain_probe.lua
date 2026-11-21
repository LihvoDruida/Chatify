-- Legacy AddMessage wrapper chain (clients without TransformMessages).
-- The virtual-chat router and the channel-label hook both wrap
-- ChatFrame.AddMessage. Toggling either must never (a) drop another addon's
-- hook that sits on top, nor (b) leave a "removed" wrapper still processing
-- every line, which made label passes grow with each toggle.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")
local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))

-- Model a client without the secure post-render API: Chatify must own
-- AddMessage there, which is where the wrapper chain exists at all.
ns.HasSecurePostRenderAPI = function() return false end
assert(ns.CanReplaceChatFrameAddMessage(), "legacy render hook must be allowed")

local db = addon.db.profile
db.shortChannels = true
db.channelModes = db.channelModes or {}
db.channelModes.GENERAL = "custom"
local Router = addon:GetModule("Router")
local frame = ChatFrame1

local delivered = {}
frame.AddMessage = function(_, text) delivered[#delivered + 1] = text end
local passes = 0
local realApply = ns.ApplyChannelLabels
ns.ApplyChannelLabels = function(...) passes = passes + 1; return realApply(...) end

local checks, serial = 0, 0
local function check(label, ok)
    checks = checks + 1
    assert(ok, "AddMessage chain probe: " .. label)
end
local function send()
    delivered, passes, serial = {}, 0, serial + 1
    -- Unique text: identical lines would trip the duplicate-spam filter.
    frame:AddMessage("|Hchannel:channel:1|h[1. General]|h Joe: line " .. serial)
    return #delivered, passes, delivered[1]
end
local function virtual(on)
    db.useVirtualChat = on
    Router:ApplyToAllFrames()
end

virtual(false)
local count, labelsOnly, text = send()
check("labels-only line delivered once", count == 1)
check("labels-only applies labels once", labelsOnly == 1)
check("label applied", text and text:find("[1]", 1, true) ~= nil)
virtual(true)
local _, virtualPasses = send()
for round = 1, 4 do
    virtual(false)
    count, passes = send()
    check("round " .. round .. ": off delivers once", count == 1)
    check("round " .. round .. ": off label passes stay " .. labelsOnly .. " (got " .. passes .. ")", passes == labelsOnly)
    virtual(true)
    count, passes = send()
    check("round " .. round .. ": on delivers once", count == 1)
    check("round " .. round .. ": on label passes stay " .. virtualPasses .. " (got " .. passes .. ")", passes == virtualPasses)
end

-- Another addon hooks AddMessage while the router is active. Turning virtual
-- chat off must keep that hook in the chain.
local thirdCalls = 0
local below = frame.AddMessage
frame.AddMessage = function(self, ...)
    thirdCalls = thirdCalls + 1
    return below(self, ...)
end
virtual(false)
thirdCalls = 0
count, passes = send()
check("third-party hook survives router unhook (calls=" .. thirdCalls .. ")", thirdCalls == 1)
check("line still delivered once through the inert router wrapper", count == 1)
check("no stale label processing after unhook (got " .. passes .. ")", passes == labelsOnly)
virtual(true)
virtual(false)
thirdCalls = 0
count, passes = send()
check("third-party hook survives a second toggle", thirdCalls == 1 and count == 1 and passes == labelsOnly)

print(string.format("AddMessage chain probe: PASS (%d checks; label passes %d off / %d on)",
    checks, labelsOnly, virtualPasses))
