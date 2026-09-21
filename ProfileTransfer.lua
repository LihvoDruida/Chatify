local addonName, ns = ...
local Chatify = ns.Chatify or LibStub("AceAddon-3.0"):GetAddon("Chatify")

local MAX_EXPORT_BYTES = 512 * 1024
local MAX_ENTRIES = 10000
local MAX_DEPTH = 12
local MAX_KEY_BYTES = 128
local MAX_STRING_BYTES = 8192
local HEADER = "CHATIFY_PROFILE\t1"

local function L(key)
    if type(ns.L) == "function" then
        local ok, value = pcall(ns.L, key)
        if ok and type(value) == "string" then return value end
    end
    return key
end

local function Encode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%._%-])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function Decode(value)
    if type(value) ~= "string" then return nil end
    local ok, decoded = pcall(function()
        return (value:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end))
    end)
    return ok and decoded or nil
end

local function EncodeKey(key)
    if type(key) == "number" and key == math.floor(key) then
        return "n" .. tostring(key)
    end
    if type(key) == "string" and #key <= MAX_KEY_BYTES then
        return "s" .. Encode(key)
    end
    return nil
end

local function DecodeKey(token)
    if type(token) ~= "string" or token == "" then return nil end
    local kind, body = token:sub(1, 1), token:sub(2)
    if kind == "n" then
        local value = tonumber(body)
        if value and value == math.floor(value) and math.abs(value) <= 1000000 then return value end
    elseif kind == "s" then
        local value = Decode(body)
        if value and #value <= MAX_KEY_BYTES and value ~= "__index" and value ~= "__newindex" and value ~= "__metatable" then
            return value
        end
    end
    return nil
end

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        if EncodeKey(key) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then return tostring(a) < tostring(b) end
        return ta < tb
    end)
    return keys
end

