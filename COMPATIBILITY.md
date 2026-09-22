# Chatify client/API compatibility

Audit date: **2026-09-22**

Chatify 2.16.3 does not treat WoW as a simple Retail-vs-Classic split. Client identity and feature capability are evaluated separately. This matters because current Classic-family clients increasingly share modern chat APIs and protected/secret-value behavior, while WoW: Forever can identify as Mainline at runtime despite requiring its own addon flavor.

## Packaging targets

| Target | TOC | Interface | Support tier |
| --- | --- | ---: | --- |
| Retail / Midnight | `Chatify.toc` | 120100 (plus 120105 test compatibility) | current |
| WoW: Forever / Camelot | `Chatify_Camelot.toc` | 16001 | beta |
| Mists of Pandaria Classic | `Chatify_Mists.toc` | 50504 | current |
| Titan Reforged / Wrath progression | `Chatify_Wrath.toc` | 38002 | current |
| Burning Crusade Classic Anniversary | `Chatify_TBC.toc` | 20506 | current |
| Classic Era | `Chatify_Vanilla.toc` | 11509 | current |
| Cataclysm Classic 4.4.2 | `Chatify_Cata.toc` | 40402 | legacy compatibility |
| Wrath Classic 3.4.5 | `Chatify_WrathLegacy.toc` | 30405 | legacy compatibility |

The legacy targets are retained for users who still run those client builds, but they are not treated as current Blizzard live branches.

## Runtime feature states

Every version-sensitive feature resolves to one of three states before Settings is built and again before the feature executes:

- **supported** — normal UI and runtime path.
- **warning** — feature remains visible, with a muted orange warning (`#D69A5B`) explaining the risk/limitation. Runtime guards remain active.
- **unavailable** — the setting/group/tab is hidden and the module/action exits without invoking the unsupported API.

This double check is intentional: old SavedVariables can still contain `enabled = true` after a user changes WoW versions. Hiding a control alone is not sufficient protection.

## Feature capability matrix

| Chatify area | Capability/runtime rule | UI behavior when missing/risky |
| --- | --- | --- |
| Channels / channel labels | `GetChannelList` plus safe render-hook path for custom labels | hide if unavailable; orange warning on protected clients |
| Chat sounds | `PlaySoundFile` | hide Sounds settings and do not enable module |
| Quick chat buttons | modern/legacy OpenChat resolver plus a valid chat-edit ParseText path | hide entire Quick Buttons group |
| Long Message Composer | outgoing chat API plus runtime channel/lockdown checks | hide if no send API; orange warning on protected clients |
| Composer queue automation | outgoing chat API plus timer scheduler and per-channel hardware-event gate | pause on restricted channels or chat lockdown; manual send remains available |
| Spam filters | message-event filter API | hide if absent; orange warning when protected chat restrictions are active |
| Mentions | safe render path or message-event filters | hide if no viable path; orange warning on protected clients |
| History | readable chat payloads only | orange warning on protected clients; protected/secret lines are skipped |
| Copy | readable chat payloads only | orange warning on protected clients |
| Native chat selection | chat frame `SetTextCopyable` | hide native-selection controls if unsupported |
| Whisper auto reply | outgoing chat API and no secret-value whisper restriction | hide whisper controls when unavailable/protected |
| Battle.net auto reply | Battle.net whisper API and no secret-value whisper restriction | hide Battle.net path when unavailable/protected |
| Guild auto reply | outgoing chat API | orange warning on protected clients; sending pauses during chat messaging lockdown |
| Chat tab setup | chat-window query + safe new-window API | hide if absent; orange warning on legacy targets |
| Communities integration | `C_Club` | internal hook disabled when unavailable |
| Protected-chat safety controls | actual secret restriction state | shown only on clients where restrictions are active |

## Modern API routing

Chatify prefers current namespace APIs and keeps guarded compatibility fallbacks only where older branches need them:

- outgoing chat: shared guarded wrapper using `C_ChatInfo.SendChatMessage` -> legacy `SendChatMessage` fallback;
- Battle.net whisper: `C_BattleNet.SendWhisper` -> legacy `BNSendWhisper` fallback;
- addon metadata/loading: `C_AddOns` first, legacy addon globals only as fallback;
- friends: `C_FriendList` first, with indexed legacy friend lookup fallback;
- chat frame/edit helpers: frame-owned operations use `ChatFrameMixin` methods first; `ChatFrameUtil` is used only for helpers it actually owns, with guarded legacy globals where required;
- mouse focus: modern `GetMouseFoci` compatibility path instead of assuming old `GetMouseFocus`;
- protected chat: `C_Secrets.HasSecretRestrictions()` is the primary capability signal;
- chat messaging lockdown: `C_ChatInfo.InChatMessagingLockdown()` is checked before protected outgoing player-chat actions.

## Forever isolation

`Forever.lua` is loaded only by `Chatify_Camelot.toc`. The load-time marker is evaluated before runtime project identity, so Forever remains a separate client flavor. Exact executable build numbers are never used for routing.

Forever is treated as a hybrid UI client. Runtime logs show Camelot, Mainline, Shared, and VanillaStyle Blizzard components coexisting in one session, so Chatify probes the API required by each feature instead of assuming that every subsystem follows one family.

