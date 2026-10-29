-- Extract names/signatures from Blizzard generated documentation, in a restricted
-- Lua environment. Constants only satisfy ignored enum/default expressions;
-- their values are deliberately NOT part of this API contract snapshot.
local function fields(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[#out+1] = table.concat({row.Name or "", row.Type or "", tostring(row.Nilable or false), row.Mixin or ""}, ":")
    end
    return table.concat(out, ";")
end
local constants = setmetatable({}, {__index = function(self) return self end, __add=function() return 0 end, __sub=function() return 0 end, __mul=function() return 0 end, __div=function() return 0 end})
local filename
local api = {AddDocumentationTable = function(_, data)
    for _, fn in ipairs(data.Functions or {}) do
        io.write(table.concat({"F", data.Namespace or "", fn.Name, fields(fn.Arguments), fields(fn.Returns), data.Name or "", filename, data.Type or "", fn.SecretArguments or ""}, "\t"), "\n")
    end
    for _, event in ipairs(data.Events or {}) do
        if event.LiteralName then io.write(table.concat({"E", event.LiteralName, fields(event.Payload), filename}, "\t"), "\n") end
    end
end}
for _, path in ipairs(arg) do
    filename = path:match("([^/]+)$")
    local environment = {APIDocumentation = api, Enum = constants, Constants = constants}
    local chunk, err
    if type(setfenv) == "function" then
        chunk, err = loadfile(path)
        if chunk then setfenv(chunk, environment) end
    else
        chunk, err = loadfile(path, "t", environment)
    end
    if chunk then
        local ok, why = pcall(chunk)
        if not ok then io.write("ERROR\t", filename, "\t", why, "\n") end
    else
        io.write("ERROR\t", filename, "\t", err, "\n")
    end
end
