-- Quick Chat button placement: horizontal offset and keep-on-screen fallbacks.
-- Pure geometry (no WoW API); coordinates are UI units, y grows upward.
local ns = {}
assert(loadfile("ChatQuickButtonPlacement.lua"))("Chatify", ns)
local R = ns.ResolveQuickChatPlacement
local screen = {left=0,right=1920,top=1080,bottom=0}
local function span(p, chat, w)
  if p.side=="LEFT" then local r=chat.left-p.gap+p.x return r-w, r end
  local l=chat.right+p.gap+p.x return l, l+w end
local W, H = 30, 146
local function rect(l,r,t,b) return {left=l,right=r,top=t,bottom=b} end

-- 1) Screenshot 1/3: room on the left -> unchanged exterior dock
local chat = rect(75,460,240,40); local sidebar = rect(42,68,240,40)
local p = R({side="LEFT", gap=18, y=-4, chat=chat, sidebar=sidebar, screen=screen, panelWidth=W, panelHeight=H})
assert(p.mode=="exterior" and p.side=="LEFT", p.mode)
local l = span(p, chat, W); assert(l >= 0)

-- 2) Screenshot 2: chat at the left edge, native column full -> flip right
chat = rect(37,430,240,40); sidebar = rect(5,30,240,40)
local natives = { rect(5,30,232,206), rect(5,30,204,178), rect(5,30,176,150), rect(5,30,148,122), rect(5,30,70,44) }
p = R({side="LEFT", gap=18, chat=chat, sidebar=sidebar, screen=screen, panelWidth=W, panelHeight=H, columnObstacles=natives})
assert(p.mode=="flipped" and p.side=="RIGHT" and p.requestedSide=="LEFT", p.mode)
local a,b = span(p, chat, W); assert(a >= 0 and b <= 1920)

-- 3) Same, but a tall chat leaves a free gap in the native column -> dock inline
chat = rect(37,430,500,40); sidebar = rect(5,30,500,40)
p = R({side="LEFT", gap=18, chat=chat, sidebar=sidebar, screen=screen, panelWidth=W, panelHeight=H, columnObstacles=natives})
assert(p.mode=="native-column" and p.slot, p.mode)
assert(p.slot.top <= 497 and p.slot.top - H >= 232, "slot above native buttons: "..p.slot.top)
assert(math.abs(p.slot.x - 17.5) < 0.01)

-- 4) Chatify's own toolbar fills that gap too -> not inline (flip instead)
local obs = { unpack(natives) }; obs[#obs+1] = rect(5,30,497,240)
p = R({side="LEFT", gap=18, chat=chat, sidebar=sidebar, screen=screen, panelWidth=W, panelHeight=H, columnObstacles=obs})
assert(p.mode=="flipped", p.mode)

-- 5) Chat spans the whole screen width -> clamp just inside the edge
chat = rect(10,1910,240,40)
p = R({side="LEFT", gap=18, chat=chat, screen=screen, panelWidth=W, panelHeight=H})
assert(p.mode=="clamped", p.mode); a,b = span(p, chat, W); assert(a == 0, a)
p = R({side="RIGHT", gap=18, chat=chat, screen=screen, panelWidth=W, panelHeight=H})
assert(p.mode=="clamped"); a,b = span(p, chat, W); assert(b == 1920, b)

-- 6) Manual X offset that already makes it fit is respected exactly
chat = rect(37,430,240,40)
p = R({side="LEFT", gap=18, x=60, chat=chat, screen=screen, panelWidth=W, panelHeight=H})
assert(p.mode=="exterior" and p.x==60)

-- 7) No geometry (old callers) -> behaves exactly as before
p = R({side="LEFT", gap=18, y=-4})
assert(p.mode=="exterior" and p.side=="LEFT" and p.gap==18 and p.x==0 and p.y==-4)

-- 8) Native slot finder for Chatify's toolbar is unchanged
assert(ns.ResolveNativeSidebarSlot({sidebar=rect(5,30,500,40), chat=rect(37,430,500,40), buttons=natives, count=3}))
local p = ns.ResolveQuickChatPlacement({side="LEFT", gap=18, y=-4, chat=chat})
assert(p.x == 0 and p.gap == 18 and p.side == "LEFT", "default x=0")
p = ns.ResolveQuickChatPlacement({side="LEFT", gap=18, x=45, chat=chat})
assert(p.x == 45, "positive x kept")
-- final x as LayoutButtons computes it: -gap + x  => on-screen at chat.left edge
assert(-p.gap + p.x == 27, "left dock pulled back on-screen")
assert(ns.ResolveQuickChatPlacement({x=-500}).x == -100, "clamp low")
assert(ns.ResolveQuickChatPlacement({x=500}).x == 100, "clamp high")
assert(ns.ResolveQuickChatPlacement({x=0/0}).x == 0, "NaN -> 0")
assert(ns.ResolveQuickChatPlacement({x=12.6}).x == 13, "rounding")
print("Quick placement probe: PASS (offset + 8 on-screen scenarios)")
