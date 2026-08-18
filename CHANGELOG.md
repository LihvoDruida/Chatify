#### 0.11.44

The copy window fixes shipped in 0.11.39 did not work. Reported again against that build, with one new detail that changes the diagnosis.

What was wrong with the 0.11.39 fix
- It treated the blank window as a scroll-frame layout problem: the scroll child was filled before it was resized and its rect was never recomputed. That reasoning was plausible and it was wrong. Rect handling was tightened and nothing changed on the client.
- The detail that settles it: closing Copy and opening History shows the *previous* window's text until you click into the box. A stale layout cannot produce old text. The text is set and the display is simply not regenerated until the box is interacted with.
- That single behaviour accounts for every symptom filed separately: blank on open, unchanged after a tab switch, previous contents after switching windows, the caret and Select All appearing one action late. Dragging to select may well be working already and merely invisible for the same reason.

Changed
- The window now takes keyboard focus itself, one frame after the text and layout land, instead of clearing focus. Focus is the interaction the user was performing manually, so Chatify performs it. Escape closes the window as before.
- Removed the eb:SetOnUpdateMode("RunWhenVisible") call added in an earlier round. It was written on an unverified assumption about the 12.1 default, it is pcall-wrapped so a rejected argument would be silent, and it sits on the exact path under investigation. An unverified call there is a variable, not a safeguard.

Added
- /chatcopy diag prints what the window actually looks like on the client: whether the FrameXML scrolling-edit helpers still exist on this build, the EditBox's text length against what Chatify set, its size, visibility and focus state, and the scroll frame's range, offset and child. Every read goes through pcall so the dump cannot itself error.

This release is reasoned from the reported behaviour, not from a confirmed mechanism. If the window still misbehaves, /chatcopy diag output taken with it open is what will settle it.

#### 0.11.43

Second half of the 0.11.39 render-path regression: a short mention rule colouring part of a longer word.

Fixed
- With rules for both "Malivil" and "Mal", the word "Malivil" came out with only its first three letters coloured, making a whole-word rule look like it was matching a partial word. Whole-word matching was never wrong - ns.ApplyMentionRules refuses "Mal" inside "malivil" correctly, in every mode. The fault was in where the render path put the highlight.
- A parked message stays in the queue for a few seconds so it can reach every chat frame that shows the channel. The swap searched the rendered line for that message as a substring, so the entry left over from a previous line ("Mal") found itself inside the next one and coloured three letters of "Malivil". 0.11.42 fixed the same matching mistake where it corrupted the sender link; this is the remaining case.
- The swap now requires the parked message to be the whole body of the line, which is what it always is - everything Blizzard puts around it comes first. A fragment match is no longer possible. Where two parked messages could both end the line, the longer one wins, since that can only happen when one is a suffix of the other.

Testing
- tools/mention_probe.lua now runs the reported two-rule configuration: it asserts whole-word matching directly, then sends "Mal" followed by "Malivil" without clearing the queue and checks each line carries only its own highlight. Run against 0.11.42 the middle case fails with |cffffd700Mal|rivil.

#### 0.11.42

Fixes mention highlighting corrupting the sender link. Introduced in 0.11.39 with the render-time mention path.

Fixed
- A mention whose word also appears in your own character name put raw |Hplayer:...| markup on screen instead of a chat line. The render path swaps the raw message for the coloured one inside the line Blizzard built, and it took the first match - but the rendered line contains the sender's name three times: in the link data, in the visible [Name], and only then as the message. A colour code inserted into the link data breaks the link, so the game printed the markup instead of drawing it.
- Same cause behind the sender name being highlighted instead of the message text: the second of those three positions is the link's display text.
- The swap now targets the message body only. Matches that start inside a hyperlink block are skipped, and of the rest the one running to the end of the line wins, since everything Blizzard puts in front of the body - timestamp, channel label, sender - comes earlier. A match that starts exactly at a link boundary is still accepted, so a message opening with an item link is highlighted as before.

Testing
- tools/mention_probe.lua now renders the exact line from the report, plus the shorter-rule variant where the word sits inside the link data, and a message opening with an item link. Run against 0.11.41 all three fail with visibly broken markup.
- check_all.sh piped the probes through `tail`, so the pipeline reported tail's exit status and a failing probe was announced as "All checks passed". Fixed; the failure above is what surfaced it.

#### 0.11.41

Chatify no longer replaces SetItemRef. Reported as two errors on clicking a Discord name link in chat.

