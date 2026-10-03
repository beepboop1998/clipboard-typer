/*
    ClipboardTyper.ahk
    Responsibility: Pastes into windows that block paste by typing the clipboard as real keystrokes:
                    remote-support sessions (BeyondTrust / Bomgar), VM consoles (VMware, Proxmox/noVNC,
                    Hyper-V), server consoles (iLO, iDRAC, KVM-over-IP), and RDP with clipboard turned off.
    Dependencies: none (standalone; single file on purpose so it can be dropped anywhere and run)
    Author: reuben
    Version: see VERSION below
    License: MIT
    Usage: copy text > press Ctrl+Shift+Alt+V (or tray icon > Type clipboard)
           > click the target field > it types.
           Esc cancels while it waits for the click. While typing, any click or Esc stops it.
           Step mode (tray icon > Step mode): each press types the next line into the focused field instead.
           Settings are the constants under "Settings" below. Tray icon > How to use has the details.
*/
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Constants ---
VERSION := "1.1.0"
STEP_MENU_ITEM := "Step mode (one line per press)"
SHOW_TEXT_MENU_ITEM := "Show typed text (step mode)"

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
STEP_MODE := false               ; start in step mode: each press types the next line (toggle any time: tray icon > Step mode)
STEP_SELECT_ALL_FIRST := true    ; step mode: press Ctrl+A before typing, so each line replaces the field's text
STEP_STATUS_MS := 1500           ; step mode: how long the "2/5 typed" status shows
STEP_SHOW_TEXT := false          ; step mode: show the typed line in the status. Off so passwords never appear on screen
                                 ; (turn on any time: tray icon > Show typed text)

; --- Wiring ---
; NOTE: instance names differ from class names; AHK v2 names are case-insensitive, so
;       inputSender := InputSender() would try to overwrite the class and fail at load.
sender := InputSender(SEND_MODE, KEY_DELAY_MS, KEY_PRESS_MS)
typer := ClipboardTyper(sender, MAX_CHARS, CLICK_TIMEOUT_SEC, FOCUS_SETTLE_MS, STEP_MODE, STEP_SELECT_ALL_FIRST, STEP_STATUS_MS, STEP_SHOW_TEXT)

hotkeyCallback := ObjBindMethod(typer, "OnHotkey")
typeCallback := ObjBindMethod(typer, "TypeClipboard")
activeCallback := ObjBindMethod(typer, "IsActive")
clickCallback := ObjBindMethod(typer, "OnClick")
cancelCallback := ObjBindMethod(typer, "Cancel")
if !hotkeyCallback || !typeCallback || !activeCallback || !clickCallback || !cancelCallback {
    throw Error("Failed to bind ClipboardTyper callbacks", "Main")
}
; NOTE: the hotkey follows step mode; the tray's "Type clipboard" always types everything
Hotkey(HOTKEY_TYPE_CLIPBOARD, hotkeyCallback)
; NOTE: click and Esc only act while a run is in progress; otherwise they pass through untouched.
;       The click is never blocked (~) so it still lands in the session.
HotIf(activeCallback)
Hotkey("*~LButton", clickCallback)
Hotkey("*Esc", cancelCallback)
HotIf()

hotkeyLabel := DescribeHotkey(HOTKEY_TYPE_CLIPBOARD)
A_TrayMenu.Add()
A_TrayMenu.Add("Type clipboard", typeCallback)
A_TrayMenu.Add(STEP_MENU_ITEM, OnStepMenu)
if typer.IsStepMode() {
    A_TrayMenu.Check(STEP_MENU_ITEM)
}
A_TrayMenu.Add(SHOW_TEXT_MENU_ITEM, OnShowTextMenu)
if typer.IsShowingStepText() {
    A_TrayMenu.Check(SHOW_TEXT_MENU_ITEM)
}
A_TrayMenu.Add("How to use", ShowHelp)
A_IconTip := IconTipText()
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

; Tray menu > Step mode: flips step mode and keeps the check mark and tray tooltip in sync.
OnStepMenu(itemName, *) {
    if typer.ToggleStepMode() {
        A_TrayMenu.Check(itemName)
    } else {
        A_TrayMenu.Uncheck(itemName)
    }
    A_IconTip := IconTipText()
}

; Tray menu > Show typed text: flips the step-mode text preview and keeps the check mark and tray tooltip in sync.
OnShowTextMenu(itemName, *) {
    if typer.ToggleShowStepText() {
        A_TrayMenu.Check(itemName)
    } else {
        A_TrayMenu.Uncheck(itemName)
    }
    A_IconTip := IconTipText()
}

