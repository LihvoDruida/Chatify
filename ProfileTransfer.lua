local addonName, ns = ...
local Chatify = ns.Chatify or LibStub("AceAddon-3.0"):GetAddon("Chatify")

local MAX_EXPORT_BYTES = 512 * 1024
local MAX_ENTRIES = 10000
local MAX_DEPTH = 12
local MAX_KEY_BYTES = 128
local MAX_STRING_BYTES = 8192
local HEADER = "CHATIFY_PROFILE\t2"
local FOOTER = "CHATIFY_END"

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
        if not EncodeKey(key) then return nil, L("Profile contains an unsupported key.") end
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then return tostring(a) < tostring(b) end
        return ta < tb
    end)
    return keys
end

-- Adler-32 uses exact integer arithmetic on Lua 5.1 and needs no bit library.
local function Checksum(text)
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04X%04X", b, a)
end

local function ExportTable(root)
    local lines, count, ancestors = {}, 0, {}
    local function walk(tbl, path, depth)
        if depth > MAX_DEPTH then return nil, L("Profile nesting exceeds export limit.") end
        if ancestors[tbl] then return nil, L("Profile contains a cyclic table.") end
        ancestors[tbl] = true
        local keys, err = SortedKeys(tbl)
        if not keys then ancestors[tbl] = nil; return nil, err end
        for i = 1, #keys do
            count = count + 1
            if count > MAX_ENTRIES then ancestors[tbl] = nil; return nil, L("Profile contains too many entries.") end
            local key = keys[i]
            local childPath = path == "" and EncodeKey(key) or (path .. "/" .. EncodeKey(key))
            local value, kind = tbl[key], type(tbl[key])
            if kind == "table" then
                lines[#lines + 1] = childPath .. "\tT\t"
                local ok, why = walk(value, childPath, depth + 1)
                if not ok then ancestors[tbl] = nil; return nil, why end
            elseif kind == "string" then
                if #value > MAX_STRING_BYTES then ancestors[tbl] = nil; return nil, L("Profile contains text exceeding export limit.") end
                lines[#lines + 1] = childPath .. "\tS\t" .. Encode(value)
            elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
                lines[#lines + 1] = childPath .. "\tN\t" .. tostring(value)
            elseif kind == "boolean" then
                lines[#lines + 1] = childPath .. "\tB\t" .. (value and "1" or "0")
            else
                ancestors[tbl] = nil
                return nil, L("Profile contains an unsupported value.")
            end
        end
        ancestors[tbl] = nil
        return true
    end
    local ok, err = walk(root, "", 0)
    if not ok then return nil, err end
    local body = table.concat(lines, "\n")
    if body == "" then return nil, L("Cannot export an empty profile.") end
    local text = HEADER .. "\n" .. body .. "\n" .. FOOTER .. "\t" .. tostring(count) .. "\t" .. Checksum(body)
    if #text > MAX_EXPORT_BYTES then return nil, L("Profile export is too large.") end
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

-- Validate the actual supported schema, not just root keys. Maps with dynamic
-- keys are intentionally limited to the value shape that their consumers use.
local dynamicStrings = {
    channelLabels = true, channelLabelsNamed = true, channelLabelNames = true,
    channelLabelsNumbered = true,
}
local enums = {
    channelModes = {default=true, short=true, custom=true, hidden=true},
    spamFilterMode = {block=true, log=true},
    chatTabsTemplate = {PM=true, GUILD=true, RAID=true},
    copyTabMode = {ALL=true, VISIBLE=true, PINNED=true, SELECTED=true},
    language = {client=true, enUS=true, ukUA=true},
    retailChatFilterMode = {full=true, lockdown=true, off=true},
    quickChatButtonTheme = {AUTO=true, STANDARD=true, ELVUI=true, GW2UI=true},
    ["composer.continuation"] = {BOTH=true, START=true, END=true, NONE=true},
    ["composer.defaultChannel"] = {SAY=true, YELL=true, PARTY=true, RAID=true, GUILD=true, OFFICER=true, INSTANCE_CHAT=true, WHISPER=true, CHANNEL=true},
}
local numberRanges = {
    lineSpacing={0, 20}, historyLimit={1, 10000}, historyStorageKB={1, 100000},
    throttleTime={0, 86400}, throttleMinLength={0, 10000},
    spamLogLimit={0, 10000}, scrollbackLines={0, 100000},
    chatFadeTime={0, 86400}, scrollLinesPerNotch={1, 100},
    senderIconScale={1, 400}, senderIconOffset={-100, 100},
    quickChatButtonSize={1, 256}, quickChatButtonGap={-500, 500},
    quickChatButtonYOffset={-500, 500}, quickChatButtonAlpha={0, 1},
    quickChatPanelAlpha={0, 1}, quickChatButtonSpacing={0, 200},
    quickChatButtonFontScale={0.1, 5}, copyNativeTimeout={0, 86400},
    ["composer.automationDelay"]={0, 3600}, ["composer.chunkLimit"]={1, 10000},
    ["autoReply.cooldown"]={0, 86400},
}

local function ValidateValue(value, example, path, depth)
    if depth > MAX_DEPTH then return false, path .. ": nesting limit" end
    local kind = type(example)
    if type(value) ~= kind then return false, path .. ": expected " .. kind end
    if kind == "number" then
        if value ~= value or math.abs(value) == math.huge then return false, path .. ": invalid number" end
        local bounds = numberRanges[path]
        if bounds and (value < bounds[1] or value > bounds[2]) then return false, path .. ": out of range" end
        if not bounds and math.abs(value) > 1000000 then return false, path .. ": out of range" end
    elseif kind == "string" then
        local allowed = enums[path]
        if allowed and not allowed[value] then return false, path .. ": unsupported option" end
    elseif kind == "table" then
        local root = path:match("^[^.]+")
        for k, v in pairs(value) do
            local keyKind = type(k)
            if keyKind ~= "string" and keyKind ~= "number" then return false, path .. ": invalid map key" end
            if path == "spamKeywords" or path == "mentionRules" then
                if keyKind ~= "number" or k < 1 or k ~= math.floor(k) then return false, path .. ": invalid list index" end
            elseif root == "channelModes" or dynamicStrings[root] or root == "copyTabFrames" then
                if keyKind ~= "string" and keyKind ~= "number" then return false, path .. ": invalid key" end
            end
            local expected = example[k]
            if expected == nil then
                if root == "spamKeywords" then expected = ""
                elseif root == "mentionRules" and path == "mentionRules" then expected = example[1]
                elseif root == "channelModes" then expected = "default"
                elseif dynamicStrings[root] then expected = ""
                elseif root == "copyTabFrames" then expected = true
                elseif path == "sounds.events" then expected = "None"
                else return false, path .. "." .. tostring(k) .. ": unknown field" end
            end
            local childPath = path .. "." .. tostring(k)
            if root == "channelModes" then
                if type(v) ~= "string" or not enums.channelModes[v] then return false, childPath .. ": unsupported mode" end
            else
                local ok, why = ValidateValue(v, expected, childPath, depth + 1)
                if not ok then return false, why end
            end
        end
    end
    return true
end

local function ValidateProfile(root)
    local defaults = ns.defaults and ns.defaults.profile
    if type(defaults) ~= "table" then return nil, L("Chatify defaults are unavailable.") end
    if next(root) == nil then return nil, L("Cannot import an empty profile.") end
    for key, value in pairs(root) do
        local expected = defaults[key]
        if expected == nil and (key == "_chatifyMentionSettingsMigrated" or key == "_chatifyCompatMigrated") then
            expected = true -- legacy migration markers must survive round-trip
        end
        if expected == nil then return nil, "Unknown profile field: " .. tostring(key) end
        local ok, err = ValidateValue(value, expected, tostring(key), 0)
        if not ok then return nil, err end
    end
    return root
end

local function ParseProfile(text)
    if type(text) ~= "string" or text == "" or #text > MAX_EXPORT_BYTES then
        return nil, L("Invalid or empty Chatify profile text.")
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local first, rest = text:match("^([^\n]+)\n?(.*)$")
    if first ~= HEADER then return nil, L("Unsupported or incomplete profile format. Export a new backup first.") end
    local body, expectedCount, expectedSum = rest:match("^(.*)\n" .. FOOTER .. "\t(%d+)\t(%x%x%x%x%x%x%x%x)$")
    if not body or #body == 0 or Checksum(body) ~= expectedSum then
        return nil, L("Profile backup is incomplete or has failed its checksum.")
    end
    local root, count, seen = {}, 0, {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line == "" then return nil, L("Profile contains an invalid line.") end
        count = count + 1
        if count > MAX_ENTRIES then return nil, L("Profile contains too many entries.") end
        local path, kind, raw = line:match("^([^\t]+)\t([TSNB])\t(.*)$")
        if not path or seen[path] then return nil, L("Profile contains an invalid or duplicate line.") end
        seen[path] = true
        local tokens = {}
        for token in path:gmatch("[^/]+") do tokens[#tokens + 1] = token end
        if #tokens == 0 or #tokens > MAX_DEPTH + 1 or path:find("//", 1, true) then return nil, L("Profile nesting is invalid.") end
        local parent, key = EnsurePath(root, tokens)
        if not parent or key == nil then return nil, L("Profile contains an invalid key.") end
        if kind == "T" then
            if raw ~= "" or parent[key] ~= nil and type(parent[key]) ~= "table" then return nil, L("Profile table is invalid.") end
            parent[key] = parent[key] or {}
        elseif kind == "S" then
            local value = Decode(raw)
            if value == nil or #value > MAX_STRING_BYTES then return nil, L("Profile contains an invalid text value.") end
            parent[key] = value
        elseif kind == "N" then
            local value = tonumber(raw)
            if not value or value ~= value or math.abs(value) == math.huge then return nil, L("Profile contains an invalid number.") end
            parent[key] = value
        elseif kind == "B" then
            if raw ~= "0" and raw ~= "1" then return nil, L("Profile contains an invalid boolean.") end
            parent[key] = raw == "1"
        end
    end
    if count ~= tonumber(expectedCount) then return nil, L("Profile entry count does not match.") end
    return ValidateProfile(root)
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

local function ReplaceProfile(profile, source)
    for key in pairs(profile) do profile[key] = nil end
    for key, value in pairs(source) do profile[key] = DeepCopy(value, 0) end
end

function ns.ImportProfileText(text)
    local imported, err = ParseProfile(text)
    if not imported then return false, err end
    local profile = Chatify and Chatify.db and Chatify.db.profile
    if type(profile) ~= "table" then return false, L("Chatify profile is unavailable.") end
    local snapshot = DeepCopy(profile, 0)
    -- Build everything before mutating the AceDB profile table.
    local nextProfile = DeepCopy(imported, 0)
    local ok, applyErr = pcall(function()
        ReplaceProfile(profile, nextProfile)
        if type(Chatify.RefreshConfig) == "function" then Chatify:RefreshConfig() end
    end)
    if not ok then
        ReplaceProfile(profile, snapshot)
        -- Best effort to restore the previous visual state as well as the data.
        if type(Chatify.RefreshConfig) == "function" then pcall(Chatify.RefreshConfig, Chatify) end
        return false, L("Profile application failed; previous settings restored.") .. " " .. tostring(applyErr)
    end
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
