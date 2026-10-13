-- Atomic, typed, checksummed profile transfers. Requires no external libraries.
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
local profile = assert(addon.db.profile)
local function check(ok, why) if not ok then error("profile probe: " .. tostring(why)) end end
local function export() local value, err = ns.ExportProfileText(); check(value, err); return value end
profile.channelLabelsNamed.GENERAL = "#Польовий"
local backup = export()
check(backup:match("^CHATIFY_PROFILE\t2"), "v2 format missing")
profile.channelLabelsNamed.GENERAL = "#Changed"
local ok, why = ns.ImportProfileText(backup)
check(ok, why)
check(profile.channelLabelsNamed.GENERAL == "#Польовий", "roundtrip lost unicode channel label")
local baseline = export()
local function reject(text, reason)
    local success = ns.ImportProfileText(text)
    check(not success, "accepted " .. reason)
    check(export() == baseline, "invalid import changed profile: " .. reason)
end
reject("CHATIFY_PROFILE\t2", "header only")
reject(baseline:sub(1, -12), "truncated footer")
reject(baseline:gsub("N\t0", "S\t0", 1), "corrupt checksum")
reject(baseline:gsub("enableTimestamps\tB\t1", "enableTimestamps\tS\tfalse", 1), "bad boolean")
reject(baseline:gsub("lineSpacing\tN\t0", "lineSpacing\tS\t9", 1), "bad number")
-- An attacker or broken generator can produce a *valid* checksum around
-- type-invalid data. This must be rejected by the schema, not only integrity.
local function reseal(text)
    local body = assert(text:match("^CHATIFY_PROFILE\t2\n(.*)\nCHATIFY_END\t%d+\t%x+$"))
    local a, b = 1, 0
    for i = 1, #body do
        a = (a + body:byte(i)) % 65521
        b = (b + a) % 65521
    end
    local _, lines = body:gsub("\n", "")
    return "CHATIFY_PROFILE\t2\n" .. body .. "\nCHATIFY_END\t" .. tostring(lines + 1) .. "\t" .. string.format("%04X%04X", b, a)
end
local typeChanged = baseline:gsub("enableTimestamps\tB\t1", "enableTimestamps\tS\tfalse", 1)
check(typeChanged ~= baseline, "test fixture for typed boolean not found")
reject(reseal(typeChanged), "valid checksum but invalid boolean type")
local invalidMode = baseline:gsub("spamFilterMode\tS\tblock", "spamFilterMode\tS\tunsafe", 1)
check(invalidMode ~= baseline, "test fixture for enum not found")
reject(reseal(invalidMode), "valid checksum but unknown enum")
reject(reseal("CHATIFY_PROFILE\t2\nspamKeywords\tT\t\nCHATIFY_END\t1\t00000000"), "invalid nested format")

profile.spamKeywords = {}
for i = 1, 10050 do profile.spamKeywords[i] = "kw" .. i end
local text, err = ns.ExportProfileText()
check(text == nil and type(err) == "string", "silent cutoff on keyword count")
profile.spamKeywords = {"hello"}
profile.autoReply.busyMessage = string.rep("x", 8193)
text, err = ns.ExportProfileText()
check(text == nil and type(err) == "string", "silent cutoff on string")
profile.autoReply.busyMessage = "normal"
local good = export()
local orig = addon.RefreshConfig
local calls = 0
addon.RefreshConfig = function() calls = calls + 1; if calls == 1 then error("apply failure") end end
profile.lineSpacing = 3
ok, why = ns.ImportProfileText(good)
check(not ok and type(why) == "string", "refresh failure must reject")
check(profile.lineSpacing == 3, "refresh failure did not roll back")
addon.RefreshConfig = orig
print("profile integrity: PASS")
