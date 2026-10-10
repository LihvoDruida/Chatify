-- WoW: Forever (internal beta codename: Camelot) load-time marker.
--
-- Forever is a hybrid client: Camelot, Mainline, Shared and VanillaStyle UI
-- components can coexist in the same runtime. This marker is listed only by
-- Chatify_Camelot.toc; runtime detection also accepts Camelot constants and its
-- interface range when a client falls back to the generic TOC.
-- Keep game identity separate from capability and probe each API before use.
local addonName, ns = ...

ns.Client = ns.Client or {}
ns.Client.isForever = true
ns.Client.flavor = "forever"
ns.Client.tocFlavor = "camelot"
ns.Client.addonName = addonName
-- Capability hints for diagnostics and feature routing. These do not bypass
-- runtime API probes; they describe the expected Forever architecture so a
-- missing API can be treated as a beta regression instead of as Classic Era.
ns.Client.interface = 16001
ns.Client.usesMainlineUI = true
ns.Client.usesModernChat = true
ns.Client.usesSecretValues = true
ns.Client.chatFrameUtilExpected = true
ns.Client.hybridUI = true
ns.Client.prefersCapabilityDetection = true

