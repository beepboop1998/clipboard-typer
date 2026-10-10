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
4. Press **Ctrl+Shift+Alt+V**, or double-click the tray icon.
5. Within 10 seconds, click the field you want it typed into. Typing starts right away.

Before you click, a tooltip shows how many characters it will type and how many times it will press Enter. While it types, the tooltip shows progress.

**To stop it,** press **Esc** or click anywhere. It also stops by itself if another window takes focus. Pressing Esc before you click cancels the run.

### The tray menu

Right-click the tray icon for everything else:

```
Type clipboard                     (same as double-clicking the icon)
Step mode (one line per press)
──────────────
Step options                    ▸  Show typed text · Select field text first (Ctrl+A)
Troubleshooting                 ▸  Debug logging · Open log folder · Edit script settings · Reload script
──────────────
How to use
Exit
```

Hover over the icon to see the hotkey and any setting that's switched on, such as step mode or debug logging.

## Step mode: one line per press

Use this to type a list one item at a time, such as names copied from a spreadsheet into a search box. Right-click the tray icon and tick **Step mode (one line per press)**. Then each press of **Ctrl+Shift+Alt+V**:

- selects the text in the field that has focus (Ctrl+A) and types the next line in its place. There's no click step.
- shows its progress, like `2/3 typed`.

The status doesn't show the text itself, so a password never appears on screen. To see each line as it's typed (`2/3: camera-02`), for example when working through a list of names, tick tray icon > **Step options** > **Show typed text**. It's off by default and off again every time the script starts. Untick it before typing a password.

After the last line it shows "End of list" and types nothing. Copy anything to start again at line 1. A clipboard with a single line types that line on every press.

Blank lines are skipped, and from a multi-column spreadsheet copy only the first column is typed. A line longer than `MAX_CHARS` is skipped with a message instead of typed. Step mode never presses Enter, Tab, Delete or Backspace. Because it presses Ctrl+A first, make sure a text field has focus. To type without selecting first, untick tray icon > **Step options** > **Select field text first (Ctrl+A)**, or set `STEP_SELECT_ALL_FIRST` to `false` to start that way.

While step mode is on, the tray menu's **Type clipboard** and double-clicking the tray icon still type the whole clipboard.

## Good to know

- **Line breaks press Enter and tabs press Tab.** In a terminal, every line runs as a command and a tab triggers auto-complete. A single trailing line break, like the one Excel adds to a copied cell, is dropped so one value doesn't press Enter.
- **It types about 30 characters a second**, slow enough for laggy remote sessions. The limit is 2,000 characters per run.
- **Your keyboard layout must match the remote machine's** (for example, both US English). If symbols like `@` and `"` come out swapped, the layouts differ. See `SEND_MODE` below.

## Settings

Settings are the constants near the top of `ClipboardTyper.ahk`. Open it with tray icon > **Troubleshooting** > **Edit script settings** (or any text editor), save, then choose **Troubleshooting** > **Reload script**. If the edit has a syntax error, the running copy keeps going and says it couldn't reload. If a value is invalid, the new copy replaces the running one and stops with a message naming the setting: fix it and double-click the script to start it again.

| Setting | Default | What it does |
|---|---|---|
| `HOTKEY_TYPE_CLIPBOARD` | `"^+!v"` | The hotkey (Ctrl+Shift+Alt+V). `^` is Ctrl, `+` is Shift, `!` is Alt, `#` is Win |
| `SEND_MODE` | `"Raw"` | `"Raw"` sends real key presses and works in most remote consoles. `"Text"` sends Unicode characters and ignores keyboard layout, but many remote consoles ignore it |
| `KEY_DELAY_MS` | `20` | Pause after each keystroke. Raise it to 40–50 if characters go missing |
| `KEY_PRESS_MS` | `10` | How long each key is held down |
| `MAX_CHARS` | `2000` | Longer clipboards are refused. In step mode, longer lines are skipped |
| `CLICK_TIMEOUT_SEC` | `10` | How long it waits for your click |
| `FOCUS_SETTLE_MS` | `300` | Pause between your click and the first keystroke, so the field can take focus |
| `SHOW_STARTUP_TIP` | `true` | Set to `false` to hide the notification at launch, for example if it runs at Windows startup |
| `STEP_MODE` | `false` | Start with step mode on. You can switch it any time from the tray menu |
| `STEP_SELECT_ALL_FIRST` | `true` | In step mode, press Ctrl+A before typing so each line replaces the field's text. Switch it any time from tray icon > **Step options** |
| `STEP_STATUS_MS` | `1500` | How long the step-mode status (`2/3 typed`) stays on screen |
| `STEP_SHOW_TEXT` | `false` | Start with **Show typed text** on, so the step-mode status includes the line it typed. Leave it `false` if you ever type passwords |
| `DEBUG_LOG` | `false` | Start with debug logging on (tray icon > **Troubleshooting** > **Debug logging**): `debug.log` next to the script records what each run did: lengths, line numbers, why it stopped, and the target's program and window class. Never the text itself or window titles |

## Troubleshooting

- **Characters are missing:** raise `KEY_DELAY_MS` to 40–50.
- **Symbols are wrong:** your keyboard layout and the remote machine's differ. Match them, or try `SEND_MODE := "Text"`.
- **The hotkey does nothing inside a remote session:** the session is capturing your keys. Press the hotkey while your own desktop has focus, then click into the session. The tray menu works too.
- **Nothing types into a window that's running as administrator:** Windows blocks input from normal programs into admin windows. Run the script as administrator.
- **Something else went wrong:** check `error.log` next to the script (tray icon > **Troubleshooting** > **Open log folder**). For more detail, tick **Troubleshooting** > **Debug logging**, repeat what went wrong, and look at `debug.log`. A run that starts typing writes a line like `typed 12/80 stop=esc`; the reason is `done`, `esc`, `click`, `focus` (another window took focus) or `sendfail`. A run cancelled before you click writes `wait result=esc` or `wait result=timeout`, and each step-mode press writes a `step line=2/5 ... result=...` line instead. An `esc` line shows that Esc reached the script.

## Privacy and security

- It runs only on your PC and never connects to anything. It never saves what's on your clipboard; `error.log` only records error messages. `debug.log`, written only while debug logging is on (`DEBUG_LOG`, or tray icon > **Troubleshooting** > **Debug logging** for the current session), records lengths, timings, stop reasons and the target's program and window class, never the text or window titles.
- If a run is stopped, crashes, or the script exits mid-keystroke, it lets go of any Shift, Ctrl, Alt or Win key it left held down, so what you type afterwards isn't affected.
- Nothing from the clipboard is shown on screen unless you turn on **Show typed text** in the tray menu.
- The text is typed as ordinary keystrokes. Anything that records keystrokes will see it, including keystroke or command logging in a remote session. Keep that in mind before typing a password.
- Clipboard sync is often turned off on purpose. Check that typing text into a session fits your organization's policy.

## Known limitations

- If another window grabs focus by itself while it types (a popup, for example), one character can land in that window. In testing this happened in about 1 in 5 such cases. Stopping it yourself with Esc or a click doesn't have this problem.
- Characters that aren't on your keyboard layout (accented letters, emoji) are sent as Unicode, which some remote consoles ignore.

## Running the tests

Double-click `tests/RunTests.ahk`. It runs unit checks, then drives your mouse and keyboard for about 4 minutes against two test windows, in both send modes and in step mode. Don't touch them until the results appear. Results go to `tests/results.txt`. Close any running Clipboard Typer first; the runner checks for this.

## License

MIT. See [LICENSE](LICENSE).
