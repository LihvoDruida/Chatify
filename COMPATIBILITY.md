# Chatify client/API compatibility

Audit date: **2026-09-20**

Chatify 2.15.1 does not treat WoW as a simple Retail-vs-Classic split. Client identity and feature capability are evaluated separately. This matters because current Classic-family clients increasingly share modern chat APIs and protected/secret-value behavior, while WoW: Forever can identify as Mainline at runtime despite requiring its own addon flavor.

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
- chat frame/edit helpers: `ChatFrameUtil` and current edit-box mixins first where Blizzard moved the old globals;
- mouse focus: modern `GetMouseFoci` compatibility path instead of assuming old `GetMouseFocus`;
- protected chat: `C_Secrets.HasSecretRestrictions()` is the primary capability signal;
- chat messaging lockdown: `C_ChatInfo.InChatMessagingLockdown()` is checked before protected outgoing actions.

## Forever isolation

`Forever.lua` is loaded only by `Chatify_Camelot.toc`. The load-time marker is evaluated before runtime project identity, so Forever remains a separate client flavor. Exact executable build numbers are never used for routing.

Forever is treated as a hybrid UI client. Runtime logs show Camelot, Mainline, Shared, and VanillaStyle Blizzard components coexisting in one session, so Chatify probes the API required by each feature instead of assuming that every subsystem follows one family.

Secret-value restrictions are treated as active when the runtime reports them. Chatify checks secret/accessibility inspectors before converting, comparing, matching, storing, copying, or highlighting chat payloads.

Modern Blizzard Settings calls use only the numeric category ID returned by AceConfigDialog. Category names and frame objects are never passed to `Settings.OpenToCategory` or `C_SettingsUtil.OpenSettingsPanel`; legacy frame-based opening is kept as a separate fallback.

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
