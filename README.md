# Chatify (World of Warcraft Addon)
[![WoW Version](https://img.shields.io/badge/WoW-retail-%231488DB?style=for-the-badge&logo=worldofwarcraft&logoColor=white)](https://worldofwarcraft.blizzard.com/)
[![CurseForge](https://img.shields.io/badge/CurseForge-Download-%23F16436?style=for-the-badge&logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/chatify-chat-enhancer)
[![GitHub Release](https://img.shields.io/github/v/release/LihvoDruida/Chatify?include_prereleases&style=for-the-badge&label=Release&logo=github&logoColor=white)](https://github.com/LihvoDruida/Chatify/releases)
![Language](https://img.shields.io/badge/Language-Lua-%232C2D72?style=for-the-badge&logo=lua&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-%23A6E22E?style=for-the-badge)

**Chatify** is a lightweight, modular addon for World of Warcraft (Retail) written in Lua. It cleans up the standard chat interface, adds message history, URL copying, spam filtering, and sound alerts.

## ✨ Features

* **🎨 Visual Customization:** Configurable fonts and shadows.
* **📜 Chat History:** Saves chat messages between sessions and reloads (Multi-frame support).
* **🔗 Utilities:** Clickable URLs (`discord.gg`, `youtube.com`) and copy-text functionality via timestamps.
* **🛡 Spam Filter:** Blocks messages containing specific user-defined keywords.
* **🔔 Alerts:** Plays a sound when you receive a Whisper or when your name is mentioned in raid/party chat.
* **⚙️ Settings GUI:** Built-in configuration menu (no code editing required).

## 📂 Project Structure

The addon is split into logical modules for better maintainability:

* `Chatify.toc` — Addon manifest (metadata and file list).
* `Config.lua` — Default settings and variable initialization.
* `Settings.lua` — GUI code (Options panel).
* `ChatFilters.lua` — Text processing logic (URLs, spam, class colors).
* `ChatHistory.lua` — System for saving and restoring chat history.
* `ChatVisuals.lua` — Visual tweaks (fonts, hiding elements).
* `ChatCopy.lua` — Logic for the copy-text window.

## 🚀 Installation (For Developers)

1.  Navigate to your WoW AddOns folder:
    * **Windows:** `World of Warcraft\_retail_\Interface\AddOns`
2.  Clone the repository:
    ```bash
    git clone [https://github.com/YOUR_USERNAME/Chatify.git](https://github.com/YOUR_USERNAME/Chatify.git)
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

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.


## Compatibility Notes

- Retail 12.x uses a restricted safe path inspired by modern Prat patterns: filters stay on Blizzard's secure message pipeline, while risky direct chat-frame rewrites stay disabled.
- Auto Reply is now actually loaded from the TOC, so its settings are no longer dead UI.
- Extra TOC variants were added for TBC/Wrath/Vanilla packaging.
