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
        case "Enter":
            RunEnterSuite()
        case "StepEnter":
            RunStepEnterSuite()
        case "Saved":
            RunSavedSuite()
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
    Check("T1 debug log: stop=done", LogHas("DEBUG typed (\d+)/\1 ms=\d+ cps=\S+ stop=done", mark), LogTail(mark))
    if speed := LogMatch("DEBUG typed (\d+)/\1 ms=(\d+) cps=(\S+) stop=done", mark) {
        Out("INFO " . label . " pass speed at Normal: " . speed[3] . " chars/s (" . speed[1] . " chars in " . speed[2] . " ms)")
    }

    ; V1 each Speed preset, picked at runtime through the tray's own callback (test-only hotkeys
    ;    Ctrl+Shift+Alt+1..4), types slower than the one before it; the same plain text every time
    ladder := ""
    last := 1000000
    ordered := true
    for key in ["1", "2", "3", "4"] {  ; Fast, Normal, Slow, Very slow
        Send("^+!" . key)
        Sleep(300)
        Clear()
        mark := LogMark()
        Trigger("abcdefghijklmnopqrstuvwxyzabcd")
        ClickIn("CT_Target")
        got := WaitIdle("CT_Target")
        speed := LogMatch("DEBUG typed 30/30 ms=\d+ cps=([\d.]+) stop=done", mark)
        cps := speed ? speed[1] + 0 : -1
        ordered := ordered && got == "abcdefghijklmnopqrstuvwxyzabcd" && cps > 0 && cps < last
        last := cps
        ladder .= (ladder = "" ? "" : " > ") . (speed ? speed[1] : "none")
    }
    Send("^+!2")  ; NOTE: back to Normal for the tests below
    Sleep(300)
    Check("V1 Fast > Normal > Slow > Very slow, picked from the tray at runtime", ordered, ladder . " chars/s")
    Out("INFO " . label . " pass speed ladder (Fast > Normal > Slow > Very slow): " . ladder . " chars/s")

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
    Check("T3 debug log: stop=click", LogHas("DEBUG typed \d+/80 ms=\d+ cps=\S+ stop=click", mark), LogTail(mark))

    ; T4 Esc during typing stops it
    Clear()
    mark := LogMark()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    Send("{Esc}")
    got := WaitIdle("CT_Target")
    Check("T4 Esc during typing stops it", IsPartial(got, longText), StrLen(got) . "/80 chars")
    Check("T4 debug log: stop=esc", LogHas("DEBUG typed \d+/80 ms=\d+ cps=\S+ stop=esc", mark), LogTail(mark))

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
    Check("T5 debug log: stop=focus", LogHas("DEBUG typed \d+/80 ms=\d+ cps=\S+ stop=focus", mark), LogTail(mark))

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

    ; S10 a focus change stops a step line; the list stays on it and the next press retypes it whole
    longLine := Repeat("abcdefghij", 8)
    Clear()
    mark := LogMark()
    StartStepLine(longLine . "`r`nnext")
    WinActivate("CT_Other")
    got := WaitIdle("CT_Target")
    other := ControlGetText("Edit1", "CT_Other")
    Check("S10 focus change stops a step line", IsPartial(got, longLine) && other == "" && LogHas("DEBUG step line=1/2 len=80 result=stopped stop=focus", mark), StrLen(got) . "/80 chars, other=" . Show(other) . "; " . LogTail(mark))
    got := StepPress()
    Check("S10 the next press retypes the stopped line whole", got == longLine, StrLen(got) . "/80 chars")
    got := StepPress()
    Check("S10 then the list moves on", got == "next", "got=" . Show(got))

    ; S10b Esc stops a step line (and is swallowed, so it can't reach the app)
    Clear()
    mark := LogMark()
    StartStepLine(longLine . "`r`nnext again")
    Send("{Esc}")
    got := WaitIdle("CT_Target")
    Check("S10b Esc stops a step line", IsPartial(got, longLine) && LogHas("DEBUG step line=1/2 len=80 result=stopped stop=esc", mark), StrLen(got) . "/80 chars; " . LogTail(mark))

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

; The "Enter" pass runs the typer with AFTER_TYPING := "Enter".
RunEnterSuite() {
    longText := Repeat("abcdefghij", 8)

    ; T9 Enter follows a run that typed everything (the test Edit is multi-line, so Enter adds `r`n)
    Clear()
    mark := LogMark()
    Trigger("abc")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T9 Enter follows a completed run", got == "abc`r`n" && LogHas("DEBUG after key=Enter result=sent", mark), "got=" . Show(got) . "; " . LogTail(mark))

    ; T10 no Enter after a run stopped with Esc
    Clear()
    mark := LogMark()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    Send("{Esc}")
    got := WaitIdle("CT_Target")
    Check("T10 a run stopped with Esc gets no Enter", IsPartial(got, longText) && LogHas("DEBUG typed \d+/80 .*stop=esc", mark)
        && LogHas("DEBUG after key=Enter result=skipped-stopped", mark) && !LogHas("result=sent", mark), StrLen(got) . "/80 chars; " . LogTail(mark))
}

; The "StepEnter" pass runs the typer with STEP_MODE := true and AFTER_TYPING := "Enter".
RunStepEnterSuite() {
    longLine := Repeat("abcdefghij", 8)

    ; S9 each press types its line, then Enter; the next press replaces both
    Clear()
    SetClip("alpha`r`nbeta+1")
    got1 := StepPress()
    got2 := StepPress()
    Check("S9 each step press types its line then Enter", got1 == "alpha`r`n" && got2 == "beta+1`r`n", Show(got1) . " / " . Show(got2))

    ; S11 a stopped step line gets no Enter, and neither does its retyped version
    Clear()
    mark := LogMark()
    StartStepLine(longLine . "`r`nnext")
    WinActivate("CT_Other")
    got := WaitIdle("CT_Target")
    other := ControlGetText("Edit1", "CT_Other")
    Check("S11 a stopped step line gets no Enter", IsPartial(got, longLine) && other == "" && LogHas("DEBUG after key=Enter result=skipped-stopped", mark), StrLen(got) . "/80 chars, other=" . Show(other) . "; " . LogTail(mark))
    got := StepPress()
    Check("S11 the retyped line gets no Enter either", got == longLine && LogHas("DEBUG after key=Enter result=skipped-retry", mark), "got " . StrLen(got) . " chars" . (InStr(got, "`n") ? " with a line break" : "") . "; " . LogTail(mark))
}

; The "Saved" pass starts the typer with SAVE_SETTINGS on and a saved .ini (written by RunTests):
; KeyDelayMs=60, KeyPressMs=20, AfterTyping=Enter. The script itself says 20/10 and no key.
RunSavedSuite() {
    ; P1 saved settings win over the script's: the start line shows the saved speed, and Enter follows the text
    Clear()
    Trigger("abc")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("P1 saved After typing: Enter applies", got == "abc`r`n", "got=" . Show(got))
    Check("P1 saved speed applies", LogHas("DEBUG start .* delay=60 press=20 source=ini"), LogTail())
}

; Copies the list, presses the hotkey in the target field, and returns once the first line has started typing.
StartStepLine(listText) {
    SetClip(listText)
    Sleep(300)  ; NOTE: extra time for the clipboard change to register before the press
    WinActivate("CT_Target")
    WinWaitActive("CT_Target", , 2)
    ControlFocus("Edit1", "CT_Target")
    Send("^+!v")
    WaitForTyping("CT_Target")
}

; Waits (up to 5s) until the field has some text, so a stop lands mid-line however late the hotkey fires.
WaitForTyping(winTitle) {
    start := A_TickCount
    while ControlGetText("Edit1", winTitle) == "" && A_TickCount - start < 5000 {
        Sleep(50)
    }
    Sleep(300)
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

; The first match after mark (a RegExMatch object), or "" when none.
LogMatch(pattern, mark := 0) {
    for line in StrSplit(ReadIfExists(debugLog), "`n", "`r") {
        if A_Index > mark && RegExMatch(line, pattern, &match) {
            return match
        }
    }
    return ""
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