For live chat-tab routing, modern/Forever clients use Blizzard's complete tab-selection path (`FCF_Tab_OnClick`) when it is available instead of changing only the dock selection. Chatify also consumes `ChatFrame.OnEditBoxPreSendText`, which fires after Blizzard resolves slash-command chat types and before the outgoing send call. `ChatFrameUtil.SetLastActiveWindow` is always given the frame's edit box, matching Blizzard's current contract. Guarded dock/global fallbacks remain for older clients.

Secret-value restrictions are treated as active when the runtime reports them. Chatify checks secret/accessibility inspectors before converting, comparing, matching, storing, copying, or highlighting chat payloads.

Modern Blizzard Settings calls use only the numeric category ID returned by AceConfigDialog. Category names and frame objects are never passed to `Settings.OpenToCategory` or `C_SettingsUtil.OpenSettingsPanel`; legacy frame-based opening is kept as a separate fallback.


## Secure post-render formatting

On clients that expose `ScrollingMessageFrame:TransformMessages`, Chatify observes Blizzard `AddMessage` with `hooksecurefunc` and transforms only the exact readable entry after Blizzard has rendered it. The match includes the rendered message, event name, and event-argument table identity. Chatify returns Blizzard color and metadata fields unchanged.

This path is preferred over replacing `frame.AddMessage`. The legacy wrapper remains only for older clients without the post-render API. Channel labels, mention highlighting, URL decoration, short visible player names, and optional race/class sender icons all use the same formatter so modern and legacy clients do not maintain separate feature logic. Blizzard currently uses `TransformMessages` in its own chat-frame utilities, making it the preferred low-interference path where available.

Sender shortening changes only the visible label inside a player hyperlink. The `|Hplayer:Name-Realm:...|h` routing payload remains untouched. Race/class decoration requires readable event metadata and `GetPlayerInfoByGUID`; inaccessible or protected values are skipped rather than guessed.

## History storage budget and search

Persistent history is captured from the Blizzard chat frame that actually receives each `AddMessage` call. This is the primary routing source on clients with `hooksecurefunc`, so Chatify does not infer History destinations from shared `CHAT_MSG_*` registrations. General, Guild, Raid, Whisper, and custom chat tabs therefore keep independent frame buckets. The older event-routing path is retained only as a compatibility fallback when secure post-hooks are unavailable. Chatify also detects when another addon replaces a frame's `AddMessage` method after initialization and reattaches the observer on the next chat-window refresh.

History schema version 3 records `captureMode = frame-addmessage`. Older frame buckets created by event-routing heuristics are discarded once during migration because a bucket that was already merged cannot be separated reliably after storage. `Virtual` history remains preserved.

Persistent history is bounded twice: per-tab line limits and a global approximate byte budget. The default byte budget is 128 KiB, the settings UI exposes 32-512 KiB, and the internal clamp is 32-1024 KiB. Individual stored lines over 4096 bytes are rejected. When the budget is exceeded, Chatify removes oldest entries fairly across stored buckets instead of allowing one busy tab to evict every other tab. Virtual-chat history participates in the same estimate and pruning path.

The Chatify History window includes a literal, case-insensitive search field. The search source is bound to the exact selected chat-frame key; switching History tabs replaces the source before the query is evaluated. A stale entry list from another tab is never searched. Before filtering, Chatify refreshes entries from that same frame only, so newly captured lines can appear while the History window remains open. The UI shows the current scope (`Search in <tab>`). ASCII case folding is supplemented with explicit Ukrainian/Cyrillic uppercase-to-lowercase pairs because stock Lua byte-based `string.lower` does not case-fold those UTF-8 characters. Copy mode remains unchanged.

## Profile backup format

Chatify can export and import its profile through `/chatifyexport`, `/chatifyimport`, or Settings. The backup contains profile settings only; `ChatifyHistoryDB` is never included. The import format is parsed as typed data without `load`, `loadstring`, or execution of pasted text. Parsing is bounded by total bytes, entry count, nesting depth, key size, and string size, and unknown top-level profile keys are discarded.

## TOC safety

Every generated TOC now begins directly with `## Interface`. A plain single-`#` comment is never placed before the first directive. This avoids the modern-client TOC parsing regression where directives after an initial single-`#` line can be skipped.

## Validation limits

The package is statically validated for Lua syntax, TOC dependencies, version metadata, flavor isolation, feature gates and modern/legacy fallback ordering. Runtime guards are designed to fail closed.

Static validation is not a substitute for launching every Blizzard client. Forever is beta, while Cataclysm 4.4.2 and Wrath 3.4.5 are legacy compatibility targets, so those paths should be considered runtime-probed rather than claimed as live-tested.

## Compatibility hardening

Chatify keeps its own capability model and uses modern API patterns where they are safer than expansion-specific assumptions:

- `ChatFrameUtil.GetOutMessageFormatKey()` is preferred for current Blizzard chat formatting, with legacy GlobalString fallback.
- Joined-channel caches are invalidated after Communities add/remove operations and numbered-channel swaps, not only after channel events.
- Secret values are rejected before string operations.
- Modern `ChatFrameUtil` helpers are preferred when Blizzard moved old `ChatFrame_*` globals.

