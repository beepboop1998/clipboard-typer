/*
    RunTests.ahk
    Responsibility: Runs Unit.ahk, then E2E.ahk against copies of ClipboardTyper.ahk in Raw mode, Text mode
                    and step mode, and writes everything to tests\results.txt.
    Dependencies: Unit.ahk, E2E.ahk, TestTarget.ahk, LeakProbe.ahk (optional), ..\ClipboardTyper.ahk
    Author: reuben
    Usage: double-click. Arguments (optional, any order):
             leak        also run LeakProbe.ahk (adds about 2 minutes)
             unattended  skip the prompts; exit code = number of FAIL lines
    NOTE: the end-to-end part drives the real mouse and keyboard for about 3 minutes. Don't touch them.
*/
#Requires AutoHotkey v2.0
#SingleInstance Force

args := " " . StrLower(Join(A_Args, " ")) . " "
withLeak := InStr(args, " leak ")
unattended := InStr(args, " unattended ")
ahk := A_AhkPath
scriptPath := A_ScriptDir . "\..\ClipboardTyper.ahk"
resultsFile := A_ScriptDir . "\results.txt"
workDir := A_Temp . "\ClipboardTyperTests"

; Guard: a running ClipboardTyper would also answer the test hotkey
DetectHiddenWindows(true)
for hwnd in WinGetList("ahk_class AutoHotkey") {
    if RegExMatch(WinGetTitle(hwnd), "i)\\ClipboardTyper[^\\]*\.ahk - AutoHotkey") {
        Finish("Close the running Clipboard Typer first (tray icon > Exit), then run the tests again.", 1)
    }
}
DetectHiddenWindows(false)

if !unattended {
    answer := MsgBox("The end-to-end tests drive your mouse and keyboard for about "
        . (withLeak ? 5 : 3) . " minutes. Don't touch them until the results appear.`n`nStart?",
        "ClipboardTyper tests", "OKCancel Icon!")
    if answer != "OK" {
        ExitApp()
    }
}

try FileDelete(resultsFile)
DirCreate(workDir)
try FileDelete(workDir . "\error.log")
RunWait('"' . ahk . '" "' . A_ScriptDir . '\Unit.ahk" "' . resultsFile . '"')

source := FileRead(scriptPath, "UTF-8")
for mode in ["Raw", "Text", "Step"] {
    copyPath := MakeTestCopy(source, mode)
    if copyPath = "" {
        continue  ; MakeTestCopy already logged the FAIL
    }
    Run('"' . ahk . '" "' . A_ScriptDir . '\TestTarget.ahk" CT_Target 40', , , &targetPid)
    Run('"' . ahk . '" "' . A_ScriptDir . '\TestTarget.ahk" CT_Other 440', , , &otherPid)
    ; NOTE: started from System32 so the suite also covers an unwritable working dir
    Run('"' . ahk . '" "' . copyPath . '"', A_WinDir . "\System32", , &typerPid)
    Sleep(1000)
    RunWait('"' . ahk . '" "' . A_ScriptDir . '\E2E.ahk" "' . resultsFile . '" ' . mode)
    if withLeak && mode = "Raw" {
        for method in ["activate", "click"] {
            RunWait('"' . ahk . '" "' . A_ScriptDir . '\LeakProbe.ahk" "' . resultsFile . '" ' . method . ' 5')
        }
    }
    for pid in [typerPid, targetPid, otherPid] {
        ProcessClose(pid)
    }
    try FileDelete(copyPath)
}

; The typer copies log next to themselves; any entry means something failed silently
if FileExist(workDir . "\error.log") {
    Out("FAIL error.log was written during the run:`n" . FileRead(workDir . "\error.log"))
} else {
    Out("PASS no error.log entries during the run")
}

results := FileRead(resultsFile, "UTF-8")
StrReplace(results, "`nPASS ", , , &passes)
StrReplace(results, "`nFAIL ", , , &fails)
Out("== SUMMARY pass=" . passes . " fail=" . fails)
Finish("Passed: " . passes . "   Failed: " . fails . "`n`nDetails: tests\results.txt", fails)


; Writes a copy of the script for one test pass, with no startup notification. Returns its path, or "" on failure.
; "Raw" and "Text" set SEND_MODE with step mode off; "Step" uses Raw with step mode on.
MakeTestCopy(source, mode) {
    sendMode := mode = "Step" ? "Raw" : mode
    stepMode := mode = "Step" ? "true" : "false"
    copy := RegExReplace(source, 'm)^SEND_MODE := "\w+"', 'SEND_MODE := "' . sendMode . '"', &modeHits)
    copy := RegExReplace(copy, "m)^SHOW_STARTUP_TIP := \w+", "SHOW_STARTUP_TIP := false", &tipHits)
    copy := RegExReplace(copy, "m)^STEP_MODE := \w+", "STEP_MODE := " . stepMode, &stepHits)
    if modeHits != 1 || tipHits != 1 || stepHits != 1 {
        Out("FAIL could not set SEND_MODE/SHOW_STARTUP_TIP/STEP_MODE in the test copy (settings lines renamed?)")
        return ""
    }
    copyPath := workDir . "\ClipboardTyper.test-" . mode . ".ahk"
    try FileDelete(copyPath)
    FileAppend(copy, copyPath, "UTF-8")
    return copyPath
}

Finish(message, exitCode) {
    if !unattended {
        MsgBox(message, "ClipboardTyper tests", exitCode ? "Icon!" : "Iconi")
    }
    ExitApp(exitCode)
}

Out(line) {
    FileAppend(line . "`n", resultsFile, "UTF-8")
}

Join(items, separator) {
    result := ""
    for item in items {
        result .= (A_Index > 1 ? separator : "") . item
    }
    return result
}
