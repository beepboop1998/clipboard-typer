/*
    Unit.ahk
    Responsibility: Checks the parts of ClipboardTyper.ahk that don't need real input: hotkey labels,
                    settings validation, send-mode prefix, tray tip, help text, and error.log placement.
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
}

Out(line) {
    FileAppend(line . "`n", resultsFile, "UTF-8")
}

Check(name, got, want) {
    Out((got == want ? "PASS " : "FAIL ") . name . (got == want ? "" : "  | got=" . got . "  want=" . want))
}

Rejects(name, makeFn) {
    try {
        makeFn()
        Out("FAIL " . name . " was accepted")
    } catch Error as e {
        Out("PASS " . name . " rejected: " . e.Message)
    }
}
