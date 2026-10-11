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

**To stop it,** press **Esc**, click anywhere, or press any key. The key you press is blocked, so it can't mix into the text or reach the session (an Enter can't run a half-typed command). It also stops by itself if another window takes focus. Pressing Esc before you click cancels the run.

**It refuses targets that are clearly wrong.** If your click lands on the desktop, the taskbar, Start or Search, or one of Clipboard Typer's own windows, or the window you clicked doesn't take focus, it types nothing and says why.

### The tray menu

Right-click the tray icon for everything else:

```
Type clipboard                     (same as double-clicking the icon)
Step mode (one line per press)
──────────────
Speed: Normal                   ▸  Fast · Normal · Slow · Very slow · Custom...
After typing: nothing           ▸  Nothing · Press Enter · Press Tab
Step options                    ▸  Show typed text · Select field text first (Ctrl+A)
Troubleshooting                 ▸  Debug logging · Open log folder · Edit script settings · Reload script
──────────────
How to use
Exit
```

Hover over the icon to see the hotkey and any setting that's switched on, such as step mode, After typing, debug logging or a speed other than Normal.

### Speed

If characters go missing in a slow or laggy session, choose tray icon > **Speed** > **Slow** or **Very slow**. **Fast** suits a local window or a quick connection. Each speed is labelled by the pause after each key (Normal is 20 ms); **Custom...** sets any pause from 0 to 1000 ms. A change applies from the next run. Opening the tray menu while it types takes focus from the window, which stops the run. When a run finishes, the notice shows the real speed, like `Typed 42 chars in 1.4s (30/s)`.

### After typing

To press a key once everything is typed, choose tray icon > **After typing** > **Press Enter** (to submit a password or run a command) or **Press Tab** (to move to the next field). The click prompt says so before you click (`then presses Enter`), and the tray tooltip shows `then Enter`.

The key is only pressed when the whole text went through and the window you clicked still has focus. A run stopped with Esc, a click or a key press, or one where another window took focus, never gets it. When After typing is on at startup, a notification and a tooltip remind you, even with `SHOW_STARTUP_TIP` off.

## Step mode: one line per press

Use this to type a list one item at a time, such as names copied from a spreadsheet into a search box. Right-click the tray icon and tick **Step mode (one line per press)**. Then each press of **Ctrl+Shift+Alt+V**:

- selects the text in the field that has focus (Ctrl+A) and types the next line in its place. There's no click step.
- presses the **After typing** key, if one is set, so each press can fill in a value and submit it (Enter) or move to the next field (Tab).
- shows its progress, like `2/3 typed` or `2/3 typed + Enter`.

The status doesn't show the text itself, so a password never appears on screen. To see each line as it's typed (`2/3: camera-02`), for example when working through a list of names, tick tray icon > **Step options** > **Show typed text**. It's off by default and off again every time the script starts. Untick it before typing a password.

After the last line it shows "End of list" and types nothing. Copy anything to start again at line 1. A clipboard with a single line types that line on every press.

Blank lines are skipped, and from a multi-column spreadsheet copy only the first column is typed. A line longer than `MAX_CHARS` is skipped with a message instead of typed. Step mode itself never presses Enter, Tab, Delete or Backspace; After typing can add one Enter or Tab after each line.

**To stop a line,** press Esc, click, or press any key. The list stays on that line, and the next press types it again (Ctrl+A first replaces what was typed) without the After typing key, so you can check it before anything runs. In Linux shells and other consoles Ctrl+A moves to the start of the line instead of selecting it, so clear the line yourself before pressing again.

