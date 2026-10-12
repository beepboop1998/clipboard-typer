/*
    Unit.ahk
    Responsibility: Checks the parts of ClipboardTyper.ahk that don't need real input: hotkey labels,
                    settings validation, send-mode prefix, tray menu and tip, help text, error.log placement,
                    step-mode line splitting and toggling, the Logger, the error handler and the
                    stuck-modifier release.
    Dependencies: ..\ClipboardTyper.ahk (included, so its wiring runs too)
    Author: reuben
    Usage: Unit.ahk <results file>   (started by RunTests.ahk)
*/
#Requires AutoHotkey v2.0
; NOTE: set before the include so the script loads with an unwritable working dir, like a Startup-folder launch
SetWorkingDir(A_WinDir . "\System32")
resultsFile := A_Args.Length >= 1 ? A_Args[1] : A_ScriptDir . "\results.txt"
OnError(UnitHarnessError, -1)  ; NOTE: registered first, so it also catches errors in the included startup
try FileDelete(A_ScriptDir . "\Unit.ini")  ; NOTE: before the include, whose startup applies saved settings
#Include %A_ScriptDir%\..\ClipboardTyper.ahk
OnError(OnUnhandledError, 0)   ; NOTE: the app's handler would swallow this file's errors silently

Out("== Unit")

for pair in [["^+!v", "Ctrl+Shift+Alt+V"], ["#v", "Win+V"], ["F8", "F8"], ["^Numpad1", "Ctrl+Numpad1"], ["$*~!F12", "Alt+F12"], ["", ""]] {
    Check("DescribeHotkey '" . pair[1] . "'", DescribeHotkey(pair[1]), pair[2])
}
; NOTE: KEY_DELAY_MS/KEY_PRESS_MS pick the starting speed: Normal unless the script was edited
startSpeed := "Custom (" . Round(KEY_DELAY_MS) . " ms)"
startItem := TrayMenu.CUSTOM_SPEED_ITEM
for preset in TrayMenu.SPEED_PRESETS {
    if preset.delay = KEY_DELAY_MS && preset.press = KEY_PRESS_MS {
        startSpeed := preset.name
        startItem := preset.name . " (" . preset.delay . " ms)"
    }
}
startAfterKey := typer.GetAfterTyping()  ; NOTE: AFTER_TYPING picks the starting After typing key
startAfterShown := startAfterKey = "" ? "nothing" : startAfterKey
tipStates := ""
for state in [STEP_MODE ? "step mode" : "", STEP_SHOW_TEXT ? "shows typed text" : "", startAfterKey != "" ? "then " . startAfterKey : "",
    DEBUG_LOG ? "debug logging" : "", startSpeed != "Normal" ? StrLower(startSpeed) : ""] {
    if state != "" {
        tipStates .= (tipStates = "" ? " - " : ", ") . state
    }
}
Check("tray tip", A_IconTip, "Clipboard Typer " . VERSION . " (" . DescribeHotkey(HOTKEY_TYPE_CLIPBOARD) . ")" . tipStates)
Check("Raw prefix", InputSender("Raw", 20, 10, appLog)._sendPrefix, "{Raw}")
Check("Text prefix", InputSender("Text", 20, 10, appLog)._sendPrefix, "{Text}")

Rejects("SEND_MODE 'Bogus'", () => InputSender("Bogus", 20, 10, appLog), "SEND_MODE")
Rejects("KEY_DELAY_MS -5", () => InputSender("Raw", -5, 10, appLog), "KEY_DELAY_MS")
Rejects("KEY_DELAY_MS 'fast'", () => InputSender("Raw", "fast", 10, appLog), "KEY_DELAY_MS")
Rejects("KEY_PRESS_MS 1001", () => InputSender("Raw", 20, 1001, appLog), "KEY_PRESS_MS")
Rejects("KEY_DELAY_MS 2.5", () => InputSender("Raw", 2.5, 10, appLog), "KEY_DELAY_MS")
Rejects("InputSender without a logger", () => InputSender("Raw", 20, 10), "Logger")
Rejects("MAX_CHARS 0", () => ClipboardTyper(sender, appLog, 0, 10, 300), "MAX_CHARS")
Rejects("MAX_CHARS 1.5", () => ClipboardTyper(sender, appLog, 1.5, 10, 300), "MAX_CHARS")
Rejects("CLICK_TIMEOUT_SEC 0", () => ClipboardTyper(sender, appLog, 2000, 0, 300), "CLICK_TIMEOUT_SEC")
Rejects("FOCUS_SETTLE_MS -1", () => ClipboardTyper(sender, appLog, 2000, 10, -1), "FOCUS_SETTLE_MS")
Rejects("STEP_STATUS_MS 0", () => ClipboardTyper(sender, appLog, 2000, 10, 300, false, true, 0), "STEP_STATUS_MS")
Rejects("ClipboardTyper without a logger", () => ClipboardTyper(sender, "", 2000, 10, 300), "Logger")
Rejects("AFTER_TYPING 'Space'", () => ClipboardTyper(sender, appLog, 2000, 10, 300, false, true, 1500, false, "Space"), "AFTER_TYPING")

; Step mode line splitting (lines joined with | for comparison)
for pair in [
    ["alpha`r`n`r`nbeta+1`r`ngamma{x}`r`n", "alpha|beta+1|gamma{x}", "blank line and trailing CRLF dropped"],
    ["cam01`tsite A`r`ncam02`tsite B`r`n", "cam01|cam02", "first column only"],
    ["  padded  `n`t`n", "padded", "trimmed; tab-only line dropped"],
    ["`tsecond column only", "", "empty first cell dropped, not column 2"],
    ["mac1`rmac2", "mac1|mac2", "lone CR is a line break"],
    ["back`bspace", "backspace", "control chars removed"],
    ["", "", "empty clipboard"]] {
    Check("step split: " . pair[3], JoinLines(typer._SplitLines(pair[1])), pair[2])
}

