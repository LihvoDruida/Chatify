# Chatify client/API compatibility

Audit date: **2026-09-18**

Chatify 2.11 no longer treats WoW as a simple Retail-vs-Classic split. Client identity and feature capability are evaluated separately. This matters because current Classic-family clients increasingly share modern chat APIs and protected/secret-value behavior, while WoW: Forever can identify as Mainline at runtime despite requiring its own addon flavor.

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

- outgoing chat: `C_ChatInfo.SendChatMessage` -> legacy `SendChatMessage` fallback;
- Battle.net whisper: `C_BattleNet.SendWhisper` -> legacy `BNSendWhisper` fallback;
- addon metadata/loading: `C_AddOns` first, legacy addon globals only as fallback;
- friends: `C_FriendList` first, with indexed legacy friend lookup fallback;
- chat frame/edit helpers: `ChatFrameUtil` and current edit-box mixins first where Blizzard moved the old globals;
- mouse focus: modern `GetMouseFoci` compatibility path instead of assuming old `GetMouseFocus`;
- protected chat: `C_Secrets.HasSecretRestrictions()` is the primary capability signal;
- chat messaging lockdown: `C_ChatInfo.InChatMessagingLockdown()` is checked before protected outgoing actions.

## Forever isolation

`Forever.lua` is loaded only by `Chatify_Camelot.toc`. The load-time marker is evaluated before `WOW_PROJECT_MAINLINE`, so Forever does not collapse into Retail even when its runtime project ID looks Mainline. Forever remains a separate client identity while using the modern Mainline-style UI/API capability paths.

## TOC safety

Every generated TOC now begins directly with `## Interface`. A plain single-`#` comment is never placed before the first directive. This avoids the modern-client TOC parsing regression where directives after an initial single-`#` line can be skipped.

## Validation limits

The package is statically validated for Lua syntax, TOC dependencies, version metadata, flavor isolation, feature gates and modern/legacy fallback ordering. Runtime guards are designed to fail closed.

Static validation is not a substitute for launching every Blizzard client. Forever is beta, while Cataclysm 4.4.2 and Wrath 3.4.5 are legacy compatibility targets, so those paths should be considered runtime-probed rather than claimed as live-tested.
