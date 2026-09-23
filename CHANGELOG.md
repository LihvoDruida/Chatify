## 2.17.3 - 2026-09-23

### Fixed

- Hardened Retail/Midnight and WoW: Forever whisper handling against third-party chat taint that can make Blizzard `ChatFrameUtil.SetLastTellTarget()` receive a secret sender on an insecure execution path.
- `SetLastTellTarget` guard now prefers `securecallfunction` to re-enter Blizzard's original helper in its native security context, preserving the reply target when the client supports the secure bridge.
- On clients without the secure bridge, the fallback drops only inaccessible secret tell targets instead of allowing Blizzard's `strupper()` conversion to raise.
- The guard is no longer limited to Chatify-owned `AddMessage` wrappers: Chatify can detect an already-tainted upstream chat surface and install the compatibility guard before the first protected whisper.
- Added `ADDON_LOADED`/world/restriction-state rechecks so late-loading addons are covered without installing the guard on an otherwise clean chat stack.

### Diagnostics

- Runtime chat diagnostics now report the detected external taint owner/surface, the active tell-target guard mode, `MessageEventHandler` ownership, and `ChatFrame1.AddMessage` ownership.
- This makes reports such as `execution tainted by 'CDPulse'` distinguishable from Chatify-originated taint instead of attributing every secret-string failure to the chat addon.

# Chatify Changelog

## 2.17.2 - 2026-09-23

### WoW: Forever

- Add native-aware first-name/surname mention matching for Forever's required two-part character names.
- Prefer `UnitNameUnmodified("player")` for the local identity, then fall back to `C_PlayerInfo.GetName({ unit = "player" })`, `UnitFullName`, and `UnitName`.
- Probe Forever-only `C_PlayerInfo.ShouldDisplaySurname` for diagnostics without depending on it for matching; the public API exposes a display predicate, not separate first-name/surname getters.
- Split only on the Forever flavor and accept both visible `First Surname` and canonical `First-Surname` forms.
- Upgrade existing player-name mention rules in-place so one rule reacts to the first name, surname, and both full-name forms.
- Keep manually edited non-player mention rules independent; editing a player rule away from the current identity disables automatic identity alias expansion.
- Show the resolved Forever first name, surname, API source, and surname-display probe directly in Mention Manager.
- Keep Retail and Classic mention behavior unchanged.

### Mention Manager

- Rework mention matching to choose the earliest/longest alias match, preventing nested highlights when a full name and its first-name/surname aliases overlap.
- Apply whole-word boundaries to ASCII full-name phrases as well as single-word mention rules.

## 2.17.1 - 2026-09-23

### Fixed

- Fix **Raid Warning** short/custom/hidden channel labels on Retail/Midnight when the rendered line is prefixed by a Blizzard/Chatify timestamp.
- Pass the originating `CHAT_MSG_*` event into the render-time channel label transformer so the non-hyperlink `CHAT_RAID_WARNING_GET` fallback can be scoped to `CHAT_MSG_RAID_WARNING` instead of matching unrelated text.
- Preserve any leading timestamp and inline markup while replacing `[Raid Warning]` with the configured value such as `[RW]`.
- Keep the existing hyperlink rewrite for Raid Leader/Raid/Party and the anchored no-event fallback for legacy clients.

## 2.17.0 - 2026-09-23

### Filter Engine 3.0

- Add a protected-client post-render blocking path using the chat frame's stored event metadata and `RemoveMessagesByPredicate`, so readable keyword matches can be removed on WoW: Forever even when message-event filters are intentionally disabled for taint safety.
- Keep legacy `ChatFrame_AddMessageEventFilter` filtering on clients where it is safe; never run both paths for the same message.
- Normalize WoW hyperlink/color/texture/atlas/Kstring markup while preserving readable hyperlink labels.
- Fold zero-width, bidi, combining, full-width, accented Latin, and common Cyrillic/Greek lookalike characters before keyword matching.
- Add conservative leetspeak matching for alphabetic blocklist terms of four or more characters, catching variants such as `b00st` without applying aggressive substitutions to short keywords.
- Cache one spam decision per Blizzard `eventArgs` table so the same message shown in several chat windows is evaluated and logged only once.
- Apply keyword additions/removals immediately without `/reload` and keep the protected-chat mode selector runtime-live.
- Normalize missing/corrupt `spamKeywords` profile data to an empty table during profile setup.
- Let Hide Join/Leave Messages use the same post-render removal path when protected-client event filters are detached.

### WoW: Forever

