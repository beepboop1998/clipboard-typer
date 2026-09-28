/*
    ClipboardTyper.ahk
    Responsibility: Types the clipboard into the clicked window as paced keystrokes, for remote
                    consoles and VMs with no clipboard (VM consoles, iLO/iDRAC, noVNC, BeyondTrust PRA).
    Dependencies: none (standalone; single file on purpose so it can be dropped anywhere and run)
    Author: reuben
    Version: see VERSION below
    License: MIT
    Usage: copy text > press Ctrl+Shift+Alt+V (or tray icon > Type clipboard)
           > click the target field > it types.
           Esc cancels while it waits for the click. While typing, any click or Esc stops it.
           Settings are the constants under "Settings" below. Tray icon > How to use has the details.
*/
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Constants ---
VERSION := "1.0.0"

; --- Settings (edit these) ---
HOTKEY_TYPE_CLIPBOARD := "^+!v"  ; Ctrl+Shift+Alt+V  (^ Ctrl, + Shift, ! Alt, # Win)
SEND_MODE := "Raw"               ; "Raw": real key presses; works in most remote consoles, needs the same keyboard layout on both ends
                                 ; "Text": Unicode characters; layout-independent, but many remote viewers ignore them
KEY_DELAY_MS := 20               ; pause after each keystroke; raise to 40-50 if the session drops characters
KEY_PRESS_MS := 10               ; how long each key is held down
MAX_CHARS := 2000                ; refuse anything longer than this
CLICK_TIMEOUT_SEC := 10          ; how long to wait for the click on the target field
FOCUS_SETTLE_MS := 300           ; give the remote field time to take focus after the click
SHOW_STARTUP_TIP := true         ; notification on launch; set to false if this runs at Windows startup

; --- Wiring ---
; NOTE: instance names differ from class names; AHK v2 names are case-insensitive, so
;       inputSender := InputSender() would try to overwrite the class and fail at load.
sender := InputSender(SEND_MODE, KEY_DELAY_MS, KEY_PRESS_MS)
typer := ClipboardTyper(sender, MAX_CHARS, CLICK_TIMEOUT_SEC, FOCUS_SETTLE_MS)

typeCallback := ObjBindMethod(typer, "TypeClipboard")
activeCallback := ObjBindMethod(typer, "IsActive")
clickCallback := ObjBindMethod(typer, "OnClick")
cancelCallback := ObjBindMethod(typer, "Cancel")
if !typeCallback || !activeCallback || !clickCallback || !cancelCallback {
    throw Error("Failed to bind ClipboardTyper callbacks", "Main")
}
Hotkey(HOTKEY_TYPE_CLIPBOARD, typeCallback)
; NOTE: click and Esc only act while a run is in progress; otherwise they pass through untouched.
;       The click is never blocked (~) so it still lands in the session.
HotIf(activeCallback)
Hotkey("*~LButton", clickCallback)
Hotkey("*Esc", cancelCallback)
HotIf()

hotkeyLabel := DescribeHotkey(HOTKEY_TYPE_CLIPBOARD)
A_TrayMenu.Add()
A_TrayMenu.Add("Type clipboard", typeCallback)
A_TrayMenu.Add("How to use", ShowHelp)
A_IconTip := "Clipboard Typer " . VERSION . " (" . hotkeyLabel . ")"
if SHOW_STARTUP_TIP {
    TrayTip("Press " . hotkeyLabel . " to type the clipboard.`nRight-click the tray icon for help.", "Clipboard Typer " . VERSION . " is running", "Iconi Mute")
}


; --- Entry-point helpers ---
; Turns an AHK hotkey string such as "^+!v" into "Ctrl+Shift+Alt+V" for the tray tip and help,
; so they stay correct when HOTKEY_TYPE_CLIPBOARD is changed.
DescribeHotkey(hk) {
    if hk = "" {
        return ""  ; guard: nothing to describe
    }
    label := ""
    key := hk
    while StrLen(key) > 1 && InStr("^+!#<>*~$", SubStr(key, 1, 1)) {
        switch SubStr(key, 1, 1) {
            case "^": label .= "Ctrl+"
            case "+": label .= "Shift+"
            case "!": label .= "Alt+"
            case "#": label .= "Win+"
        }
        key := SubStr(key, 2)
    }
    return label . StrUpper(SubStr(key, 1, 1)) . SubStr(key, 2)
}

; Tray menu > How to use
ShowHelp(*) {
    MsgBox(
        "1. Copy the text you want typed.`n"
        . "2. Press " . hotkeyLabel . " (or tray icon > Type clipboard).`n"
        . "3. Within " . CLICK_TIMEOUT_SEC . "s, click the field to type into. Typing starts right after.`n`n"
        . "Stop: press Esc or click anywhere. It also stops if another window takes focus.`n"
        . "Line breaks press Enter and tabs press Tab. Limit: " . MAX_CHARS . " characters.`n`n"
        . "Wrong symbols? The remote keyboard layout differs from yours; try SEND_MODE := `"Text`".`n"
        . "Characters dropped? Raise KEY_DELAY_MS.`n"
        . "Settings are the constants near the top of the script. Errors go to error.log next to it.",
        "Clipboard Typer " . VERSION . ": How to use", "Iconi")
}


class InputSender {
    ; --- Properties ---
    _sendPrefix := ""
    _keyDelayMs := 0
    _pressMs := 0

    ; --- Constructor ---
    __New(sendMode, keyDelayMs, pressMs) {
        if sendMode != "Raw" && sendMode != "Text" {
            throw Error('SEND_MODE must be "Raw" or "Text", not "' . sendMode . '"', A_ThisFunc)
        }
        if !IsNumber(keyDelayMs) || !IsNumber(pressMs) || keyDelayMs < 0 || pressMs < 0 {
            throw Error("KEY_DELAY_MS and KEY_PRESS_MS must be numbers, 0 or more", A_ThisFunc)
        }
        ; NOTE: {Raw} sends real key codes, which is what remote viewers forward. {Text} sends every
        ;       char as VK_PACKET, which many remote viewers drop. With {Raw} the session's keyboard
        ;       layout must match this PC's, since the remote side turns key codes back into characters.
        this._sendPrefix := "{" . sendMode . "}"
        this._keyDelayMs := keyDelayMs
        this._pressMs := pressMs
    }

    ; --- Public Methods ---
    ; Sends text literally at a pace remote consoles can keep up with.
    TypeText(text) {
        if text = "" {
            return false  ; guard: nothing to send
        }
        try {
            SetKeyDelay(this._keyDelayMs, this._pressMs)  ; NOTE: per-thread setting, so set it on every call
            SendEvent(this._sendPrefix . text)
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            return false
        }
    }

    ; --- Private Methods ---
    _LogError(caller, message) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ERROR [" . caller . "]: " . message . "`n"
        try {
            FileAppend(line, A_ScriptDir . "\error.log")  ; NOTE: absolute; the working dir may not be writable
        } catch {
            OutputDebug(line)  ; NOTE: last resort; this runs inside callers' catch blocks so it must never throw
        }
    }
}


class ClipboardTyper {
    ; --- Properties ---
    _inputSender := ""
    _maxChars := 0
    _clickTimeoutSec := 0
    _focusSettleMs := 0
    _phase := ""            ; "" idle, "waiting" for the target click, "typing"
    _clicked := false
    _cancelled := false
    _notifyMs := 2500
    _progressEvery := 25    ; chars between progress tooltip updates
    _clearTipCallback := ""

    ; --- Constructor ---
    __New(sender, maxChars, clickTimeoutSec, focusSettleMs) {
        if !IsObject(sender) {
            throw Error("InputSender is required", A_ThisFunc)
        }
        if !IsInteger(maxChars) || maxChars < 1 {
            throw Error("MAX_CHARS must be a whole number, 1 or more", A_ThisFunc)
        }
        if !IsNumber(clickTimeoutSec) || clickTimeoutSec <= 0 {
            throw Error("CLICK_TIMEOUT_SEC must be a number above 0", A_ThisFunc)
        }
        if !IsNumber(focusSettleMs) || focusSettleMs < 0 {
            throw Error("FOCUS_SETTLE_MS must be a number, 0 or more", A_ThisFunc)
        }
        this._inputSender := sender
        this._maxChars := maxChars
        this._clickTimeoutSec := clickTimeoutSec
        this._focusSettleMs := focusSettleMs
        this._clearTipCallback := ObjBindMethod(this, "_ClearTip")
    }

    ; --- Public Methods ---
    ; Hotkey / tray entry point: read clipboard, wait for a click on the target field, type it.
    TypeClipboard(*) {
        if this._phase != "" {
            return false  ; guard: already running, ignore repeat triggers
        }
        this._phase := "waiting"
        this._clicked := false
        this._cancelled := false
        try {
            text := this._ReadClipboard()
            if text = "" {
                this._Notify("Clipboard has no text")
                return false
            }
            if StrLen(text) > this._maxChars {
                this._Notify("Clipboard is " . StrLen(text) . " chars (max " . this._maxChars . ")")
                return false
            }
            targetId := this._WaitForTargetClick(text)
            if !targetId {
                return false  ; _WaitForTargetClick already told the user why
            }
            this._phase := "typing"
            return this._TypeInto(targetId, text)
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            this._Notify("Error (see error.log)")
            return false
        } finally {
            this._phase := ""
        }
    }

    ; Hotkey condition: the click and Esc hotkeys only fire while a run is in progress.
    IsActive(*) {
        return this._phase != ""
    }

    ; Click hotkey: while waiting it picks the target, while typing it stops.
    OnClick(*) {
        if this._phase = "typing" {
            this._cancelled := true
            return
        }
        this._clicked := true
    }

    ; Esc hotkey: cancels the wait or stops typing.
    Cancel(*) {
        this._cancelled := true
    }

    ; --- Private Methods ---
    _ReadClipboard() {
        try {
            text := A_Clipboard
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            return ""
        }
        text := StrReplace(text, "`r`n", "`n")  ; one Enter per line break
        if SubStr(text, -1) = "`n" {
            text := SubStr(text, 1, -1)  ; NOTE: drop the trailing line break Excel adds, so a single cell doesn't press Enter
        }
        return text
    }

    _WaitForTargetClick(text) {
        StrReplace(text, "`n", "`n", , &enterCount)
        prompt := "Click the field to type " . StrLen(text) . " chars into"
        if enterCount > 0 {
            prompt .= " (presses Enter " . enterCount . "x)"  ; NOTE: warn before multi-line text runs commands
        }
        this._ShowTip(prompt . "`nEsc to cancel (" . this._clickTimeoutSec . "s)")
        ; NOTE: _clicked is set by the *~LButton hotkey (OnClick); a button already held when this starts doesn't count
        deadline := A_TickCount + this._clickTimeoutSec * 1000
        while !this._clicked {
            if this._cancelled {
                this._Notify("Cancelled")
                return 0
            }
            if A_TickCount > deadline {
                this._Notify("Cancelled: no click within " . this._clickTimeoutSec . "s")
                return 0
            }
            Sleep(20)
        }
        try {
            KeyWait("LButton")  ; wait for release so the click reaches the session first
            Sleep(this._focusSettleMs)
            return WinGetID("A")
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            this._Notify("Couldn't find the clicked window (see error.log)")
            return 0
        }
    }

    _TypeInto(targetId, text) {
        total := StrLen(text)
        typed := 0
        Loop Parse text {
            ; NOTE: checked per character so a click, Esc, or focus change stops it mid-text
            if this._cancelled {
                this._Notify("Stopped at " . typed . "/" . total)
                return false
            }
            if !WinActive("ahk_id " . targetId) {
                this._Notify("Stopped at " . typed . "/" . total . ": session window lost focus")
                return false
            }
            if Mod(typed, this._progressEvery) = 0 {
                this._ShowTip("Typing " . typed . "/" . total . "`nClick or Esc to stop")
            }
            if !this._inputSender.TypeText(A_LoopField) {
                this._Notify("Send failed at " . typed . "/" . total . " (see error.log)")
                return false
            }
            typed += 1
        }
        this._Notify("Typed " . total . " chars")
        return true
    }

    _ShowTip(message) {
        SetTimer(this._clearTipCallback, 0)  ; cancel a pending auto-clear so it can't wipe this tip
        ToolTip(message)
    }

    ; NOTE: clears on a one-shot timer rather than Sleep, so the hotkey works again immediately.
    ;       Standalone script, so this SetTimer is the exception to the TimingEngine rule.
    _Notify(message) {
        this._ShowTip(message)
        SetTimer(this._clearTipCallback, -this._notifyMs)
    }

    _ClearTip() {
        ToolTip()
    }

    _LogError(caller, message) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ERROR [" . caller . "]: " . message . "`n"
        try {
            FileAppend(line, A_ScriptDir . "\error.log")  ; NOTE: absolute; the working dir may not be writable
        } catch {
            OutputDebug(line)  ; NOTE: last resort; this runs inside callers' catch blocks so it must never throw
        }
    }
}
