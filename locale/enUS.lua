local addonName, ns = ...
local Locale = ns.Locale
if not Locale then return end

Locale:RegisterLocale("enUS", {
    ["Client Default"] = "Client Default",
})