- Correct `/chatifydb` diagnostics for the current Forever beta SavedVariables restore bug: the client may write SavedVariables successfully but fail to restore them after `/reload`, relog, or restart.
- Stop telling Forever users that an unrestored database necessarily means the file was never written.
- Keep Chatify's AceDB lifecycle unchanged and compatible with external SavedVariables restore workarounds instead of replacing the global database table after AceDB has attached it.

## 2.16.4 - 2026-09-22

### Fixed

- Fix Forever live-tab rendering by routing automatic channel selection through Blizzard's complete `FCF_Tab_OnClick` path when available, including selected-frame, edit-box, fade, and repaint bookkeeping.
- Pass `frame.editBox` rather than the `ChatFrame` itself to `ChatFrameUtil.SetLastActiveWindow` / `ChatEdit_SetLastActiveWindow`.
- Listen to `ChatFrame.OnEditBoxPreSendText` on modern clients so `/p`, `/raid`, `/g`, and related chat types reveal the receiving docked tab after Blizzard resolves the final chat type but before the outgoing line is sent.
- Prefer the dock manager's actual selected window over potentially stale `SELECTED_CHAT_FRAME` / `SELECTED_DOCK_FRAME` globals on hybrid clients.
- Refresh fade/display state after fallback dock selection so a newly selected Forever tab consumes already queued lines immediately.

### Changed

- Default Chatify tab setup now selects configured tabs through the same Blizzard tab-click path used by a real user click, with guarded legacy fallbacks.
- Keep `UpdateHeader` routing as an immediate UI response while using the pre-send callback as the authoritative final routing check on modern/Forever clients.

## 2.16.3 - 2026-09-22

### Fixed

- Route channel membership checks through the current `ChatFrameMixin:ContainsChannel()` API with `ChatFrame_ContainsChannel` retained only as a legacy fallback.
- Route `RemoveAllMessageGroups`, `RemoveAllChannels`, and `AddMessageGroup` through one frame-method compatibility helper instead of assuming equivalent `ChatFrameUtil` functions exist.
- Accept numeric channel targets in the central send wrapper and preserve Blizzard's valid empty-message behavior for AFK/DND clearing.
- Fail closed when protected-client message filters initialize before the saved profile is attached.
- Add the two missing English/Ukrainian localization entries used by Settings.

### Changed

- Remove the unfinished `ChatProxy.lua` prototype from the production package; manifests loaded it, but no runtime path consumed it and its own integration plan was never started.
- Remove the orphaned legacy `locale_loader.lua`; current localization is exclusively handled by `Locales.lua` and `Locale:RegisterLocale`.
- Remove the obsolete `C_BattleNet.SendAccountMessage` fallback; current clients use `C_BattleNet.SendWhisper`, with `BNSendWhisper` retained for legacy clients.
- Re-verify current packaging targets without changing their interface numbers.

## 2.16.2 - 2026-09-21

### Fixed

- Stop stacking secure `AddMessage` history hooks when chat-window refresh events fire.
- Add an eventArgs identity guard so one Blizzard message cannot be stored several times by duplicate post-hook callbacks.
- Migrate 2.16.1 frame history to schema v4 and collapse adjacent duplicate rows created by the old hook stacking bug.
- Keep History Search bound to the currently open chat frame and replace its source even when that frame is empty.
- Use the current frame's own `GetMessageInfo` buffer as the only search fallback; never reuse a previous tab's results.
- Automatically select the docked Blizzard chat tab that receives Guild, Party, Raid, Raid Warning, Instance, Say, or Yell when Chatify changes chat type.
- Apply the same receiving-tab selection to native slash chat type changes through `ChatEdit_UpdateHeader`, preventing Party/Raid messages from remaining hidden until the tab is clicked.


## 2.16.1 - 2026-09-21

### Per-tab history isolation

- Replace CHAT_MSG event-registration routing as the primary History capture path with exact per-ChatFrame `AddMessage` post-hooks.
- Store a line only in the Blizzard chat frame that actually received it, preventing General, Guild, Raid, Whisper, and other tabs from bleeding into each other.
- Keep the old event router only as a fallback when `hooksecurefunc` is unavailable; never run both capture paths at once.
- Persist the new history schema as version 3 with `captureMode = frame-addmessage`.
- Drop legacy frame buckets once when upgrading because already-merged version 2 history cannot be separated reliably after the fact; virtual history is preserved.
- Keep protected-line placeholders scoped to the exact frame that received the protected message.
- Reattach the History post-hook if another addon replaces a chat frame's `AddMessage` implementation after Chatify initialized.

### Tab-scoped history search

