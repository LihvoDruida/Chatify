# Chatify Changelog

## [2.12.0] - 2026-09-20

### Compatibility
- Compare Chatify chat handling with current Prat 3.0 patterns and adopt the safer modern API routes where they improve reliability.
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

