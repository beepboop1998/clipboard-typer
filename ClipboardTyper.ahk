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
DEBUG_LOG := false               ; record what each run did in debug.log next to the script (never the text itself)

; --- Wiring ---
; NOTE: instance names differ from class names; AHK v2 names are case-insensitive, so
;       inputSender := InputSender() or logger := Logger() would try to overwrite the class and fail at load.
;       For the same reason never name a global after a built-in function (e.g. log is the built-in Log).
appLog := Logger(A_ScriptDir, DEBUG_LOG)
InstallKeybdHook()  ; NOTE: unconditional, so GetKeyState(key, "P") reads the physical state for the stuck-key release
sender := InputSender(SEND_MODE, KEY_DELAY_MS, KEY_PRESS_MS, appLog)
typer := ClipboardTyper(sender, appLog, MAX_CHARS, CLICK_TIMEOUT_SEC, FOCUS_SETTLE_MS, STEP_MODE, STEP_SELECT_ALL_FIRST, STEP_STATUS_MS, STEP_SHOW_TEXT)

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
OnExit(OnScriptExit)
OnError(OnUnhandledError)  ; NOTE: last, so an invalid setting above still shows AutoHotkey's error dialog at startup
if SHOW_STARTUP_TIP {
    TrayTip("Press " . hotkeyLabel . " to type the clipboard.`nRight-click the tray icon for help.", "Clipboard Typer " . VERSION . " is running", "Iconi Mute")
}
appLog.Debug("start", DebugStartFields())


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

; OnError: logs an error no try/catch handled, lets go of stuck modifiers, and shows a short notice
; instead of AutoHotkey's dialog. A critical error (mode ExitApp) keeps the dialog, so the exit is explained.
OnUnhandledError(thrown, mode) {
    try {
        if thrown is Error {
            appLog.Error("Unhandled", thrown.Message, thrown)
        } else {
            ; NOTE: Type() only, never the value: a thrown string could hold clipboard text
            appLog.Error("Unhandled", "Non-error value thrown: " . Type(thrown))
        }
        try sender.ReleaseStuckModifiers()
        if mode = "ExitApp" {
            return 0
        }
        try TrayTip("Clipboard Typer hit an error" . (appLog.LastErrorWritten() ? " (see error.log)" : "") . ".", "Clipboard Typer " . VERSION, "Iconx Mute")
        return 1
    } catch {
        return 0  ; NOTE: never fail inside the error handler; AutoHotkey's own dialog takes over
    }
}

; OnExit: a script that ends mid-keystroke (Exit, Reload, shutdown, a newer copy starting) must not
; leave a key held down in the session.
OnScriptExit(reason, *) {
    try sender.ReleaseInFlightKey()
    try sender.ReleaseStuckModifiers()
    try appLog.Debug("exit", "reason=" . reason)
}