Step mode won't type into the desktop, the taskbar or Clipboard Typer's own windows, or into a focused button, checkbox or list (in ordinary Windows forms; it can't tell inside a remote session or a web page). With **After typing: Press Tab**, every stop in the tab order must be a text box. Because it presses Ctrl+A first, make sure a text field has focus. To type without selecting first, untick tray icon > **Step options** > **Select field text first (Ctrl+A)**, or set `STEP_SELECT_ALL_FIRST` to `false` to start that way.

While step mode is on, the tray menu's **Type clipboard** and double-clicking the tray icon still type the whole clipboard.

## Good to know

- **Line breaks press Enter and tabs press Tab.** In a terminal, every line runs as a command and a tab triggers auto-complete. A single trailing line break, like the one Excel adds to a copied cell, is dropped so one value doesn't press Enter.
- **At Speed: Normal it types about 30 characters a second**, slow enough for most remote sessions; change it from tray icon > **Speed**. The limit is 2,000 characters per run.
- **Your keyboard layout must match the remote machine's** (for example, both US English). If symbols like `@` and `"` come out swapped, the layouts differ. See `SEND_MODE` below.

## Settings

Settings are the constants near the top of `ClipboardTyper.ahk`. Open it with tray icon > **Troubleshooting** > **Edit script settings** (or any text editor), save, then choose **Troubleshooting** > **Reload script**. If the edit has a syntax error, the running copy keeps going and says it couldn't reload. If a value is invalid, the new copy replaces the running one and stops with a message naming the setting: fix it and double-click the script to start it again.

| Setting | Default | What it does |
|---|---|---|
| `HOTKEY_TYPE_CLIPBOARD` | `"^+!v"` | The hotkey (Ctrl+Shift+Alt+V). `^` is Ctrl, `+` is Shift, `!` is Alt, `#` is Win |
| `SEND_MODE` | `"Raw"` | `"Raw"` sends real key presses and works in most remote consoles. `"Text"` sends Unicode characters and ignores keyboard layout, but many remote consoles ignore it |
| `KEY_DELAY_MS` | `20` | Starting speed: the pause after each keystroke, 0 to 1000 ms. Change it any time from tray icon > **Speed** |
| `KEY_PRESS_MS` | `10` | Starting speed: how long each key is held down, 0 to 1000 ms. The **Speed** presets set this too |
| `MAX_CHARS` | `2000` | Longer clipboards are refused. In step mode, longer lines are skipped |
| `CLICK_TIMEOUT_SEC` | `10` | How long it waits for your click |
| `FOCUS_SETTLE_MS` | `300` | Pause between your click and the first keystroke, so the field can take focus |
| `SHOW_STARTUP_TIP` | `true` | Set to `false` to hide the notification at launch, for example if it runs at Windows startup |
| `STEP_MODE` | `false` | Start with step mode on. You can switch it any time from the tray menu |
| `STEP_SELECT_ALL_FIRST` | `true` | In step mode, press Ctrl+A before typing so each line replaces the field's text. Switch it any time from tray icon > **Step options** |
| `STEP_STATUS_MS` | `1500` | How long the step-mode status (`2/3 typed`) stays on screen |
| `STEP_SHOW_TEXT` | `false` | Start with **Show typed text** on, so the step-mode status includes the line it typed. Leave it `false` if you ever type passwords |
| `AFTER_TYPING` | `""` | Start with an After typing key: `"Enter"` or `"Tab"` (tray icon > **After typing**) |
| `STOP_ON_KEYPRESS` | `true` | A key you press while it types stops it, and the key is blocked. Set to `false` to stop only with Esc or a click |
| `BLOCKED_TARGET_CLASSES` | desktop, taskbars, Start/Search | Window classes it never types into. Remove one if a window you need is refused; the refusal names its class |
| `REQUIRE_CLICKED_FOCUS` | `true` | Refuse to type when the window you clicked didn't take focus. Set to `false` if a remote viewer is wrongly refused |
| `DEBUG_LOG` | `false` | Start with debug logging on (tray icon > **Troubleshooting** > **Debug logging**): `debug.log` next to the script records what each run did: lengths, line numbers, why it stopped, and the target's program and window class. Never the text itself or window titles |

## Troubleshooting

- **Characters are missing:** tray icon > **Speed** > **Slow**, or **Very slow** for a very laggy session.
- **"Won't type into the desktop, taskbar or Start":** your click landed there, or that window has focus. Click the field itself. If a window you need is refused, remove its class (named in the message) from `BLOCKED_TARGET_CLASSES`.
- **"The window you clicked didn't take focus":** click the field again. If it happens every time with one remote viewer, set `REQUIRE_CLICKED_FOCUS := false` and tell us which viewer.
- **"Focused control isn't a text box" (step mode):** a button, checkbox or list has focus, often after **After typing: Press Tab**. Click the text field and press again.
- **Symbols are wrong:** your keyboard layout and the remote machine's differ. Match them, or try `SEND_MODE := "Text"`.
- **The hotkey does nothing inside a remote session:** the session is capturing your keys. Press the hotkey while your own desktop has focus, then click into the session. The tray menu works too.
- **Nothing types into a window that's running as administrator:** Windows blocks input from normal programs into admin windows. Run the script as administrator.
- **Something else went wrong:** check `error.log` next to the script (tray icon > **Troubleshooting** > **Open log folder**). For more detail, tick **Troubleshooting** > **Debug logging**, repeat what went wrong, and look at `debug.log`. A run that starts typing writes a line like `typed 12/80 ms=410 cps=29.3 stop=esc`; the reason is `done`, `esc`, `click`, `key` (you pressed a key), `focus` (another window took focus) or `sendfail`. An `after key=Enter result=...` line follows when After typing is set. A run cancelled before you click writes `wait result=esc` or `wait result=timeout`, and each step-mode press writes a `step line=2/5 ... result=...` line instead. An `esc` line shows that Esc reached the script.

## Privacy and security

- It runs only on your PC and never connects to anything. It never saves what's on your clipboard; `error.log` only records error messages. `debug.log`, written only while debug logging is on (`DEBUG_LOG`, or tray icon > **Troubleshooting** > **Debug logging** for the current session), records lengths, timings, stop reasons and the target's program and window class, never the text or window titles.
- If a run is stopped, crashes, or the script exits mid-keystroke, it lets go of any Shift, Ctrl, Alt or Win key it left held down, so what you type afterwards isn't affected.
- Nothing from the clipboard is shown on screen unless you turn on **Show typed text** in the tray menu.
- The text is typed as ordinary keystrokes. Anything that records keystrokes will see it, including keystroke or command logging in a remote session. Keep that in mind before typing a password.
- Clipboard sync is often turned off on purpose. Check that typing text into a session fits your organization's policy.

## Known limitations

- If another window grabs focus by itself while it types (a popup, for example), one character can land in that window. In testing this happened in about 1 in 5 such cases. Stopping it yourself with Esc or a click doesn't have this problem.
- Characters that aren't on your keyboard layout (accented letters, emoji) are sent as Unicode, which some remote consoles ignore.
- The After typing key has the same race: if another window grabs focus at the very last moment, the Enter or Tab can land there.
- Inside a remote session or a web page, Clipboard Typer can't tell whether the focused field is a text box.
- The hotkey that starts a run can't be pressed inside a remote session that captures your keys; start the run from your own desktop or the tray icon (see Troubleshooting).

## Running the tests

Double-click `tests/RunTests.ahk`. It runs unit checks, then drives your mouse and keyboard for about 5 minutes against two test windows, in both send modes (each at every Speed preset), in step mode and with After typing: Enter. Don't touch them until the results appear. Results go to `tests/results.txt`. Close any running Clipboard Typer first; the runner checks for this.

## License

MIT. See [LICENSE](LICENSE).
