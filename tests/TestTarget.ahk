/*
    TestTarget.ahk
    Responsibility: A small always-on-top window with a multi-line Edit for the end-to-end tests to type into.
    Dependencies: none
    Author: reuben
    Usage: TestTarget.ahk <window title> <x position>   (started by RunTests.ahk)
*/
#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent

g := Gui("+AlwaysOnTop", A_Args.Length >= 1 ? A_Args[1] : "CT_Target")
g.Add("Edit", "w360 h120 Multi WantTab")
g.Show("x" . (A_Args.Length >= 2 ? A_Args[2] : 40) . " y60 NoActivate")