- Bind History Search to the exact current chat-frame key instead of a shared popup entry list.
- Refuse to render stale search results if the selected History tab changes before its source is refreshed.
- Show the active search scope directly in the label, for example `Search in Guild`.
- Keep the same query when switching tabs, but re-run it only against the newly opened tab.
- Refresh the current frame history before each search so an open History window can see newly captured lines without borrowing data from another tab.
- Add explicit Ukrainian/Cyrillic case folding for literal search because Lua byte-based `string.lower` does not case-fold UTF-8 Cyrillic.

## 2.16.0 - 2026-09-21

### Secure post-render chat pipeline

- Add `ChatTransforms.lua` and prefer Blizzard `ScrollingMessageFrame:TransformMessages()` for readable chat entries when the API is available.
- Observe `AddMessage` with `hooksecurefunc` instead of replacing it on modern protected-chat clients.
- Match the exact rendered entry by message, event, and event-argument identity before transforming it.
- Route channel labels, mention highlighting, URL decoration, short visible player names, and sender icons through one post-render formatter.
- Stop taking ownership of `frame.AddMessage` when the secure post-render API is available; keep the existing legacy wrapper only as a fallback for older clients.
- Preserve Blizzard message colors and metadata when a line is transformed.

### Sender formatting

- Add Short Player Names while preserving the full `Name-Realm` player-link routing target.
- Add optional race and class atlas icons before readable player senders.
- Add sender icon scale and baseline offset controls.
- Skip sender decoration when GUID, sender, class, race, sex, atlas metadata, or event arguments are protected or unavailable.

### History safety and search

- Add a persistent history byte budget with a 128 KiB default and a configurable 32-512 KiB UI range.
- Reject individual history lines larger than 4096 bytes and prune the oldest lines before SavedVariables becomes dangerously large.
- Include virtual-chat history in the storage estimate and proactive pruning path.
- Add literal, case-insensitive search directly inside Chatify History for the currently selected chat tab.
- Keep search local to the selected history tab and preserve normal Copy mode without an extra search row.

### Profile backup

- Add `/chatifyexport` and `/chatifyimport`.
- Add Export Settings and Import Settings controls in Chatify settings.
- Export only Chatify profile settings; persistent chat history is intentionally excluded.
- Parse imports as a bounded typed data format instead of executing pasted Lua.
- Reject unknown top-level settings, excessive nesting, oversized values, invalid keys, invalid numbers, and oversized exports.

## 2.15.1 - 2026-09-21

### AceGUI text safety

- Update the bundled AceGUI Label widget surface to the current upstream Label revision and register Chatify's protected-text hardening as the next widget revision.
- Prevent secret, inaccessible, table, function, boolean, and other invalid values from reaching `FontString:SetText` through shared AceGUI Label instances.
- Keep the hardening effective when multiple addons embed AceGUI and LibStub selects widgets from different addon copies.
- Guard joined channel names before normalization or use in the settings UI.
- Sanitize dynamic Chatify AceConfig names and descriptions before they reach AceGUI.
- Keep normal strings and numeric labels unchanged.

## 2.15.0 - 2026-09-21

### Composer queue automation

- Restore timed queue automation as an optional Composer workflow.
- Add Start Auto Send, Resume Auto Send, and Stop Auto Send controls directly in the Composer.
- Add configurable automation delay from 0.8 to 10 seconds.
- Add optional auto-start immediately after a manual Split / Refresh Preview action.
- Add optional resume after a hardware-restricted chunk is sent manually.
- Add optional wait-and-resume behavior when Blizzard temporarily enables chat messaging lockdown.
- Pause automation instead of attempting timer sends for Say, Yell, Channel, or any other route treated as hardware-event restricted.
- Stop active automation when the draft, channel, whisper target, navigation state, or split configuration changes.
- Keep manual Send available when automation pauses for a required player click.
- Add a timer fallback for clients without `C_Timer.After`, using a lightweight frame OnUpdate scheduler.
- Keep outgoing messages behind the existing channel permission, protected-value, client capability, and chat-lockdown checks.
- Expose automation settings both in Chatify Settings and inside the Composer window.
- Add automation capability diagnostics and compatibility documentation.

## 2.14.0 - 2026-09-21

### Long Message Composer parity and automation

