# Own MessageEventHandler — scope inventory

Status: **assessment only. No code written.**

Purpose: establish what a Chatify-owned `MessageEventHandler` has to cover before any
of it is written, so the decision to proceed or stop is made against measurements
rather than an estimate.

Sources measured: Blizzard's published UI source, `Gethe/wow-ui-source`, branches
`live` (Retail 12.x, `Mainline/ChatFrameOverrides.lua`), `classic_era` and
`classic_titan` (`Classic/ChatFrameOverrides.lua`). Prat was **not** consulted for any
of this and must not be: Prat is GPL, Chatify is MIT, and its
`addon/MessageEventHandler.lua` has deliberately not been opened.

---

## 1. Why this is being done

Chatify's render hook writes `frame.AddMessage`, which taints Blizzard's dispatch from
`ChatFrameOverrides.lua:667` downward. 0.11.51 contained the single victim of that
taint (`SetLastTellTarget`) with a guard.

Moving the injection point earlier — to `frame.MessageEventHandler`, read at
`ChatFrame.lua:14` — taints from above `MessageFormatter` (660) and
`ChatHistory_GetAccessID` (661). Those are the calls behind the "messages never appear
during an encounter" failure that the retail filter mode exists to avoid. So the
earlier injection point is only viable if Chatify supplies its own body for everything
between line 14 and the display call, rather than letting Blizzard's run tainted.

That body is what this document sizes.

---

## 2. Measured size

| Flavour | Handler lines | `if`/`elseif` branches |
|---|---|---|
| Retail 12.x (`live`) | 421 | 88 |
| Classic Era | 380 | 79 |
| Classic Titan (Mists-era) | 412 | 84 |

This is the handler body alone. It excludes everything it calls.

---

## 3. Event families to cover

43 distinct message types are branched on in the Retail body, plus 8 prefix matches
and 2 non-`CHAT_MSG` events.

**Prefix matches** (each covers a family, not one event):
`CHANNEL*`, `MONSTER*`, `RAID_BOSS*`, `BG_SYSTEM_*`, `ACHIEVEMENT*`,
`GUILD_ACHIEVEMENT*`, `SPELL_*`, `COMBAT_*`

**Exact types:**
`SAY`, `YELL`, `EMOTE`, `TEXT_EMOTE`, `GUILD`, `GUILD_DISCORD`, `GUILD_ITEM_LOOTED`,
`WHISPER`, `WHISPER_INFORM`, `BN_WHISPER`, `BN_WHISPER_INFORM`,
`BN_WHISPER_PLAYER_OFFLINE`, `BN_INLINE_TOAST_ALERT`, `BN_INLINE_TOAST_BROADCAST`,
`BN_INLINE_TOAST_BROADCAST_INFORM`, `CHANNEL_LIST`, `CHANNEL_NOTICE`,
`CHANNEL_NOTICE_USER`, `COMMUNITIES_CHANNEL`, `SYSTEM`, `FILTERED`, `IGNORED`,
`RESTRICTED`, `OPENING`, `LOOT`, `MONEY`, `CURRENCY`, `SKILL`, `TRADESKILLS`,
`PET_INFO`, `TARGETICONS`, `PING`, `VOICE_TEXT`

**Non-`CHAT_MSG`:** `CAUTIONARY_CHAT_MESSAGE`, `VOICE_CHAT_CHANNEL_TRANSCRIBING_CHANGED`

**Flavour delta:** only `GUILD`, `GUILD_DISCORD` and `PING` are Retail-only. Classic
Era and Classic Titan branch on an identical set otherwise. The bodies differ in
detail, not in coverage, so per-flavour handlers cannot simply be one file with three
constants — but the divergence is smaller than the line counts suggest.

---

## 4. External surface

Identical across all three flavours measured. Every one of these has to be either
called correctly or reimplemented:

