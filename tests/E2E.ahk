/*
    E2E.ahk
    Responsibility: End-to-end suite: drives a running ClipboardTyper with synthetic hotkeys, clicks and Esc,
                    and checks what lands in the TestTarget windows.
    Dependencies: a running ClipboardTyper, TestTarget windows "CT_Target" and "CT_Other"
    Author: reuben
    Usage: E2E.ahk <results file> <label>   (started by RunTests.ahk; label "Step" runs the step-mode suite)
    NOTE: SendLevel 1 so ClipboardTyper's hook hotkeys (*~LButton, *Esc) treat this input like a person's.
          Saves and restores the clipboard, mouse position and CapsLock state.
*/
#Requires AutoHotkey v2.0
#SingleInstance Off

resultsFile := A_Args[1]
label := A_Args.Length >= 2 ? A_Args[2] : ""
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
    if label = "Step" {
        RunStepSuite()
    } else {
        RunSuite()
    }
} catch Error as e {
    Out("FAIL harness error: " . e.Message . " (line " . e.Line . ")")
    failCount += 1
}
A_Clipboard := savedClip
SetCapsLockState(capsWasOn ? "On" : "Off")
MouseMove(mouseX, mouseY, 0)
Out("TOTAL " . label . " pass=" . passCount . " fail=" . failCount)
ExitApp(failCount)


RunSuite() {
    longText := Repeat("abcdefghij", 8)

    ; T1 happy path: characters AHK treats specially, tab, CRLF, trailing CRLF dropped
    Clear()
    Trigger("Hello {World}! ^+#`r`nline2`tTab @`"q`" ~%``;`r`n")
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T1 symbols/tab/newline typed exactly, trailing CRLF dropped", got == "Hello {World}! ^+#`r`nline2`tTab @`"q`" ~%``;", "got=" . Show(got))

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
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    ClickIn("CT_Target")
    got := WaitIdle("CT_Target")
    Check("T3 click during typing stops it", IsPartial(got, longText), StrLen(got) . "/80 chars")

    ; T4 Esc during typing stops it
    Clear()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    Send("{Esc}")
    got := WaitIdle("CT_Target")
    Check("T4 Esc during typing stops it", IsPartial(got, longText), StrLen(got) . "/80 chars")

    ; T5 another window taking focus stops it
    ; NOTE: rarely one char can land in the other window (check-then-send race); LeakProbe.ahk measures the rate
    Clear()
    Trigger(longText)
    ClickIn("CT_Target")
    Sleep(1200)
    WinActivate("CT_Other")
    got := WaitIdle("CT_Target")
    other := ControlGetText("Edit1", "CT_Other")
    Check("T5 focus loss stops it, other window untouched", IsPartial(got, longText) && other == "", StrLen(got) . "/80 chars, other=" . Show(other))

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
