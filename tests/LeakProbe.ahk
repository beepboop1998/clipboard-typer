/*
    LeakProbe.ahk
    Responsibility: Measures how often a character lands in another window when focus moves mid-typing
                    (the known check-then-send race). Not pass/fail; reports a rate.
    Dependencies: a running ClipboardTyper, TestTarget windows "CT_Target" and "CT_Other"
    Author: reuben
    Usage: LeakProbe.ahk <results file> <activate|click> <runs>   (started by RunTests.ahk with "leak")
*/
#Requires AutoHotkey v2.0
#SingleInstance Off

resultsFile := A_Args[1]
method := A_Args[2]
runs := Integer(A_Args[3])
CoordMode("Mouse", "Screen")
SendLevel(1)
savedClip := ClipboardAll()
MouseGetPos(&mouseX, &mouseY)

if !WinWait("CT_Target", , 5) || !WinWait("CT_Other", , 5) {
    FileAppend("INFO leak probe: test windows not found`n", resultsFile, "UTF-8")
    ExitApp(1)
}
longText := "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
leaks := 0
Loop runs {
    ControlSetText("", "Edit1", "CT_Target")
    ControlSetText("", "Edit1", "CT_Other")
    A_Clipboard := longText
    Sleep(100)
    WinActivate("CT_Target")
    WinWaitActive("CT_Target", , 2)
    Send("^+!v")
    Sleep(250)
    ClickIn("CT_Target")
    Sleep(900 + Random(0, 400))  ; land the focus change at a random point in a keystroke
    if method = "click" {
        ClickIn("CT_Other")
    } else {
        WinActivate("CT_Other")
    }
    WaitIdle("CT_Target")
    leaks += ControlGetText("Edit1", "CT_Other") != ""
    Sleep(500)
}
FileAppend("INFO leak probe (" . method . "): " . leaks . "/" . runs . " runs put a char in the other window`n", resultsFile, "UTF-8")
A_Clipboard := savedClip
MouseMove(mouseX, mouseY, 0)
ExitApp()


ClickIn(winTitle) {
    WinGetClientPos(&clientX, &clientY, , , winTitle)
    ControlGetPos(&editX, &editY, &editW, &editH, "Edit1", winTitle)
    Click(clientX + editX + editW // 2, clientY + editY + editH // 2)
}

WaitIdle(winTitle) {
    last := ""
    stableSince := A_TickCount
    loop {
        Sleep(150)
        current := ControlGetText("Edit1", winTitle)
        if current != last {
            last := current
            stableSince := A_TickCount
        } else if A_TickCount - stableSince > 1200 {
            return current
        }
    }
}