| Call | Uses |
|---|---|
| `ChatHistory_GetAccessID` | 6 |
| `GetBNPlayerLink` | 5 |
| `FCFManager_GetChatTarget` / `ShouldSuppressMessage` | 2 |
| `ChatFrameUtil.ProcessMessageEventFilters` | 1 |
| `ChatFrameUtil.GetDecoratedSenderName` | 1 |
| `C_ChatInfo.ReplaceIconAndGroupExpressions` | 1 |
| `C_ChatInfo.IsChatLineCensored` | 1 |
| `C_Club.GetInfoFromLastCommunityChatLine` | 1 |
| `ChatFrameUtil.SetLastTellTarget` | 1 |

Plus dynamic global-string lookups (`_G["CHAT_"..arg1.."_NOTICE"]`,
`_G["BN_INLINE_TOAST_"..arg1]`), `C_BattleNet.GetAccountInfoByID`,
`C_Texture.GetTitleIconTexture` (asynchronous — has a callback that adds the message
later), `StaticPopup_Visible`, `FCF_GetChatWindowInfo`, timestamp formatting, and
per-type format-key resolution.

---

## 5. What makes this harder than the line count

1. **Owning the handler means owning `ProcessMessageEventFilters`.** Every other
   addon's chat filters are dispatched from inside it. Skipping it silently breaks
   them; calling it reintroduces exactly the taint position this move was meant to
   escape. This is the central design question and it is not answered yet.

2. **The censored-message path is asynchronous.** `C_Texture.GetTitleIconTexture`
   takes a callback that adds the message after the handler has returned, and
   `IsChatLineCensored` re-formats a line later via the `MessageFormatter` passed to
   `AddMessage`. Both cross the boundary of a single call.

3. **The proxy needs a field blacklist.** Copying a real chat frame's fields onto a
   stand-in frame must exclude display internals (`historyBuffer`, font-string and
   texture pools, scroll offsets, layout dirty flags), or the copy corrupts the real
   frame's rendering state. The exact list is empirical.

4. **`FCFManager_ShouldSuppressMessage` decides whether a message appears at all.**
   Getting it wrong drops messages silently, which is the worst possible failure mode
   here and the hardest to notice in testing.

5. **Blizzard changes this file every patch.** A copy is a permanent maintenance
   obligation: each patch needs a diff of the upstream handler against ours, or
   Chatify silently stops rendering whatever Blizzard added.

6. **The stub cannot validate it.** `tools/stub/wow_env.lua` models a small fraction
   of the calls above, and Lua 5.1 cannot model taint at all. Probes will cover
   routing and text assembly; they cannot tell us whether the result is taint-clean in
   game. That verification is in-client only.

---

## 6. Risk position

This code sits in the hottest path in the addon: every chat line, every flavour. The
existing failure mode (0.11.49) was a visible error in instanced content. The failure
mode of a wrong handler is messages not appearing, which users experience as the addon
silently eating their chat — the same symptom the retail filter mode was built to
prevent.

Suggested sequencing, if this proceeds:

1. Proxy frame plus field blacklist, capturing output only, with the real handler
   still in place and nothing rewritten. Verifiable in isolation.
2. Own handler for Retail only, behind an off-by-default setting.
3. Parity probes: same event, same args, compare our output text against Blizzard's
   captured through the proxy. This is the gate that makes the rest safe.
4. Classic flavours, only after Retail has shipped and held.

Steps 1 and 3 are worth building regardless of whether step 2 is ever finished: the
parity harness would also catch regressions in the current render hook.

---

## 7. Licence position

- Prat 3.0: GPL (LICENSE.txt is GPLv3; module headers say GPLv2-or-later).
- Chatify: MIT.
- GPL code cannot be taken into an MIT project without relicensing the whole addon.
  No Prat code is used here and none may be. Its architecture was described from
  `addon/addon.lua`; `addon/MessageEventHandler.lua` has not been opened.
- The handler body would be derived from Blizzard's published UI source, which is the
  standard and expected practice for chat addons. `README.md` should record that, in
  the same way the DynamicCam attribution is recorded in Max Camera Distance.
