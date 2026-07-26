#### 0.11.21

Maximises what works on Midnight (12.0+) while keeping the secret-value guards, plus two latent crashes found by an addon-wide scan.

Fixed
- ns.ShouldBypassWhisperMutation was called unguarded by CanMutateChatPayload but never defined anywhere. Since CanMutateChatPayload runs for every chat message, this would have thrown on every line; it was only invisible because the 0.11.20 startup error aborted module loading before any filter ran. Implemented with the semantics the whisper option already documents.
- Removed a duplicate definition of ns.CanAccessChatValue that shadowed the batch-API version.

Restored on retail
- Chat history now records whispers, emotes and achievements again. History is captured on Chatify's own event frame and never touches Blizzard's chat dispatch, so the blanket per-event block bought no safety; the per-payload secret guard is the real gate and remains in place.
- Chat filter behaviour is now a three-way choice instead of an on/off switch: Maximum (always filter), Balanced (default, pause only while chat is locked down) and Safest (never filter). Migrates the old boolean automatically.
- In Maximum mode Chatify renders timestamps itself again, restoring the configured format and colour. The native showTimestamps CVar is used in the other two modes and is explicitly cleared in Maximum so no line is stamped twice.

Performance
- Secret inspection now uses Blizzard's batch hasanysecretvalues / canaccessallvalues instead of looping over the vararg in Lua, with the loop kept as a fallback. This is the hottest path in the addon: it runs for every message, once per chat frame the event is registered on.
- GetBuildInterface ran pcall(GetBuildInfo) on every call, and IsRetailSecretValueBuild called it per message. Both answers are constant for a session and are now cached.
- The chat lockdown state is cached too, invalidated from the same event watcher that already recomputes the filter gate. The outgoing-message gate deliberately still reads it fresh, where a stale answer would cause the ADDON_ACTION_BLOCKED popup it exists to prevent.

Still disabled on 12.0+ by design: virtual chat and the AddMessage replacement (they hook Blizzard's chat frames directly), and short channel names (they overwrite Blizzard GlobalStrings, which is a genuine taint vector).

#### 0.11.20

Fixes a startup error introduced in 0.11.18 that aborted module loading.

- Fixed "Config.lua:975: attempt to call a nil value". CanUseMessageEventFilters called GetProfile(), a helper that had been removed earlier, so the call raised an error. Because it runs from ChatVisuals:OnEnable, AceAddon's module loop aborted and every module after it (quick buttons, filters, history, sounds, auto-reply) was never enabled. This is the likely cause of the icon buttons rendering without their symbols. The profile is now resolved inline and tolerates a missing db.
- Fixed the global `Chatify` never existing. AceAddon does not publish a global for you, and the addon object was only stored on the private namespace, yet all nine modules are written against a global (`if Chatify and Chatify.db then ...`). Roughly 115 references silently evaluated to nil and took their fallback path, which quietly disabled the /chatcopy slash command, the retail safe-mode enforcement in ChatFilters and ChatHistory, and the per-character auto-reply state. The addon object is now published under that name.

#### 0.11.19

Quick chat button fixes.

- Fixed a half-typed message being destroyed when the button for the channel you were already on was clicked: ChatFrame_OpenChat overwrote the edit box with the literal slash ("/g ") and the restore path was skipped because the chat type had not changed. The draft is now preserved, and the slash is no longer left sitting in the box as visible text.
- The draft is only carried over when the edit box is actually open, so stale text from a closed box is not resurrected.
- Clicking the same button twice no longer stacks the slash prefix ("/g /g ").
- Fixed Alt preview never redrawing. MODIFIER_STATE_CHANGED queued a state update, but the Alt state was absent from the button state signature, so UpdateButtonState always bailed out as unchanged. Holding Alt now swaps the label to the alternate channel (G to O, R to RW) when that channel is actually available, matching Alt + Left Click.
- Raid Warning and Officer availability now refresh on PARTY_LEADER_CHANGED and GUILD_RANKS_UPDATE. Being promoted or demoted previously left the button state stale until a group roster change or a reload.

#### 0.11.18

Corrects the 0.11.17 over-reaction and finishes the lockdown-scoped filter handling.

- 0.11.17 disabled every chat message-event filter on 12.0+ clients. That was wrong: filters are supported there, and Blizzard even added APIs (RemoveContiguousSpaces, EscapeLuaPatterns) specifically so addons can work with secret strings inside them. Spam filtering, keyword highlighting and custom link formatting are restored.
- Filters are now withdrawn only for the duration of chat messaging lockdown (boss encounters, Mythic+, rated PvP), which is when chat payloads actually carry secret values, and are reinstalled the moment it ends. Driven by ADDON_RESTRICTION_STATE_CHANGED with encounter/challenge-mode fallbacks.
- Fixed: ChatFilters called InstallMessageFilters(), which did not exist. The filter module's OnEnable was erroring out with "attempt to call a nil value". The function is now implemented and registers a lockdown refresh handler.
- Fixed: the retail filter setting was defined as retailAllowChatFilters but read as retailDisableChatFilters, so the option did nothing. Unified on retailDisableChatFilters, off by default, reframed as a troubleshooting switch.
- Timestamps on 12.0+ are handled solely by the game's showTimestamps CVar rather than a filter, so they no longer disappear mid-encounter and are never printed twice.

#### 0.11.17

Fixes the recurring "attempt to perform string conversion on a secret string value (execution tainted by 'Chatify')" error on Midnight (12.0+).

- Root cause: secret values only block operations on a *tainted* execution path. Registering any message-event filter through ChatFrame_AddMessageEventFilter puts a Chatify closure on Blizzard's chat dispatch stack, which taints it and the shared state ChatHistory_GetAccessID/ChatHistory_GetToken write into. The error then surfaces later on an unrelated event that happens to carry a secret sender (MONSTER_SAY in the reported case), which is why it appeared for chat types Chatify never filtered.
- Chatify no longer registers any chat message-event filter on 12.0+ clients. This is enforced at a single chokepoint plus both direct-call fallbacks.
- Timestamps on 12.0+ are now rendered by the game itself via the showTimestamps CVar, so they keep working during chat lockdown. Chatify only writes the CVar while its own timestamp option is on and restores the previous value when switched off.
- Consequence on 12.0+: spam filtering, keyword highlighting and custom link formatting are unavailable, because all three require a chat filter. A new opt-in "Re-enable chat filters (Retail, may cause errors)" toggle restores them for users who prefer the features over the error. Off by default; requires /reload.

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