; The tray menu as Windows sees it: AutoHotkey's own items are gone, the app's are grouped
hTray := A_TrayMenu.Handle
hSpeed := SubMenuHandle(hTray, TrayMenu.SPEED_PREFIX . startSpeed)
hAfter := SubMenuHandle(hTray, TrayMenu.AFTER_PREFIX . startAfterShown)
hStep := SubMenuHandle(hTray, TrayMenu.STEP_OPTIONS_ITEM)
hTrouble := SubMenuHandle(hTray, TrayMenu.TROUBLE_ITEM)
Check("tray top level", MenuNames(hTray), "Type clipboard|Step mode (one line per press)|-|Speed: " . startSpeed . "|After typing: " . startAfterShown . "|Step options|Troubleshooting|-|How to use|Exit")
Check("tray Speed", MenuNames(hSpeed), "Fast (10 ms)|Normal (20 ms)|Slow (40 ms)|Very slow (80 ms)|-|Custom...")
Check("Speed starts on KEY_DELAY_MS/KEY_PRESS_MS", TickedItems(hSpeed), startItem)
Check("tray Step options", MenuNames(hStep), "Show typed text|Select field text first (Ctrl+A)")
Check("tray Troubleshooting", MenuNames(hTrouble), "Debug logging|-|Open log folder|Edit script settings|Reload script|-|Forget saved settings")
Check("double-click runs Type clipboard", A_TrayMenu.Default, TrayMenu.TYPE_ITEM)
Check("tray tip comes from _TipText", tray._TipText(), A_IconTip)

; Step mode toggle keeps the check mark and tray tooltip in sync
Check("step mode off at start", typer.IsStepMode() ? "on" : "off", STEP_MODE ? "on" : "off")
; NOTE: the toggle checks below start from off, whatever STEP_MODE and STEP_SHOW_TEXT say; both are restored after them
if typer.IsStepMode() {
    typer.ToggleStepMode()
}
tray.Refresh()
tray.OnStepMode()
Check("tray toggle turns step mode on", typer.IsStepMode() ? "on" : "off", "on")
Check("step mode item ticked", MenuChecked(hTray, TrayMenu.STEP_ITEM), "ticked")
Check("tray tip shows step mode", InStr(A_IconTip, " - step mode") ? "yes" : "no", "yes")
tray.OnStepMode()
Check("tray toggle turns step mode off", typer.IsStepMode() ? "on" : "off", "off")
Check("step mode item unticked", MenuChecked(hTray, TrayMenu.STEP_ITEM), "unticked")

; Step status hides the typed text unless Show typed text is on (passwords stay off screen)
Check("show typed text matches STEP_SHOW_TEXT at start", typer.IsShowingStepText() ? "on" : "off", STEP_SHOW_TEXT ? "on" : "off")
if typer.IsShowingStepText() {
    typer.ToggleShowStepText()
}
tray.Refresh()
Check("status with text hidden", typer._StepStatus(2, 5, "hunter2"), "2/5 typed")
tray.OnShowText()
Check("tray toggle shows typed text", typer.IsShowingStepText() ? "on" : "off", "on")
Check("show typed text item ticked", MenuChecked(hStep, TrayMenu.SHOW_TEXT_ITEM), "ticked")
Check("status with text shown", typer._StepStatus(2, 5, "camera-02"), "2/5: camera-02")
Check("tray tip warns about typed text even with step mode off", InStr(A_IconTip, " - shows typed text") ? "yes" : "no: " . A_IconTip, "yes")
tray.OnStepMode()
Check("tray tip says typed text is shown", InStr(A_IconTip, "step mode, shows typed text") ? "yes" : "no: " . A_IconTip, "yes")
tray.OnStepMode()
tray.OnShowText()
Check("tray toggle hides typed text again", typer.IsShowingStepText() ? "on" : "off", "off")
if typer.IsStepMode() != !!STEP_MODE {
    typer.ToggleStepMode()
}
if typer.IsShowingStepText() != !!STEP_SHOW_TEXT {
    typer.ToggleShowStepText()
}
tray.Refresh()

; Select field text first follows STEP_SELECT_ALL_FIRST and toggles from Step options
Check("select-all item matches STEP_SELECT_ALL_FIRST", MenuChecked(hStep, TrayMenu.SELECT_ALL_ITEM), STEP_SELECT_ALL_FIRST ? "ticked" : "unticked")
tray.OnSelectAll()
Check("tray toggle flips select-all", typer.IsSelectingAllFirst() ? "on" : "off", STEP_SELECT_ALL_FIRST ? "off" : "on")
Check("select-all item follows", MenuChecked(hStep, TrayMenu.SELECT_ALL_ITEM), STEP_SELECT_ALL_FIRST ? "unticked" : "ticked")
tray.OnSelectAll()