- Restore the full long-message editing workflow instead of keeping Composer as a minimal splitter.
- Keep the Composer window, draft, preview, selected chunk, and send state alive when the window is closed and reopened during the session.
- Add Composer-local controls for chunk byte limit, chunk counters, continuation markers, current-chat import, auto preview, auto advance, final-chunk protection, remembered whisper target, and optional spell-check integration.
- Keep Composer-local settings synchronized with the main Chatify settings profile.
- Automatically rebuild an already-loaded preview when splitter settings change.
- Automatically build a preview after importing the current chat draft or opening Composer with command text when Auto-build Preview is enabled.
- Preserve the last whisper target when configured, and keep it when Clear resets the message.
- Restore manual one-message-at-a-time send state with last-sent tracking and final-chunk duplicate protection.
- Restore automatic advance to the next chunk after a successful send, with an option to disable it.
- Allow normal channel selection to change between already-split chunks without rebuilding; Per Line routing remains fixed until the preview is rebuilt.
- Add Previous Chunk / Next Chunk navigation state and disable invalid actions automatically.
- Add an in-Composer Help window and a shortcut to Chatify settings.
- Add optional Misspelled integration after Composer edit-box setup and strip visual spell-check markup before splitting or sending.
- Refresh available channels automatically when group, guild, or world state changes.
- Add `/chatlong` as an additional Composer command.
- Keep all outgoing messages on the existing capability, protected-value, channel-permission, and chat-lockdown checks.

## 2.13.2 - 2026-09-21

- Integrated the existing quick-chat draft preservation path with Long Message Composer.
- LM now imports the currently typed visible chat draft, active supported chat type and whisper target when available.
- Added a Use Current Chat button for refreshing the Composer from the active Blizzard chat input without clearing the original draft.
- Added an option to disable automatic current-draft import while keeping manual import available.
- Kept protected/secret chat values fail-closed during draft and target import.
- Preserved the selected Composer channel when the active Blizzard chat type is unsupported by Composer.

## 2.13.1

- Added an opt-in Long Message Mode toggle.
- Added an `LM` quick-access button below the Guild/Raid/Party/Instance/Say button stack when Long Message Mode is enabled.
- The new button uses the active quick-button theme and opens the Long Message Composer directly.
- Long Message Mode can be toggled at runtime without `/reload`; the quick-button layout refreshes immediately.
- Composer settings and direct opening are disabled while the mode is off, while the settings tab remains available so it can be enabled again.

## [2.13.0] - 2026-09-21

### Long Message Composer
- Add a dedicated long-message editor with manual one-chunk-at-a-time sending.
- Split messages by WoW's byte limit without cutting UTF-8 characters in the middle.
- Prefer word boundaries and reserve space for chunk counters and continuation markers before splitting.
- Add per-line channel routing for `/s`, `/e`, `/y`, `/p`, `/raid`, `/rw`, `/i`, `/g`, `/o`, and `/w Name`.
- Add raid target marker insertion for `{rt1}` through `{rt8}`.
- Add chunk preview, previous/next navigation, byte usage, and safe runtime channel checks.
- Add configurable chunk limit, counters, continuation markers, and default channel.
- Add `/chatcompose` and `/chatcomposer` commands.

### Chat API hardening
- Add a shared modern-first outgoing chat wrapper used by the composer and auto-reply paths.
- Re-check chat messaging lockdown immediately before every composer send.
- Reject protected message/target values before calling the outgoing chat API.
- Hide the composer settings and commands when no supported outgoing chat API exists.

## [2.12.1] - 2026-09-20

### Forever hardening
- Treat Forever as a hybrid Camelot/Mainline/VanillaStyle client and route behavior by API capability instead of project identity.
- Keep client build numbers diagnostic-only; no Forever behavior depends on an exact executable build.
- Remove the remaining secret-restriction fallback based on `WOW_PROJECT_ID`.
- Expand secret-value API detection to scalar, batch, and accessibility inspectors and fail closed when the scalar inspector is unavailable.
- Preserve protected values before any Chatify string processing.
- Store and validate the numeric Blizzard Settings category ID returned by AceConfigDialog before calling modern Settings APIs.
- Keep legacy settings opening isolated to `InterfaceOptionsFrame_OpenToCategory`.
- Remove a duplicate chat-edit capability declaration found during the compatibility audit.

## [2.12.0] - 2026-09-20

### Compatibility
- Review current chat-handling patterns and adopt safer modern API routes where they improve reliability.
- Rebuild joined-channel caches when Communities channels are added/removed and when numbered channels are swapped.
- Prefer `ChatFrameUtil.GetOutMessageFormatKey()` for built-in chat formatting, with `CHAT_*_GET` fallback for older clients.
- Keep Forever isolated through the Camelot TOC while adding explicit modern-chat capability hints for diagnostics and beta regressions.
- Keep secret-value checks before string operations and retain per-feature runtime guards.

