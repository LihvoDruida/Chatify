local locale = GetLocale()
local L

if locale == "ukUA" then
    L = Chatify_Locale_ukUA
else
    L = Chatify_Locale_enUS
end

Chatify.L = L
