# Clipboard Typer

**Paste into windows that won't let you paste.** Clipboard Typer types whatever is on your clipboard as real keystrokes. That makes it work in remote consoles, virtual machine consoles and remote-support sessions where copy and paste is blocked, turned off, or was never there.

Instead of retyping a long password, command, config line or license key by hand, copy it on your own PC, press **Ctrl+Shift+Alt+V**, and click where it should go.

It's a single AutoHotkey v2 script for Windows. There's nothing to install beyond AutoHotkey, it needs no admin rights, and it never connects to anything.

## What it's for

- **Remote support and privileged access sessions** with clipboard sync turned off, such as BeyondTrust Privileged Remote Access and BeyondTrust Remote Support (formerly Bomgar)
- **Virtual machine consoles:** the VMware vSphere / ESXi web console and VMRC, Proxmox and other noVNC consoles, Hyper-V, VirtualBox
- **Server management consoles:** HPE iLO, Dell iDRAC, KVM-over-IP switches
- **Remote Desktop (RDP) and Citrix sessions** where clipboard redirection is disabled
- **Screens with no clipboard at all:** BIOS/UEFI setup, OS installers, login prompts, recovery shells

**Tested so far:** BeyondTrust Privileged Remote Access. The others take keystrokes the same way but haven't been tested yet. If you try one, please open an issue and say whether it worked.

## How to use

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Download `ClipboardTyper.ahk` and double-click it. A tray icon appears, with a notification showing the hotkey.
3. Copy the text on your own PC.
4. Press **Ctrl+Shift+Alt+V**, or right-click the tray icon and choose **Type clipboard**.
5. Within 10 seconds, click the field you want it typed into. Typing starts right away.

Before you click, a tooltip shows how many characters it will type and how many times it will press Enter. While it types, the tooltip shows progress.

**To stop it,** press **Esc** or click anywhere. It also stops by itself if another window takes focus. Pressing Esc before you click cancels the run.

The tray icon's **How to use** item shows these steps inside the app.

## Good to know

- **Line breaks press Enter and tabs press Tab.** In a terminal, every line runs as a command and a tab triggers auto-complete. A single trailing line break, like the one Excel adds to a copied cell, is dropped so one value doesn't press Enter.
- **It types about 30 characters a second**, slow enough for laggy remote sessions. The limit is 2,000 characters per run.
- **Your keyboard layout must match the remote machine's** (for example, both US English). If symbols like `@` and `"` come out swapped, the layouts differ. See `SEND_MODE` below.

## Settings

Settings are the constants near the top of `ClipboardTyper.ahk`. Edit them in any text editor, save, and double-click the script again to reload it. If a value is invalid, the script says which one when it starts.

| Setting | Default | What it does |
|---|---|---|
| `HOTKEY_TYPE_CLIPBOARD` | `"^+!v"` | The hotkey (Ctrl+Shift+Alt+V). `^` is Ctrl, `+` is Shift, `!` is Alt, `#` is Win |
| `SEND_MODE` | `"Raw"` | `"Raw"` sends real key presses and works in most remote consoles. `"Text"` sends Unicode characters and ignores keyboard layout, but many remote consoles ignore it |
| `KEY_DELAY_MS` | `20` | Pause after each keystroke. Raise it to 40–50 if characters go missing |
| `KEY_PRESS_MS` | `10` | How long each key is held down |
| `MAX_CHARS` | `2000` | Longer clipboards are refused |
| `CLICK_TIMEOUT_SEC` | `10` | How long it waits for your click |
| `FOCUS_SETTLE_MS` | `300` | Pause between your click and the first keystroke, so the field can take focus |
| `SHOW_STARTUP_TIP` | `true` | Set to `false` to hide the notification at launch, for example if it runs at Windows startup |

## Troubleshooting

- **Characters are missing:** raise `KEY_DELAY_MS` to 40–50.
- **Symbols are wrong:** your keyboard layout and the remote machine's differ. Match them, or try `SEND_MODE := "Text"`.
- **The hotkey does nothing inside a remote session:** the session is capturing your keys. Press the hotkey while your own desktop has focus, then click into the session. The tray menu works too.
- **Nothing types into a window that's running as administrator:** Windows blocks input from normal programs into admin windows. Run the script as administrator.
- **Something else went wrong:** check `error.log` next to the script.

## Privacy and security

- It runs only on your PC and never connects to anything. It never saves what's on your clipboard; `error.log` only records error messages.
- The text is typed as ordinary keystrokes. Anything that records keystrokes will see it, including keystroke or command logging in a remote session. Keep that in mind before typing a password.
- Clipboard sync is often turned off on purpose. Check that typing text into a session fits your organization's policy.

## Known limitations

- If another window grabs focus by itself while it types (a popup, for example), one character can land in that window. In testing this happened in about 1 in 5 such cases. Stopping it yourself with Esc or a click doesn't have this problem.
- Characters that aren't on your keyboard layout (accented letters, emoji) are sent as Unicode, which some remote consoles ignore.

## Running the tests

Double-click `tests/RunTests.ahk`. It runs unit checks, then drives your mouse and keyboard for about 3 minutes against two test windows, in both send modes. Don't touch them until the results appear. Results go to `tests/results.txt`. Close any running Clipboard Typer first; the runner checks for this.

## License

MIT. See [LICENSE](LICENSE).
