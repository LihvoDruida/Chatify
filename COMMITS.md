# Commit plan (0.11.21 → 0.11.26)

I have no access to your repository, so nothing has been committed. Copy the
changed files over your working tree, then use the commits below. They are split
so each one is revertable on its own — if the channel-label rewrite turns out to
be wrong, you can drop it without losing the Mythic+ fix.

If you would rather ship it all at once, skip to "Single commit" at the bottom.

## 0. Before you start

    git checkout -b fix/chat-in-instances

Delete the dash-named flavour files, which the client never loaded:

    git rm Chatify-BCC.toc Chatify-Mists.toc Chatify-TBC.toc \
           Chatify-Titan.toc Chatify-Vanilla.toc Chatify-Wrath.toc

## 1. Chat dying inside Mythic+ and raids (0.11.22)

Files: Config.lua, ChatRouter.lua, ChatAutoReply.lua, ChatVisuals.lua, Settings.lua

    git add Config.lua ChatRouter.lua ChatAutoReply.lua ChatVisuals.lua Settings.lua
    git commit -F- <<'EOF'
fix: chat going silent and unscrollable in M+ and raid encounters

The "Balanced" filter mode withdrew our message-event filters at
ENCOUNTER_START, which is too late to help. Taint is not symmetrical
with chat messaging lockdown: a filter closure that already ran in the
open world has marked Blizzard's chat dispatch and the shared state
ChatHistory_GetAccessID/GetToken write into, and that mark survives
until /reload. Once the encounter starts and payloads become secret,
Blizzard's handler errors on every line and no player message renders
at all.

Safest is now the effective default on secret-value builds, resolved at
read time rather than written back, so the same SavedVariables still
behave normally on Classic and pre-12 Retail. An explicit choice in the
options sets retailChatFilterModeUserSet and is always honoured.

Also in this change:

- Balanced now withdraws filters for the whole taint risk window (any
  time inside instanced content) rather than only during the encounter,
  and tracks instance transitions via ZONE_CHANGED_NEW_AREA.
- Virtual chat forced the view back to the bottom on every incoming
  line whenever ChatFrame:AtBottom was missing or errored, because the
  stick-to-bottom flag defaulted to true. Scrollback was unusable
  exactly when chat is busiest.
- The router applied the spam keyword filter and duplicate throttle to
  every line regardless of channel, so short repeated group calls
  ("go", "kick", "pull") were dropped for up to throttleTime seconds.
  Guild, officer, party, raid, instance, raid warning and whispers are
  now exempt, matching ns.ProcessSpamMessage.
- ChatAutoReply's CHAT_MSG_GUILD handler ran IsPlayerMentioned on the
  raw message with no guard, throwing "string conversion on a secret
  string value" on every guild line during lockdown.
- ns.ApplyNativeTimestamps wrote the showTimestamps CVar from a
  lockdown flip that fires mid-combat, which is refused and produces an
  ADDON_ACTION_BLOCKED popup. Deferred to PLAYER_REGEN_ENABLED.

Reported-by: user
EOF

## 2. Cross-version API audit (0.11.23)

Files: Config.lua, ChatVisuals.lua, ChatQuickButtons.lua, ChatRouter.lua,
ChatFilters.lua, ChatSounds.lua

    git commit -F- <<'EOF'
refactor: cross-version API compatibility layer and hot-path cleanup

Added ns.GetCVarCompat / ns.SetCVarCompat. The native-timestamp path
called the flat GetCVar/SetCVar globals directly; those are deprecation
shims on modern Retail and the only spelling that exists on Classic.

Added ns.GetChatAPI / ns.CallChatAPI, a resolver for the ChatFrame_* /
FCF_* / ChatEdit_* helpers that 12.0 is moving into ChatFrameUtil. The
flat global is still preferred where it exists, because that is what
ElvUI, GW2_UI and Prat hook and resolving straight to the namespace
would bypass them. Only the routing decision is memoised, never the
function object, so a hook installed later is still picked up.

Fixed four ChatFrameUtil fallbacks that passed the namespace table as
an implicit self, e.g. ChatFrameUtil.OpenChat(ChatFrameUtil, text,
frame). Blizzard's util namespaces are plain function tables, so the
message text became the table. Dormant only because the flat globals
still exist; they would have broken the day they are removed.

