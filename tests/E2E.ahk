/*
    E2E.ahk
    Responsibility: End-to-end suite: drives a running ClipboardTyper with synthetic hotkeys, clicks and Esc,
                    and checks what lands in the TestTarget windows.
    Dependencies: a running ClipboardTyper, TestTarget windows "CT_Target" and "CT_Other"
    Author: reuben
    Usage: E2E.ahk <results file> <pass> <debug.log path>   (started by RunTests.ahk; the pass name picks the suite)
    NOTE: SendLevel 1 so ClipboardTyper's hook hotkeys (*~LButton, *Esc) treat this input like a person's.
          Saves and restores the clipboard, mouse position, CapsLock state and Shift.
*/
#Requires AutoHotkey v2.0
#SingleInstance Off

resultsFile := A_Args[1]
label := A_Args.Length >= 2 ? A_Args[2] : ""
debugLog := A_Args.Length >= 3 ? A_Args[3] : ""  ; the typer copy's debug.log (DEBUG_LOG is on in every test copy)
CoordMode("Mouse", "Screen")
SendLevel(1)
savedClip := ClipboardAll()
MouseGetPos(&mouseX, &mouseY)
capsWasOn := GetKeyState("CapsLock", "T")
passCount := 0
failCount := 0
Out("== E2E " . label)

if !WinWait("CT_Target", , 5) || !WinWait("CT_Other", , 5) {
    Out("FAIL setup: test windows not found")
    ExitApp(1)
}
try {
    switch label {
        case "Raw", "Text":
            RunSuite()
        case "Step":
            RunStepSuite()
        default:
            Check("known pass name", false, "no suite for pass '" . label . "'")
    }
} catch Error as e {
    Out("FAIL harness error: " . e.Message . " (line " . e.Line . ")")
    failCount += 1
}
A_Clipboard := savedClip
SetCapsLockState(capsWasOn ? "On" : "Off")
Send("{Blind}{LShift up}{RShift up}")  ; NOTE: a failed T12 must not leave Shift down for the next pass or the tester
MouseMove(mouseX, mouseY, 0)
Out("TOTAL " . label . " pass=" . passCount . " fail=" . failCount)
ExitApp(failCount)


