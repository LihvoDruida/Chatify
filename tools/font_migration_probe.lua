-- Font resolution and migration of retired font settings.
-- The stub models the real client: SetFont succeeds only for files that exist
-- (Blizzard Fonts\* always exist), and LibSharedMedia returns nil for unknown
-- names instead of a default.
package.path = "tools/stub/?.lua;" .. package.path
local env = require("wow_env")
env.install("classic")

local function exists(path)
    if path:lower():match("^fonts[\\/]") then return true end
    local rel = path:gsub("^[Ii]nterface\\[Aa]dd[Oo]ns\\Chatify\\", ""):gsub("\\", "/")
    local f = io.open(rel, "rb")
    if f then f:close(); return true end
    return false
end
CreateFont = function() return { SetFont = function(_, path) return exists(path) end } end

local ns = {}
for line in assert(io.open("Chatify.toc")):lines() do
    if not line:match("^#") and line:match("%.lua%s*$") then
        assert(loadfile((line:gsub("\\", "/"))))("Chatify", ns)
    end
end
local LSM = LibStub("LibSharedMedia-3.0", true)
if LSM then
    local registered = {}
    local register = LSM.Register
    LSM.Register = function(self, kind, key, value, ...)
        registered[kind .. "\0" .. key] = value
        if register then return register(self, kind, key, value, ...) end
    end
    LSM.Fetch = function(_, kind, key) return registered[kind .. "\0" .. key] end
end
local addon = assert(LibStub("AceAddon-3.0"):GetAddon("Chatify"))
assert(pcall(addon.OnInitialize, addon))

local checks = 0
local function check(label, ok)
    checks = checks + 1
    assert(ok, "font migration probe: " .. label)
end

-- Every bundled font entry must point at a file that ships.
for _, entry in ipairs(ns.Lists.Fonts or {}) do
    if type(entry.path) == "string" and entry.path:find("Chatify", 1, true) then
        check("bundled font file exists: " .. entry.path, exists(entry.path))
    end
end

local EXO = "Interface\\AddOns\\Chatify\\assets\\Fonts\\Exo2-Regular.ttf"
local retiredPath = "Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf"
check("retired fonts/ directory is gone", not exists(retiredPath))
for _, legacy in ipairs({ "Exo 2 (Chatify)", "exo 2 (chatify)", retiredPath,
                          "interface/addons/chatify/fonts/exo2.ttf", "Chatify: Exo 2" }) do
    check("resolves " .. legacy .. " to bundled Exo 2", ns.ResolveFontPath(legacy) == EXO)
end
for name, path in pairs({ ["Friz Quadrata (WoW)"] = "Fonts\\FRIZQT__.TTF",
                          ["Arial Narrow (WoW)"] = "Fonts\\ARIALN.TTF",
                          ["Morpheus (Quest)"] = "Fonts\\MORPHEUS.TTF" }) do
    check("legacy Blizzard font " .. name, ns.ResolveFontPath(name) == path)
end
check("custom font path kept verbatim", ns.ResolveFontPath("Interface\\AddOns\\Other\\X.ttf") == "Interface\\AddOns\\Other\\X.ttf")

-- Saved profiles are rewritten so the settings dropdown shows the real font.
for _, legacy in ipairs({ "Exo 2 (Chatify)", retiredPath }) do
    local db = { fontID = legacy }
    check("migrates " .. legacy, ns.MigrateRetiredFontSettings(db) and db.fontID == "Chatify: Exo 2")
end
for _, current in ipairs({ "Chatify: Exo 2", "Friz Quadrata (WoW)", "Interface\\AddOns\\Other\\X.ttf" }) do
    local db = { fontID = current }
    check("leaves " .. current, not ns.MigrateRetiredFontSettings(db) and db.fontID == current)
end
check("ignores missing fontID", not ns.MigrateRetiredFontSettings({}))

-- The migration runs on profile load/change.
addon.db.profile.fontID = "Exo 2 (Chatify)"
addon:RefreshConfig()
check("RefreshConfig migrates the active profile", addon.db.profile.fontID == "Chatify: Exo 2")

print(string.format("font migration probe: PASS (%d checks)", checks))
