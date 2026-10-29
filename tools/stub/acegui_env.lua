-- Load the shipped AceGUI core and real widget implementations on the frame
-- fixture. Only XML-created regions, fonts and WoW xpcall varargs are modelled.
-- Geometry assertions cover Lua layout contracts, not Blizzard text rendering.
local M = {}
function M.install(env)
    local unpack = unpack or table.unpack
    local baseCreateFrame = CreateFrame
    local function model(f)
        f.testPoints = {}
        f.SetPoint = function(self, ...) self.testPoints[#self.testPoints+1] = {...} end
        f.ClearAllPoints = function(self) self.testPoints = {} end
        f.GetStringWidth = function(self) return #self:GetText() * 7 end
        f.GetFontString = function(self)
            self.testFontString = self.testFontString or model(env.newFrame('FontString'))
            return self.testFontString
        end
        f.CreateFontString = function() return model(env.newFrame('FontString')) end
        f.GetTexture = function() return nil end
        f.GetTextInsets = function() return 0, 0, 0, 0 end
        return f
    end
    CreateFrame = function(kind, name, parent, template)
        local f = model(baseCreateFrame(kind, name, parent, template))
        if name and template == 'UIDropDownMenuTemplate' then
            for _, suffix in ipairs({'Left','Middle','Right','Button','Text'}) do
                _G[name..suffix] = model(env.newFrame(suffix == 'Button' and 'Button' or 'Texture'))
            end
        end
        if name and template == 'UIPanelScrollFrameTemplate' then
            _G[name..'ScrollBar'] = model(env.newFrame('Slider'))
        end
        return f
    end
    CreateFont = function() return model(env.newFrame('Font')) end
    GameFontNormalSmall = model(env.newFrame('Font'))
    GameFontHighlightSmall = model(env.newFrame('Font'))
    ChatFontNormal = model(env.newFrame('Font'))
    ACCEPT, OKAY = 'Accept', 'Okay'
    table.wipe = wipe
    local errors = {}
    geterrorhandler = function() return function(err) errors[#errors+1] = tostring(err) end end
    local savedXpcall = xpcall
    xpcall = function(fn, handler, ...)
        local args, n = {...}, select('#', ...)
        return savedXpcall(function() return fn(unpack(args, 1, n)) end, handler)
    end
    assert(loadfile('libs/AceGUI-3.0/AceGUI-3.0.lua'))()
    for _, name in ipairs({'Container-Frame','Container-ScrollFrame','Widget-Label','Widget-Button','Widget-EditBox','Widget-MultiLineEditBox','Widget-DropDown','Widget-DropDown-Items','Widget-CheckBox','Widget-Slider'}) do
        assert(loadfile('libs/AceGUI-3.0/widgets/AceGUI'..name..'.lua'))()
    end
    return { errors = errors, gui = LibStub('AceGUI-3.0') }
end
return M
