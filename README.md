# Launcheer

[简体中文](README.zh-CN.md) | **English**

Launcheer brings the familiar Launchpad experience to your Mac: a full-screen app grid, folders, trackpad paging, and quick app search. Open apps with a mouse, keyboard, or a game controller recognized by macOS.

**Requires macOS 26.0 or later and Apple Silicon.** One installer is used across supported macOS versions; native component compatibility is checked at startup.

## Features

| Feature | What you can do |
| --- | --- |
| App launcher | Browse apps across pages and launch them with a click |
| Folders and layout | Drag to reorder apps, create folders, and move apps between them; your layout is saved locally |
| Search | Find apps in the launcher, or enable a separate global search panel with name, Pinyin, and initial matching |
| Keyboard and controller navigation | Move between apps, confirm a selection, and go back without a mouse |
| Background | Follow your desktop wallpaper or choose a custom image, with a translucent background |
| Appearance | Use fade and blur transitions, turn transitions off, or change Launcheer’s Dock icon |

## Quick start

Use the **Apple Silicon DMG**. Open it, double-click **`Install Launcheer.pkg`**, and follow the macOS Installer prompts to confirm and authorize installation.

Installer asks you to quit any running Launcheer instance and installs the app in `/Applications` on the startup disk. Your layout and preferences are kept. No Terminal commands or restart are required by the installer.

The PKG is unsigned and contains an ad-hoc signed App; it is not notarized. macOS may still require explicit approval after downloading. The installer does not bypass macOS security checks.

1. Open `Launcheer.app` from Applications.
2. Press **Option + Space** to show or hide the launcher.
3. Click an app to launch it, or type its name in the search field.
4. Enter **`/settings`** in the launcher search field to open settings. You can also use **Settings…** in Launcheer’s application or Dock menu.

The first scan shows app names and placeholder icons, then fills in icons as they become available. Clicking an empty area hides the launcher; it stays running for the next shortcut.

### Controls

| Input | Action |
| --- | --- |
| Option + Space | Show or hide the launcher |
| Horizontal trackpad swipe | Move between pages |
| Arrow keys / Return | Select / open an app or folder |
| Esc | Go back, then hide the launcher |
| Drag an icon | Reorder apps or move them into or out of a folder |
| Right-click an app | Show it in Finder |
| Controller D-pad or left stick / A / B | Select / confirm / go back |
| `/version` in launcher search | Show the running version and build |

On the main grid, moving right past the last app selects the first app on the next page. In a folder, directional navigation stays within the current grid; press **B** to leave the folder.

## Settings

- **Background:** choose an image or select **Follow Desktop**. The change applies immediately. If macOS restricts access to the wallpaper, use **Allow Reading Current Wallpaper…** in Launcheer’s application or Dock menu to select that image.
- **Transitions:** enable **Disable Transitions** for immediate showing and hiding.
- **App icon:** choose or restore Launcheer’s Dock icon. This changes the running app’s Dock appearance, not its icon in Finder.
- **Global app search:** enable it, then press **Option + Shift + Space**. Record a custom shortcut in settings; it must include Command, Option, or Control. Use ↑ / ↓ to select, Return to launch, and Esc to dismiss.

Global app search is off by default and searches applications only. To use Command + Space, first free that shortcut in macOS Spotlight settings.

## FAQ

### Does Launcheer replace the system Dock or require disabling SIP?

No. It runs as a separate app. The main grid keeps the Dock visible; opening a folder hides it temporarily, and closing the folder restores it.

### Does it support every Mac and macOS version?

Launcheer targets **macOS 26.0 or later on Apple Silicon**, using the same installer across versions. It checks and initializes the native components on your Mac rather than requiring the build machine’s Dock version. The same GitHub-built app has passed headless native-component compatibility checks on **macOS 26.2 and 26.6.2**. This does not verify every macOS version or replace interface testing. Intel is not supported. If required system components are unavailable, Launcheer reports an incompatibility.

### Why does the background differ from my desktop?

Launcheer uses a static wallpaper image with translucency and blur. Live wallpaper playback is not supported. If the image cannot be read, the launcher remains usable; select a readable image in settings.

### Where is my layout saved?

Your layout and selected images are saved locally in `~/Library/Application Support/Launcheer/`. Updates preserve the current layout. Launcheer does not import the legacy Launcheer layout format or Apple’s Launchpad layout.

## License

Launcheer’s original code is licensed under the [MIT License](LICENSE). Copyright (c) 2026 ehehrun.

Apple system components and resources retain their respective rights and are not covered by this MIT license. Launcheer is an independent project and is not affiliated with Apple.
