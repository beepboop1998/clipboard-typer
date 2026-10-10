/*
    Unit.ahk
    Responsibility: Checks the parts of ClipboardTyper.ahk that don't need real input: hotkey labels,
                    settings validation, send-mode prefix, tray tip, help text, error.log placement,
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
#Include %A_ScriptDir%\..\ClipboardTyper.ahk
OnError(OnUnhandledError, 0)   ; NOTE: the app's handler would swallow this file's errors silently

Out("== Unit")

for pair in [["^+!v", "Ctrl+Shift+Alt+V"], ["#v", "Win+V"], ["F8", "F8"], ["^Numpad1", "Ctrl+Numpad1"], ["$*~!F12", "Alt+F12"], ["", ""]] {
    Check("DescribeHotkey '" . pair[1] . "'", DescribeHotkey(pair[1]), pair[2])
}
Check("tray tip", A_IconTip, "Clipboard Typer " . VERSION . " (" . DescribeHotkey(HOTKEY_TYPE_CLIPBOARD) . ")")
Check("Raw prefix", InputSender("Raw", 20, 10, appLog)._sendPrefix, "{Raw}")
Check("Text prefix", InputSender("Text", 20, 10, appLog)._sendPrefix, "{Text}")

Rejects("SEND_MODE 'Bogus'", () => InputSender("Bogus", 20, 10, appLog), "SEND_MODE")
Rejects("KEY_DELAY_MS -5", () => InputSender("Raw", -5, 10, appLog), "KEY_DELAY_MS")
Rejects("KEY_DELAY_MS 'fast'", () => InputSender("Raw", "fast", 10, appLog), "KEY_DELAY_MS")
Rejects("InputSender without a logger", () => InputSender("Raw", 20, 10), "Logger")
Rejects("MAX_CHARS 0", () => ClipboardTyper(sender, appLog, 0, 10, 300), "MAX_CHARS")
Rejects("MAX_CHARS 1.5", () => ClipboardTyper(sender, appLog, 1.5, 10, 300), "MAX_CHARS")
Rejects("CLICK_TIMEOUT_SEC 0", () => ClipboardTyper(sender, appLog, 2000, 0, 300), "CLICK_TIMEOUT_SEC")
Rejects("FOCUS_SETTLE_MS -1", () => ClipboardTyper(sender, appLog, 2000, 10, -1), "FOCUS_SETTLE_MS")
Rejects("STEP_STATUS_MS 0", () => ClipboardTyper(sender, appLog, 2000, 10, 300, false, true, 0), "STEP_STATUS_MS")
Rejects("ClipboardTyper without a logger", () => ClipboardTyper(sender, "", 2000, 10, 300), "Logger")

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

; Step status hides the typed text unless Show typed text is on (passwords stay off screen)
Check("show typed text matches STEP_SHOW_TEXT at start", typer.IsShowingStepText() ? "on" : "off", STEP_SHOW_TEXT ? "on" : "off")
Check("status with text hidden", typer._StepStatus(2, 5, "hunter2"), "2/5 typed")
OnShowTextMenu(SHOW_TEXT_MENU_ITEM)
Check("tray toggle shows typed text", typer.IsShowingStepText() ? "on" : "off", "on")
Check("status with text shown", typer._StepStatus(2, 5, "camera-02"), "2/5: camera-02")
Check("tray tip warns about typed text even with step mode off", InStr(A_IconTip, " - shows typed text") ? "yes" : "no: " . A_IconTip, "yes")
OnStepMenu(STEP_MENU_ITEM)
Check("tray tip says typed text is shown", InStr(A_IconTip, "step mode, shows typed text") ? "yes" : "no: " . A_IconTip, "yes")
OnStepMenu(STEP_MENU_ITEM)
OnShowTextMenu(SHOW_TEXT_MENU_ITEM)
Check("tray toggle hides typed text again", typer.IsShowingStepText() ? "on" : "off", "off")

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
    Check("help mentions Show typed text", InStr(text, "Show typed text") ? "yes" : "no", "yes")
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