ns.GetProjectKey treated anything below interface 120000 without
WOW_PROJECT_ID as unknown, making IsMainlineClient false on every
pre-Midnight Retail client. Mainline floor lowered to 100000.

Performance:

- ns.HasSecretChatValue and ns.CanAccessChatValue bail immediately
  where the secret-value API is absent. These run once per message per
  registered chat frame, and every Classic client was walking the full
  vararg to prove nothing could be secret.
- The spam normalizer's LRU used table.remove(order, 1), shifting all
  256 entries per message once warm. Replaced with a ring buffer.
- Visual style cache and router frame tables are weak-keyed; temporary
  chat windows were pinned along with their original AddMessage until
  reload.

Restored on Retail: mention sounds, which were queued from inside
ns.ApplyMentionRules and so went silent with the filters. The fallback
listens on Chatify's own event frame and runs only while the filter
path is not in force, so a mention is never announced twice.
EOF

## 3. Per-version TOC files (0.11.24a)

Files: Chatify.toc, Chatify_*.toc, tools/generate_tocs.py, .gitignore

    git add Chatify.toc Chatify_*.toc tools/generate_tocs.py .gitignore
    git commit -F- <<'EOF'
build: separate .toc per game version, generated from a single source

Chatify.toc is now Mainline only (Interface 120007) and is the source
of truth for version, metadata and file list. Chatify_Vanilla,
Chatify_TBC, Chatify_Wrath, Chatify_Cata and Chatify_Mists are
generated from it by tools/generate_tocs.py, which swaps only
Interface, X-Flavor and X-Expansion.

Note the underscore. The client looks for AddonName_<Flavour>.toc and
only recognises the dash form for a couple of legacy names, so the old
Chatify-Wrath.toc never loaded on any client — which is how those files
drifted to 0.11.15 while Chatify.toc was on 0.11.21. Run the script
after every version bump; --check fails on stale files and can be wired
into CI.

Interface 38001 has no flavour file: there is no verified TOC suffix
for that client, and it falls back to Chatify.toc.
EOF

## 4. Prat feature parity, taint-free subset (0.11.24)