IconTipText() {
    tip := "Clipboard Typer " . VERSION . " (" . hotkeyLabel . ")"
    if typer.IsStepMode() {
        tip .= " - step mode"
    }
    ; NOTE: shown even with step mode off, so the preview can't be forgotten before step mode is turned back on
    if typer.IsShowingStepText() {
        tip .= (typer.IsStepMode() ? ", " : " - ") . "shows typed text"
    }
    return tip
}

; Tray menu > How to use
ShowHelp(*) {
    MsgBox(
        "1. Copy the text you want typed.`n"
        . "2. Press " . hotkeyLabel . " (or tray icon > Type clipboard).`n"
        . "3. Within " . CLICK_TIMEOUT_SEC . "s, click the field to type into. Typing starts right after.`n`n"
        . "Stop: press Esc or click anywhere. It also stops if another window takes focus.`n"
        . "Line breaks press Enter and tabs press Tab. Limit: " . MAX_CHARS . " characters.`n`n"
        . "Step mode (tray icon > Step mode): each press of " . hotkeyLabel . " types the next line into the field "
        . "that has focus, replacing its text. No click needed. Blank lines are skipped and only the first column "
        . "of a spreadsheet copy is typed. Copy again to restart at line 1. Tray icon > Type clipboard still "
        . "types everything. The status shows only the line number; tick tray icon > Show typed text to see the "
        . "line itself, and leave it off for passwords.`n`n"
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

    ; Sends a key combination such as "^a". Use TypeText for literal text.
    Send(keys) {
        if keys = "" {
            return false  ; guard: nothing to send
        }
        try {
            SetKeyDelay(this._keyDelayMs, this._pressMs)  ; NOTE: per-thread setting, so set it on every call
            SendEvent(keys)
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
    _phase := ""            ; "" idle, "waiting" for the target click, "typing", "stepping" (step mode)
    _clicked := false
    _cancelled := false
    _notifyMs := 2500
    _progressEvery := 25    ; chars between progress tooltip updates
    _clearTipCallback := ""
    _stepMode := false
    _stepSelectAllFirst := true
    _stepStatusMs := 1500
    _lines := []            ; step mode: clipboard lines, rebuilt after each copy
    _index := 1             ; step mode: next line to type
    _needsReload := true    ; step mode: set on every clipboard change
    _clipChangeCallback := ""
    _showStepText := false  ; step mode: show the typed line in the status (off so passwords stay off screen)

    ; --- Constructor ---
    __New(sender, maxChars, clickTimeoutSec, focusSettleMs, stepMode := false, stepSelectAllFirst := true, stepStatusMs := 1500, showStepText := false) {
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
        if !IsNumber(stepStatusMs) || stepStatusMs <= 0 {
            throw Error("STEP_STATUS_MS must be a number above 0", A_ThisFunc)
        }
        this._inputSender := sender
        this._maxChars := maxChars
        this._clickTimeoutSec := clickTimeoutSec
        this._focusSettleMs := focusSettleMs
        this._stepMode := !!stepMode
        this._stepSelectAllFirst := !!stepSelectAllFirst
        this._stepStatusMs := stepStatusMs
        this._showStepText := !!showStepText
        this._clearTipCallback := ObjBindMethod(this, "_ClearTip")
        this._clipChangeCallback := ObjBindMethod(this, "_OnClipboardChange")
        if !this._clipChangeCallback {
            throw Error("Failed to bind _OnClipboardChange", A_ThisFunc)
        }
        OnClipboardChange(this._clipChangeCallback)
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
    ; NOTE: not while stepping, so Esc and clicks still reach the app during a step-mode press
    IsActive(*) {
        return this._phase != "" && this._phase != "stepping"
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

    ; Main hotkey: in step mode types the next line, otherwise the whole clipboard.
    OnHotkey(thisHotkey := "", *) {
        if this._stepMode {
            return this.TypeNextLine(thisHotkey)
        }
        return this.TypeClipboard()
    }

    ; Step mode: types the next clipboard line into the focused field, replacing its text.
    ; No click needed, and it never sends Enter, Tab, Delete or Backspace.
    TypeNextLine(thisHotkey := "") {
        if this._phase != "" {
            return false  ; guard: already running, ignore repeat triggers
        }
        this._phase := "stepping"
        try {
            if !this._WaitForKeysUp(thisHotkey) {
                this._LogError(A_ThisFunc, "Hotkey keys still held after 2s; nothing typed")
                this._Notify("Keys still held; nothing typed. Release them and press again.")
                return false
            }
            if this._needsReload {
                lines := this._ReadLines()
                if !IsObject(lines) {
                    this._Notify("Couldn't read the clipboard (see error.log)")
                    return false  ; NOTE: _needsReload stays set, so the next press retries the read
                }
                this._lines := lines
                this._index := 1
                this._needsReload := false
            }
            total := this._lines.Length
            if total = 0 {
                this._Notify("Clipboard has no text")
                return false
            }
            if this._index > total {
                this._Notify("End of list (" . total . "/" . total . "). Copy the list again to restart.")
                return false
            }
            item := this._lines[this._index]
            ; NOTE: checked before Ctrl+A; stepping has no click/Esc stop, so a huge line must never start
            if StrLen(item) > this._maxChars {
                this._Notify("Line " . this._index . "/" . total . " is " . StrLen(item) . " chars (max " . this._maxChars . "); skipped")
                if total > 1 {
                    this._index += 1  ; NOTE: move past it so the rest of the list stays reachable
                }
                return false
            }
            if this._stepSelectAllFirst && !this._inputSender.Send("^a") {
                this._Notify("Send failed (see error.log)")
                return false
            }
            if !this._inputSender.TypeText(item) {
                this._Notify("Send failed (see error.log)")
                return false  ; NOTE: _index doesn't advance, so the next press retries this line
            }
            this._Notify(this._StepStatus(this._index, total, item), this._stepStatusMs)
            if total > 1 {
                this._index += 1  ; NOTE: a single line retypes on every press, like the full typer
            }
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            this._Notify("Error (see error.log)")
            return false
        } finally {
            this._phase := ""
        }
    }

    ; Tray menu: flips step mode. Turning it on restarts at line 1 of the current clipboard. Returns the new state.
    ToggleStepMode() {
        this._stepMode := !this._stepMode
        if this._stepMode {
            this._needsReload := true
        }
        return this._stepMode
    }

    IsStepMode() {
        return this._stepMode
    }

    ; Tray menu: flips whether the step-mode status shows the typed line. Returns the new state.
    ToggleShowStepText() {
        this._showStepText := !this._showStepText
        return this._showStepText
    }

    IsShowingStepText() {
        return this._showStepText
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

    ; Step mode: reads the clipboard as a list of lines. Returns "" if the clipboard can't be read.
    _ReadLines() {
        try {
            text := A_Clipboard
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message)
            return ""
        }
        return this._SplitLines(text)
    }

    ; One item per line: first column only (a typed Tab would move focus out of the field),
    ; control characters removed (so nothing types as Enter or Backspace), trimmed, blanks dropped.
    _SplitLines(text) {
        if text = "" {
            return []  ; guard: nothing copied
        }
        lines := []
        text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")  ; NOTE: a lone CR is a line break too
        for piece in StrSplit(text, "`n") {
            tabPos := InStr(piece, "`t")
            if tabPos {
                piece := SubStr(piece, 1, tabPos - 1)
            }
            piece := Trim(RegExReplace(piece, "[\x00-\x1F\x7F]"))
            if piece != "" {
                lines.Push(piece)
            }
        }
        return lines
    }

    ; Step mode: waits until the hotkey's keys are up, so held modifiers can't combine with the typed
    ; text and key auto-repeat can't skip items. False if anything is still held after 2s.
    ; NOTE: checks the logical state too. Send reuses a modifier that's logically down instead of
    ;       pressing its own, so a late Ctrl release (e.g. from another tool) would turn ^a into "a".
    _WaitForKeysUp(thisHotkey) {
        keys := ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
        mainKey := RegExReplace(thisHotkey, "[\^!+#*~$<>]")
        if mainKey != "" && !InStr(mainKey, " ") {
            keys.Push(mainKey)
        }
        for key in keys {
            if !KeyWait(key, "T2") || !KeyWait(key, "L T2") {
                return false
            }
        }
        return true
    }

    ; OnClipboardChange: any new copy restarts step mode at line 1 of the new clipboard.
    _OnClipboardChange(*) {
        this._needsReload := true
    }

    ; Step mode status after a press. Shows the typed line only when Show typed text is on, so a
    ; password never appears on screen by default; when off it carries nothing derived from the text.
    _StepStatus(index, total, item) {
        if this._showStepText {
            return index . "/" . total . ": " . item
        }
        return index . "/" . total . " typed"
    }

    _ShowTip(message) {
        SetTimer(this._clearTipCallback, 0)  ; cancel a pending auto-clear so it can't wipe this tip
        ToolTip(message)
    }

    ; NOTE: clears on a one-shot timer rather than Sleep, so the hotkey works again immediately.
    ;       Standalone script, so this SetTimer is the exception to the TimingEngine rule.
    _Notify(message, durationMs := 0) {
        this._ShowTip(message)
        SetTimer(this._clearTipCallback, -(durationMs > 0 ? durationMs : this._notifyMs))
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