Chatify does not use `WOW_PROJECT_MAINLINE` as the identity check for Forever. Forever remains a dedicated `Chatify_Camelot.toc` target because game identity and UI/API capability are separate concerns.

## Long Message Composer

The composer operates on text entered by the player, not incoming protected chat payloads. It remains capability-gated because modern clients can temporarily block addon-initiated sends. Every send re-checks the messaging-lockdown state before calling Blizzard.

Splitting is byte-aware because WoW chat limits are byte-based, but cuts are moved to valid UTF-8 boundaries so Ukrainian and other multibyte text is not corrupted. Chunk counters and continuation markers are included in the size calculation before a cut is chosen.

Per-line routing is parsed before splitting. Each logical line keeps its own chat type and whisper target, and channel availability is checked again when the chunk is actually sent. Manual one-chunk sending is always available; optional queue automation can advance through supported chunks with a configured delay and pauses on hardware-restricted routes.

## Long Message quick access

Long Message Mode is opt-in. When enabled and Quick Chat Buttons are available, Chatify adds an `LM` button below the channel button stack. The button only opens the existing composer; outgoing sends still pass through the same per-client capability, protected-value, and messaging-lockdown checks as the composer itself.
## Composer integration

Long Message Composer reuses the active Blizzard chat draft context exposed by Chatify Quick Buttons. When enabled, the LM button can import a visible draft, supported active chat type, and a readable whisper target without clearing the original edit box. Protected or inaccessible values are skipped. Unsupported active chat types never override the Composer channel.
## Composer session and automation

Long Message Composer keeps its draft and preview state when its window is hidden during the current UI session. Manual one-chunk sending remains available, and optional queue automation can send supported prepared chunks in order with a configurable delay.

Automation is capability-gated rather than client-name-gated. Party, Raid, Raid Warning, Instance, Guild, Officer, Whisper, and other non-hardware routes can use timed sends when the current client allows them. Say, Yell, Channel, or another route treated as hardware-event restricted pauses the queue and waits for a player Send click. If Resume After Manual Chunk is enabled, automation continues from the next chunk after that click.

During chat messaging lockdown the queue pauses. Resume After Chat Lockdown can keep the queue waiting and retry only after the runtime guard reports that addon chat sending is available again. Closing the Composer, editing the draft, changing routing, rebuilding the preview, or disabling automation invalidates pending timer callbacks.

Splitter settings are available both in Chatify Settings and directly inside Composer. Changing byte limit, counter, or continuation-marker settings rebuilds an already-loaded preview. Optional automation can also build the preview after importing the active Blizzard chat draft or opening Composer with text from a slash command.

Normal channel selection is resolved at send time, allowing the player to switch channels between prepared chunks without rebuilding. Per Line mode is intentionally different: its channel and whisper target are bound to each logical line during splitting and remain fixed until the preview is rebuilt.

Composer remembers the selected default channel through the Chatify profile and can remember a manually entered whisper target. Closing the Composer window hides it instead of discarding the active session; Clear resets the loaded message and preview.

Successful sends can automatically advance to the next chunk. The final chunk can be locked after sending to reduce accidental duplicate posts; browsing away, rebuilding, or clearing resets that lock.

If the optional Misspelled addon is present, Composer can attach it to the editor after Chatify finishes configuring the edit box. Any visual spell-check markup is removed before splitting or sending.


## AceGUI shared-widget safety

AceGUI widget registrations are global through LibStub. When several addons embed AceGUI, the active core and individual widgets can come from different addon folders depending on their registered revisions. Chatify therefore ships the current Label widget surface plus a protected-text guard as a newer Label revision. Values that are secret, inaccessible, or not valid FontString text are dropped before `FontString:SetText` is called. Chatify also sanitizes its own dynamic option names, descriptions, and joined-channel names before they reach AceConfig.


## History hook and dock-tab routing (2.16.2)

Chatify history secure-hooks each concrete Blizzard `ChatFrame:AddMessage` exactly once per UI session. `hooksecurefunc` itself replaces the method with a secure wrapper, so method-identity comparisons must not be used as a signal to re-hook on `UPDATE_CHAT_WINDOWS`; doing so stacks callbacks and duplicates persisted rows. Schema v4 migrates 2.16.1 buckets by collapsing adjacent exact duplicates.

History Search always refreshes from the currently selected frame bucket and may fall back only to that same frame's `GetMessageInfo` buffer. Empty tabs replace the search source with an empty list rather than retaining a previous tab snapshot.

When a user changes to Guild/Party/Raid/Raid Warning/Instance/Say/Yell and the currently selected dock tab does not receive that message group, Chatify selects the first docked Blizzard chat frame whose `ContainsMessageGroup` reports that it does. This applies to both Chatify quick-channel buttons and native slash chat-type changes where `ChatEdit_UpdateHeader` is available. Older clients without `ContainsMessageGroup` use a conservative `messageTypeList` fallback; if neither is readable Chatify leaves Blizzard's selected tab unchanged.