### Text and UI
- Remove emoji from Chatify UI text and changelog headings.
- Replace symbol separators with plain text separators that render reliably in WoW fonts.
- Shorten protected-chat and compatibility warnings so the settings panel explains the result instead of internal implementation details.

## [2.11.1] - 2026-09-20

### Bug Fixes

- Fix Raid Warning short/custom/hidden channel labels on Retail/Midnight when Blizzard renders `CHAT_RAID_WARNING_GET` without a `|Hchannel:...|h` hyperlink.
- Keep the existing hyperlink rewrite for clients that expose Raid Warning as a channel link and add a locale-safe GlobalString template fallback only for the Raid Warning path.
- Preserve per-client behavior without writing to Blizzard `CHAT_*_GET` globals or bypassing protected-chat guards.

## [2.11] - 2026-09-18

### Per-client capability model

- Replace the old Retail-vs-Classic assumption with runtime capability states: `supported`, `warning`, and `unavailable`.
- Hide unsupported settings, groups, and tabs completely instead of leaving controls that can call missing APIs.
- Re-check capability again when the module/action executes so stale SavedVariables cannot force an unsupported path.
- Add muted orange (`#D69A5B`) compatibility warnings for features that remain usable but can be limited by protected chat or legacy APIs.
- Add client identity, Interface number, support tier, and per-feature capability states to diagnostics.

### WoW API modernization

- Prefer `C_ChatInfo.SendChatMessage` and `C_BattleNet.SendWhisper`, retaining guarded legacy fallbacks for old clients.
- Route name-based friend checks through `C_FriendList.GetFriendInfo(name)` with a safe indexed legacy fallback; do not misuse GUID-only `C_FriendList.IsFriend()` with chat sender names.
- Route moved chat helpers through `ChatFrameUtil` / modern chat edit-box mixins with legacy fallback names where required.
- Use `C_Secrets.HasSecretRestrictions()` and `C_ChatInfo.InChatMessagingLockdown()` as capability signals instead of assuming restrictions from expansion names.
- Guard LFG/battleground activity reads and outgoing auto-reply paths with API presence checks and `pcall`.

### Feature isolation

- Hide Quick Buttons, Channels, Sounds, native text selection, chat-tab setup, auto-reply paths, and other controls when their required API is unavailable.
- Split Auto Reply capability into normal whisper, Battle.net whisper, and guild reply so one unsupported channel no longer disables or risks the others.
- Disable Communities integration when `C_Club` is unavailable.
- Keep History and Copy readable-line-only on protected clients and clearly warn that secret payloads are skipped.
- Prevent spam/mention filters from attaching when the current client cannot provide a safe filter/render path.

### Client targets

- Update Classic Era to Interface `11509`.
- Update Burning Crusade Classic Anniversary to Interface `20506`.
- Update Mists of Pandaria Classic to Interface `50504`.
- Move the current Wrath-progression package to Titan Reforged Interface `38002`.
- Preserve Wrath Classic `30405` as a separate `Chatify_WrathLegacy.toc` compatibility target.
- Preserve Cataclysm Classic `40402` as an explicitly marked legacy target.
- Keep WoW: Forever / Camelot `16001` isolated through its dedicated TOC marker.
- Ensure every TOC starts with `## Interface` before any single-`#` comment.
- Add `COMPATIBILITY.md` with the supported-client matrix, capability rules, and validation limits.

## [2.10] - 2026-09-18

### New Features

- Add dedicated World of Warcraft: Forever / Camelot target (`Chatify_Camelot.toc`, Interface 16001)
- Detect Forever at load time instead of collapsing it into Retail or Classic
- Add separate `forever` client flavor plus `UsesMainlineUI()` capability helper

### Compatibility & Safety

- Treat Forever as a modern Mainline-UI client with Midnight-style secret-value chat restrictions
- Prefer `C_Secrets.HasSecretRestrictions()` over numeric TOC guesses when available
- Keep Forever out of Classic-only chat/sidebar layout paths
- Extend chat taint diagnostics with flavor, interface, Forever marker, and `C_Secrets` state
- Prefer modern `C_ChatInfo.SendChatMessage` and `C_BattleNet.SendWhisper` on Retail/Forever, with legacy fallbacks for older Classic clients
- Update protected-chat settings text for both Retail and Forever

## [2.9] - 2026-09-07

### Bug Fixes

- Add taint-safe visual mention notification route

- Preserve unreadable messages in chat history

- Make filter isolation diagnostics reproducible

- Skip AddMessage wrapping for combat log frames

- Decouple AddMessage taint protection from chat filters


### New Features

- Add isolated ChatProxy foundation for taint-safe rendering

