/*
    Unit.ahk
    Responsibility: Checks the parts of ClipboardTyper.ahk that don't need real input: hotkey labels,
                    settings validation, send-mode prefix, tray tip, help text, error.log placement,
                    and step-mode line splitting and toggling.
    Dependencies: ..\ClipboardTyper.ahk (included, so its wiring runs too)
    Author: reuben
    Usage: Unit.ahk <results file>   (started by RunTests.ahk)
*/
#Requires AutoHotkey v2.0
; NOTE: set before the include so the script loads with an unwritable working dir, like a Startup-folder launch
SetWorkingDir(A_WinDir . "\System32")
#Include %A_ScriptDir%\..\ClipboardTyper.ahk

resultsFile := A_Args.Length >= 1 ? A_Args[1] : A_ScriptDir . "\results.txt"
Out("== Unit")

for pair in [["^+!v", "Ctrl+Shift+Alt+V"], ["#v", "Win+V"], ["F8", "F8"], ["^Numpad1", "Ctrl+Numpad1"], ["$*~!F12", "Alt+F12"], ["", ""]] {
    Check("DescribeHotkey '" . pair[1] . "'", DescribeHotkey(pair[1]), pair[2])
}
Check("tray tip", A_IconTip, "Clipboard Typer " . VERSION . " (" . DescribeHotkey(HOTKEY_TYPE_CLIPBOARD) . ")")
Check("Raw prefix", InputSender("Raw", 20, 10)._sendPrefix, "{Raw}")
Check("Text prefix", InputSender("Text", 20, 10)._sendPrefix, "{Text}")

Rejects("SEND_MODE 'Bogus'", () => InputSender("Bogus", 20, 10))
Rejects("KEY_DELAY_MS -5", () => InputSender("Raw", -5, 10))
Rejects("KEY_DELAY_MS 'fast'", () => InputSender("Raw", "fast", 10))
Rejects("MAX_CHARS 0", () => ClipboardTyper(sender, 0, 10, 300))
Rejects("MAX_CHARS 1.5", () => ClipboardTyper(sender, 1.5, 10, 300))
Rejects("CLICK_TIMEOUT_SEC 0", () => ClipboardTyper(sender, 2000, 0, 300))
Rejects("FOCUS_SETTLE_MS -1", () => ClipboardTyper(sender, 2000, 10, -1))
Rejects("STEP_STATUS_MS 0", () => ClipboardTyper(sender, 2000, 10, 300, false, true, 0))

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

; Step mode toggle keeps the tray tooltip in sync
Check("step mode off at start", typer.IsStepMode() ? "on" : "off", STEP_MODE ? "on" : "off")
OnStepMenu(STEP_MENU_ITEM)
Check("tray toggle turns step mode on", typer.IsStepMode() ? "on" : "off", "on")
Check("tray tip shows step mode", InStr(A_IconTip, " - step mode") ? "yes" : "no", "yes")
OnStepMenu(STEP_MENU_ITEM)
Check("tray toggle turns step mode off", typer.IsStepMode() ? "on" : "off", "off")

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
typer.DeleteProp("_Notify")
typer._needsReload := true

; error.log must land next to the script even though the working dir is System32
logPath := A_ScriptDir . "\error.log"  ; NOTE: A_ScriptDir is tests\ here, since this file is the main script
try FileDelete(logPath)
typer._LogError("Unit", "log placement check")
Check("error.log written next to script", FileExist(logPath) ? "yes" : "no", "yes")
try FileDelete(logPath)

; Help: open it the way the tray menu does, read the dialog, close it
helpTitle := "Clipboard Typer " . VERSION . ": How to use"
SetTimer(GrabHelp, -600)
ShowHelp()
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
}

Out(line) {
    FileAppend(line . "`n", resultsFile, "UTF-8")
}

Check(name, got, want) {
    Out((got == want ? "PASS " : "FAIL ") . name . (got == want ? "" : "  | got=" . got . "  want=" . want))
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

Rejects(name, makeFn) {
    try {
        makeFn()
        Out("FAIL " . name . " was accepted")
    } catch Error as e {
        Out("PASS " . name . " rejected: " . e.Message)
    }
}