; Debug logging from the tray: starts debug.log with a start line, ticks, and shows in the tooltip
if appLog.IsDebugEnabled() {
    tray.OnDebugLogging()  ; NOTE: start from off, so DEBUG_LOG := true in the script can't flip the checks below
}
for name in ["debug.log", "debug.old.log"] {
    try FileDelete(A_ScriptDir . "\" . name)
}
tray.OnDebugLogging()
Check("tray turns debug logging on", appLog.IsDebugEnabled() ? "on" : "off", "on")
Check("debug logging item ticked", MenuChecked(hTrouble, TrayMenu.DEBUG_ITEM), "ticked")
Check("tray tip says debug logging", InStr(A_IconTip, "debug logging") ? "yes" : "no: " . A_IconTip, "yes")
startLine := FileExist(A_ScriptDir . "\debug.log") ? FileRead(A_ScriptDir . "\debug.log") : ""
Check("debug.log starts with a start line", RegExMatch(startLine, "i)DEBUG start ver=\S+ ahk=\S+ .* layout=[0-9A-F]{8}") ? "yes" : "no: " . startLine, "yes")
tray.OnDebugLogging()
Check("tray turns debug logging off", appLog.IsDebugEnabled() ? "on" : "off", "off")
Check("debug logging item unticked", MenuChecked(hTrouble, TrayMenu.DEBUG_ITEM), "unticked")
try FileDelete(A_ScriptDir . "\debug.log")

; Speed: SetDelays checks its range; each preset sets delay and press, ticks only itself and renames the Speed item
for bad in [[-1, 10], [1001, 10], ["fast", 10], [20, -1], [2.5, 10]] {
    Check("SetDelays rejects " . bad[1] . "/" . bad[2], sender.SetDelays(bad[1], bad[2]) ? "accepted" : "rejected", "rejected")
}
Check("SetDelays accepts 0 and numeric text", (sender.SetDelays(0, " 40 ") && sender.GetDelayMs() = 0 && sender.GetPressMs() = 40) ? "yes" : "no", "yes")
for preset in TrayMenu.SPEED_PRESETS {
    item := preset.name . " (" . preset.delay . " ms)"
    tray.OnSpeedPreset(item)
    Check("preset " . preset.name . " sets delay/press", sender.GetDelayMs() . "/" . sender.GetPressMs(), preset.delay . "/" . preset.press)
    Check("preset " . preset.name . " is the only ticked item", TickedItems(hSpeed), item)
    Check("Speed item shows " . preset.name, InStr(MenuNames(hTray), "|Speed: " . preset.name . "|") ? "yes" : "no: " . MenuNames(hTray), "yes")
}
Check("tray tip names a non-default speed", InStr(A_IconTip, "very slow") ? "yes" : "no: " . A_IconTip, "yes")
Check("debug start line shows the speed in use", InStr(DebugStartFields(), " delay=80 press=30 ") ? "yes" : "no: " . DebugStartFields(), "yes")
tray.OnSpeedPreset("Normal (20 ms)")
Check("tray tip leaves Normal out", InStr(A_IconTip, "normal") ? "no: " . A_IconTip : "yes", "yes")

; Dialogs from the tray wait until a run ends: a box on top of a paused run can't get Esc or keys
trayDialogSeen := false
lastNotice := ""
tray.DefineProp("_Notice", {Call: SpyNotify})
SetTimer(CloseTrayDialogs, 250)  ; NOTE: closes (and records) any dialog that opens, so a broken refusal fails instead of hanging
typer._phase := "waiting"
tray.OnCustomSpeed()
Check("Custom... refused during a run", (trayDialogSeen ? "opened" : "refused") . " / " . (InStr(lastNotice, "Stop the current run") ? "notice" : "no notice"), "refused / notice")
lastNotice := ""
tray.OnHelp()
Check("How to use refused during a run", (trayDialogSeen ? "opened" : "refused") . " / " . (InStr(lastNotice, "Stop the current run") ? "notice" : "no notice"), "refused / notice")
typer._phase := ""
SetTimer(CloseTrayDialogs, 0)
tray.DeleteProp("_Notice")

; Custom speed: whole ms from 0 to 1000; a preset's delay applies that whole preset
Check("custom 25 applied", tray._ApplyCustomDelay("25") ? "yes" : "no", "yes")
Check("custom 25 keeps the press time", sender.GetDelayMs() . "/" . sender.GetPressMs(), "25/10")
Check("custom 25 ticks Custom", TickedItems(hSpeed), "Custom...")
Check("custom 25 label", InStr(MenuNames(hTray), "|Speed: Custom (25 ms)|") ? "yes" : "no: " . MenuNames(hTray), "yes")
for bad in ["abc", "2.5", "", 1001, -1] {
    Check("custom '" . bad . "' refused and changes nothing", (tray._ApplyCustomDelay(bad) ? "applied" : "refused") . " " . sender.GetDelayMs(), "refused 25")
}
Check("custom 1000 applied", (tray._ApplyCustomDelay(1000) && sender.GetDelayMs() = 1000) ? "yes" : "no", "yes")
Check("custom 700 applied", (tray._ApplyCustomDelay(700) && sender.GetDelayMs() = 700) ? "yes" : "no", "yes")
tray.OnSpeedPreset("Very slow (80 ms)")
tray._ApplyCustomDelay(20)
Check("custom 20 after Very slow is Normal, press too", sender.GetDelayMs() . "/" . sender.GetPressMs() . " " . TickedItems(hSpeed), "20/10 Normal (20 ms)")
sender.SetDelays(40, 30)
tray.Refresh()
Check("Slow's delay with another press time is Custom", TickedItems(hSpeed) . " / " . (InStr(MenuNames(hTray), "|Speed: Custom (40 ms)|") ? "labelled" : "not labelled"), "Custom... / labelled")
sender.SetDelays(KEY_DELAY_MS, KEY_PRESS_MS)  ; NOTE: back to the starting speed
tray.Refresh()

; Run stats in the done message
Check("done message with time and rate", typer._DoneMessage(42, 1400), "Typed 42 chars in 1.4s (30/s)")
Check("done message for a run too short to time", typer._DoneMessage(1, 0), "Typed 1 chars")
Check("done message with the after-typing key", typer._DoneMessage(42, 1400, "Enter"), "Typed 42 chars + Enter in 1.4s (30/s)")

; After typing: "", Enter or Tab in any case; the tray ticks it, names it and shows it in the tooltip
for pair in [["", ""], ["Enter", "Enter"], ["enter", "Enter"], ["TAB", "Tab"]] {
    Check("SetAfterTyping '" . pair[1] . "'", (typer.SetAfterTyping(pair[1]) ? "accepted " : "rejected ") . typer.GetAfterTyping(), "accepted " . pair[2])
}
Check("SetAfterTyping 'Space' rejected, Tab kept", (typer.SetAfterTyping("Space") ? "accepted " : "rejected ") . typer.GetAfterTyping(), "rejected Tab")
typer.SetAfterTyping("")
tray.Refresh()
Check("tray After typing", MenuNames(hAfter), "Nothing|Press Enter|Press Tab")
Check("After typing starts on Nothing", TickedItems(hAfter), "Nothing")
tray.OnAfterTyping("Press Enter")
Check("tray sets After typing to Enter", typer.GetAfterTyping(), "Enter")
Check("Press Enter ticked", TickedItems(hAfter), "Press Enter")
Check("After typing item shows Enter", InStr(MenuNames(hTray), "|After typing: Enter|") ? "yes" : "no: " . MenuNames(hTray), "yes")
Check("tray tip says then Enter", InStr(A_IconTip, "then Enter") ? "yes" : "no: " . A_IconTip, "yes")
tray.OnAfterTyping("Nothing")
Check("tray sets After typing back to nothing", typer.GetAfterTyping() . "|" . TickedItems(hAfter), "|Nothing")
typer.SetAfterTyping(startAfterKey)  ; NOTE: back to the starting key
tray.Refresh()

; The click prompt counts every Enter, and the after-typing key
for c in [["abc", "", "Click the field to type 3 chars into"],
    ["a`nb`nc", "", "Click the field to type 5 chars into (presses Enter 2x)"],
    ["abc", "Enter", "Click the field to type 3 chars into (then presses Enter)"],
    ["a`nb`nc", "Enter", "Click the field to type 5 chars into (presses Enter 3x, the last one after the text)"],
    ["abc", "Tab", "Click the field to type 3 chars into (then presses Tab)"],
    ["a`nb", "Tab", "Click the field to type 3 chars into (presses Enter 1x, then presses Tab)"]] {
    Check("click prompt: " . StrReplace(c[1], "`n", "\n") . " + '" . c[2] . "'", typer._ClickPrompt(c[1], c[2]), c[3])
}

; Unsafe targets: desktop, taskbar, Start/Search and non-text controls; never a title in the notice
for c in [["Progman", "explorer.exe", true], ["WorkerW", "explorer.exe", true], ["Shell_TrayWnd", "explorer.exe", true],
    ["Shell_SecondaryTrayWnd", "explorer.exe", true], ["Notepad", "notepad.exe", false],
    ["Windows.UI.Core.CoreWindow", "SearchHost.exe", true], ["Windows.UI.Core.CoreWindow", "StartMenuExperienceHost.exe", true],
    ["Windows.UI.Core.CoreWindow", "other.exe", false], ["", "", false]] {
    Check("blocked class " . c[1] . " / " . c[2], typer._IsBlockedClass(c[1], c[2]) ? "blocked" : "allowed", c[3] ? "blocked" : "allowed")
}
blockedNotice := typer._RefusalNotice("Progman", "explorer.exe", false)
Check("refusal notice names class and program", (InStr(blockedNotice, "class Progman, explorer.exe") && InStr(blockedNotice, "BLOCKED_TARGET_CLASSES")) ? "yes" : "no: " . blockedNotice, "yes")
Check("refusal notice for own windows", typer._RefusalNotice("AutoHotkeyGUI", "AutoHotkey64.exe", true), "That's a Clipboard Typer window; nothing typed. Click the field to type into.")
for c in [[1, 1, 0, 0, true], [1, 2, 0, 0, false], [1, 2, 5, 5, true], [1, 2, 5, 6, false], [0, 1, 0, 0, false], [1, 0, 0, 0, false], [1, 2, 0, 0, false]] {
    Check("same target " . c[1] . "/" . c[2] . " owners " . c[3] . "/" . c[4], typer._SameTarget(c[1], c[2], c[3], c[4]) ? "yes" : "no", c[5] ? "yes" : "no")
}
for c in [["Button", true], ["ComboBox", true], ["SysListView32", true], ["Edit", false], ["RichEdit20W", false], ["Chrome_RenderWidgetHostHWND", false], ["", false]] {
    Check("non-text control " . c[1], typer._IsNonTextControlClass(c[1]) ? "refused" : "typed into", c[2] ? "refused" : "typed into")
}
; The step check reads a ClassNN (class + instance number), so test that path too
for c in [["Button1", true], ["ComboBox2", true], ["SysListView321", true], ["SysTreeView321", true], ["SysTabControl321", true],
    ["msctls_trackbar321", true], ["Edit1", false], ["RichEdit20W1", false], ["Chrome_RenderWidgetHostHWND1", false]] {
    Check("focused control " . c[1], typer._IsNonTextControlClass(typer._ControlClassFromClassNN(c[1])) ? "refused" : "typed into", c[2] ? "refused" : "typed into")
}

; Step statuses after a press. NOTE: the flags are pinned, so an edited STEP_SELECT_ALL_FIRST or STEP_SHOW_TEXT can't change them
selectAllWas := typer.IsSelectingAllFirst()
showTextWas := typer.IsShowingStepText()
typer._stepSelectAllFirst := true
typer._showStepText := false
Check("step status + Enter", typer._StepStatus(2, 5, "x", "Enter"), "2/5 typed + Enter")
Check("step status, key skipped", typer._StepKeyMissedStatus(2, 5, "Enter", "skipped-focus"), "2/5 typed; Enter skipped (window lost focus): press again to retype it without Enter")
Check("step status, stopped", typer._StepStoppedStatus(2, 5, "Enter"), "Stopped on line 2/5; press again to retype it (no Enter)")
Check("step status, send failed", typer._StepStoppedStatus(2, 5, "", "sendfail"), "Send failed on line 2/5" . typer._ErrorHint() . "; press again to retype it")
Check("step status, retyped", typer._StepRetypedStatus(2, 5, "Tab"), "2/5 retyped without Tab: check the field, then press Tab yourself")
typer._stepSelectAllFirst := false
Check("step status, stopped without select-all", typer._StepStoppedStatus(2, 5, ""), "Stopped on line 2/5; part of it is in the field: clear it, then press again")
Check("step status, key skipped without select-all", typer._StepKeyMissedStatus(2, 5, "Enter", "skipped-focus"),
    "2/5 typed; Enter skipped (window lost focus): the line is in the field: clear it, then press again to retype it without Enter")
typer._stepSelectAllFirst := selectAllWas
typer._showStepText := showTextWas

; The key guard stops a run on a key pressed at a real-input level, and ignores this script's own keys
typer._cancelled := false
typer._stopReason := ""
stopOnKeypressWas := typer._stopOnKeypress
typer._stopOnKeypress := true  ; NOTE: the check needs the guard even when STOP_ON_KEYPRESS is false
keyGuard := typer._StartKeyGuard()
SendEvent("{F24}")  ; NOTE: SendLevel 0, like the script's own typing
Sleep(100)
Check("key guard ignores the script's own keystrokes", typer._cancelled ? "stopped" : "running", "running")
SendLevel(2)
SendEvent("{F24}")
SendLevel(0)
Sleep(100)
Check("key guard stops on a key at a real-input level", (typer._cancelled ? "stopped " : "running ") . typer._stopReason, "stopped key")
typer._StopKeyGuard(keyGuard)
typer._stopOnKeypress := stopOnKeypressWas
typer._cancelled := false
typer._stopReason := ""
typer._stopVk := 0
Check("no key guard when STOP_ON_KEYPRESS is false", ClipboardTyper(sender, appLog, 2000, 10, 300, false, true, 1500, false, "", "", false)._StartKeyGuard(), "")

; The after-typing key is checked again just before it's sent: a stop or a lost target skips it
typer._cancelled := true
typer._stopReason := "click"
Check("after key skipped after a click", typer._SendAfterKey("Enter", 1), "skipped-click")
typer._stopReason := "key"
Check("after key skipped after a key press", typer._SendAfterKey("Enter", 1), "skipped-key")
typer._cancelled := false
typer._stopReason := ""
Check("after key skipped when the target isn't active", typer._SendAfterKey("Enter", 1), "skipped-focus")  ; NOTE: HWND 1 is never active
Check("no after key set: nothing to send", typer._SendAfterKey("", 1), "")

; A click while a step line types stops it, as in a full run
typer._phase := "steptyping"
typer.OnClick()
Check("click during a step line stops it", (typer._cancelled ? "stopped " : "running ") . typer._stopReason, "stopped click")
typer._phase := ""
typer._cancelled := false
typer._stopReason := ""
typer._clicked := false

; Step mode messages for the paths that type nothing, with _Notify swapped for a spy
lastNotice := ""
typer.DefineProp("_Notify", {Call: SpyNotify})
typer._needsReload := false
typer._lines := ["alpha", "beta+1", "gamma{x}"]
typer._index := 4
Check("step past the end types nothing", typer.TypeNextLine("") ? "typed" : "nothing", "nothing")
Check("step past the end says End of list (3/3)", InStr(lastNotice, "End of list (3/3)") ? "yes" : "no: " . lastNotice, "yes")
typer._lines := []
typer.TypeNextLine("")
Check("step with no lines says Clipboard has no text", lastNotice, "Clipboard has no text")
typer._lines := ["short", StrReplace(Format("{:" . (MAX_CHARS + 1) . "}", ""), " ", "x"), "next"]
typer._index := 2
Check("step line over MAX_CHARS types nothing", typer.TypeNextLine("") ? "typed" : "nothing", "nothing")
Check("step line over MAX_CHARS says skipped", InStr(lastNotice, "is " . (MAX_CHARS + 1) . " chars (max " . MAX_CHARS . "); skipped") ? "yes" : "no: " . lastNotice, "yes")
Check("step line over MAX_CHARS moves to the next line", typer._index, 3)
; A step press resets the stop flags first, so an Esc from an earlier tray run can't stop this line
typer._lines := ["x"]
typer._index := 1
typer._cancelled := true
typer._stopReason := "esc"
seenCancelled := "spy not called"
typer.DefineProp("_CheckStepTarget", {Call: (this, *) => 1})
typer.DefineProp("_ReinstallHooks", {Call: (this, *) => false})
typer.DefineProp("_TypeChars", {Call: SpyTypeChars})
selectAllWas := typer.IsSelectingAllFirst()
typer._stepSelectAllFirst := false
typer.TypeNextLine("")
Check("step press resets a stale Esc", seenCancelled, "not cancelled")
; A typed line whose after-typing key is skipped stays on that line; the next press retypes it without the key
afterWas := typer.GetAfterTyping()
typer.SetAfterTyping("Enter")
typer._lines := ["a", "b"]
typer._index := 1
typer._retryLine := false
typer.TypeNextLine("")  ; NOTE: the stubbed target is HWND 1, which is never active, so Enter is skipped
Check("step key skipped keeps the line", typer._index . " " . (typer._retryLine ? "retry" : "no retry") . " " . (InStr(lastNotice, "Enter skipped (window lost focus)") ? "notice" : lastNotice), "1 retry notice")
typer.TypeNextLine("")
Check("the retyped line moves on without the key", typer._index . " " . (typer._retryLine ? "retry" : "no retry") . " " . (InStr(lastNotice, "retyped without Enter") ? "notice" : lastNotice), "2 no retry notice")
typer.SetAfterTyping(afterWas)
; A step line runs with the key guard on: a key at a real-input level stops it
typer._lines := ["x"]
typer._index := 1
typer._retryLine := false
seenStop := "spy not called"
stopOnKeypressWas := typer._stopOnKeypress
typer._stopOnKeypress := true
typer.DefineProp("_TypeChars", {Call: SpyTypeCharsKey})
typer.TypeNextLine("")
Check("a step line runs with the key guard on", seenStop, "key")
typer._stopOnKeypress := stopOnKeypressWas
; The real target checks refuse this script's own windows, whether clicked or focused
typer.DeleteProp("_CheckStepTarget")
ownGui := Gui("+ToolWindow", "Unit own window")
ownGui.Show("w160 h40")
WinWaitActive(ownGui.Hwnd, , 2)
Check("own window detected", typer._WindowInfo(ownGui.Hwnd).own ? "own" : "other", "own")
typer._clickedRoot := ownGui.Hwnd
lastNotice := ""
clickResult := "threw"
try clickResult := typer._CheckClickTarget()
Check("click on an own window refused", clickResult . " / " . lastNotice, "0 / That's a Clipboard Typer window; nothing typed. Click the field to type into.")
typer._clickedRoot := 0
typer._lines := ["x"]
typer._index := 1
seenCancelled := "spy not called"
typer.DefineProp("_TypeChars", {Call: SpyTypeChars})
typer.TypeNextLine("")
Check("step with an own window focused types nothing", seenCancelled . " / " . lastNotice, "spy not called / That's a Clipboard Typer window; nothing typed. Click the field to type into.")
ownGui.Destroy()
typer._stepSelectAllFirst := selectAllWas
for name in ["_ReinstallHooks", "_TypeChars"] {
    typer.DeleteProp(name)
}
typer._retryLine := false
typer.DeleteProp("_Notify")
typer._needsReload := true

; error.log must land next to the script even though the working dir is System32
logPath := A_ScriptDir . "\error.log"  ; NOTE: A_ScriptDir is tests\ here, since this file is the main script
ReportStrayErrorLog("the error.log placement check")
typer._LogError("Unit", "log placement check")
Check("error.log written next to script", FileExist(logPath) ? "yes" : "no", "yes")
try FileDelete(logPath)

; Logger: its own folder, so these checks never touch the app's logs
unitDir := A_Temp . "\ClipboardTyperUnit"
try DirDelete(unitDir, true)
DirCreate(unitDir)
unitLog := Logger(unitDir, false)
try {
    throw Error("probe")
} catch Error as e {
    unitLog.Error("Unit", e.Message, e)
}
Check("error line carries the line number", RegExMatch(FileRead(unitDir . "\error.log"), "ERROR \[Unit\]: probe \(line \d+, ") ? "yes" : "no", "yes")
unitLog.Debug("probe", "n=1")
Check("debug off writes no debug.log", FileExist(unitDir . "\debug.log") ? "yes" : "no", "no")
unitLog.SetDebugEnabled(true)
unitLog.Debug("probe", "n=1")
unitLog.Debug("probe", "n=2")
debugText := FileRead(unitDir . "\debug.log")
StrReplace(debugText, " DEBUG probe ", , , &probeLines)
Check("debug on writes one line per event", probeLines, 2)
Check("debug line has milliseconds", RegExMatch(debugText, "m)^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} DEBUG probe n=1$") ? "yes" : "no: " . debugText, "yes")
for kind in ["debug", "error"] {
    FileAppend(Format("{:1100000}", ""), unitDir . "\" . kind . ".log")
    try FileDelete(unitDir . "\" . kind . ".old.log")
    FileAppend("old", unitDir . "\" . kind . ".old.log")  ; NOTE: an older rollover must be replaced, not block the next one
    if kind = "debug" {
        unitLog.Debug("probe", "n=3")
    } else {
        unitLog.Error("Unit", "after rollover")
    }
    Check(kind . ".log starts fresh above 1 MB", FileGetSize(unitDir . "\" . kind . ".log") < 1000 ? "yes" : "no", "yes")
    Check(kind . ".old.log replaced by the big log", FileGetSize(unitDir . "\" . kind . ".old.log") > 1048576 ? "yes" : "no", "yes")
}

; The error handler: logs, survives a thrown non-Error, and keeps AutoHotkey's dialog for critical errors
ReportStrayErrorLog("the OnUnhandledError checks")
Check("OnUnhandledError suppresses the dialog for a normal error", OnUnhandledError(Error("boom-normal"), "Exit"), 1)
Check("OnUnhandledError keeps the dialog for a critical error", OnUnhandledError(Error("boom-critical"), "ExitApp"), 0)
Check("OnUnhandledError survives a thrown string", OnUnhandledError("zqSECRET-thrown", "Exit"), 1)
handlerLog := FileExist(logPath) ? FileRead(logPath) : ""
Check("unhandled errors are logged", (InStr(handlerLog, "boom-normal") && InStr(handlerLog, "boom-critical")) ? "yes" : "no: " . handlerLog, "yes")
Check("a thrown string's text is never logged", InStr(handlerLog, "zqSECRET") ? "leaked" : "not logged", "not logged")
try FileDelete(logPath)

; Stuck modifiers: a Shift that is down in software but not physically is let go and logged.
; NOTE: this script's own hook sees its own send as artificial, so LShift is logically down, physically up.
unitSender := InputSender("Raw", 20, 10, unitLog)
try {
    SendEvent("{Blind}{LShift down}")
    Sleep(50)
    Check("LShift down in software", GetKeyState("LShift") ? "down" : "up", "down")
    Check("LShift physically up", GetKeyState("LShift", "P") ? "down" : "up", "up")
    unitSender.ReleaseStuckModifiers()
    Sleep(50)
    Check("ReleaseStuckModifiers lets go of a software-only LShift", GetKeyState("LShift") ? "down" : "up", "up")
    Check("the release is logged", InStr(FileRead(unitLog.LogPath("debug")), "DEBUG release key=LShift") ? "yes" : "no", "yes")
} finally {
    SendEvent("{Blind}{LShift up}")  ; NOTE: also clears this script's own record of the key
}
Check("nothing to release when no modifier is down", unitSender.ReleaseStuckModifiers(), 0)
; The exit handler can release the key of a combination that was mid-press, like the A of Ctrl+A
for c in [["^a", 0x41], ["{Enter}", 0x0D], ["+{Tab}", 0x09], ["^+!", 0], ["{Raw}ab", 0]] {
    Check("key tracked for an exit mid-press: " . c[1], unitSender._InFlightVkForKeys(c[1]), c[2])
}
unitSender.Send("{F24}")
Check("no key tracked once Send returns", unitSender._inFlightVk, 0)

; Saved settings: a store in the temp folder, fixtures written with IniWrite (never FileAppend: a UTF-8
; BOM would hide [Settings] from the INI functions)
iniPath := unitDir . "\saved.ini"
unitStore := SettingsStore(iniPath, unitLog, true)
Check("store round trip", (unitStore.Write("KeyDelayMs", 40) && unitStore.Read("KeyDelayMs", "x") = "40") ? "yes" : "no", "yes")
Check("a saved choice is in effect", unitStore.IsInEffect() ? "in effect" : "not in effect", "in effect")
Check("store default for a missing key", unitStore.Read("NoSuchKey", "dflt"), "dflt")
Check("store write into a missing folder fails", SettingsStore(unitDir . "\no-such-folder\x.ini", unitLog, true).Write("KeyDelayMs", 1) ? "saved" : "failed", "failed")
Check("the failed write is logged", InStr(FileRead(unitDir . "\error.log"), "Couldn't save KeyDelayMs") ? "yes" : "no", "yes")
; Saving and forgetting are in debug.log by key and result, never with the value (1000 appears nowhere else)
unitLog.SetDebugEnabled(true)
unitStore.Write("KeyPressMs", 1000)
SettingsStore(unitDir . "\no-such-folder\x.ini", unitLog, true).Write("KeyPressMs", 1000)
unitDebug := FileRead(unitLog.LogPath("debug"))
Check("saves are logged by key, never with the value", (InStr(unitDebug, "DEBUG ini write=ok key=KeyPressMs") && InStr(unitDebug, "DEBUG ini write=fail key=KeyPressMs")
    && !InStr(unitDebug, "1000")) ? "yes" : "no: " . unitDebug, "yes")
FileDelete(iniPath)
; NOTE: c[5]: a saved choice was applied, so the store reports it in effect (debug source=ini)
for c in [["abc", "", "20/10 Enter", "corrupt speed keeps the script's", false],
    ["", "Space", "20/10 Enter", "unknown AfterTyping keeps the script's", false],
    ["", "Nothing", "20/10 ", "saved Nothing overrides AFTER_TYPING Enter", true],
    ["", "tAB", "20/10 Tab", "AfterTyping in any case", true],
    ["", "Tab `; note", "20/10 Enter", "an inline comment makes the value invalid", false],
    ["60", "Tab", "60/10 Tab", "saved speed and Tab applied", true]] {
    try FileDelete(iniPath)
    if c[1] != "" {
        IniWrite(c[1], iniPath, "Settings", "KeyDelayMs")
    }
    if c[2] != "" {
        IniWrite(c[2], iniPath, "Settings", "AfterTyping")
    }
    probeSender := InputSender("Raw", 20, 10, unitLog)
    probeTyper := ClipboardTyper(probeSender, unitLog, 2000, 10, 300, false, true, 1500, false, "Enter")
    probeStore := SettingsStore(iniPath, unitLog, true)
    ApplySavedSettings(probeStore, probeSender, probeTyper, unitLog)
    Check("saved settings: " . c[4], probeSender.GetDelayMs() . "/" . probeSender.GetPressMs() . " " . probeTyper.GetAfterTyping()
        . (probeStore.IsInEffect() ? " (in effect)" : ""), c[3] . (c[5] ? " (in effect)" : ""))
}
FileDelete(iniPath)
IniWrite(40, iniPath, "Settings", "KeyDelayMs")
probeSender := InputSender("Raw", 20, 10, unitLog)
probeTyper := ClipboardTyper(probeSender, unitLog, 2000, 10, 300)
Check("SAVE_SETTINGS off: nothing is read", SettingsStore(iniPath, unitLog, false).Read("KeyDelayMs", "x"), "x")
Check("SAVE_SETTINGS off: the script's speed stays", (ApplySavedSettings(SettingsStore(iniPath, unitLog, false), probeSender, probeTyper, unitLog) . " " . probeSender.GetDelayMs()), "script 20")
Check("Forget deletes the file", (unitStore.Forget() && !FileExist(iniPath)) ? "yes" : "no", "yes")
Check("forgotten choices are not in effect", unitStore.IsInEffect() ? "in effect" : "not in effect", "not in effect")
errorSize := FileGetSize(unitDir . "\error.log")
Check("Forget with nothing saved is fine, twice", (unitStore.Forget() && unitStore.Forget() && FileGetSize(unitDir . "\error.log") = errorSize) ? "yes" : "no", "yes")
IniWrite(1, iniPath, "Settings", "KeyDelayMs")
FileSetAttrib("+R", iniPath)
Check("Forget deletes a read-only file", (unitStore.Forget() && !FileExist(iniPath)) ? "yes" : "no", "yes")
IniWrite(1, iniPath, "Settings", "KeyDelayMs")
lockedIni := FileOpen(iniPath, "r -rwd")  ; NOTE: as OneDrive or a virus scanner might hold it
errorSize := FileGetSize(unitDir . "\error.log")
Check("Forget of a locked file fails and is logged", (unitStore.Forget() ? "deleted" : "failed") . (FileGetSize(unitDir . "\error.log") > errorSize ? " logged" : " not logged"), "failed logged")
lockedIni.Close()
try FileDelete(iniPath)
unitDebug := FileRead(unitLog.LogPath("debug"))
Check("Forget results are logged", (InStr(unitDebug, "DEBUG ini forget=ok") && InStr(unitDebug, "DEBUG ini forget=nothing") && InStr(unitDebug, "DEBUG ini forget=fail")) ? "yes" : "no", "yes")
unitLog.SetDebugEnabled(false)

; The real tray saves what you pick and Forget goes back to the script's settings
trayIni := SettingsPath()
if SAVE_SETTINGS {
    tray.OnSpeedPreset("Slow (40 ms)")
    Check("debug start line says source=ini once a choice is saved", InStr(DebugStartFields(), " source=ini ") ? "yes" : "no: " . DebugStartFields(), "yes")
    tray.OnAfterTyping("Press Tab")
    Check("tray saves speed and After typing", IniRead(trayIni, "Settings", "KeyDelayMs", "-") . "/" . IniRead(trayIni, "Settings", "KeyPressMs", "-") . " " . IniRead(trayIni, "Settings", "AfterTyping", "-"), "40/20 Tab")
    tray.OnAfterTyping("Nothing")
    Check("tray saves Nothing explicitly", IniRead(trayIni, "Settings", "AfterTyping", "-"), "Nothing")
    tray.OnForgetSettings()
    Check("debug start line says source=script after Forget", InStr(DebugStartFields(), " source=script ") ? "yes" : "no: " . DebugStartFields(), "yes")
    Check("Forget saved settings restores the script's settings", (FileExist(trayIni) ? "file kept " : "") . sender.GetDelayMs() . "/" . sender.GetPressMs() . " " . TickedItems(hSpeed) . " " . typer.GetAfterTyping(),
        scriptDefaults.delay . "/" . scriptDefaults.press . " " . startItem . " " . startAfterKey)
    IniWrite("enter", trayIni, "Settings", "AfterTyping")
    ApplySavedSettings(store, sender, typer, appLog)
    tray.Refresh()
    Check("saved enter shows in the tray as Enter", TickedItems(hAfter) . " / " . (InStr(MenuNames(hTray), "|After typing: Enter|") ? "labelled" : "not labelled"), "Press Enter / labelled")
    tray.OnForgetSettings()
    Check("Forget saved settings restores After typing", typer.GetAfterTyping() . " " . TickedItems(hAfter), startAfterKey . " " . (startAfterKey = "" ? "Nothing" : "Press " . startAfterKey))
} else {
    ; NOTE: SAVE_SETTINGS := false in the script: tray choices must never create the file
    tray.OnSpeedPreset("Slow (40 ms)")
    Check("SAVE_SETTINGS off: the tray saves nothing", (FileExist(trayIni) ? "saved" : "nothing saved") . (InStr(DebugStartFields(), " source=script ") ? "" : ", source not script"), "nothing saved")
    tray.OnForgetSettings()
}

; One "after" debug line per run: a step line that stops or throws, or a full run that throws once typing
; began, logs skipped-stopped exactly once (from the finally), with the typing itself replaced by spies
afterDir := unitDir . "\after"
DirCreate(afterDir)
afterLog := Logger(afterDir, true)
probeTyper := ClipboardTyper(InputSender("Raw", 20, 10, afterLog), afterLog, 2000, 10, 300, false, false, 1500, false, "Enter")
probeTyper._lines := ["x"]
probeTyper._needsReload := false
probeTyper.DefineProp("_CheckStepTarget", {Call: (this, *) => 1})
probeTyper.DefineProp("_ReinstallHooks", {Call: (this, *) => false})
probeTyper.DefineProp("_Notify", {Call: (this, *) => ""})
probeTyper.DefineProp("_TypeChars", {Call: StoppedTypeChars})
probeTyper.TypeNextLine("")
Check("a stopped step line logs skipped-stopped once", CountIn(FileRead(afterLog.LogPath("debug")), "after key=Enter result=skipped-stopped"), 1)
probeTyper.DefineProp("_TypeChars", {Call: FailingTypeChars})
probeTyper.TypeNextLine("")
Check("a step line that throws logs skipped-stopped once", CountIn(FileRead(afterLog.LogPath("debug")), "after key=Enter result=skipped-stopped"), 2)
probeTyper.DefineProp("_ReadClipboard", {Call: (this, *) => "abc"})
probeTyper.DefineProp("_WaitForTargetClick", {Call: (this, *) => 1})
probeTyper.TypeClipboard()
Check("a full run that throws mid-typing logs skipped-stopped once", CountIn(FileRead(afterLog.LogPath("debug")), "after key=Enter result=skipped-stopped"), 3)
try DirDelete(unitDir, true)

; Help: open it the way the tray menu does, read the dialog, close it
appLog.SetDebugEnabled(false)  ; NOTE: so the exit handler can't leave a debug.log in tests\
for name in ["debug.log", "debug.old.log"] {
    try FileDelete(A_ScriptDir . "\" . name)
}
helpTitle := "Clipboard Typer " . VERSION . ": How to use"
SetTimer(GrabHelp, -600)
ShowHelp()
Out("PASS Unit completed")
try FileDelete(A_ScriptDir . "\Unit.ini")
ExitApp()

GrabHelp() {
    if !WinExist(helpTitle) {
        Out("FAIL help dialog did not open")
        return
    }
    text := WinGetText(helpTitle)
    WinClose(helpTitle)
    Check("help mentions the hotkey", InStr(text, DescribeHotkey(HOTKEY_TYPE_CLIPBOARD)) ? "yes" : "no", "yes")
    Check("help mentions the limit", InStr(text, MAX_CHARS . " characters") ? "yes" : "no", "yes")
    Check("help explains step mode", InStr(text, "Step mode") ? "yes" : "no", "yes")
    Check("help mentions Show typed text", InStr(text, "Step options > Show typed text") ? "yes" : "no", "yes")
    Check("help says how to apply edited settings", InStr(text, "Reload script") ? "yes" : "no", "yes")
    Check("help points dropped characters to Speed", (InStr(text, "Speed > Slow") && !InStr(text, "Raise KEY_DELAY_MS")) ? "yes" : "no", "yes")
    Check("help explains After typing", InStr(text, "After typing") ? "yes" : "no", "yes")
    if SAVE_SETTINGS {
        Check("help mentions Forget saved settings", InStr(text, "Forget saved settings") ? "yes" : "no", "yes")
    } else {
        Check("help says tray choices last until restart", (InStr(text, "until the script restarts") && !InStr(text, "are saved")) ? "yes" : "no", "yes")
    }
}

; --- Menu inspection (Win32), so the checks see the menu the user sees ---
; Item names joined with |, separators as "-".
MenuNames(hMenu) {
    names := ""
    Loop DllCall("GetMenuItemCount", "Ptr", hMenu, "Int") {
        pos := A_Index - 1
        state := DllCall("GetMenuState", "Ptr", hMenu, "UInt", pos, "UInt", 0x400, "UInt")  ; MF_BYPOSITION
        ; NOTE: a submenu item (MF_POPUP 0x10) keeps its item count in the byte where MF_SEPARATOR (0x800) sits
        if !(state & 0x10) && (state & 0x800) {
            name := "-"
        } else {
            buf := Buffer(512, 0)
            DllCall("GetMenuStringW", "Ptr", hMenu, "UInt", pos, "Ptr", buf, "Int", 256, "UInt", 0x400, "Int")
            name := StrGet(buf, "UTF-16")
        }
        names .= (A_Index > 1 ? "|" : "") . name
    }
    return names
}

MenuPos(hMenu, itemName) {
    for name in StrSplit(MenuNames(hMenu), "|") {
        if name == itemName {
            return A_Index - 1
        }
    }
    return -1
}

SubMenuHandle(hMenu, itemName) {
    return DllCall("GetSubMenu", "Ptr", hMenu, "Int", MenuPos(hMenu, itemName), "Ptr")
}

; Names of the ticked items, joined with |.
TickedItems(hMenu) {
    ticked := ""
    for name in StrSplit(MenuNames(hMenu), "|") {
        if name != "-" && MenuChecked(hMenu, name) = "ticked" {
            ticked .= (ticked = "" ? "" : "|") . name
        }
    }
    return ticked
}

MenuChecked(hMenu, itemName) {
    pos := MenuPos(hMenu, itemName)
    if pos < 0 {
        return "missing"
    }
    return (DllCall("GetMenuState", "Ptr", hMenu, "UInt", pos, "UInt", 0x400, "UInt") & 0x8) ? "ticked" : "unticked"  ; MF_CHECKED
}

Out(line) {
    FileAppend(line . "`n", resultsFile, "UTF-8")
}

Check(name, got, want) {
    Out((got == want ? "PASS " : "FAIL ") . name . (got == want ? "" : "  | got=" . got . "  want=" . want))
}

; Presses a key at a real-input level mid-line, as a person would, and records why the line stopped.
SpyTypeCharsKey(this, text, targetId, showProgress, &typed) {
    SendLevel(2)
    SendEvent("{F24}")
    SendLevel(0)
    Sleep(100)
    global seenStop := this._stopReason
    typed := StrLen(text)
    return "done"
}

CloseTrayDialogs() {
    global trayDialogSeen
    for title in ["Clipboard Typer: custom speed", "Clipboard Typer " . VERSION . ": How to use"] {
        if WinExist(title) {
            trayDialogSeen := true
            try WinClose(title)
        }
    }
}

StoppedTypeChars(this, text, targetId, showProgress, &typed) {
    typed := 0
    return "esc"
}

FailingTypeChars(this, text, targetId, showProgress, &typed) {
    throw Error("probe failure")
}

CountIn(text, needle) {
    StrReplace(text, needle, , , &count)
    return count
}

SpyTypeChars(this, text, targetId, showProgress, &typed) {
    global seenCancelled := this._cancelled ? "cancelled" : "not cancelled"
    typed := StrLen(text)
    return "done"
}

SpyNotify(this, message, durationMs := 0) {
    global lastNotice := message
}

JoinLines(lines) {
    result := ""
    for line in lines {
        result .= (A_Index > 1 ? "|" : "") . line
    }
    return result
}

; Passes only when makeFn throws, and (with wantText) only for the expected reason.
Rejects(name, makeFn, wantText := "") {
    try {
        makeFn()
        Out("FAIL " . name . " was accepted")
    } catch Error as e {
        if wantText != "" && !InStr(e.Message, wantText) {
            Out("FAIL " . name . " rejected for the wrong reason: " . e.Message)
            return
        }
        Out("PASS " . name . " rejected: " . e.Message)
    }
}

; A check that writes tests\error.log on purpose first reports anything already there, so deleting
; the file afterwards can't hide a real error.
ReportStrayErrorLog(beforeWhat) {
    path := A_ScriptDir . "\error.log"
    if !FileExist(path) {
        return
    }
    Out("FAIL unexpected error.log entries before " . beforeWhat . ": " . FileRead(path))
    FileDelete(path)
}

; Any error this file doesn't catch fails the run and exits, instead of leaving Unit hanging.
UnitHarnessError(thrown, mode) {
    Out("FAIL Unit harness error: " . ((thrown is Error) ? thrown.Message . " (line " . thrown.Line . ")" : Type(thrown)))
    ExitApp(1)  ; NOTE: without this the included hotkeys keep Unit alive and RunTests waits for its timeout
}
