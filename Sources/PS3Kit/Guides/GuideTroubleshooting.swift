// "Troubleshooting" in Help (⌘?) and `ps3 guide troubleshooting`. Markdown, drawn by ReadmeView.

extension GuideTexts {
    static let troubleshooting = Guide(
        id: .troubleshooting,
        title: "Troubleshooting",
        summary: "What to do when PS3 Center can't find the PS3, transfers are slow or an install stalls.",
        symbol: "wrench.and.screwdriver",
        markdown: #"""
Most problems come down to three things: HEN isn't enabled, the Mac and the PS3 can't see each other, or the network is slow. Start at the top.

## PS3 Center can't find the PS3

The screen says *Can't reach the PS3*.

1. Check that the PS3 is on and that HEN is enabled (*Enable HEN* under Game, after every restart). On CFW, check that webMAN MOD is installed.
2. Check that the Mac and the PS3 are on the same network.
3. Check that macOS lets PS3 Center use the local network: System Settings → Privacy & Security → Local Network, with PS3 Center switched on. macOS asks the first time the app looks for the PS3, and if the answer was no, nothing on your network can be reached.
4. Press **Try Again**. PS3 Center tries the saved address first, then searches the local network, which takes up to half a minute.
5. If the search still finds nothing, press **Find PS3…** on the same screen (also in Settings → Console). It searches every network the Mac is on, and takes an address you type. You find the address on the PS3 under Settings → Network Settings → Settings and Connection Status List.

**A cable straight between the Mac and the PS3:** give both a fixed address in the same range, for example 192.168.2.1 on the Mac and 192.168.2.2 on the PS3. The search skips self-assigned addresses that start with 169.254.

## "The PS3 is on, but HEN isn't enabled"

The PS3 answers on the network, but webMAN doesn't: it only starts once HEN is enabled. Choose *Enable HEN* under Game on the PS3, and PS3 Center connects by itself. Do this after every restart, also after **Restart…** in PS3 Center, which can't enable HEN for you.

## The dot by the logo is yellow

The green dot by the PlayStation logo turns yellow when webMAN is slow to answer. That is normal while the PS3 is busy, for example during an install or a game. PS3 Center only treats the console as gone after three missed answers in a row, and not at all during long jobs like installing, counting storage or copying a disc.

## Transfers are slow

- The PS3's Wi-Fi only uses 2.4 GHz. A network cable is usually many times faster: to the router, through a switch, or straight to the Mac.
- Press **Measure Speed** in **Transfers**. It sends to the PS3 for five seconds, then shows the speed, the network and how long 10 GB would take. Pause the queue first.
- Settings → Transfers → Advanced has the piece size and pieces in flight. Change them only to compare results with Measure Speed. **Reset to Default** puts them back.

## An install doesn't start

PS3 Center knows an install is done when the app's folder on the PS3 changes and then settles. If nothing happens for 75 seconds, it sends the install command once more. If that doesn't help either, it stops with advice. The package is still in `/dev_hdd0/packages`, so you can install it on the PS3 under Game → Package Manager → Install Package Files → Standard.

If a game is running, installs wait on purpose. Quit the game, or press **Install Anyway**.

## Error codes

When installing an app or starting a game fails with a code like 80010006, PS3 Center adds what the code means and, where it can, what to do. To look up a code you saw on the TV, run `ps3 error 80010006` in Terminal.

## More tools

- `PS3_DEBUG=1 ps3 status` prints the FTP traffic between the Mac and the PS3.
- `PS3_HOST=192.168.1.20 ps3 status` uses that address for one command.
- GitHub answers 60 requests an hour without a token. If PS3 Center says GitHub is rate-limiting, wait a while; it reuses its last answers meanwhile. For `ps3` in Terminal, setting `GITHUB_TOKEN` to a GitHub token raises the limit.

## In Terminal

```bash
ps3 discover        # search the network and save the address
ps3 status          # does webMAN answer?
ps3 error 8001003D  # explain an error code
ps3 history         # what PS3 Center has changed
```
"""#
    )
}