; Fields for the debug log's "start" line: versions and settings, nothing from the clipboard.
DebugStartFields() {
    layout := ""
    klid := Buffer(9 * 2, 0)  ; NOTE: the full layout ID, e.g. 00020409 for US-International, not just the language
    try layout := DllCall("GetKeyboardLayoutNameW", "Ptr", klid, "Int") ? StrGet(klid, "UTF-16") : ""
    return "ver=" . VERSION . " ahk=" . A_AhkVersion . " os=" . A_OSVersion . " admin=" . (A_IsAdmin ? 1 : 0)
        . " mode=" . SEND_MODE . " delay=" . KEY_DELAY_MS . " press=" . KEY_PRESS_MS
        . " step=" . (typer.IsStepMode() ? 1 : 0) . " layout=" . layout
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


class Logger {
    ; --- Properties ---
    _logDir := ""
    _debugEnabled := false
    _debugWarned := false      ; the "can't write debug.log" notice shows once per switch-on
    _lastErrorWritten := true
    _maxBytes := 1048576       ; roll a log over to *.old.log above 1 MB

    ; --- Constructor ---
    __New(logDir, debugEnabled := false) {
        if logDir = "" {
            throw Error("Logger needs a folder", A_ThisFunc)
        }
        this._logDir := logDir
        this._debugEnabled := !!debugEnabled
    }

    ; --- Public Methods ---
    ; Appends "yyyy-MM-dd HH:mm:ss ERROR [caller]: message (line N, What)" to error.log. True if written.
    Error(caller, message, err := "") {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ERROR [" . caller . "]: " . message
        if err is Error {
            line .= " (line " . err.Line . ", " . err.What . ")"
        }
        this._lastErrorWritten := this._Write(this.LogPath("error"), line . "`n")
        return this._lastErrorWritten
    }

    ; Appends "yyyy-MM-dd HH:mm:ss.mmm DEBUG event fields" to debug.log when debug logging is on.
    ; Callers pass only lengths, counts, settings and window classes: never clipboard text or window titles.
    Debug(event, fields := "") {
        if !this._debugEnabled {
            return true  ; guard: debug logging is off
        }
        ; NOTE: FormatTime has no millisecond token (mm is minutes), so A_MSec is appended instead
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . "." . A_MSec . " DEBUG " . event . (fields != "" ? " " . fields : "") . "`n"
        if this._Write(this.LogPath("debug"), line) {
            return true
        }
        this._WarnDebugUnwritable()
        return false
    }

    SetDebugEnabled(on) {
        this._debugEnabled := !!on
        if this._debugEnabled {
            this._debugWarned := false
        }
        return this._debugEnabled
    }

    IsDebugEnabled() {
        return this._debugEnabled
    }

    ; Did the last Error() reach error.log? Notices only say "see error.log" when it did.
    LastErrorWritten() {
        return this._lastErrorWritten
    }

    ; kind "error" or "debug": the absolute path of that log.
    LogPath(kind) {
        return this._logDir . "\" . kind . ".log"
    }

    ; --- Private Methods ---
    _Write(path, line) {
        ; NOTE: the Esc and click hotkey threads log too, so rollover + append must not interleave.
        ;       The previous setting is restored rather than turned off: the typing thread must stay
        ;       interruptible by Esc and the click.
        prev := Critical("On")
        try {
            if FileExist(path) && FileGetSize(path) > this._maxBytes {
                try {
                    FileMove(path, RegExReplace(path, "\.log$", ".old.log"), 1)  ; NOTE: 1 = overwrite the previous old log
                } catch Error as e {
                    this._LogError(A_ThisFunc, "rollover failed: " . e.Message)
                }
            }
            FileAppend(line, path, "UTF-8")
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message . ": " . line)
            return false
        } finally {
            Critical(prev)
        }
    }

    _WarnDebugUnwritable() {
        if this._debugWarned {
            return  ; guard: told the user already
        }
        this._debugWarned := true
        try TrayTip("Can't write debug.log next to the script (folder read-only or file locked). "
            . "Move the script to a folder you can write to, such as Documents.", "Clipboard Typer", "Icon! Mute")
    }

    ; Last resort when a log file can't be written; must never throw.
    _LogError(caller, message) {
        OutputDebug(FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ERROR [" . caller . "]: " . message)
    }
}


class InputSender {
    ; --- Properties ---
    _sendPrefix := ""
    _keyDelayMs := 0
    _pressMs := 0
    _logger := ""
    _inFlightVk := 0    ; VK of the one key being typed right now (see _InFlightVkFor), so an exit mid-key can release it
    _modifierKeys := ["LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt", "LWin", "RWin"]

    ; --- Constructor ---
    __New(sendMode, keyDelayMs, pressMs, logWriter := "") {
        if sendMode != "Raw" && sendMode != "Text" {
            throw Error('SEND_MODE must be "Raw" or "Text", not "' . sendMode . '"', A_ThisFunc)
        }
        if !IsNumber(keyDelayMs) || !IsNumber(pressMs) || keyDelayMs < 0 || pressMs < 0 {
            throw Error("KEY_DELAY_MS and KEY_PRESS_MS must be numbers, 0 or more", A_ThisFunc)
        }
        if !IsObject(logWriter) {
            throw Error("Logger is required", A_ThisFunc)
        }
        ; NOTE: {Raw} sends real key codes, which is what remote viewers forward. {Text} sends every
        ;       char as VK_PACKET, which many remote viewers drop. With {Raw} the session's keyboard
        ;       layout must match this PC's, since the remote side turns key codes back into characters.
        this._sendPrefix := "{" . sendMode . "}"
        this._keyDelayMs := keyDelayMs
        this._pressMs := pressMs
        this._logger := logWriter
    }

    ; --- Public Methods ---
    ; Sends text literally at a pace remote consoles can keep up with.
    TypeText(text) {
        if text = "" {
            return false  ; guard: nothing to send
        }
        this._inFlightVk := this._InFlightVkFor(text)
        try {
            SetKeyDelay(this._keyDelayMs, this._pressMs)  ; NOTE: per-thread setting, so set it on every call
            SendEvent(this._sendPrefix . text)
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return false
        } finally {
            this._inFlightVk := 0
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
            this._LogError(A_ThisFunc, e.Message, e)
            return false
        }
    }

    ; Lets go of any Shift, Ctrl, Alt or Win that is down in software but not physically held, so a
    ; stopped or crashed run can't leave everything typed afterwards shifted. Returns how many it released.
    ; NOTE: reading the physical state needs the keyboard hook (InstallKeybdHook at startup).
    ReleaseStuckModifiers() {
        released := []
        try {
            for key in this._modifierKeys {
                if !GetKeyState(key) || GetKeyState(key, "P") {
                    continue  ; up, or really held by the user
                }
                ; NOTE: {Blind} lets the key go up even if AutoHotkey thinks it should stay down; the mask
                ;       key first stops a lone Win or Alt release from opening the Start menu or a menu bar
                mask := (InStr(key, "Win") || InStr(key, "Alt")) ? "{vkE8}" : ""
                SendEvent("{Blind}" . mask . "{" . key . " up}")
                released.Push(key)
            }
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
        }
        for key in released {
            this._logger.Debug("release", "key=" . key)
        }
        return released.Length
    }

    ; OnExit: if the script ends while a character key is down (inside SendEvent's press time), let it go,
    ; so a remote console doesn't auto-repeat it. True if a key was released.
    ReleaseInFlightKey() {
        vk := this._inFlightVk
        if !vk {
            return false  ; guard: no character in flight
        }
        name := Format("vk{:X}", vk)
        try {
            if !GetKeyState(name) {
                return false
            }
            SendEvent("{Blind}{" . name . " up}")
            this._logger.Debug("release", "key=inflight")  ; NOTE: never the VK: it would reveal a typed character
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return false
        }
    }

    ; --- Private Methods ---
    ; VK of a single character being sent: Enter and Tab in both modes, other characters in Raw mode only
    ; (Text mode sends them as VK_PACKET, which needs no release). 0 for longer text.
    _InFlightVkFor(text) {
        if StrLen(text) != 1 {
            return 0  ; guard: only single characters are tracked
        }
        ; NOTE: both modes send `n and `t as real Enter and Tab key presses, held for KEY_PRESS_MS
        if text = "`n" || text = "`r" {
            return 0x0D  ; Enter
        }
        if text = "`t" {
            return 0x09  ; Tab
        }
        if this._sendPrefix != "{Raw}" {
            return 0  ; guard: Text mode
        }
        try {
            return GetKeyVK(text)
        } catch {
            return 0  ; NOTE: a character with no key on this layout is sent as Unicode; nothing to release
        }
    }

    _LogError(caller, message, err := "") {
        return this._logger.Error(caller, message, err)
    }
}


class ClipboardTyper {
    ; --- Properties ---
    _inputSender := ""
    _logger := ""
    _maxChars := 0
    _clickTimeoutSec := 0
    _focusSettleMs := 0
    _phase := ""            ; "" idle, "waiting" for the target click, "typing", "stepping" (step mode)
    _clicked := false
    _cancelled := false
    _stopReason := ""       ; why the current run stopped early: "esc" or "click" (set by the hotkeys)
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
    __New(sender, logWriter, maxChars, clickTimeoutSec, focusSettleMs, stepMode := false, stepSelectAllFirst := true, stepStatusMs := 1500, showStepText := false) {
        if !IsObject(sender) {
            throw Error("InputSender is required", A_ThisFunc)
        }
        if !IsObject(logWriter) {
            throw Error("Logger is required", A_ThisFunc)
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
        this._logger := logWriter
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
        this._stopReason := ""
        try {
            text := this._ReadClipboard()
            if text = "" {
                this._Debug("run", "mode=full result=empty")
                this._Notify("Clipboard has no text")
                return false
            }
            if StrLen(text) > this._maxChars {
                this._Debug("run", "mode=full result=toolong len=" . StrLen(text))
                this._Notify("Clipboard is " . StrLen(text) . " chars (max " . this._maxChars . ")")
                return false
            }
            StrReplace(text, "`n", "`n", , &enterCount)
            this._Debug("run", "mode=full len=" . StrLen(text) . " enters=" . enterCount)
            targetId := this._WaitForTargetClick(text)
            if !targetId {
                return false  ; _WaitForTargetClick already told the user why
            }
            this._LogTarget(targetId)
            this._ReinstallHooks()
            this._phase := "typing"
            return this._TypeInto(targetId, text)
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Error" . this._ErrorHint())
            return false
        } finally {
            this._inputSender.ReleaseStuckModifiers()
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
            if this._stopReason = "" {
                this._stopReason := "click"
            }
            this._cancelled := true
            return
        }
        this._clicked := true
    }

    ; Esc hotkey: cancels the wait or stops typing.
    Cancel(*) {
        if this._stopReason = "" {
            this._stopReason := "esc"
        }
        this._cancelled := true
        this._Debug("esc", "phase=" . this._phase)  ; NOTE: shows whether Esc reached the script at all
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
                this._Debug("step", "result=keysheld")
                this._Notify("Keys still held; nothing typed. Release them and press again.")
                return false
            }
            if this._needsReload {
                lines := this._ReadLines()
                if !IsObject(lines) {
                    this._Debug("step", "result=readfail")
                    this._Notify("Couldn't read the clipboard" . this._ErrorHint())
                    return false  ; NOTE: _needsReload stays set, so the next press retries the read
                }
                this._lines := lines
                this._index := 1
                this._needsReload := false
            }
            total := this._lines.Length
            if total = 0 {
                this._Debug("step", "result=empty")
                this._Notify("Clipboard has no text")
                return false
            }
            if this._index > total {
                this._Debug("step", "line=" . this._index . "/" . total . " result=end")
                this._Notify("End of list (" . total . "/" . total . "). Copy the list again to restart.")
                return false
            }
            item := this._lines[this._index]
            ; NOTE: checked before Ctrl+A; stepping has no click/Esc stop, so a huge line must never start
            if StrLen(item) > this._maxChars {
                this._Debug("step", "line=" . this._index . "/" . total . " len=" . StrLen(item) . " result=toolong")
                this._Notify("Line " . this._index . "/" . total . " is " . StrLen(item) . " chars (max " . this._maxChars . "); skipped")
                if total > 1 {
                    this._index += 1  ; NOTE: move past it so the rest of the list stays reachable
                }
                return false
            }
            if (this._stepSelectAllFirst && !this._inputSender.Send("^a")) || !this._inputSender.TypeText(item) {
                this._Debug("step", "line=" . this._index . "/" . total . " len=" . StrLen(item) . " result=fail")
                this._Notify("Send failed" . this._ErrorHint())
                return false  ; NOTE: _index doesn't advance, so the next press retries this line
            }
            this._Debug("step", "line=" . this._index . "/" . total . " len=" . StrLen(item) . " result=typed")
            this._Notify(this._StepStatus(this._index, total, item), this._stepStatusMs)
            if total > 1 {
                this._index += 1  ; NOTE: a single line retypes on every press, like the full typer
            }
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Error" . this._ErrorHint())
            return false
        } finally {
            this._inputSender.ReleaseStuckModifiers()
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
            this._LogError(A_ThisFunc, e.Message, e)
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
                this._Debug("wait", "result=esc")
                this._Notify("Cancelled")
                return 0
            }
            if A_TickCount > deadline {
                this._Debug("wait", "result=timeout")
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
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Couldn't find the clicked window" . this._ErrorHint())
            return 0
        }
    }

    _TypeInto(targetId, text) {
        total := StrLen(text)
        typed := 0
        stop := "done"
        Loop Parse text {
            ; NOTE: checked per character so a click, Esc, or focus change stops it mid-text
            if this._cancelled {
                stop := this._stopReason != "" ? this._stopReason : "esc"
                this._Notify("Stopped at " . typed . "/" . total)
                break
            }
            if !WinActive("ahk_id " . targetId) {
                stop := "focus"
                this._Notify("Stopped at " . typed . "/" . total . ": session window lost focus")
                break
            }
            if Mod(typed, this._progressEvery) = 0 {
                this._ShowTip("Typing " . typed . "/" . total . "`nClick or Esc to stop")
            }
            if !this._inputSender.TypeText(A_LoopField) {
                stop := "sendfail"
                this._Notify("Send failed at " . typed . "/" . total . this._ErrorHint())
                break
            }
            typed += 1
        }
        this._Debug("typed", typed . "/" . total . " stop=" . stop)
        if stop != "done" {
            return false
        }
        this._Notify("Typed " . total . " chars")
        return true
    }

    ; Debug log: the program and window class of the target, never its title.
    _LogTarget(targetId) {
        if !this._logger.IsDebugEnabled() {
            return  ; guard: nothing to record
        }
        exe := ""
        cls := ""
        try exe := WinGetProcessName("ahk_id " . targetId)
        try cls := WinGetClass("ahk_id " . targetId)
        this._Debug("target", "exe=" . exe . " class=" . cls)
    }

    ; Re-registers the keyboard and mouse hooks just before typing, so they get keys before any hook a
    ; remote viewer installed while it had focus (a viewer's hook can swallow Esc). False if skipped.
    _ReinstallHooks() {
        for key in ["LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt", "LWin", "RWin"] {
            if GetKeyState(key) {
                ; NOTE: a forced reinstall can lose track of a key that is down, which would then look stuck
                this._Debug("hook", "reinstall=skip")
                return false
            }
        }
        this._Debug("hook", "reinstall=requested")  ; NOTE: logged first; these return nothing and don't throw
        try {
            InstallKeybdHook(true, true)
            InstallMouseHook(true, true)
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return false
        }
    }

    ; " (see error.log)" when the last error reached error.log, otherwise nothing.
    _ErrorHint() {
        return this._logger.LastErrorWritten() ? " (see error.log)" : ""
    }

    ; Step mode: reads the clipboard as a list of lines. Returns "" if the clipboard can't be read.
    _ReadLines() {
        try {
            text := A_Clipboard
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
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

    _LogError(caller, message, err := "") {
        return this._logger.Error(caller, message, err)
    }

    _Debug(event, fields := "") {
        return this._logger.Debug(event, fields)
    }
}
