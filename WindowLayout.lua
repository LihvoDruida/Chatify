-- Viewport fitting for addon-owned windows only. UIParent dimensions are already
-- in logical UI units; scale text only when the minimum usable layout cannot fit.
local _, ns = ...
local Layout = {}
ns.WindowLayout = Layout
local windows = setmetatable({}, { __mode = "k" })

function Layout:Fit(frame)
    local spec = windows[frame]
    if not spec or spec.fitting then return end
    spec.fitting = true
    local availableWidth = math.max(1, UIParent:GetWidth() - 32)
    local availableHeight = math.max(1, UIParent:GetHeight() - 32)
    local width = math.max(spec.minWidth, math.min(spec.width, availableWidth))
    local height = math.max(spec.minHeight, math.min(spec.height, availableHeight))
    frame:SetScale(math.min(1, availableWidth / width, availableHeight / height))
    if spec.widget then
        spec.widget:SetWidth(width)
        spec.widget:SetHeight(height)
        spec.widget:DoLayout()
    else
        frame:SetSize(width, height)
    end
    if spec.onFit then spec.onFit() end
    spec.fitting = nil
end

function Layout:Attach(frame, spec)
    windows[frame] = spec
    frame:SetClampedToScreen(true)
    -- A pooled AceGUI frame keeps hooks, but the hook is inert after Detach.
    if not frame.__chatifyViewportHooked then
        frame.__chatifyViewportHooked = true
        frame:HookScript("OnShow", function(f) Layout:Fit(f) end)
    end
    self:Fit(frame)
end

function Layout:Detach(frame)
    windows[frame] = nil
    frame:SetScale(1)
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
    for frame in pairs(windows) do
        if frame:IsShown() then Layout:Fit(frame) end
    end
end)