RunSuite() {
    longText := Repeat("abcdefghij", 8)

    ; T1 happy path: characters AHK treats specially, tab, CRLF, trailing CRLF dropped
    Clear()
    mark := LogMark()
    Trigger("Hello {World}! ^+#`r`nline2`tTab @`"q`" ~%``;`r`n")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T1 symbols/tab/newline typed exactly, trailing CRLF dropped", got == "Hello {World}! ^+#`r`nline2`tTab @`"q`" ~%``;", "got=" . Show(got))
    Check("T1 debug log: stop=done", LogHas("DEBUG typed (\d+)/\1 stop=done", mark), LogTail(mark))

    ; T2 Esc cancels the wait, and a retry straight after works (notices don't block the hotkey)
    Clear()
    Trigger("abc")
    Send("{Esc}")
    cancelledAt := A_TickCount
    Sleep(300)
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T2a Esc during wait cancels; a later click types nothing", got == "", "got=" . Show(got))
    retryAfterMs := A_TickCount - cancelledAt
    Trigger("xyz")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T2b retry " . retryAfterMs . "ms after cancel works", got == "xyz", "got=" . Show(got))

    ; T3 a click inside the same window stops typing
    Clear()
    mark := LogMark()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T3 click during typing stops it", IsPartial(got, longText), StrLen(got) . "/80 chars")
    Check("T3 debug log: stop=click", LogHas("DEBUG typed \d+/80 stop=click", mark), LogTail(mark))

    ; T4 Esc during typing stops it
    Clear()
    mark := LogMark()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    Send("{Esc}")
    got := WaitIdle("CT_Target")
    Check("T4 Esc during typing stops it", IsPartial(got, longText), StrLen(got) . "/80 chars")
    Check("T4 debug log: stop=esc", LogHas("DEBUG typed \d+/80 stop=esc", mark), LogTail(mark))

    ; T5 another window taking focus stops it
    ; NOTE: rarely one char can land in the other window (check-then-send race); LeakProbe.ahk measures the rate
    Clear()
    mark := LogMark()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    WinActivate("CT_Other")
    got := WaitIdle("CT_Target")
    other := ControlGetText("Edit1", "CT_Other")
    Check("T5 focus loss stops it, other window untouched", IsPartial(got, longText) && other == "", StrLen(got) . "/80 chars, other=" . Show(other))
    Check("T5 debug log: stop=focus", LogHas("DEBUG typed \d+/80 stop=focus", mark), LogTail(mark))

    ; T6 over the limit and empty clipboard type nothing
    Clear()
    Trigger(Repeat("a", 2001))
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T6a 2001 chars refused", got == "", StrLen(got) . " chars")
    Clear()
    Trigger("")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T6b empty clipboard refused", got == "", StrLen(got) . " chars")

    ; T7 CapsLock on still types the right case
    Clear()
    SetCapsLockState("On")
    Trigger("aB1!")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    SetCapsLockState(capsWasOn ? "On" : "Off")
    Check("T7 CapsLock on, case preserved", got == "aB1!", "got=" . Show(got))

    ; T12 a Shift held only in software is let go when a run ends.
    ; NOTE: the run types nothing (Esc during the wait): a run that types can't test this, because
    ;       AutoHotkey's own Send already lets go of a modifier another process holds only in software.
    mark := LogMark()
    try {
        Send("{LShift down}")
        Trigger("abc")
        Send("{Esc}")  ; NOTE: the wildcard *Esc still fires with Shift down
        Sleep(500)
        Check("T12 a software-held LShift is released after a run", !GetKeyState("LShift") && LogHas("DEBUG release key=LShift", mark), "LShift " . (GetKeyState("LShift") ? "down" : "up") . "; " . LogTail(mark))
    } finally {
        Send("{LShift up}")
    }

    ; T13 the typed text never reaches the logs
    Clear()
    Trigger("zqSECRET7731")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    leaked := InStr(ReadIfExists(debugLog), "zqSECRET") || InStr(ReadIfExists(RegExReplace(debugLog, "debug\.log$", "error.log")), "zqSECRET")
    Check("T13 typed text never appears in debug.log or error.log", got == "zqSECRET7731" && !leaked, "got=" . Show(got) . (leaked ? ", LEAKED into a log" : ""))

    ; T8 no click: times out, then a late click types nothing
    Clear()
    Trigger("late")
    Sleep(10700)
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T8 10s timeout; a late click types nothing", got == "", "got=" . Show(got))
}

; Step mode (the typer copy runs with STEP_MODE := true): each press types the next line into the focused field.
; NOTE: holding the hotkey (auto-repeat) can't be simulated here, because injected keys never count as
;       physically held; that check needs a person.
RunStepSuite() {
    list := "alpha`r`n`r`nbeta+1`r`ngamma{x}`r`n"

    ; S1 three presses type the three lines literally, each replacing the last; press 4 types nothing
    Clear()
    SetClip(list)
    got1 := StepPress()
    got2 := StepPress()
    got3 := StepPress()
    got4 := StepPress()
    Check("S1 presses 1-3 type alpha, beta+1, gamma{x}, each replacing the last", got1 == "alpha" && got2 == "beta+1" && got3 == "gamma{x}", Show(got1) . " / " . Show(got2) . " / " . Show(got3))
    ; NOTE: the "End of list (3/3)" wording is checked in Unit.ahk; tooltip text can't be read from another process
    Check("S1 press 4 types nothing", got4 == "gamma{x}", "field=" . Show(got4))

    ; S2 copying the list again restarts at line 1
    SetClip(list)
    got := StepPress()
    Check("S2 copying again restarts at line 1", got == "alpha", "got=" . Show(got))

    ; S3 a single line retypes on every press
    SetClip("delta")
    results := ""
    Loop 3 {
        results .= StepPress() . "|"
    }
    Check("S3 single line types delta on every press", results == "delta|delta|delta|", "got=" . Show(results))

    ; S6 a two-column sheet copy types only the first column
    SetClip("cam01`tsite A`r`ncam02`tsite B`r`n")
    got := StepPress()
    Check("S6 two-column copy types only the first column", got == "cam01", "got=" . Show(got))

    ; S8 an empty clipboard types nothing
    Clear()
    SetClip("")
    got := StepPress()
    Check("S8 empty clipboard types nothing", got == "", "got=" . Show(got))

    ; S12 a step press is logged as a result, and the line itself never reaches the logs
    Clear()
    mark := LogMark()
    SetClip("zqSECRET7731")
    got := StepPress()
    leaked := InStr(ReadIfExists(debugLog), "zqSECRET") || InStr(ReadIfExists(RegExReplace(debugLog, "debug\.log$", "error.log")), "zqSECRET")
    Check("S12 step line typed and logged, text never in debug.log or error.log"
        , got == "zqSECRET7731" && !leaked && LogHas("DEBUG step line=1/1 len=12 result=typed", mark)
        , "got=" . Show(got) . (leaked ? ", LEAKED into a log" : "") . "; " . LogTail(mark))
}

; Focuses the target field, presses the hotkey once, and returns the field's text when typing has settled.
StepPress() {
    WinActivate("CT_Target")
    WinWaitActive("CT_Target", , 2)
    ControlFocus("Edit1", "CT_Target")
    Send("^+!v")
    return WaitIdle("CT_Target")
}

SetClip(clipText) {
    A_Clipboard := clipText
    Sleep(200)  ; let the typer's OnClipboardChange run before the next press
}

; --- Helpers ---
Trigger(clipText) {
    A_Clipboard := clipText
    Sleep(100)
    WinActivate("CT_Target")
    WinWaitActive("CT_Target", , 2)
    Send("^+!v")
    Sleep(250)
}

ClickIn(winTitle) {
    WinGetClientPos(&clientX, &clientY, , , winTitle)
    ControlGetPos(&editX, &editY, &editW, &editH, "Edit1", winTitle)
    Click(clientX + editX + editW // 2, clientY + editY + editH // 2)
}

Clear() {
    ControlSetText("", "Edit1", "CT_Target")
    ControlSetText("", "Edit1", "CT_Other")
}

; Returns the Edit's text once it has stopped changing for 1.2s.
WaitIdle(winTitle, maxMs := 25000) {
    last := ""
    stableSince := A_TickCount
    start := A_TickCount
    loop {
        Sleep(150)
        current := ControlGetText("Edit1", winTitle)
        if current != last {
            last := current
            stableSince := A_TickCount
        } else if A_TickCount - stableSince > 1200 {
            return current
        }
        if A_TickCount - start > maxMs {
            return current
        }
    }
}

; True when typing started and then stopped early: a non-empty strict prefix of the full text.
IsPartial(got, full) {
    return got != "" && StrLen(got) < StrLen(full) && SubStr(full, 1, StrLen(got)) == got
}

Repeat(text, count) {
    result := ""
    Loop count {
        result .= text
    }
    return result
}

; --- Debug log helpers (the typer copy writes debug.log; tooltips can't be read from another process) ---
; Number of complete lines in debug.log now; pass it to LogHas to look only at what comes after.
LogMark() {
    StrReplace(ReadIfExists(debugLog), "`n", "`n", , &count)
    return count
}

; True when a line after mark matches the regex. False when debug.log is missing, so that check fails
; and the rest still run.
LogHas(pattern, mark := 0) {
    for line in StrSplit(ReadIfExists(debugLog), "`n", "`r") {
        if A_Index > mark && RegExMatch(line, pattern) {
            return true
        }
    }
    return false
}

; The debug lines after mark, for a FAIL line's details.
LogTail(mark := 0) {
    tail := ""
    for line in StrSplit(ReadIfExists(debugLog), "`n", "`r") {
        if A_Index > mark && line != "" {
            tail .= " / " . RegExReplace(line, "^\S+ \S+ DEBUG ")
        }
    }
    return "log:" . (tail = "" ? " (nothing)" : tail)
}

ReadIfExists(path) {
    try {
        return FileExist(path) ? FileRead(path) : ""
    } catch {
        return ""  ; NOTE: the typer may be appending right now; the check reads again next time
    }
}

Show(text) {
    return StrReplace(StrReplace(StrReplace(text, "`r", "\r"), "`n", "\n"), "`t", "\t")
}

Check(name, ok, detail := "") {
    global passCount, failCount
    if ok {
        passCount += 1
    } else {
        failCount += 1
    }
    Out((ok ? "PASS " : "FAIL ") . name . (detail != "" ? "  | " . detail : ""))
}

Out(line) {
    FileAppend(line . "`n", resultsFile, "UTF-8")
}
