# cmarks

A native macOS Markdown viewer. Documents render exactly the way GitHub renders them, and stay open in workspaces, tabs and split panes.

[한국어 README](README.md)

## Why

Quick Look in the Finder shows a Markdown preview only while the file is selected; click another file or folder and it disappears. cmarks keeps documents open as tabs, lets you open a project folder as a workspace, put two documents side by side, and refreshes a document in place when an editor or an AI tool changes it. It is a reader, not an editor.

## Features

- **GitHub-accurate rendering** using GitHub's own Markdown engine (cmark-gfm) and stylesheet: tables, task lists, strikethrough, footnotes, alerts (Note, Tip, Important, Warning, Caution), syntax highlighting, emoji shortcodes, math (KaTeX), Mermaid diagrams, heading anchors, front matter. Light and dark mode follow the system.
- **Workspaces, tabs and splits**: folder-based workspaces, tabs per pane, split right or down, drag to resize, pane zoom, session restore. Keyboard layout matches [cmux](https://github.com/manaflow-ai/cmux).
- **Sidebar**: file tree that tracks file system changes, document outline with the current heading highlighted, Quick Open (⌘P, fuzzy matching).
- **Live reload**: saving a file updates only the blocks that changed, keeping your scroll position. Deleted or moved files are detected and restored automatically when they reappear.
- **Document tools**: find, back/forward, zoom, print, export as PDF. ⌘-click a link to open it in a new tab, ⌥-click for a split.
- **Settings**: toggle rendering extensions, content width, Markdown extensions and ignored folders, behavior, and every keyboard shortcut.
- **Large documents**: heavy post-processing is skipped above 2 MB; above 5 MB only the beginning is shown until you choose "Show All".
- **Integration**: Finder "Open With", drag and drop, the `cmarks` command-line tool, `cmarks://open?path=` deep links. The installer can make cmarks the default app for `.md` files.

## Install

Requires macOS 15 Sequoia or later. Universal binary (Apple silicon and Intel).

**DMG**: download `cmarks-<version>.dmg` from [Releases](https://github.com/yuchanghyun/cmarks/releases) and drag cmarks to Applications. Builds are signed with a Developer ID and notarized by Apple.

**Homebrew**:

```sh
brew tap yuchanghyun/cmarks https://github.com/yuchanghyun/cmarks
brew trust yuchanghyun/cmarks
brew install --cask cmarks
```

**From source**: Xcode 26 or later and `brew install xcodegen node pnpm`, then `make assets && make run`.

## Language

The interface is available in English and Korean and follows the macOS system language. To use a different language for cmarks only, add it under System Settings ▸ General ▸ Language & Region ▸ Applications.

## Default shortcuts

| Action | Shortcut |
|---|---|
| New workspace · Workspace 1–8 · Last | ⌘N · ⌘1–8 · ⌘9 |
| Quick Open · Open · Close Tab · Reopen Closed Tab | ⌘P · ⌘O · ⌘W · ⌘⇧T |
| Next · Previous tab | ⌘⇧] · ⌘⇧[ (⌃Tab · ⌃⇧Tab) |
| Split right · Split down · Toggle pane zoom | ⌘D · ⌘⇧D · ⌘⇧↩ |
| Focus pane · Resize pane | ⌥⌘ arrows · ⌃⌥⌘ arrows |
| Back · Forward · Reload | ⌘[ · ⌘] · ⌘R |
| Find · Find Next · Find Previous | ⌘F · ⌘G · ⌘⇧G |
| Zoom In · Zoom Out · Actual Size | ⌘= · ⌘- · ⌘0 |
| Sidebar · Outline · Cycle appearance | ⌘B · ⌘⇧O · ⌥⌘T |
| Show in Finder · Open in External Editor | ⌥⌘R · ⌘⇧E |
| Print · Export as PDF | ⌥⌘P · ⌥⌘⇧P |

Every shortcut can be changed in Settings ▸ Shortcuts.

## Known limitations

- Web links (http, https) always open in the default browser.
- Single window.
- Two `$` signs in one paragraph (for example `$5 and $10`) can be mistaken for math; math can be turned off in Settings.

## License

[MIT](LICENSE). Licenses of bundled third-party libraries are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