local function ExportTable(root)
    local lines = { HEADER }
    local count = 0
    local function walk(tbl, path, depth)
        if depth > MAX_DEPTH or count >= MAX_ENTRIES then return end
        local keys = SortedKeys(tbl)
        if #keys == 0 and path ~= "" then
            lines[#lines + 1] = path .. "\tT\t"
            count = count + 1
            return
        end
        for i = 1, #keys do
            if count >= MAX_ENTRIES then break end
            local key = keys[i]
            local token = EncodeKey(key)
            local childPath = path == "" and token or (path .. "/" .. token)
            local value = tbl[key]
            local kind = type(value)
            if kind == "table" then
                lines[#lines + 1] = childPath .. "\tT\t"
                count = count + 1
                walk(value, childPath, depth + 1)
            elseif kind == "string" and #value <= MAX_STRING_BYTES then
                lines[#lines + 1] = childPath .. "\tS\t" .. Encode(value)
                count = count + 1
            elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                lines[#lines + 1] = childPath .. "\tN\t" .. tostring(value)
                count = count + 1
            elseif kind == "boolean" then
                lines[#lines + 1] = childPath .. "\tB\t" .. (value and "1" or "0")
                count = count + 1
            end
        end
    end
    walk(root, "", 0)
    local text = table.concat(lines, "\n")
    if #text > MAX_EXPORT_BYTES then
        return nil, L("Profile export is too large.")
    end
    return text
end

local function EnsurePath(root, tokens)
    local current = root
    for i = 1, #tokens - 1 do
        local key = DecodeKey(tokens[i])
        if key == nil then return nil end
        local nextValue = current[key]
        if type(nextValue) ~= "table" then
            nextValue = {}
            current[key] = nextValue
        end
        current = nextValue
    end
    return current, DecodeKey(tokens[#tokens])
end

local function ParseProfile(text)
    if type(text) ~= "string" or text == "" or #text > MAX_EXPORT_BYTES then
        return nil, L("Invalid or empty Chatify profile text.")
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local first, rest = text:match("^([^\n]+)\n?(.*)$")
    if first ~= HEADER then return nil, L("This is not a Chatify profile export.") end

    local root, count = {}, 0
    for line in (rest .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            count = count + 1
            if count > MAX_ENTRIES then return nil, L("Profile contains too many entries.") end
            local path, kind, raw = line:match("^([^\t]+)\t([TSNB])\t(.*)$")
            if not path then return nil, L("Profile contains an invalid line.") end
            local tokens = {}
            for token in path:gmatch("[^/]+") do tokens[#tokens + 1] = token end
            if #tokens == 0 or #tokens > MAX_DEPTH then return nil, L("Profile nesting is invalid.") end
            local parent, key = EnsurePath(root, tokens)
            if not parent or key == nil then return nil, L("Profile contains an invalid key.") end

            if kind == "T" then
                if type(parent[key]) ~= "table" then parent[key] = {} end
            elseif kind == "S" then
                local value = Decode(raw)
                if value == nil or #value > MAX_STRING_BYTES then return nil, L("Profile contains an invalid text value.") end
                parent[key] = value
            elseif kind == "N" then
                local value = tonumber(raw)
                if not value or value ~= value or value == math.huge or value == -math.huge then return nil, L("Profile contains an invalid number.") end
                parent[key] = value
            elseif kind == "B" then
                if raw ~= "0" and raw ~= "1" then return nil, L("Profile contains an invalid boolean.") end
                parent[key] = raw == "1"
            end
        end
    end

    -- Only known Chatify top-level settings are importable. Nested maps are allowed
    -- because channels, mention rules and event maps legitimately have dynamic keys.
    local defaults = ns.defaults and ns.defaults.profile
    if type(defaults) ~= "table" then return nil, L("Chatify defaults are unavailable.") end
    for key in pairs(root) do
        if defaults[key] == nil then root[key] = nil end
    end
    return root
end

local function DeepCopy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > MAX_DEPTH then return {} end
    local out = {}
    for key, child in pairs(value) do
        local kt = type(key)
        local vt = type(child)
        if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
            out[key] = DeepCopy(child, (depth or 0) + 1)
        end
    end
    return out
end

function ns.ExportProfileText()
    local profile = Chatify and Chatify.db and Chatify.db.profile
    if type(profile) ~= "table" then return nil, L("Chatify profile is unavailable.") end
    return ExportTable(profile)
end

function ns.ImportProfileText(text)
    local imported, err = ParseProfile(text)
    if not imported then return false, err end
    local profile = Chatify and Chatify.db and Chatify.db.profile
    if type(profile) ~= "table" then return false, L("Chatify profile is unavailable.") end

    local wipeFn = wipe or table.wipe
    if type(wipeFn) == "function" then
        wipeFn(profile)
    else
        for key in pairs(profile) do profile[key] = nil end
    end
    local copy = DeepCopy(imported, 0)
    for key, value in pairs(copy) do profile[key] = value end

    if type(Chatify.RefreshConfig) == "function" then pcall(Chatify.RefreshConfig, Chatify) end
    return true, L("Chatify settings imported. Reload the UI if a visual option does not refresh immediately.")
end

local transferFrame
local function CreateTransferFrame()
    if transferFrame then return transferFrame end
    local f = CreateFrame("Frame", "ChatifyProfileTransferFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(650, 330)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 16, insets = {left=4,right=4,top=4,bottom=4} })
        f:SetBackdropColor(0,0,0,0.98)
        f:SetBackdropBorderColor(0.95,0.72,0.18,1)
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    f.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 18, -46)
    hint:SetPoint("TOPRIGHT", -18, -46)
    hint:SetJustifyH("LEFT")
    f.hint = hint

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -76)
    scroll:SetPoint("BOTTOMRIGHT", -40, 56)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(570)
    edit:SetHeight(210)
    edit:SetMaxLetters(MAX_EXPORT_BYTES)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    edit:SetScript("OnTextChanged", function(self) if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    local action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    action:SetSize(150, 24)
    action:SetPoint("BOTTOMLEFT", 18, 20)
    f.action = action
    local selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectAll:SetSize(110, 24)
    selectAll:SetPoint("LEFT", action, "RIGHT", 10, 0)
    selectAll:SetText(L("Select All"))
    selectAll:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText(0, -1) end)
    f.selectAll = selectAll
    f:Hide()
    return f
end

function ns.OpenProfileExport()
    local text, err = ns.ExportProfileText()
    if not text then
        if Chatify and Chatify.Print then Chatify:Print(err or L("Profile export failed.")) end
        return
    end
    local f = CreateTransferFrame()
    f.title:SetText(L("Export Chatify Settings"))
    f.hint:SetText(L("Copy this text to a file outside WoW. Chat history is not included."))
    f.action:Hide()
    f.selectAll:Show()
    f.edit:SetText(text)
    f.edit:SetFocus()
    f.edit:HighlightText(0, -1)
    f:Show()
end

function ns.OpenProfileImport()
    local f = CreateTransferFrame()
    f.title:SetText(L("Import Chatify Settings"))
    f.hint:SetText(L("Paste a complete Chatify profile export below. Imported text is parsed as data and never executed as Lua."))
    f.selectAll:Hide()
    f.action:Show()
    f.action:SetText(L("Apply Settings"))
    f.action:SetScript("OnClick", function()
        local text = f.edit:GetText() or ""
        local ok, message = ns.ImportProfileText(text)
        if Chatify and Chatify.Print then Chatify:Print(message or (ok and L("Settings imported.") or L("Import failed."))) end
        if ok then f:Hide() end
    end)
    f.edit:SetText("")
    f.edit:SetFocus()
    f:Show()
end
