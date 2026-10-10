/*
    RunTests.ahk
    Responsibility: Runs Unit.ahk, then E2E.ahk against copies of ClipboardTyper.ahk in Raw mode, Text mode
                    and step mode, and writes everything to tests\results.txt.
    Dependencies: Unit.ahk, E2E.ahk, TestTarget.ahk, LeakProbe.ahk (optional), ..\ClipboardTyper.ahk
    Author: reuben
    Usage: double-click. Arguments (optional, any order):
             leak        also run LeakProbe.ahk (adds about 2 minutes)
             unattended  skip the prompts; exit code = number of FAIL lines
    NOTE: the end-to-end part drives the real mouse and keyboard for about 4 minutes. Don't touch them.
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

; One end-to-end pass per entry, in this order. Each pass runs a copy of the script with these settings
; (plus SHOW_STARTUP_TIP := false and DEBUG_LOG := true) and the E2E suite of the same name.
PASS_ORDER := ["Raw", "Text", "Step"]
PASS_SETTINGS := Map(
    "Raw",  Map("SEND_MODE", '"Raw"',  "STEP_MODE", "false"),
    "Text", Map("SEND_MODE", '"Text"', "STEP_MODE", "false"),
    "Step", Map("SEND_MODE", '"Raw"',  "STEP_MODE", "true"))

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
        . (withLeak ? 6 : 4) . " minutes. Don't touch them until the results appear.`n`nStart?",
        "ClipboardTyper tests", "OKCancel Icon!")
    if answer != "OK" {
        ExitApp()
    }
}

try FileDelete(resultsFile)
DirCreate(workDir)
try FileDelete(workDir . "\error.log")
try FileDelete(workDir . "\error.old.log")
for name in ["debug.log", "debug.old.log", "error.log", "error.old.log"] {
    try FileDelete(A_ScriptDir . "\" . name)  ; NOTE: Unit.ahk is the main script there, so its logs land in tests\
}

; Unit, with a time limit, so an unattended run can't hang on it
Run('"' . ahk . '" "' . A_ScriptDir . '\Unit.ahk" "' . resultsFile . '"', , , &unitPid)
if ProcessWaitClose(unitPid, 120) {  ; NOTE: non-zero means it timed out
    ProcessClose(unitPid)
    Out("FAIL Unit.ahk did not finish within 120s")
}
if !FileExist(resultsFile) || !InStr(FileRead(resultsFile, "UTF-8"), "`nPASS Unit completed") {
    Out("FAIL Unit did not complete")
}
if FileExist(A_ScriptDir . "\error.log") {
    Out("FAIL tests\error.log was written during Unit:`n" . FileRead(A_ScriptDir . "\error.log"))
}

source := FileRead(scriptPath, "UTF-8")
debugLog := workDir . "\debug.log"
for pass in PASS_ORDER {
    copyPath := MakeTestCopy(source, pass, PASS_SETTINGS[pass])
    if copyPath = "" {
        continue  ; MakeTestCopy already logged the FAIL
    }
    for name in ["debug.log", "debug.old.log"] {
        try FileDelete(workDir . "\" . name)  ; NOTE: each pass checks only its own debug lines
    }
    Run('"' . ahk . '" "' . A_ScriptDir . '\TestTarget.ahk" CT_Target 40', , , &targetPid)
    Run('"' . ahk . '" "' . A_ScriptDir . '\TestTarget.ahk" CT_Other 440', , , &otherPid)
    ; NOTE: started from System32 so the suite also covers an unwritable working dir
    Run('"' . ahk . '" "' . copyPath . '"', A_WinDir . "\System32", , &typerPid)
    Sleep(1000)
    RunWait('"' . ahk . '" "' . A_ScriptDir . '\E2E.ahk" "' . resultsFile . '" ' . pass . ' "' . debugLog . '"')
    if withLeak && pass = "Raw" {
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

results := "`n" . FileRead(resultsFile, "UTF-8")  ; NOTE: leading `n so a PASS or FAIL on line 1 is counted too
StrReplace(results, "`nPASS ", , , &passes)
StrReplace(results, "`nFAIL ", , , &fails)
Out("== SUMMARY pass=" . passes . " fail=" . fails)
Finish("Passed: " . passes . "   Failed: " . fails . "`n`nDetails: tests\results.txt", fails)


; Writes a copy of the script for one test pass, with no startup notification and debug logging on.
; Returns its path, or "" on failure. Every setting must match exactly once, so a renamed settings
; line fails loudly instead of silently testing the defaults.
MakeTestCopy(source, pass, settings) {
    copy := source
    fixed := Map("SHOW_STARTUP_TIP", "false", "DEBUG_LOG", "true")
    for table in [settings, fixed] {
        for name, value in table {
            copy := RegExReplace(copy, 'm)^' . name . ' := (?:"\w*"|\w+)', name . " := " . value, &hits)
            if hits != 1 {
                Out("FAIL could not set " . name . " in the " . pass . " test copy (settings line renamed?)")
                return ""
            }
        }
    }
    copyPath := workDir . "\ClipboardTyper.test-" . pass . ".ahk"
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
