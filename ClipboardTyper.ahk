/*
    ClipboardTyper.ahk
    Responsibility: Pastes into windows that block paste by typing the clipboard as real keystrokes:
                    remote-support sessions (BeyondTrust / Bomgar), VM consoles (VMware, Proxmox/noVNC,
                    Hyper-V), server consoles (iLO, iDRAC, KVM-over-IP), and RDP with clipboard turned off.
    Dependencies: none (standalone; single file on purpose so it can be dropped anywhere and run)
    Author: reuben
    Version: see VERSION below
    License: MIT
    Usage: copy text > press Ctrl+Shift+Alt+V (or double-click the tray icon)
           > click the target field > it types.
           Esc cancels while it waits for the click. While typing, any click or Esc stops it.
           Step mode (tray icon > Step mode): each press types the next line into the focused field instead.
           Settings are the constants under "Settings" below (tray icon > Troubleshooting > Edit script
           settings, then Reload script). Tray icon > How to use has the details.
*/
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Constants ---
VERSION := "1.2.0"

; --- Settings (edit these) ---
HOTKEY_TYPE_CLIPBOARD := "^+!v"  ; Ctrl+Shift+Alt+V  (^ Ctrl, + Shift, ! Alt, # Win)
SEND_MODE := "Raw"               ; "Raw": real key presses; works in most remote consoles, needs the same keyboard layout on both ends
                                 ; "Text": Unicode characters; layout-independent, but many remote viewers ignore them
KEY_DELAY_MS := 20               ; starting speed: pause after each keystroke, 0-1000 ms (change any time: tray icon > Speed)
KEY_PRESS_MS := 10               ; starting speed: how long each key is held down, 0-1000 ms
MAX_CHARS := 2000                ; refuse anything longer than this
CLICK_TIMEOUT_SEC := 10          ; how long to wait for the click on the target field
FOCUS_SETTLE_MS := 300           ; give the remote field time to take focus after the click
SHOW_STARTUP_TIP := true         ; notification on launch; set to false if this runs at Windows startup
STEP_MODE := false               ; start in step mode: each press types the next line (toggle any time: tray icon > Step mode)
STEP_SELECT_ALL_FIRST := true    ; step mode: press Ctrl+A before typing, so each line replaces the field's text
                                 ; (switch any time: tray icon > Step options)
STEP_STATUS_MS := 1500           ; step mode: how long the "2/5 typed" status shows
STEP_SHOW_TEXT := false          ; step mode: show the typed line in the status. Off so passwords never appear on screen
                                 ; (turn on any time: tray icon > Step options > Show typed text)
DEBUG_LOG := false               ; start with debug logging on (tray: Troubleshooting > Debug logging): what each run did,
                                 ; in debug.log next to the script; never the text itself
AFTER_TYPING := ""               ; "", "Enter" or "Tab": key pressed after a run that typed everything (tray icon > After typing)
STOP_ON_KEYPRESS := true         ; a key you press while it types stops it, and the key is blocked so it can't mix into the text
BLOCKED_TARGET_CLASSES := "Progman,WorkerW,Shell_TrayWnd,Shell_SecondaryTrayWnd,Windows.UI.Core.CoreWindow"
                                 ; never type into these window classes: desktop, taskbars, Start/Search
                                 ; (Windows.UI.Core.CoreWindow only when it belongs to Start or Search)
REQUIRE_CLICKED_FOCUS := true    ; refuse when the window you clicked didn't take focus; set to false if a viewer is wrongly refused
SAVE_SETTINGS := true            ; remember the tray's Speed and After typing in <script name>.ini next to the script;
                                 ; a saved choice overrides KEY_DELAY_MS, KEY_PRESS_MS and AFTER_TYPING (false: never read or write it)

; --- Wiring ---
; NOTE: instance names differ from class names; AHK v2 names are case-insensitive, so
;       inputSender := InputSender(), logger := Logger() or settingsStore := SettingsStore() would try to overwrite
;       the class and fail at load.
;       For the same reason never name a global after a built-in function (e.g. log is the built-in Log).
appLog := Logger(A_ScriptDir, DEBUG_LOG)
InstallKeybdHook()  ; NOTE: unconditional, so GetKeyState(key, "P") reads the physical state for the stuck-key release
sender := InputSender(SEND_MODE, KEY_DELAY_MS, KEY_PRESS_MS, appLog)
typer := ClipboardTyper(sender, appLog, MAX_CHARS, CLICK_TIMEOUT_SEC, FOCUS_SETTLE_MS, STEP_MODE, STEP_SELECT_ALL_FIRST, STEP_STATUS_MS, STEP_SHOW_TEXT,
    AFTER_TYPING, BLOCKED_TARGET_CLASSES, STOP_ON_KEYPRESS, REQUIRE_CLICKED_FOCUS)
scriptDefaults := {delay: sender.GetDelayMs(), press: sender.GetPressMs(), after: typer.GetAfterTyping()}  ; NOTE: before saved choices apply
store := SettingsStore(SettingsPath(), appLog, SAVE_SETTINGS)
ApplySavedSettings(store, sender, typer, appLog)  ; NOTE: also tells the store whether saved choices are in use (debug source=)

hotkeyCallback := ObjBindMethod(typer, "OnHotkey")
activeCallback := ObjBindMethod(typer, "IsActive")
clickCallback := ObjBindMethod(typer, "OnClick")
cancelCallback := ObjBindMethod(typer, "Cancel")
if !hotkeyCallback || !activeCallback || !clickCallback || !cancelCallback {
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
tray := TrayMenu(A_TrayMenu, typer, sender, appLog, store, scriptDefaults, ShowHelp, DebugStartFields, VERSION, hotkeyLabel)
tray.Build()
OnExit(OnScriptExit)
OnError(OnUnhandledError)  ; NOTE: last, so an invalid setting above still shows AutoHotkey's error dialog at startup
if SHOW_STARTUP_TIP {
    TrayTip("Press " . hotkeyLabel . " or double-click the tray icon to type the clipboard.`nRight-click the tray icon for options and help.", "Clipboard Typer " . VERSION . " is running", "Iconi Mute")
}
ShowAfterTypingReminder()
if !appLog.Debug("start", DebugStartFields()) {
    appLog.SetDebugEnabled(false)  ; NOTE: as in Troubleshooting > Debug logging: unwritable, so untick it (the Logger said why)
    tray.Refresh()
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
        . " mode=" . SEND_MODE . " delay=" . sender.GetDelayMs() . " press=" . sender.GetPressMs() . " source=" . (store.IsInEffect() ? "ini" : "script")
        . " step=" . (typer.IsStepMode() ? 1 : 0) . " after=" . (typer.GetAfterTyping() = "" ? "nothing" : typer.GetAfterTyping())
        . " layout=" . layout
}

; <script name>.ini next to the script, e.g. ClipboardTyper.ini; test copies and Unit.ahk each get their own.
SettingsPath() {
    return A_ScriptDir . "\" . RegExReplace(A_ScriptName, "i)\.ahk$") . ".ini"
}

; Applies the Speed and After typing saved from the tray. A value that isn't valid is logged and the script's
; setting is kept. Returns "ini" when a saved choice was applied, otherwise "script".
ApplySavedSettings(savedStore, keySender, clipTyper, logWriter) {
    if !savedStore.IsEnabled() {
        logWriter.Debug("ini", "read=disabled")
        return "script"  ; guard: SAVE_SETTINGS is off
    }
    notSaved := "<not saved>"  ; NOTE: a sentinel, since an empty value is a value (and invalid)
    delay := Trim(savedStore.Read("KeyDelayMs", notSaved))
    press := Trim(savedStore.Read("KeyPressMs", notSaved))
    after := Trim(savedStore.Read("AfterTyping", notSaved))
    if delay = notSaved && press = notSaved && after = notSaved {
        logWriter.Debug("ini", "read=missing")
        return "script"
    }
    applied := false
    invalid := []
    if delay != notSaved || press != notSaved {
        if keySender.SetDelays(delay != notSaved ? delay : keySender.GetDelayMs(), press != notSaved ? press : keySender.GetPressMs()) {
            applied := true
        } else {
            invalid.Push("KeyDelayMs/KeyPressMs")
            logWriter.Error(A_ThisFunc, 'Ignored saved speed "' . delay . '/' . press . '"; using the script' . "'s")
        }
    }
    if after != notSaved {
        ; NOTE: "Nothing" is written for no key, so it can override AFTER_TYPING := "Enter"; an empty value is invalid
        if (after = "Nothing" && clipTyper.SetAfterTyping("")) || (after != "" && after != "Nothing" && clipTyper.SetAfterTyping(after)) {
            applied := true
        } else {
            invalid.Push("AfterTyping")
            logWriter.Error(A_ThisFunc, 'Ignored saved AfterTyping "' . after . '"; using the script' . "'s")
        }
    }
    joined := ""
    for name in invalid {
        joined .= (A_Index > 1 ? "," : "") . name
    }
    logWriter.Debug("ini", "read=" . (joined = "" ? "ok" : "invalid:" . joined))
    savedStore.MarkInEffect(applied)
    return applied ? "ini" : "script"
}

; At startup: an After typing key that is switched on is announced even with SHOW_STARTUP_TIP off,
; since a forgotten Enter can run a half-checked command. Shown as a notification and as a tooltip,
; because Focus assist can hide notifications while a full-screen session has focus.
ShowAfterTypingReminder() {
    key := typer.GetAfterTyping()
    if key = "" {
        return  ; guard: nothing to remind about
    }
    message := "After typing is set to press " . key . ". Change it: tray icon > After typing."
    try TrayTip(message, "Clipboard Typer " . VERSION, "Icon! Mute")
    typer.ShowNotice(message, 5000)
}

; Tray menu > How to use
ShowHelp(*) {
    MsgBox(
        "1. Copy the text you want typed.`n"
        . "2. Press " . hotkeyLabel . " or double-click the tray icon.`n"
        . "3. Within " . CLICK_TIMEOUT_SEC . "s, click the field to type into. Typing starts right after.`n`n"
        . "Stop: press Esc" . (STOP_ON_KEYPRESS ? ", click anywhere, or press any key" : " or click anywhere") . ". It also stops if another window takes focus.`n"
        . "Line breaks press Enter and tabs press Tab. Limit: " . MAX_CHARS . " characters. "
        . "It won't type into the desktop, the taskbar or Start.`n"
        . "Tray icon > After typing: press Enter or Tab once everything is typed (never after a stopped run).`n`n"
        . "Step mode (tray icon > Step mode): each press of " . hotkeyLabel . " types the next line into the field "
        . "that has focus, replacing its text. No click needed. Blank lines are skipped and only the first column "
        . "of a spreadsheet copy is typed. Copy again to restart at line 1. Tray icon > Type clipboard and double-clicking "
        . "the tray icon still type everything. The status shows only the line number; tick tray icon > Step options > Show typed text "
        . "to see the line itself, and leave it off for passwords. Esc" . (STOP_ON_KEYPRESS ? ", a click or a key press" : " or a click") . " stops a line; "
        . "the next press types it again, without the After typing key.`n`n"
        . "Wrong symbols? The remote keyboard layout differs from yours; try SEND_MODE := `"Text`".`n"
        . "Characters dropped? Tray icon > Speed > Slow (or Very slow).`n"
        . (SAVE_SETTINGS ? "Speed and After typing chosen in the tray are saved and override the script's settings "
            . "(Troubleshooting > Forget saved settings).`n"
            : "Speed and After typing chosen in the tray last until the script restarts (SAVE_SETTINGS is off).`n")
        . "Settings are the constants near the top of the script: tray icon > Troubleshooting > Edit script settings, "
        . "save, then Troubleshooting > Reload script. Errors go to error.log next to the script; "
        . "Troubleshooting > Debug logging records more in debug.log.",
        "Clipboard Typer " . VERSION . ": How to use", "Iconi")
}


class TrayMenu {
    ; --- Labels ---
    static TYPE_ITEM := "Type clipboard"
    static STEP_ITEM := "Step mode (one line per press)"
    static SPEED_PREFIX := "Speed: "         ; the Speed item's label is this plus the current speed
    static CUSTOM_SPEED_ITEM := "Custom..."
    ; NOTE: labelled by delay, not a rate: each pause is rounded up to the system timer step (10-16 ms)
    ;       and Text mode ignores the press time, so a fixed characters-per-second figure would be wrong
    static SPEED_PRESETS := [
        {name: "Fast", delay: 10, press: 5},
        {name: "Normal", delay: 20, press: 10},
        {name: "Slow", delay: 40, press: 20},
        {name: "Very slow", delay: 80, press: 30}]
    static AFTER_PREFIX := "After typing: "  ; the After typing item's label is this plus the current choice
    static AFTER_CHOICES := [
        {key: "", item: "Nothing", shown: "nothing"},
        {key: "Enter", item: "Press Enter", shown: "Enter"},
        {key: "Tab", item: "Press Tab", shown: "Tab"}]
    static STEP_OPTIONS_ITEM := "Step options"
    static SHOW_TEXT_ITEM := "Show typed text"
    static SELECT_ALL_ITEM := "Select field text first (Ctrl+A)"
    static TROUBLE_ITEM := "Troubleshooting"
    static DEBUG_ITEM := "Debug logging"
    static OPEN_LOG_ITEM := "Open log folder"
    static EDIT_ITEM := "Edit script settings"
    static RELOAD_ITEM := "Reload script"
    static FORGET_ITEM := "Forget saved settings"
    static HELP_ITEM := "How to use"
    static EXIT_ITEM := "Exit"

    ; --- Properties ---
    _menu := ""             ; the tray menu (A_TrayMenu), passed in
    _typer := ""
    _sender := ""
    _logger := ""
    _helpFn := ""
    _startFieldsFn := ""    ; returns the fields of the debug log's "start" line
    _version := ""
    _hotkeyLabel := ""
    _speedMenu := ""
    _speedItemName := ""    ; the Speed item's current label
    _speedItemPos := ""     ; the Speed item's position ("4&"): Rename by position can't miss after a failed rename
    _menuWarned := false    ; the "couldn't update the menu" notice shows once
    _afterMenu := ""
    _afterItemName := ""    ; the After typing item's current label
    _afterItemPos := ""     ; the After typing item's position ("5&")
    _store := ""
    _defaults := ""         ; the script's own speed and After typing, for Forget saved settings
    _saveWarned := false    ; the "couldn't save" notice shows once
    _stepMenu := ""
    _troubleMenu := ""
    _callbacks := ""        ; method name -> callback bound to this, bound once

    ; --- Constructor ---
    ; NOTE: the first parameter is neither "menu" nor "trayMenu": names ignore case, so either would hide
    ;       the Menu class or this TrayMenu class inside the constructor
    __New(rootMenu, typer, sender, logWriter, savedStore, defaults, helpFn, startFieldsFn, version, hotkeyLabel) {
        if !IsObject(savedStore) || !IsObject(defaults) {
            throw Error("TrayMenu needs the SettingsStore and the script's defaults", A_ThisFunc)
        }
        if !IsObject(rootMenu) || !IsObject(typer) || !IsObject(sender) || !IsObject(logWriter) {
            throw Error("TrayMenu needs the tray menu, the typer, the InputSender and a Logger", A_ThisFunc)
        }
        if !HasMethod(helpFn) || !HasMethod(startFieldsFn) {
            throw Error("TrayMenu needs the help and debug-start functions", A_ThisFunc)
        }
        this._menu := rootMenu
        this._typer := typer
        this._sender := sender
        this._logger := logWriter
        this._helpFn := helpFn
        this._startFieldsFn := startFieldsFn
        this._version := version
        this._hotkeyLabel := hotkeyLabel
        this._store := savedStore
        this._defaults := defaults
        this._speedMenu := Menu()
        this._afterMenu := Menu()
        this._stepMenu := Menu()
        this._troubleMenu := Menu()
        this._callbacks := Map()
        for name in ["OnTypeClipboard", "OnStepMode", "OnSpeedPreset", "OnCustomSpeed", "OnAfterTyping", "OnShowText",
            "OnSelectAll", "OnDebugLogging", "OnOpenLogFolder", "OnEditSettings", "OnReload", "OnForgetSettings", "OnHelp", "OnExitItem"] {
            callback := ObjBindMethod(this, name)
            if !callback {
                throw Error("Failed to bind " . name, A_ThisFunc)
            }
            this._callbacks[name] := callback
        }
    }

    ; --- Public Methods ---
    ; Replaces AutoHotkey's own tray items (Open, Window Spy, Suspend, ...) with the app's menu.
    Build() {
        cb := this._callbacks
        this._speedMenu.Delete()
        for preset in TrayMenu.SPEED_PRESETS {
            this._speedMenu.Add(this._PresetLabel(preset), cb["OnSpeedPreset"], "Radio")
        }
        this._speedMenu.Add()
        this._speedMenu.Add(TrayMenu.CUSTOM_SPEED_ITEM, cb["OnCustomSpeed"], "Radio")
        this._afterMenu.Delete()
        for choice in TrayMenu.AFTER_CHOICES {
            this._afterMenu.Add(choice.item, cb["OnAfterTyping"], "Radio")
        }
        this._stepMenu.Delete()
        this._stepMenu.Add(TrayMenu.SHOW_TEXT_ITEM, cb["OnShowText"])
        this._stepMenu.Add(TrayMenu.SELECT_ALL_ITEM, cb["OnSelectAll"])
        this._troubleMenu.Delete()
        this._troubleMenu.Add(TrayMenu.DEBUG_ITEM, cb["OnDebugLogging"])
        this._troubleMenu.Add()
        this._troubleMenu.Add(TrayMenu.OPEN_LOG_ITEM, cb["OnOpenLogFolder"])
        this._troubleMenu.Add(TrayMenu.EDIT_ITEM, cb["OnEditSettings"])
        this._troubleMenu.Add(TrayMenu.RELOAD_ITEM, cb["OnReload"])
        this._troubleMenu.Add()
        this._troubleMenu.Add(TrayMenu.FORGET_ITEM, cb["OnForgetSettings"])
        if !this._store.IsEnabled() {
            this._troubleMenu.Disable(TrayMenu.FORGET_ITEM)  ; NOTE: SAVE_SETTINGS is off, so nothing is saved
        }
        m := this._menu
        m.Delete()
        m.Add(TrayMenu.TYPE_ITEM, cb["OnTypeClipboard"])
        m.Add(TrayMenu.STEP_ITEM, cb["OnStepMode"])
        m.Add()
        this._speedItemName := this._SpeedLabel()
        m.Add(this._speedItemName, this._speedMenu)
        this._speedItemPos := "4&"  ; NOTE: after Type clipboard, Step mode and the separator
        this._afterItemName := this._AfterLabel()
        m.Add(this._afterItemName, this._afterMenu)
        this._afterItemPos := "5&"  ; NOTE: right after Speed
        m.Add(TrayMenu.STEP_OPTIONS_ITEM, this._stepMenu)
        m.Add(TrayMenu.TROUBLE_ITEM, this._troubleMenu)
        m.Add()
        m.Add(TrayMenu.HELP_ITEM, cb["OnHelp"])
        m.Add(TrayMenu.EXIT_ITEM, cb["OnExitItem"])
        m.Default := TrayMenu.TYPE_ITEM  ; NOTE: double-clicking the tray icon runs it (ClickCount stays 2)
        this.Refresh()
    }

    ; Brings the check marks and the tray tooltip in line with the current settings.
    Refresh() {
        try {
            this._SetCheck(this._menu, TrayMenu.STEP_ITEM, this._typer.IsStepMode())
            this._SetCheck(this._stepMenu, TrayMenu.SHOW_TEXT_ITEM, this._typer.IsShowingStepText())
            this._SetCheck(this._stepMenu, TrayMenu.SELECT_ALL_ITEM, this._typer.IsSelectingAllFirst())
            this._SetCheck(this._troubleMenu, TrayMenu.DEBUG_ITEM, this._logger.IsDebugEnabled())
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
        }
        this._SyncSpeed()
        this._SyncAfterTyping()
        A_IconTip := this._TipText()
    }

    ; Tray > Type clipboard (also the double-click action): always types everything, even in step mode.
    OnTypeClipboard(*) {
        return this._typer.TypeClipboard()
    }

    OnStepMode(*) {
        if this._typer.ToggleStepMode() && this._typer.GetAfterTyping() != "" {
            this._typer.ShowNotice("Step mode: each press types a line, then presses " . this._typer.GetAfterTyping() . ".", 4000)
        }
        this.Refresh()
    }

    ; Tray > After typing > Nothing / Press Enter / Press Tab. Applies from the next run.
    OnAfterTyping(itemName, *) {
        for choice in TrayMenu.AFTER_CHOICES {
            if choice.item = itemName {
                if this._typer.SetAfterTyping(choice.key) {
                    this._Save("AfterTyping", choice.key = "" ? "Nothing" : choice.key)
                }
                if choice.key != "" && this._typer.IsStepMode() {
                    this._typer.ShowNotice("Step mode: each press types a line, then presses " . choice.key . ".", 4000)
                }
                break
            }
        }
        this.Refresh()
    }

    ; Tray > Speed > a preset. Applies from the next run (opening the tray menu takes focus, which stops a run).
    OnSpeedPreset(itemName, *) {
        for preset in TrayMenu.SPEED_PRESETS {
            if this._PresetLabel(preset) = itemName {
                if this._sender.SetDelays(preset.delay, preset.press) {
                    this._SaveSpeed()
                }
                break
            }
        }
        this.Refresh()
    }

    ; Tray > Speed > Custom...: asks for the pause between keys. Cancel changes nothing.
    OnCustomSpeed(*) {
        if this._RefuseWhileBusy(TrayMenu.CUSTOM_SPEED_ITEM) {
            this.Refresh()  ; NOTE: puts the radio dot back where it was
            return false
        }
        try {
            box := InputBox("Milliseconds between keys (0-1000). Now: " . this._sender.GetDelayMs()
                . "`nHigher is slower; raise it if the session drops characters.", "Clipboard Typer: custom speed", "w320 h150", this._sender.GetDelayMs())
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notice("Couldn't open the custom speed box" . this._ErrorHint() . ".")
            this.Refresh()
            return false
        }
        if box.Result != "OK" {
            this.Refresh()  ; NOTE: Cancel or timeout; also puts the radio dot back where it was
            return false
        }
        if !this._ApplyCustomDelay(box.Value) {
            try MsgBox("Enter a whole number of milliseconds from 0 to 1000. The speed wasn't changed.", "Clipboard Typer: custom speed", "Icon!")
            return false
        }
        return true
    }

    OnShowText(*) {
        this._typer.ToggleShowStepText()
        this.Refresh()
    }

    OnSelectAll(*) {
        this._typer.ToggleSelectAllFirst()
        this.Refresh()
    }

    ; Tray > Troubleshooting > Debug logging. Turning it on starts the log with a "start" line; if that
    ; can't be written it turns itself off again (the Logger has already said why).
    OnDebugLogging(*) {
        if this._logger.IsDebugEnabled() {
            this._logger.SetDebugEnabled(false)
        } else {
            this._logger.SetDebugEnabled(true)
            if !this._logger.Debug("start", this._startFieldsFn.Call()) {
                this._logger.SetDebugEnabled(false)
            }
        }
        this.Refresh()
    }

    ; Tray > Troubleshooting > Open log folder: Explorer with the newest kind of log selected.
    OnOpenLogFolder(*) {
        path := ""
        for kind in ["debug", "error"] {
            if FileExist(this._logger.LogPath(kind)) {
                path := this._logger.LogPath(kind)
                break
            }
        }
        if path = "" {
            this._Notice("No log yet. Errors go to error.log; tick Troubleshooting > Debug logging for more.")
            return false
        }
        try {
            Run('explorer.exe /select,"' . path . '"')
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notice("Couldn't open the log folder" . this._ErrorHint() . ".")
            return false
        }
    }

    OnEditSettings(*) {
        try {
            Edit()
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notice("Couldn't open the script for editing" . this._ErrorHint() . ".")
            return false
        }
    }

    ; Tray > Troubleshooting > Reload script: picks up edited settings. A successful reload ends this
    ; copy during the Sleep; reaching the line after it means the new copy didn't start.
    OnReload(*) {
        try {
            Reload()
            Sleep(1000)
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
        }
        this._Notice("Couldn't reload: the edited script has an error. Fix it and try again.")
        return false
    }

    ; Tray > Troubleshooting > Forget saved settings: deletes the .ini and goes back to the script's own
    ; Speed and After typing, for this session and every restart.
    OnForgetSettings(*) {
        forgotten := this._store.Forget()
        this._sender.SetDelays(this._defaults.delay, this._defaults.press)
        this._typer.SetAfterTyping(this._defaults.after)
        this.Refresh()
        if forgotten {
            this._Notice("Saved settings forgotten; using the script's Speed and After typing.")
        } else {
            this._Notice("Couldn't delete the saved settings file; they'll come back on restart" . this._ErrorHint() . ".")
        }
        return forgotten
    }

    OnHelp(*) {
        if this._RefuseWhileBusy(TrayMenu.HELP_ITEM) {
            return false
        }
        return this._helpFn.Call()
    }

    ; A dialog opened during a run would sit on top of the paused run: the Esc hotkey would swallow its Esc
    ; and the key guard would block its keys. So dialogs wait until the run ends. True when refused.
    _RefuseWhileBusy(itemName) {
        if !this._typer.IsBusy() {
            return false
        }
        this._Notice("Stop the current run (Esc) or let it finish, then choose " . itemName . " again.")
        return true
    }

    OnExitItem(*) {
        ExitApp()
    }

    ; --- Private Methods ---
    ; The tray tooltip: name, hotkey, and any setting that isn't at its default. The safety-relevant
    ; states come first, since Windows shows only 127 characters.
    _TipText() {
        states := []
        if this._typer.IsStepMode() {
            states.Push("step mode")
        }
        ; NOTE: shown even with step mode off, so the preview can't be forgotten before step mode is turned back on
        if this._typer.IsShowingStepText() {
            states.Push("shows typed text")
        }
        if this._typer.GetAfterTyping() != "" {
            states.Push("then " . this._typer.GetAfterTyping())
        }
        if this._logger.IsDebugEnabled() {
            states.Push("debug logging")
        }
        speed := this._SpeedName()
        if speed != "Normal" {
            states.Push(StrLower(speed))
        }
        tip := "Clipboard Typer " . this._version . " (" . this._hotkeyLabel . ")"
        for i, state in states {
            tip .= (i = 1 ? " - " : ", ") . state
        }
        return SubStr(tip, 1, 127)
    }

    ; Custom speed: a whole number of ms from 0 to 1000. A value equal to a preset's delay applies that
    ; whole preset (press time too), so the ticked item always describes the real speed. True if applied.
    _ApplyCustomDelay(value) {
        if !this._sender.IsValidDelay(value) {
            return false  ; guard: not a valid delay (the same rule as KEY_DELAY_MS)
        }
        value := Integer(Trim(value))
        for preset in TrayMenu.SPEED_PRESETS {
            if preset.delay = value {
                applied := this._sender.SetDelays(preset.delay, preset.press)
                if applied {
                    this._SaveSpeed()
                }
                this.Refresh()
                return applied
            }
        }
        applied := this._sender.SetDelays(value, this._sender.GetPressMs())
        if applied {
            this._SaveSpeed()
        }
        this.Refresh()
        return applied
    }

    ; The preset matching the current delay and press time, or "" for a custom speed.
    _CurrentPreset() {
        for preset in TrayMenu.SPEED_PRESETS {
            if preset.delay = this._sender.GetDelayMs() && preset.press = this._sender.GetPressMs() {
                return preset
            }
        }
        return ""
    }

    _SpeedName() {
        preset := this._CurrentPreset()
        return IsObject(preset) ? preset.name : "Custom (" . this._sender.GetDelayMs() . " ms)"
    }

    _SpeedLabel() {
        return TrayMenu.SPEED_PREFIX . this._SpeedName()
    }

    _PresetLabel(preset) {
        return preset.name . " (" . preset.delay . " ms)"
    }

    ; Ticks exactly one Speed item (a preset only when both delay and press match it, otherwise Custom)
    ; and renames the Speed item to show the current speed.
    _SyncSpeed() {
        current := this._CurrentPreset()
        try {
            for preset in TrayMenu.SPEED_PRESETS {
                this._SetCheck(this._speedMenu, this._PresetLabel(preset), IsObject(current) && preset.name = current.name)
            }
            this._SetCheck(this._speedMenu, TrayMenu.CUSTOM_SPEED_ITEM, !IsObject(current))
            label := this._SpeedLabel()
            if this._speedItemPos != "" && label != this._speedItemName {
                this._menu.Rename(this._speedItemPos, label)
                this._speedItemName := label
            }
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._WarnMenu()
        }
    }

    ; One notice when the menu can't be updated; the setting itself still applies.
    _WarnMenu() {
        if this._menuWarned {
            return  ; guard: told the user already
        }
        this._menuWarned := true
        this._Notice("Couldn't update the tray menu; the setting still applies" . this._ErrorHint() . ".")
    }

    _AfterLabel() {
        for choice in TrayMenu.AFTER_CHOICES {
            if choice.key = this._typer.GetAfterTyping() {
                return TrayMenu.AFTER_PREFIX . choice.shown
            }
        }
        return TrayMenu.AFTER_PREFIX . "nothing"
    }

    ; Ticks the current After typing choice and renames the After typing item to show it.
    _SyncAfterTyping() {
        try {
            for choice in TrayMenu.AFTER_CHOICES {
                this._SetCheck(this._afterMenu, choice.item, choice.key = this._typer.GetAfterTyping())
            }
            label := this._AfterLabel()
            if this._afterItemPos != "" && label != this._afterItemName {
                this._menu.Rename(this._afterItemPos, label)
                this._afterItemName := label
            }
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._WarnMenu()
        }
    }

    _SaveSpeed() {
        this._Save("KeyDelayMs", this._sender.GetDelayMs())
        this._Save("KeyPressMs", this._sender.GetPressMs())
    }

    ; Saves one tray choice. The first failure says so once; the choice still applies until restart.
    _Save(key, value) {
        if this._store.Write(key, value) {
            return true
        }
        if !this._saveWarned {
            this._saveWarned := true
            this._Notice("Couldn't save settings next to the script (folder read-only or file locked); this choice lasts until restart"
                . this._ErrorHint() . ".")
        }
        return false
    }

    _SetCheck(menuObj, itemName, isOn) {
        if isOn {
            menuObj.Check(itemName)
        } else {
            menuObj.Uncheck(itemName)
        }
    }

    _Notice(message) {
        try TrayTip(message, "Clipboard Typer", "Iconi Mute")
    }

    _ErrorHint() {
        return this._logger.LastErrorWritten() ? " (see error.log)" : ""
    }

    _LogError(caller, message, err := "") {
        return this._logger.Error(caller, message, err)
    }
}


class SettingsStore {
    ; --- Properties ---
    _path := ""             ; absolute path of the .ini file
    _logger := ""
    _enabled := true        ; SAVE_SETTINGS: when false the file is never read or written
    _section := "Settings"
    _inEffect := false      ; saved choices are in use (applied at startup or saved since); false after Forget

    ; --- Constructor ---
    __New(path, logWriter, enabled := true) {
        if path = "" || !IsObject(logWriter) {
            throw Error("SettingsStore needs a file path and a Logger", A_ThisFunc)
        }
        this._path := path
        this._logger := logWriter
        this._enabled := !!enabled
    }

    ; --- Public Methods ---
    IsEnabled() {
        return this._enabled
    }

    ; For the debug start line: "ini" while saved choices are in use, "script" otherwise.
    MarkInEffect(isOn) {
        this._inEffect := !!isOn
    }

    IsInEffect() {
        return this._inEffect
    }

    ; The saved value, or default when there is none, the file can't be read, or saving is off.
    ; NOTE: IniRead keeps an inline "; comment" as part of the value, so comments go on their own line.
    Read(key, default) {
        if !this._enabled {
            return default  ; guard: saving is off
        }
        try {
            return IniRead(this._path, this._section, key, default)
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return default
        }
    }

    ; True when saved (or saving is off, so there's nothing to do).
    ; NOTE: IniWrite creates the file as UTF-16, which is what the INI functions read correctly.
    Write(key, value) {
        if !this._enabled {
            return true  ; guard: saving is off
        }
        try {
            IniWrite(value, this._path, this._section, key)
        } catch Error as e {
            this._LogError(A_ThisFunc, "Couldn't save " . key . ": " . e.Message, e)
            this._logger.Debug("ini", "write=fail key=" . key)  ; NOTE: never the value
            return false
        }
        this._inEffect := true
        this._logger.Debug("ini", "write=ok key=" . key)
        return true
    }

    ; Deletes the saved settings. True when nothing is saved afterwards (also when nothing was saved).
    ; NOTE: the caller goes back to the script's settings either way, so saved choices stop being in use.
    Forget() {
        this._inEffect := false
        if !this._enabled || !FileExist(this._path) {
            this._logger.Debug("ini", "forget=nothing")
            return true  ; guard: nothing to forget
        }
        try FileSetAttrib("-R", this._path)
        try {
            FileDelete(this._path)
        } catch Error as e {
            this._LogError(A_ThisFunc, "Couldn't delete " . this._path . ": " . e.Message, e)
            this._logger.Debug("ini", "forget=fail")
            return false
        }
        this._logger.Debug("ini", "forget=ok")
        return true
    }

    ; --- Private Methods ---
    _LogError(caller, message, err := "") {
        return this._logger.Error(caller, message, err)
    }
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
        if this._ToDelay(keyDelayMs) = "" || this._ToDelay(pressMs) = "" {
            throw Error("KEY_DELAY_MS and KEY_PRESS_MS must be whole numbers from 0 to 1000", A_ThisFunc)
        }
        if !IsObject(logWriter) {
            throw Error("Logger is required", A_ThisFunc)
        }
        ; NOTE: {Raw} sends real key codes, which is what remote viewers forward. {Text} sends every
        ;       char as VK_PACKET, which many remote viewers drop. With {Raw} the session's keyboard
        ;       layout must match this PC's, since the remote side turns key codes back into characters.
        this._sendPrefix := "{" . sendMode . "}"
        this._keyDelayMs := this._ToDelay(keyDelayMs)
        this._pressMs := this._ToDelay(pressMs)
        this._logger := logWriter
    }

    ; --- Public Methods ---
    ; Changes the typing speed: pause after each key and how long each key is held, in ms (0 to 1000,
    ; whole numbers or numeric strings). Takes effect from the next keystroke sent. False if rejected.
    SetDelays(delayMs, pressMs) {
        delay := this._ToDelay(delayMs)
        press := this._ToDelay(pressMs)
        if delay = "" || press = "" {
            this._logger.Debug("setting", "speed=rejected")
            return false
        }
        this._keyDelayMs := delay
        this._pressMs := press
        this._logger.Debug("setting", "speed=" . delay . "/" . press)
        return true
    }

    GetDelayMs() {
        return this._keyDelayMs
    }

    ; The one rule for a delay or press time (constants, tray, saved settings): a whole number of ms, 0-1000.
    IsValidDelay(value) {
        return this._ToDelay(value) != ""
    }

    GetPressMs() {
        return this._pressMs
    }

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
        this._inFlightVk := this._InFlightVkForKeys(keys)  ; NOTE: the A of Ctrl+A is held for KEY_PRESS_MS too
        try {
            SetKeyDelay(this._keyDelayMs, this._pressMs)  ; NOTE: per-thread setting, so set it on every call
            SendEvent(keys)
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return false
        } finally {
            this._inFlightVk := 0
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
    ; A delay or press time as a whole number of ms from 0 to 1000, or "" if it isn't one.
    _ToDelay(value) {
        if value is String {
            value := Trim(value)
        }
        if !IsInteger(value) || value < 0 || value > 1000 {
            return ""
        }
        return Integer(value)
    }

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

    ; The main key of a combination such as "^a" or "{Enter}", so ReleaseInFlightKey can let go of it if
    ; the script exits mid-press (the modifiers are ReleaseStuckModifiers' job). 0 when there isn't one.
    _InFlightVkForKeys(keys) {
        key := RegExReplace(RegExReplace(keys, "^[\^!+#]+"), "^\{(\w+)\}$", "$1")
        if key = "" || (StrLen(key) > 1 && !RegExMatch(key, "^\w+$")) {
            return 0  ; guard: not a single key
        }
        try {
            return GetKeyVK(key)
        } catch {
            return 0
        }
    }

    _LogError(caller, message, err := "") {
        return this._logger.Error(caller, message, err)
    }
}


class ClipboardTyper {
    ; --- Labels ---
    ; NOTE: every UWP/XAML app window has this class; it is refused only when it belongs to Start or Search
    static CORE_WINDOW_CLASS := "Windows.UI.Core.CoreWindow"
    static START_SEARCH_EXES := ["StartMenuExperienceHost.exe", "ShellExperienceHost.exe", "SearchHost.exe", "SearchApp.exe", "SearchUI.exe"]
    ; Focused controls step mode won't type into (ClassNN without its number): typing a line there would
    ; press a button, toggle a checkbox or pick a list entry
    ; NOTE: "(32)?" because a ClassNN like SysListView321 loses its class's own 32 with the instance number
    static NON_TEXT_CONTROLS := "^(Button|ComboBox|ListBox|SysListView(32)?|SysTreeView(32)?|SysTabControl(32)?|msctls_trackbar(32)?)$"

    ; --- Properties ---
    _inputSender := ""
    _logger := ""
    _maxChars := 0
    _clickTimeoutSec := 0
    _focusSettleMs := 0
    _phase := ""            ; "" idle, "waiting" for the target click, "typing", "stepping" (step-mode checks), "steptyping"
    _clicked := false
    _clickedRoot := 0       ; top-level window under the mouse at the target click
    _cancelled := false
    _stopReason := ""       ; why the current run stopped early: "esc", "click" or "key"
    _notifyMs := 2500
    _progressEvery := 25    ; chars between progress tooltip updates
    _clearTipCallback := ""
    _realKeyCallback := ""  ; key guard: a key the user pressed while it types
    _afterLogged := false   ; this run's "after" debug line is written (one per run, see _LogAfter)
    _stopVk := 0            ; key guard: the key that stopped the run, held until it's let go (see _WaitForStopKeyRelease)
    _stepMode := false
    _stepSelectAllFirst := true
    _stepStatusMs := 1500
    _lines := []            ; step mode: clipboard lines, rebuilt after each copy
    _index := 1             ; step mode: next line to type
    _needsReload := true    ; step mode: set on every clipboard change
    _retryLine := false     ; step mode: the line at _index stopped or missed its after-typing key; retype it without the key
    _clipChangeCallback := ""
    _showStepText := false  ; step mode: show the typed line in the status (off so passwords stay off screen)
    _afterTyping := ""      ; "", "Enter" or "Tab": key pressed after a run that typed everything
    _blockedClasses := ""   ; Map of lowercase window class -> true
    _stopOnKeypress := true
    _requireClickedFocus := true

    ; --- Constructor ---
    __New(sender, logWriter, maxChars, clickTimeoutSec, focusSettleMs, stepMode := false, stepSelectAllFirst := true, stepStatusMs := 1500, showStepText := false,
        afterTyping := "", blockedClasses := "", stopOnKeypress := true, requireClickedFocus := true) {
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
        if !this._CanonicalAfterKey(afterTyping, &afterKey) {
            throw Error('AFTER_TYPING must be "", "Enter" or "Tab", not "' . afterTyping . '"', A_ThisFunc)
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
        this._afterTyping := afterKey
        this._blockedClasses := Map()
        for name in StrSplit(blockedClasses, ",", " `t") {
            if name != "" {
                this._blockedClasses[StrLower(name)] := true
            }
        }
        this._stopOnKeypress := !!stopOnKeypress
        this._requireClickedFocus := !!requireClickedFocus
        this._clearTipCallback := ObjBindMethod(this, "_ClearTip")
        this._realKeyCallback := ObjBindMethod(this, "_OnRealKey")
        this._clipChangeCallback := ObjBindMethod(this, "_OnClipboardChange")
        if !this._clearTipCallback || !this._realKeyCallback || !this._clipChangeCallback {
            throw Error("Failed to bind ClipboardTyper callbacks", A_ThisFunc)
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
        this._clickedRoot := 0
        this._cancelled := false
        this._stopReason := ""
        this._stopVk := 0
        this._afterLogged := false
        afterKey := this._afterTyping  ; NOTE: a change made mid-run applies from the next run, so this run does what its prompt said
        guard := ""
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
            this._Debug("run", "mode=full len=" . StrLen(text) . " enters=" . enterCount . " after=" . this._AfterName(afterKey))
            targetId := this._WaitForTargetClick(text, afterKey)
            if !targetId {
                return false  ; _WaitForTargetClick already told the user why
            }
            this._ReinstallHooks()
            this._phase := "typing"
            guard := this._StartKeyGuard()  ; NOTE: after the reinstall, so its hook sees keys before a viewer's hook
            return this._TypeInto(targetId, text, afterKey)
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Error" . this._ErrorHint())
            return false
        } finally {
            if afterKey != "" && !this._afterLogged && this._phase = "typing" {
                this._LogAfter(afterKey, "skipped-stopped")  ; NOTE: typing began but the key's turn never came
            }
            this._WaitForStopKeyRelease()
            this._StopKeyGuard(guard)
            this._inputSender.ReleaseStuckModifiers()
            this._phase := ""
        }
    }

    ; Hotkey condition: the click and Esc hotkeys only fire while a run waits or types.
    ; NOTE: not during step mode's checks (stepping), so Esc and clicks still reach the app until a line starts
    IsActive(*) {
        return this._phase != "" && this._phase != "stepping"
    }

    ; Click hotkey: while waiting it picks the target, while typing (or typing a step line) it stops.
    OnClick(*) {
        if this._phase = "typing" || this._phase = "steptyping" {
            if this._stopReason = "" {
                this._stopReason := "click"
            }
            this._cancelled := true
            return
        }
        hwnd := 0
        try MouseGetPos(, , &hwnd)
        this._clickedRoot := hwnd ? DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") : 0  ; GA_ROOT
        this._clicked := true
    }

    ; Esc hotkey: cancels the wait or stops typing. The Esc itself never reaches the window.
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

    ; Step mode: types the next clipboard line into the focused field, replacing its text. No click needed.
    ; It sends no Enter, Tab, Delete or Backspace of its own; After typing may add one Enter or Tab.
    TypeNextLine(thisHotkey := "") {
        if this._phase != "" {
            return false  ; guard: already running, ignore repeat triggers
        }
        this._phase := "stepping"
        ; NOTE: reset per press, so an Esc that stopped a tray "Type clipboard" run can't stop this line
        this._cancelled := false
        this._clicked := false
        this._stopReason := ""
        this._stopVk := 0
        this._afterLogged := false
        afterKey := this._afterTyping
        guard := ""
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
                this._retryLine := false
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
            index := this._index
            item := this._lines[index]
            lineInfo := "line=" . index . "/" . total . " len=" . StrLen(item)
            ; NOTE: checked before Ctrl+A, so a huge line never starts
            if StrLen(item) > this._maxChars {
                this._Debug("step", lineInfo . " result=toolong")
                this._Notify("Line " . index . "/" . total . " is " . StrLen(item) . " chars (max " . this._maxChars . "); skipped")
                this._Advance(total)  ; NOTE: move past it so the rest of the list stays reachable
                this._retryLine := false
                return false
            }
            targetId := this._CheckStepTarget(lineInfo)
            if !targetId {
                return false  ; _CheckStepTarget already told the user why
            }
            isRetry := this._retryLine
            this._ReinstallHooks()  ; NOTE: after _WaitForKeysUp, so no key is held during the reinstall
            this._phase := "steptyping"
            guard := this._StartKeyGuard()
            if this._stepSelectAllFirst && !this._inputSender.Send("^a") {
                this._Debug("step", lineInfo . " result=fail")
                this._Notify("Send failed" . this._ErrorHint())
                return false  ; NOTE: _index doesn't advance, so the next press retries this line
            }
            stop := this._TypeChars(item, targetId, false, &typed)
            if stop != "done" {
                this._retryLine := true  ; NOTE: the list stays on this line; the next press retypes it
                this._Debug("step", lineInfo . " result=stopped stop=" . stop)
                this._Notify(this._StepStoppedStatus(index, total, afterKey, stop), this._stepStatusMs)
                return false
            }
            if isRetry {
                ; NOTE: a retyped line never gets the after-typing key: in a console, Ctrl+A may not have
                ;       replaced the partial line, so the user checks the field before anything runs
                this._retryLine := false
                this._Advance(total)
                this._Debug("step", lineInfo . " result=retyped")
                if afterKey != "" {
                    this._LogAfter(afterKey, "skipped-retry")
                    this._Notify(this._StepRetypedStatus(index, total, afterKey), this._stepStatusMs)
                } else {
                    this._Notify(this._StepStatus(index, total, item), this._stepStatusMs)
                }
                return true
            }
            sent := this._SendAfterKey(afterKey, targetId)
            this._Debug("step", lineInfo . " result=typed after=" . this._AfterName(afterKey))
            if sent = "" || sent = "sent" {
                this._Advance(total)
                this._Notify(this._StepStatus(index, total, item, sent = "sent" ? afterKey : ""), this._stepStatusMs)
                return true
            }
            this._retryLine := true  ; NOTE: the key didn't go out; the next press retypes the line without it
            this._Notify(this._StepKeyMissedStatus(index, total, afterKey, sent), this._stepStatusMs)
            return true
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Error" . this._ErrorHint())
            return false
        } finally {
            if afterKey != "" && !this._afterLogged && this._phase = "steptyping" {
                this._LogAfter(afterKey, "skipped-stopped")  ; NOTE: stopped, Ctrl+A failed or it threw after the line began
            }
            this._WaitForStopKeyRelease()
            this._StopKeyGuard(guard)
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
        this._retryLine := false
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

    ; Tray menu: flips whether step mode selects the field's text (Ctrl+A) before typing. Returns the new state.
    ToggleSelectAllFirst() {
        this._stepSelectAllFirst := !this._stepSelectAllFirst
        return this._stepSelectAllFirst
    }

    IsSelectingAllFirst() {
        return this._stepSelectAllFirst
    }

    ; Tray menu > After typing: "", "Enter" or "Tab" (any case). Applies from the next run. False if rejected.
    SetAfterTyping(key) {
        if !this._CanonicalAfterKey(key, &afterKey) {
            return false
        }
        this._afterTyping := afterKey
        this._Debug("setting", "after=" . this._AfterName(afterKey))
        return true
    }

    GetAfterTyping() {
        return this._afterTyping
    }

    ; True while a run waits for its click, types, or checks a step line.
    IsBusy() {
        return this._phase != ""
    }

    ; A status tooltip from outside a run (startup reminder, tray notices).
    ShowNotice(message, durationMs := 0) {
        this._Notify(message, durationMs)
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

    _WaitForTargetClick(text, afterKey) {
        this._ShowTip(this._ClickPrompt(text, afterKey) . "`nEsc to cancel (" . this._clickTimeoutSec . "s)")
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
            return this._CheckClickTarget()
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            this._Notify("Couldn't find the clicked window" . this._ErrorHint())
            return 0
        }
    }

    ; The prompt before the click, with every Enter (and Tab) the run will press, so multi-line text
    ; can't run commands by surprise.
    _ClickPrompt(text, afterKey) {
        StrReplace(text, "`n", "`n", , &enterCount)
        prompt := "Click the field to type " . StrLen(text) . " chars into"
        if afterKey = "Enter" {
            prompt .= enterCount = 0 ? " (then presses Enter)" : " (presses Enter " . (enterCount + 1) . "x, the last one after the text)"
        } else if afterKey = "Tab" {
            prompt .= enterCount = 0 ? " (then presses Tab)" : " (presses Enter " . enterCount . "x, then presses Tab)"
        } else if enterCount > 0 {
            prompt .= " (presses Enter " . enterCount . "x)"
        }
        return prompt
    }

    ; After the target click: refuses the desktop, taskbar, Start and this script's own windows (whether
    ; clicked or active), and a clicked window that didn't take focus. Returns the window to type into, or 0.
    _CheckClickTarget() {
        activeId := WinGetID("A")
        for hwnd in [this._clickedRoot, activeId] {
            info := this._WindowInfo(hwnd)
            if hwnd && (info.own || this._IsBlockedClass(info.cls, info.exe)) {
                this._Debug("target", "exe=" . info.exe . " class=" . info.cls . " blocked=1" . (info.own ? " own=1" : ""))
                this._Notify(this._RefusalNotice(info.cls, info.exe, info.own), 5000)
                return 0
            }
        }
        if this._requireClickedFocus {
            clicked := this._clickedRoot
            ; NOTE: without this, the text (and a saved Enter) would go to whatever was active before the click
            if !this._ClickTookFocus(clicked, activeId) && clicked && WinWaitActive(clicked, , 1) {
                activeId := clicked  ; NOTE: slow to activate; waited up to 1s for it
            }
            if !this._ClickTookFocus(clicked, activeId) {
                this._Debug("target", "blocked=notactive clicked=" . this._WindowInfo(clicked).cls . " active=" . this._WindowInfo(activeId).cls)
                this._Notify("The window you clicked didn't take focus; nothing typed.", 5000)
                return 0
            }
        }
        info := this._WindowInfo(activeId)
        this._Debug("target", "exe=" . info.exe . " class=" . info.cls . " blocked=0")
        return activeId
    }

    ; Step mode has no click, so the window and control that have focus are checked instead.
    ; Returns the window to type into, or 0 (and says why).
    _CheckStepTarget(lineInfo) {
        targetId := 0
        try targetId := WinGetID("A")
        info := this._WindowInfo(targetId)
        if !targetId || info.own || this._IsBlockedClass(info.cls, info.exe) {
            this._Debug("step", lineInfo . " result=blocked class=" . info.cls . (info.own ? " own=1" : ""))
            this._Notify(targetId ? this._RefusalNotice(info.cls, info.exe, info.own) : "No window has focus; nothing typed.", 5000)
            return 0
        }
        focused := 0
        try focused := ControlGetFocus(targetId)
        if focused {
            controlClass := ""
            try controlClass := this._ControlClassFromClassNN(ControlGetClassNN(focused))
            if this._IsNonTextControlClass(controlClass) {
                this._Debug("step", lineInfo . " result=blocked control=" . controlClass)
                this._Notify("Focused control isn't a text box; nothing typed.", 5000)
                return 0
            }
        }
        return targetId
    }

    ; Class, program and whether it's one of this script's own windows. Never the title.
    _WindowInfo(hwnd) {
        info := {cls: "", exe: "", own: false}
        if !hwnd {
            return info  ; guard: no window
        }
        try info.cls := WinGetClass(hwnd)
        try info.exe := WinGetProcessName(hwnd)
        try info.own := WinGetPID(hwnd) = ProcessExist()  ; NOTE: ProcessExist() with no name is this script's PID
        return info
    }

    _RootOwner(hwnd) {
        return hwnd ? DllCall("GetAncestor", "Ptr", hwnd, "UInt", 3, "Ptr") : 0  ; GA_ROOTOWNER
    }

    _ClickTookFocus(clickedRoot, activeId) {
        return this._SameTarget(clickedRoot, activeId, this._RootOwner(clickedRoot), this._RootOwner(activeId))
    }

    ; Did the clicked window take focus? The same window, or windows with the same root owner, so a viewer
    ; whose session canvas is an owned popup of its frame isn't refused.
    _SameTarget(clickedRoot, activeId, clickedOwner, activeOwner) {
        if !clickedRoot || !activeId {
            return false  ; guard: one of them is unknown
        }
        return clickedRoot = activeId || (clickedOwner && clickedOwner = activeOwner)
    }

    _IsBlockedClass(cls, exe) {
        if cls = "" || !this._blockedClasses.Has(StrLower(cls)) {
            return false
        }
        if cls = ClipboardTyper.CORE_WINDOW_CLASS {
            for name in ClipboardTyper.START_SEARCH_EXES {
                if exe = name {
                    return true
                }
            }
            return false
        }
        return true
    }

    ; "Button1" -> "Button". The class's own trailing digits go too ("SysListView321" -> "SysListView").
    _ControlClassFromClassNN(classNN) {
        return RegExReplace(classNN, "\d+$")
    }

    _IsNonTextControlClass(controlClass) {
        return controlClass != "" && RegExMatch(controlClass, ClipboardTyper.NON_TEXT_CONTROLS) > 0
    }

    ; Why nothing was typed: names the window class and program (never the title), so a wrongly blocked
    ; target can be allowed again.
    _RefusalNotice(cls, exe, isOwn) {
        if isOwn {
            return "That's a Clipboard Typer window; nothing typed. Click the field to type into."
        }
        return "Won't type into the desktop, taskbar or Start (class " . cls . ", " . exe . "); nothing typed. "
            . "To allow it, remove the class from BLOCKED_TARGET_CLASSES."
    }

    ; Whole-clipboard run: types the text, then the after-typing key if everything went through.
    _TypeInto(targetId, text, afterKey) {
        total := StrLen(text)
        startTick := A_TickCount
        stop := this._TypeChars(text, targetId, true, &typed)
        ms := A_TickCount - startTick
        ; NOTE: A_TickCount moves in 10-16 ms steps, so a very short run can measure 0 ms
        this._Debug("typed", typed . "/" . total . " ms=" . ms . " cps=" . (ms < 1 ? "-" : Format("{:.1f}", typed * 1000 / ms)) . " stop=" . stop)
        if stop != "done" {
            this._Notify(this._StoppedMessage(stop, typed, total))
            return false
        }
        sent := this._SendAfterKey(afterKey, targetId)
        if sent = "" || sent = "sent" {
            this._Notify(this._DoneMessage(total, ms, sent = "sent" ? afterKey : ""))
            return true
        }
        this._Notify("Typed " . total . " chars; " . this._KeyMissed(afterKey, sent))
        return false
    }

    ; The typing loop shared by both modes. Returns why it ended: done, esc, click, key, focus or sendfail.
    _TypeChars(text, targetId, showProgress, &typed) {
        total := StrLen(text)
        typed := 0
        Loop Parse text {
            ; NOTE: checked per character so a click, Esc, key press or focus change stops it mid-text
            if this._cancelled {
                return this._stopReason != "" ? this._stopReason : "esc"
            }
            if !WinActive(targetId) {
                return "focus"
            }
            if showProgress && Mod(typed, this._progressEvery) = 0 {
                this._ShowTip("Typing " . typed . "/" . total . "`n" . (this._stopOnKeypress ? "Click, Esc or any key to stop" : "Click or Esc to stop"))
            }
            if !this._inputSender.TypeText(A_LoopField) {
                return "sendfail"
            }
            typed += 1
        }
        return "done"
    }

    ; Presses the after-typing key, but only if nothing stopped the run and the target still has focus.
    ; Returns "" (no key set), "sent", "fail" or "skipped-<reason>".
    _SendAfterKey(afterKey, targetId) {
        if afterKey = "" {
            return ""
        }
        if this._cancelled {
            result := "skipped-" . (this._stopReason != "" ? this._stopReason : "esc")
        } else if !WinActive(targetId) {
            result := "skipped-focus"
        } else if !this._inputSender.TypeText(afterKey = "Enter" ? "`n" : "`t") {  ; NOTE: like a line break, so a key held at exit is released
            result := "fail"
        } else {
            result := "sent"
        }
        this._LogAfter(afterKey, result)
        return result
    }

    ; Debug: what happened to the after-typing key. One line per run: a run that stopped after typing
    ; began gets "skipped-stopped" from the finally of TypeClipboard or TypeNextLine.
    _LogAfter(afterKey, result) {
        this._afterLogged := true
        this._Debug("after", "key=" . afterKey . " result=" . result)
    }

    ; Blocks every key the user presses while it types (Esc is left to the Esc hotkey) and stops the run,
    ; so the key can't mix into the text or reach the window, where an Enter would run a half-typed line.
    ; Returns the InputHook, or "" when STOP_ON_KEYPRESS is off or it couldn't start.
    ; NOTE: I2 ignores input sent at SendLevel 0 or 1: this script's own keystrokes and the test suite's.
    _StartKeyGuard() {
        if !this._stopOnKeypress {
            return ""  ; guard: switched off
        }
        try {
            guard := InputHook("L0 I2")
            guard.KeyOpt("{All}", "+N +S")
            guard.KeyOpt("{Esc}", "-N -S")
            guard.OnKeyDown := this._realKeyCallback
            guard.Start()
            return guard
        } catch Error as e {
            this._LogError(A_ThisFunc, e.Message, e)
            return ""
        }
    }

    _StopKeyGuard(guard) {
        if !IsObject(guard) {
            return  ; guard: nothing started
        }
        try guard.Stop()
    }

    ; Key guard: a key the user pressed while it types.
    _OnRealKey(guard, vk, sc) {
        if this._stopReason = "" {
            this._stopReason := "key"
            this._stopVk := vk
            this._Debug("key", "phase=" . this._phase)  ; NOTE: never which key: it could be part of a password typed by hand
        }
        this._cancelled := true
    }

    ; After a stop, keeps the key guard (or the Esc hotkey) on until the key that stopped the run is let go,
    ; so a held key's auto-repeat can't reach the window once they end (an Enter would run the partial line).
    _WaitForStopKeyRelease() {
        key := this._stopVk ? Format("vk{:X}", this._stopVk) : (this._stopReason = "esc" ? "Esc" : "")
        if key != "" {
            try KeyWait(key, "T2")  ; NOTE: the physical state (keyboard hook), so it returns once the key is up
        }
    }

    ; "Typed 42 chars in 1.4s (30/s)", "Typed 42 chars + Enter in 1.4s (30/s)"; without the time when
    ; the run was too short to measure.
    _DoneMessage(chars, ms, keyName := "") {
        message := "Typed " . chars . " chars" . (keyName != "" ? " + " . keyName : "")
        if ms < 1 {
            return message
        }
        return message . " in " . Format("{:.1f}", ms / 1000) . "s (" . Round(chars * 1000 / ms) . "/s)"
    }

    _StoppedMessage(stop, typed, total) {
        switch stop {
            case "focus": return "Stopped at " . typed . "/" . total . ": session window lost focus"
            case "key": return "Stopped at " . typed . "/" . total . ": key pressed"
            case "sendfail": return "Send failed at " . typed . "/" . total . this._ErrorHint()
            default: return "Stopped at " . typed . "/" . total
        }
    }

    ; "Enter skipped (window lost focus)", "Enter failed (see error.log)".
    _KeyMissed(afterKey, sent) {
        if sent = "fail" {
            return afterKey . " failed" . this._ErrorHint()
        }
        switch sent {
            case "skipped-focus": reason := "window lost focus"
            case "skipped-key": reason := "key pressed"
            default: reason := "stopped"
        }
        return afterKey . " skipped (" . reason . ")"
    }

    ; Step mode status after a press. Shows the typed line only when Show typed text is on, so a
    ; password never appears on screen by default; when off it carries nothing derived from the text.
    _StepStatus(index, total, item, keyName := "") {
        status := this._showStepText ? index . "/" . total . ": " . item : index . "/" . total . " typed"
        return keyName != "" ? status . " + " . keyName : status
    }

    ; "Stopped on line 2/5; ..." or, when a keystroke couldn't be sent, "Send failed on line 2/5 (see error.log); ...".
    _StepStoppedStatus(index, total, afterKey, stop := "") {
        lead := (stop = "sendfail" ? "Send failed" : "Stopped") . " on line " . index . "/" . total
            . (stop = "sendfail" ? this._ErrorHint() : "")
        if !this._stepSelectAllFirst {
            return lead . "; part of it is in the field: clear it, then press again"
        }
        return lead . "; press again to retype it" . (afterKey != "" ? " (no " . afterKey . ")" : "")
    }

    _StepKeyMissedStatus(index, total, afterKey, sent) {
        lead := index . "/" . total . " typed; " . this._KeyMissed(afterKey, sent)
        if !this._stepSelectAllFirst {
            return lead . ": the line is in the field: clear it, then press again to retype it without " . afterKey
        }
        return lead . ": press again to retype it without " . afterKey
    }

    _StepRetypedStatus(index, total, afterKey) {
        return index . "/" . total . " retyped without " . afterKey . ": check the field, then press " . afterKey . " yourself"
    }

    _Advance(total) {
        if total > 1 {
            this._index += 1  ; NOTE: a single line retypes on every press, like the full typer
        }
    }

    ; "", "Enter" or "Tab" in any case -> canonical spelling in &afterKey. False for anything else.
    _CanonicalAfterKey(key, &afterKey) {
        afterKey := ""
        for name in ["", "Enter", "Tab"] {
            if key = name {
                afterKey := name
                return true
            }
        }
        return false
    }

    _AfterName(afterKey) {
        return afterKey = "" ? "nothing" : afterKey
    }

    ; " (see error.log)" when the last error reached error.log, otherwise nothing.
    _ErrorHint() {
        return this._logger.LastErrorWritten() ? " (see error.log)" : ""
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
        this._retryLine := false
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