Fixed
- Chatify took over the global SetItemRef with AceHook:RawHook, so every hyperlink click in the game ran through addon code before reaching Blizzard's handler. That taints the execution path, and Blizzard's own handlers call protected functions on it. Clicking a Discord name link produced "AddOn 'Chatify' tried to call the protected function 'GetDiscordUserName()'" followed by "bad argument #2 to 'format' (string expected, got no value)" - the second being a consequence of the first, since the blocked call returned nothing and Blizzard formatted the name it never got.
- Chatify was not involved in that link at all. Being in the call stack was enough.
- Link dispatch is now a hooksecurefunc post-hook, which taints nothing. Blizzard's dispatch ignores link types it does not know, so Chatify's own |Hchatcopy:| timestamps and |Hurl:| links reach the handler exactly as before, and every other link is now handled on a clean path.
- The handler is wrapped in pcall: a hook that errors inside a Blizzard function aborts Blizzard's own execution.

Testing
- tools/stub/wow_env.lua now models AceHook:RawHook on a global for real instead of stubbing it to a no-op. A test that cannot observe a Blizzard global being replaced cannot catch a taint vector, which is how this survived every check until a user reported it.
- tools/hook_probe.lua asserts SetItemRef is never replaced and that our own link types still reach the secure hook. Run against 0.11.40 it fails on both.

#### 0.11.40

Fixes a hook that read the wrong argument from a Blizzard API. Reported with a full trace by a user running Prat alongside Chatify.

Fixed
- Chatify hooked FCF_SetChatWindowFontSize as function(chatFrame), but the function is declared FCF_SetChatWindowFontSize(self, chatFrame, fontSize). The first argument is the caller, not the frame, so the wrong object was styled. It now reads the second.
- This was wrong even without a second chat addon installed. When Blizzard's own font-size dropdown calls the API, `self` is the dropdown button, so Chatify styled the button and never restyled the chat frame. It only became visible as an error when Prat's Font module called the API with a plain module table as `self`, which has no frame methods for ns.GetEditBox to call.
- ns.GetEditBox no longer assumes the object it is given is a frame. It checks GetName/GetID before calling them, so a bad argument returns nil instead of raising.
- Added ns.IsChatFrame and applied it to every entry point that receives a "chat frame" from outside Chatify: the two StyleFrame hooks and the router's window-refresh hook, which is shared by three Blizzard functions of which only one puts the chat frame first.

Testing
- tools/hook_probe.lua drives the hooks with the argument shapes real callers use - Prat's, Blizzard's dropdown, and all-nil - and is wired into check_all.sh. Run against 0.11.39 it reproduces the reported error exactly.

#### 0.11.39

Three user-reported bugs: the Mention Manager was silently doing nothing on Retail, and the Copy / History window was largely unusable with a mouse.

Fixed - Mention Manager
- Mentions are highlighted on modern Retail again. ns.ApplyMentionRules only ever runs from inside a chat message-event filter, and on 12.0+ those filters are not installed by default, so nothing ever called it. The rules matched perfectly and were never consulted; the options panel still showed them as active. The mention *sound* had a fallback since 0.11.3x, the highlight had none.
- The highlight now has one. Chatify's own event frame matches the rule with the full event context, so per-channel scoping still resolves correctly, and parks the coloured message; the AddMessage wrapper then swaps it into the line Blizzard built. Nothing is attached to Blizzard's chat dispatch, so no taint is introduced and the Safest filter mode stays safe. Only messages that actually matched a rule are ever parked, so an ordinary chat line costs one comparison.
- Exactly one of the two paths is ever live, keyed on whether the filters are actually installed rather than on whether they are currently permitted. Nothing is highlighted twice, and there is no gap while the lockdown gate flips mid-session.
- The Mention Manager tab now says which path is in force on 12.0+.

Fixed - Copy and History window
- Text can be selected by dragging again. An OnMouseDown handler called SetFocus() on every click, which reset the cursor and discarded the selection anchor the click had just placed. It was also redundant: the EditBox already takes focus when clicked.
- The window no longer opens blank until the first click. The scroll child was filled before it was resized and its rect was never recomputed afterwards, so the scroll frame laid the content out against the 1px placeholder height the EditBox is created with. The child is now sized first, the rect is refreshed after the text lands, and once more on the next frame - the first pass runs in the same frame as Show(), when the anchors are not resolved yet and GetWidth() cannot answer honestly.
- The caret and the selection no longer render one action behind. ScrollingEdit_OnCursorChanged / ScrollingEdit_OnUpdate were called under a plain `if`, so on a client without those FrameXML globals both handlers were silently no-ops. The same cursor-following algorithm is now implemented locally as a fallback, and the child rect is refreshed on cursor changes too.
- Select All shows the selection immediately. Highlighting in the same frame as SetFocus is unreliable, because a selection is only drawn while the box holds focus and the focus change has not been applied yet; it is now reasserted a frame later.
- All of the above applied to the History window as well, which is the same window in a different mode.

Testing
- tools/mention_probe.lua drives the whole mention path in both client shapes - chat event first, AddMessage second - and is wired into check_all.sh. It reproduces the 0.11.38 bug in one run and is the check that would have caught it.

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