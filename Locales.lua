local addonName, ns = ...
ns.Locale = ns.Locale or {}
local Locale = ns.Locale

Locale.tables = Locale.tables or {}
Locale.supported = Locale.supported or {
    enUS = true,
    ukUA = true,
}
Locale.order = Locale.order or { "client", "enUS", "ukUA" }
Locale.nativeNames = Locale.nativeNames or {
    enUS = "English",
    ukUA = "Українська",
}

local type = type
local tostring = tostring
local format = string.format
local GetLocale = GetLocale

function Locale:RegisterLocale(localeCode, localeTable)
    if type(localeCode) ~= "string" or type(localeTable) ~= "table" then return end
    self.tables[localeCode] = localeTable
end

function Locale:IsSupported(localeCode)
    return type(localeCode) == "string" and self.supported[localeCode] == true
end

function Locale:GetClientLocale()
    local clientLocale = GetLocale and GetLocale() or "enUS"
    if self:IsSupported(clientLocale) then
        return clientLocale
    end
    return "enUS"
end

function Locale:GetOverride()
    local db = ns.Chatify and ns.Chatify.db and ns.Chatify.db.profile
    local value = db and db.language or "client"
    if value == "client" then
        return value
    end
    if self:IsSupported(value) then
        return value
    end
    return "client"
end

function Locale:GetActiveLocale()
    local override = self:GetOverride()
    if override == "client" then
        return self:GetClientLocale()
    end
    if self:IsSupported(override) then
        return override
    end
    return "enUS"
end

function Locale:GetTable(localeCode)
    local resolved = localeCode
    if resolved == nil or resolved == "client" then
        resolved = self:GetActiveLocale()
    end
    return self.tables[resolved] or self.tables.enUS or {}
end

function Locale:Get(key)
    if type(key) ~= "string" then
        return key
    end

    local activeTable = self:GetTable(self:GetActiveLocale())
    local value = activeTable and activeTable[key]
    if value ~= nil then
        return value
    end

    local fallbackTable = self.tables.enUS or {}
    value = fallbackTable[key]
    if value ~= nil then
        return value
    end

    return key
end

function Locale:SetOverride(localeCode)
    local db = ns.Chatify and ns.Chatify.db and ns.Chatify.db.profile
    if not db then return end

    if localeCode == "client" or self:IsSupported(localeCode) then
        db.language = localeCode
    else
        db.language = "client"
    end
end

function Locale:GetNativeLanguageName(localeCode)
    if localeCode == "client" then
        local clientLocale = self:GetClientLocale()
        local baseLabel = self:Get("Client Default") or "Client Default"
        local clientLabel = self.nativeNames[clientLocale] or tostring(clientLocale)
        return format("%s (%s)", baseLabel, clientLabel)
    end

    return self.nativeNames[localeCode] or tostring(localeCode)
end

function Locale:GetOptionsValues()
    local values = {}
    for _, localeCode in ipairs(self.order) do
        values[localeCode] = self:GetNativeLanguageName(localeCode)
    end
    return values
end

function Locale:TranslateValueTable(values)
    if type(values) ~= "table" then
        return values
    end

    local translated = {}
    for key, value in pairs(values) do
        if type(value) == "string" then
            translated[key] = self:Get(value)
        else
            translated[key] = value
        end
    end
    return translated
end

function Locale:LocalizeOptions(node, visited)
    if type(node) ~= "table" then return end

    visited = visited or {}
    if visited[node] then return end
    visited[node] = true

    if type(node.name) == "string" then
        node.name = self:Get(node.name)
    end

    if type(node.desc) == "string" then
        node.desc = self:Get(node.desc)
    elseif type(node.desc) == "function" and not node.__chatifyLocalizedDesc then
        local original = node.desc
        node.desc = function(...)
            local result = original(...)
            if type(result) == "string" then
                return Locale:Get(result)
            end
            return result
        end
        node.__chatifyLocalizedDesc = true
    end

    if type(node.confirmText) == "string" then
        node.confirmText = self:Get(node.confirmText)
    end

    if type(node.values) == "table" then
        node.values = self:TranslateValueTable(node.values)
    elseif type(node.values) == "function" and not node.__chatifyLocalizedValues then
        local original = node.values
        node.values = function(...)
            return Locale:TranslateValueTable(original(...))
        end
        node.__chatifyLocalizedValues = true
    end

    if type(node.args) == "table" then
        for _, child in pairs(node.args) do
            self:LocalizeOptions(child, visited)
        end
    end
end

ns.L = function(key)
    return Locale:Get(key)
end
