-- WoW: Forever (internal beta codename: Camelot) load-time marker.
--
-- Forever currently shares Mainline's modern UI/runtime and most 12.1.5 APIs,
-- while using its own game flavor and TOC (Interface 16001).  Runtime project
-- constants are not a reliable discriminator because the beta can identify as
-- WOW_PROJECT_MAINLINE.  This file is therefore listed ONLY by Chatify_Camelot.toc.
-- Keep identity (Forever) separate from capability (modern/secret-value UI).
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

