// "The Terminal and Claude" in Help (⌘?) and `ps3 guide cli-and-claude`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let cliAndClaude = Guide(
        id: .cliAndClaude,
        title: "The Terminal and Claude",
        summary: "Use the ps3 command in Terminal, and let Claude read your PS3 to help troubleshoot.",
        symbol: "terminal",
        markdown: #"""
Everything the app does, the `ps3` command can do in Terminal too. They share the same engine, settings and queue, so you can mix them freely. `ps3` can also let Claude read your PS3 and help you troubleshoot.

## Install the command

`ps3` is built from PS3 Center's source code, which needs Xcode. In the project folder, run:

```bash
make install    # builds ps3 and links it as ~/.local/bin/ps3
```

Run it again to update. If Terminal can't find `ps3`, use the full path `~/.local/bin/ps3`, or add `~/.local/bin` to your PATH.

## The basics

- **`ps3`** on its own opens a menu of the most common commands. Type a number, or a command.
- **`ps3 status`** shows health, temperatures, the fan, free space and what is running. Add `--watch` to keep it updating.
- **`--json`** prints JSON instead of text, for scripts and widgets. `status`, `apps` and `history` switch to JSON by themselves when their output goes to another program. `ps3 status --watch --json` prints one line per reading.
- **`--host <ip>`** talks to the PS3 at that address, for one command.
- **`ps3 guide`** lists these guides; `ps3 guide send` prints one, and `ps3 guide glossary` explains words like HEN.

## Changes are careful

Commands that change the PS3 follow the same rules as the app:

- Most ask before they act, and **`-y`** answers yes for you.
- **`--dry-run`** shows what would happen without doing it, for example `ps3 apps update --dry-run` or `ps3 send Game.iso --dry-run`.
- Installs and refreshing the game list wait while a game is running. **`--force`** goes ahead anyway.
- Everything that changes the console is logged. **`ps3 history`** shows the log, and the app shows the same list in the Status tab.

## One set of settings

The app and `ps3` read the same file, `~/.config/ps3center/config.json`: the PS3's address, the PS3 folder, Game Folders, Package Folders and the transfer settings. Change a folder in the app and `ps3` sees it, and the other way round.

```bash
ps3 config                                # show the settings
ps3 config set host 192.168.1.20          # the PS3's address
ps3 config folder add PS3ISO ~/Games/PS3  # link a game folder
```

The queue is shared too, but only one of them sends at a time. If the app is already sending, `ps3 queue start` says so and stops.

## Let Claude help

`ps3 mcp` is an MCP server, a standard way for an AI assistant to use tools on your Mac. With it, Claude can read your PS3's status and health, your homebrew and its updates, your games, the maintenance report and the history, and explain error codes.

> Every tool only reads. Claude can't change anything on the PS3. You make changes with `ps3` or in the app.

To add it to Claude Code:

```bash
claude mcp add ps3 -- ~/.local/bin/ps3 mcp
```

In Claude Desktop, add this to `claude_desktop_config.json`, with your own user name:

```json
{ "mcpServers": { "ps3": { "command": "/Users/<you>/.local/bin/ps3", "args": ["mcp"] } } }
```

Then ask, for example, *Why is my PS3 so hot?* or *What does 8001003D mean?* If HEN isn't enabled, Claude is told so and can tell you.

## In Terminal

```bash
ps3                         # the menu
ps3 status --watch
ps3 apps update --dry-run
ps3 history
ps3 guide                   # these guides
```
"""#
    )
}
