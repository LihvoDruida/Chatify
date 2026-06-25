# Chatify (World of Warcraft Addon)
[![WoW Version](https://img.shields.io/badge/WoW-retail-%231488DB?style=for-the-badge&logo=worldofwarcraft&logoColor=white)](https://worldofwarcraft.blizzard.com/)
[![CurseForge](https://img.shields.io/badge/CurseForge-Download-%23F16436?style=for-the-badge&logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/chatify-chat-enhancer)
[![GitHub Release](https://img.shields.io/github/v/release/LihvoDruida/Chatify?include_prereleases&style=for-the-badge&label=Release&logo=github&logoColor=white)](https://github.com/LihvoDruida/Chatify/releases)
![Language](https://img.shields.io/badge/Language-Lua-%232C2D72?style=for-the-badge&logo=lua&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-%23A6E22E?style=for-the-badge)

**Chatify** is a lightweight, modular addon for World of Warcraft written in Lua. It cleans up the standard chat interface, adds message history, safer chat copying, spam filtering, mention controls, sound alerts, and quick channel buttons.

## ✨ Features

* **🎨 Visual Customization:** Configurable fonts and shadows.
* **📜 Chat History:** Saves chat messages between sessions for a dedicated selectable History window. It never replays old lines into the live chat frame.
* **🔗 Utilities:** Clickable URLs (`discord.gg`, `youtube.com`) and ChatCopy 2.0 with selectable chat-window tabs.
* **🛡 Spam Filter 2.0:** Blocks spam keywords and repeated messages with channel rules, whitelists, counters, and a log-only tuning mode.
* **🔔 Mention Manager:** The single place for name/text highlights and mention sounds, with custom color, sound, channel scope, case sensitivity, whole-word matching, and sound cooldown.
* **⚙️ Settings GUI:** Built-in configuration menu (no code editing required).

## 📂 Project Structure

The addon is split into logical modules for better maintainability:

* `Chatify.toc` — Addon manifest (metadata and file list).
* `Config.lua` — Default settings and variable initialization.
* `Settings.lua` — GUI code (Options panel).
* `ChatFilters.lua` — Safe text processing logic (URLs, spam rules, mention highlights).
* `ChatHistory.lua` — Per-frame history store and History window data provider.
* `ChatVisuals.lua` — Visual tweaks (fonts, hiding elements).
* `ChatCopy.lua` — ChatCopy 2.0 popup, shared tabbed copy/history window, safe copy cache, native selection guard, and configurable chat-window tabs.

## 🚀 Installation (For Developers)

1.  Navigate to your WoW AddOns folder:
    * **Windows:** `World of Warcraft\_retail_\Interface\AddOns`
2.  Clone the repository:
    ```bash
    git clone https://github.com/LihvoDruida/Chatify.git
    ```
3.  Ensure the folder is named `Chatify`.
4.  Launch the game or type `/reload` if already running.

## 🎮 Usage

You can access the configuration menu via:
* **Game Menu:** `Esc` -> `Options` -> `AddOns` -> `Chatify`
* **Slash Commands:**
    * `/chatify`
    * `/mcm`

## 🤝 Contributing

Contributions are welcome!
1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/NewFeature`).
3.  Commit your changes (`git commit -m 'Add some NewFeature'`).
4.  Push to the branch (`git push origin feature/NewFeature`).
5.  Open a Pull Request.

## Quality & Testing

Chatify is checked as a release product, not only as separate Lua files. The release checklist covers TOC metadata, required files, settings loading, copy window behavior, spam filters, mention alerts, saved variables, and Retail-safe chat handling.

The Ukrainian QA notes and terminology are kept in [`docs/QUALITY_AND_TESTING.md`](docs/QUALITY_AND_TESTING.md).

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.


## Retail Safe Mode

On modern Retail builds, Chatify avoids unsafe whisper / BNet whisper processing. Settings show the active safe-mode status so users can clearly see why these paths are limited:

- History is limited to safely captured events.
- Virtual Chat remains disabled on protected Retail builds.
- Whisper / BN whisper auto-replies are disabled on modern Retail when Blizzard restricts those events.
- Native direct chat selection is the recommended copy path.

## Spam Filter 2.0

Spam filtering remains compact but now supports channel rules, guild/friend/party/raid whitelist, repeated-message cooldown, runtime counters, and a last-20 debug log. Use **Log Only** mode to tune rules without hiding messages.

## Mention Manager

Mention rules can target words or phrases such as `Sebas`, `RL`, or `Ключ`. Each rule can define highlight color, sound, channels, case sensitivity, whole-word matching, and sound cooldown. Name/text mention sounds are no longer configured in the generic Sounds tab; that tab only controls generic channel notifications.

## ChatCopy 2.0

ChatCopy opens a styled copy popup for the selected Blizzard chat frame and keeps the global safe event cache only as a fallback. The popup now has its own tab strip, so users can switch between General, Party, Guild, Whisper, custom renamed windows, and duplicate window names without closing the copy panel.

Configuration options are available in **Chatify → General & Visual → Copy Chat**:

- **All usable chat tabs** — show all normal chat windows that are not hidden by default.
- **Visible or docked tabs only** — keep the copy popup focused on currently visible/docked chat windows.
- **Manual selection only** — show only windows enabled in the per-tab checklist.
- **Selected chat only** — keep the copy popup limited to the currently selected chat frame.

Combat Log and Voice are hard-blocked from ChatCopy: they are not shown in the tab strip, cannot be enabled in the checklist, and are skipped by direct selection compatibility mode. Hidden chat windows are unchecked by default; a normal hidden custom tab can still be enabled manually if needed.

The per-tab checklist is keyed by Blizzard chat frame ID, not by display text. This means renamed tabs and duplicate names remain stable; duplicates get numbered labels in the popup.


## Chat History Window

The History button is placed next to the Settings and Copy Chat buttons. On Retail, Chatify can share the main chat sidebar stack. On Classic-era clients (Vanilla, Burning Crusade Classic, Wrath/Titan and Mists Classic), Chatify uses a detached mini stack and leaves Blizzard's native scroll/menu buttons untouched so the client-specific chat buttons do not clip, overlap, or get reparented incorrectly. The window uses the same selectable popup foundation as ChatCopy, but is styled and labeled as a History viewer and reads from Chatify's saved per-frame history store only.

History tabs follow the same rules as ChatCopy tabs: Combat Log and Voice are excluded, hidden windows stay disabled by default, renamed tabs are supported, and empty secondary tabs do not borrow messages from General. On modern Retail clients, history capture follows the same protected-payload policy as ChatCopy and avoids whisper/BN/protected event payloads. Saved history is never injected back into visible chat frames after login or `/reload`.

## Safe Chat Tabs

The setup panel can create or update PM, Guild, and Raid/Guild/PM tab templates. Existing tabs are reused instead of duplicated, and the restore action only repairs the main chat groups without deleting custom windows.

## Compatibility Notes

- Retail 12.x uses a restricted safe path inspired by modern Prat patterns: filters stay on Blizzard's secure message pipeline, while risky direct chat-frame rewrites stay disabled.
- ElvUI chat panels are now detected automatically. Quick channel buttons refresh after ElvUI chat layout updates and can use Auto, Standard, ElvUI, or GW2 UI skin modes without losing the default Blizzard-compatible fallback.
- GW2 UI chat is now detected through its custom chat container flow. Quick channel buttons anchor to the rebuilt GW2 chat frame, use GW2-style textures and font, and refresh after GW2 chat settings updates without needing `/reload`.
- Auto Reply is now actually loaded from the TOC, so its settings are no longer dead UI.
- Extra TOC variants were added for TBC/Wrath/Vanilla packaging.


## Compatibility
- Includes `LibChatAnims` for Floating Chat Frame alert flash functions, following the Prat 3.0 approach to use animation groups instead of legacy `UIFrameFlash`.


## Quick Button Skin Behavior

Quick chat button skins can be forced to Standard, ElvUI, or GW2 UI even if those addons are not installed. In that case Chatify applies only the visual style and keeps its normal behavior, anchors, and chat logic. Auto mode still follows detected chat UI addons when they are active.

## PTR 12.1 note

This build includes a small compatibility layer for PTR clients where older embedded AceGUI checkbox code can fail on missing UI helpers. For PTR testing, delete the old `Interface/AddOns/Chatify` folder before installing this archive so stale bundled libraries do not remain from an older build.


- Classic-era chat button compatibility keeps Blizzard chat controls untouched; Chatify Settings, Copy and History use a detached toolbar on BCC, Vanilla, Wrath/Titan and MoP Classic.


### Internal fonts

Chatify resolves internal fonts through addon-rooted paths so the same font choice works on Retail, MoP Classic, Wrath/Titan, Vanilla and Burning Crusade Classic. The resolver checks both supported internal locations:

- `Interface\\AddOns\\Chatify\\assets\\Fonts\\Exo2.ttf`
- `Interface\\AddOns\\Chatify\\fonts\\Exo2.ttf`

If a selected internal font is unavailable in a local build, Chatify safely falls back to the active Blizzard chat font and then the default WoW font instead of breaking chat rendering.