Files: Config.lua, ChatVisuals.lua, Settings.lua, locale/*.lua

    git commit -F- <<'EOF'
feat: window behaviour options (scrollback, fade, scroll speed, spacing)

Compared against Prat-3.0. Its most valuable modules do not need a chat
filter at all — they configure the chat window itself, which is
taint-free and works identically on every flavour. That is the class of
feature added here, and it is what remains available on 12.0+ now that
message filtering is off by default.

- Scrollback depth (SetMaxLines). The game keeps 128 lines per window,
  which is the real reason scrollback runs out during a busy fight.
  Default 500, up to 5000. SetMaxLines reallocates the buffer and so
  clears the window, hence it is only called when the value differs.
- Fade control (SetFading / SetTimeVisible). Combat log left alone.
- Scroll speed, lines per wheel notch. Prat replaces the frame's
  OnMouseWheel script; this hooks it and only adds the extra notches, so
  Blizzard's handler keeps running and ElvUI's replacement is not
  clobbered. Shift is left to Blizzard; Ctrl adds page scrolling.
  Inert while a chat replacement addon is loaded.
- Line spacing (SetSpacing) and hanging indent (SetIndentedWordWrap),
  the latter probed rather than flavour-gated.
- Hide the game's chat menu and Quick Join buttons, with the OnShow
  guard Blizzard's re-show behaviour requires.

Not ported: PlayerNames, ServerNames, Substitutions, AltNames. All
require rewriting message text, i.e. a message-event filter, which on
12.0+ is the exact mechanism that breaks chat inside instanced content.
EOF

## 5. Settings restructure and localisation (0.11.25)

Files: Settings.lua, locale/enUS.lua, locale/ukUA.lua

    git add Settings.lua locale/
    git commit -F- <<'EOF'
fix(i18n): route every options string through T(), and regroup the panel

137 option names and descriptions were plain string literals rather
than T(...) calls, so they could never be translated no matter what the
locale files contained — the panel was effectively English-only. All of
them now go through T(), including single-line header entries and one
description split across a concatenation. 41 new keys added to ukUA;
enUS filled out to the complete key set so the locale files can be
diffed against the panel.

Missing options, now exposed:

- enableTimestamps had no control at all, so timestamps could only be
  switched off by editing SavedVariables.
- timestampColor and urlColor were likewise unreachable. Both validate
  their input as six hex digits.

Structure: General & Visual was a flat list of 32 controls; split into
Language, Compatibility & Safety, Text & Appearance, Timestamps, Chat
Window and Quick Chat Buttons. Filters & History uses child tabs, and
its spam section — 25 controls with fractional ordering and a genuine
order collision between headerKeywords and addKeyword — is now six
named groups. Sounds, Mention Manager, Auto Reply and Setup & Reset got
the same treatment. Loose header and spacer pseudo-entries are gone and
ordering within every group is sequential from 1.
EOF

## 6. Channel labels and copy-window timestamps (0.11.26)

Files: Config.lua, ChatVisuals.lua, ChatRouter.lua, ChatCopy.lua,
Settings.lua, locale/*.lua

    git commit -F- <<'EOF'
fix: channel shortening on Retail, duplicated timestamps in copy window

"Shorten Channel Names" worked by overwriting Blizzard's CHAT_*_GET
GlobalStrings, and that path was disabled on 12.0+ because those
globals feed the secure chat handler. The toggle was live in the
options panel and did nothing, without saying so.

Reimplemented as a rewrite of the rendered line inside our own
AddMessage hook, matching on the channel token inside the hyperlink
(|Hchannel:PARTY|h[Party]|h). That token is locale-independent and
identical on every flavour, so there is now one implementation instead
of a Classic-only one, and numbered channels are covered for the first
time. Secret values pass through untouched and nothing is registered on
Blizzard's chat dispatch. Nothing writes to the global environment any
more, which also ends the collision with Prat and ElvUI.

The copy window reads rendered lines via GetMessageInfo, so the visible
timestamp was already in the text and BuildEntry prefixed its own. It
became obvious on 12.0+ because we now drive Blizzard's showTimestamps
CVar there. The leading stamp is parsed off and reused as the entry
time; patterns are anchored and narrow, so "Player: meet at 12:30" is
left alone. This also fixes every copied line falling back to time(),
stamping the whole window with the moment it was opened.

Adds custom channel labels: free text for the nine named channels and
the first ten numbered ones, layered over Shorten Channel Names rather
than conflicting with it. The option list is generated from
ns.Lists.ChannelLabels.

Reported-by: user
EOF

## Single commit

If you would rather not split it:

    git add -A
    git commit -F- <<'EOF'
fix: chat breaking inside Mythic+ and raids, plus cross-version audit

Headline fix: on 12.0+ the default filter mode withdrew our
message-event filters at ENCOUNTER_START, which is too late — a filter
closure that already ran in the open world has tainted Blizzard's chat
dispatch for the rest of the session, and once payloads become secret
no player message renders at all. Safest is now the effective default
on secret-value builds, without overwriting saved profiles.

Also: scroll-to-bottom no longer fights the user, group channels are
exempt from the router's spam throttle, guild auto-reply is guarded
against secret values, and CVar writes are deferred out of combat.

Cross-version audit: CVar and ChatFrameUtil compatibility layers, four
fixed call sites that passed the namespace table as implicit self, a
corrected mainline detection floor, and hot-path work (short-circuits
in the per-message guards, ring buffer instead of an O(n) LRU,
weak-keyed frame tables).

Separate per-version .toc files, generated from Chatify.toc by
tools/generate_tocs.py — the old dash-named ones never loaded.

New taint-free window options from a Prat-3.0 comparison: scrollback
depth, fade control, scroll speed, line spacing, indent, button hiding.

Settings panel regrouped, and 137 strings that were never translatable
now go through T().

Channel shortening reimplemented so it works on Retail, custom channel
labels added, and duplicated timestamps in the copy window fixed.
EOF

## After committing

    python3 tools/generate_tocs.py --check   # should pass
    git push -u origin fix/chat-in-instances
