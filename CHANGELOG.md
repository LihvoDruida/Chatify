#### 0.11.16

Cross-version + Midnight (12.0/12.1) audit pass.

- TOC: consolidated the six broken `-Flavor.toc` files (dash suffix — never loaded on Classic) into one multi-flavor `Chatify.toc` with comma-delimited interface versions; added Cataclysm Classic (40402) and 12.1.0 (120100). Removed the redundant Titan TOC.
- Secret Values: fixed retail detection to Mainline 12.0+ only (was firing from interface 110000, silently disabling history/timestamps/virtual chat/auto-reply on TWW 11.x and PTR builds).
- Chat lockdown: added `InChatMessagingLockdown` handling. Whisper timestamps, link/keyword/mention formatting and history now work during normal play and are only suspended while the client is actually protecting chat (encounters, Mythic+, PvP). Added a `Never modify whispers (Retail)` opt-out.
- Auto-reply: gated all outgoing SendChatMessage/BNSendWhisper calls behind the lockdown check to stop ADDON_ACTION_BLOCKED popups; switched all persisted cooldown/pending timestamps from GetTime() (uptime, resets on relog) to wall-clock time() so replies no longer get blocked forever after a relog.
- Short channel names: no longer disabled on retail (they only swap GlobalStrings, which carry no secret values); added the missing RAID_WARNING short form.
- Hardened BNet presence-id extraction against the trailing `discordInfo` argument added to CHAT_MSG_* in 12.1.
- Auto-reply default messages are stored as stable source strings instead of being frozen to the load-time locale.
- Slash commands: dropped the collision-prone `/mcm`; added `/cfy` alongside `/chatify`.
- Cleanup: removed dead code (unused proxy/hidden-frame helpers, empty stubs), the self-nested Chatify.zip, a duplicate Exo2 font, and the orphaned locale_loader.lua; packager now ignores docs/.

#### release 5.4

- Toc Bumps Cata and Retail
- Fix camera distance adjustment in combat, optimize event handling and CVar updates.