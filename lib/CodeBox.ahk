class CodeBox {
    static _Instances := Map(), _SubCtrls := Map()
    static _DebounceTimers := Map(), _KeywordCache := Map()
    static Themes := Map(), Syntaxes := Map()
    static _Initialized := false
    static _SubclassProcCallback := ""


    static _CursorHand := DllCall("LoadCursorW", "Ptr", 0, "Ptr", 32649, "Ptr")
    static _CursorArrow := DllCall("LoadCursorW", "Ptr", 0, "Ptr", 32512, "Ptr")
    static _CursorIBeam := DllCall("LoadCursorW", "Ptr", 0, "Ptr", 32513, "Ptr")

    static Plugins := []
    static DebugLogPath := "" ; Set to a file path like "codebox_debug.log" to enable logging

    static RegisterPlugin(name, pluginClass) {
        this.Plugins.Push({ name: name, class: pluginClass, enabled: true })
    }

    static TogglePlugin(name, state) {
        for p in this.Plugins {
            if (p.name == name) {
                p.enabled := state
                return true
            }
        }
        return false
    }

    static IsPluginEnabled(name) {
        for p in this.Plugins {
            if (p.name == name)
                return p.enabled
        }
        return false
    }

    static Invoke(method, args*) {
        for p in this.Plugins {
            if p.enabled && p.class.HasProp(method) {
                try {
                    methodObj := p.class.%method%
                    if (methodObj is Func) {
                        totalArgs := args.Length + 1
                        if (!methodObj.IsVariadic && totalArgs > methodObj.MaxParams) {
                            safeArgs := []
                            takeCount := Max(0, methodObj.MaxParams - 1)
                            loop Min(args.Length, takeCount) {
                                safeArgs.Push(args[A_Index])
                            }
                            return methodObj(p.class, safeArgs*)
                        } else {
                            return methodObj(p.class, args*)
                        }
                    }
                    return p.class.%method%(args*)
                } catch Error as err {
                    this.LogDebug("Plugin error (" p.name "." method "): " err.Message)
                }
            }
        }
        return false
    }

    static Emit(eventName, args*) {
        handled := false
        for p in this.Plugins {
            if p.enabled && p.class.HasProp(eventName) {
                try {
                    methodObj := p.class.%eventName%
                    if (methodObj is Func) {
                        totalArgs := args.Length + 1
                        if (!methodObj.IsVariadic && totalArgs > methodObj.MaxParams) {
                            safeArgs := []
                            takeCount := Max(0, methodObj.MaxParams - 1)
                            loop Min(args.Length, takeCount) {
                                safeArgs.Push(args[A_Index])
                            }
                            res := methodObj(p.class, safeArgs*)
                        } else {
                            res := methodObj(p.class, args*)
                        }
                    } else {
                        res := p.class.%eventName%(args*)
                    }
                    if res {
                        handled := true
                        break
                    }
                } catch Error as err {
                    this.LogDebug("Plugin event error (" p.name "." eventName "): " err.Message)
                }
            }
        }
        return handled
    }

    static LogDebug(msg) {
        if this.DebugLogPath {
            try FileAppend(Format("{1}: {2}`n", FormatTime(, "HH:mm:ss"), msg), this.DebugLogPath)
        }
    }

    static Init() {
        if this._Initialized
            return
        if !DllCall("GetModuleHandle", "Str", "msftedit.dll", "Ptr")
            DllCall("LoadLibrary", "Str", "msftedit.dll", "Ptr")

        this.Emit("OnInit")
        try {
            dataClass := %"CodeBox_Data"%
            dataClass.Init()
        }

        OnMessage(0x0100, ObjBindMethod(this, "_OnKeyDown"))
        OnMessage(0x0102, ObjBindMethod(this, "_OnChar"))
        OnMessage(0x0201, ObjBindMethod(this, "_OnLButtonDown"))
        OnMessage(0x0202, ObjBindMethod(this, "_OnLButtonUp"))
        OnMessage(0x020A, ObjBindMethod(this, "_OnMouseWheel"))
        OnMessage(0x020E, ObjBindMethod(this, "_OnMouseHWheel"))
        OnMessage(0x011A, ObjBindMethod(this, "_OnGestureNotify"))
        OnMessage(0x0119, ObjBindMethod(this, "_OnGesture"))
        OnMessage(0x0020, ObjBindMethod(this, "_OnSetCursor"))
        OnMessage(0x0200, ObjBindMethod(this, "_OnMouseMove"))
        OnMessage(0x007B, ObjBindMethod(this, "_OnContextMenu"))
        OnMessage(0x0002, ObjBindMethod(this, "_OnDestroy"))
        OnMessage(0x0007, ObjBindMethod(this, "_OnSetFocus"))
        OnMessage(0x0018, ObjBindMethod(this, "_OnShowWindow"))
        OnMessage(0x0047, ObjBindMethod(this, "_OnWindowPosChanged"))

        this._Initialized := true
    }

    static Add(guiObj, options := "", text := "", language := "ahk2", theme := "Dark") {
        this.Init()
        bkgColor := this.Themes.Has(theme) ? this.Themes[theme]["Background"] : 0x1E1E1E

        dummy := guiObj.Add("Text", options)
        dummy.GetPos(&px, &py, &pw, &ph), dummy.Visible := false

        ctrl := guiObj.Add("Custom", "ClassRichEdit50W +0x043011C4 +0x00010000 -E0x200 x" px " y" py " w" pw " h" ph, "")
        ctrl.LineNumCtrl := guiObj.Add("Custom", "ClassRichEdit50W +0x04000804 -0x200000 -E0x200")

        ctrl.CodeBox := true
        ctrl.IsHighlighting := false
        ctrl.AutoIndent := true, ctrl.AutoClose := true, ctrl.AutoSuggest := true
        ctrl.Events := Map()

        ctrl._LineNums := true
        ctrl._WordWrap := true, ctrl._HexView := false
        ctrl._x := px, ctrl._y := py, ctrl._w := pw, ctrl._h := ph

        ctrl.DefineProp("Language", { 
            get: c => c._HexView && c.HasProp("OriginalLang") ? c.OriginalLang : c.CodeBoxLang, 
            set: (c, v) => (
                c._HexView ? (c.OriginalLang := v) : (c.CodeBoxLang := v),
                this.Emit("OnLanguageChange", c)
            ) 
        })
        ctrl.DefineProp("Theme", { get: c => c.CodeBoxTheme, set: (c, v) => (c.CodeBoxTheme := v, this.Emit("OnThemeChange", c)) })
        ctrl.DefineProp("Text", { get: c => this._GetText(c), set: (c, v) => this._SetText(c, v) })
        ctrl.DefineProp("WordWrap", { get: c => c._WordWrap, set: (c, v) => (
            c._WordWrap := v, SendMessage(0x0448, 0, v ? 0 : 1, c.Hwnd),
            c.ForceLineUpdate := true, this.Emit("OnScroll", c)
        ) })
        ctrl.DefineProp("LineNumbers", { get: c => c._LineNums, set: (c, v) => (
            c._LineNums := v, c.LineNumCtrl.Visible := v, c.ForceLineUpdate := true, CodeBox._Move(c), this.Emit("OnScroll", c)
        ) })

        ctrl.DefineProp("HexView", { get: c => c._HexView, set: (c, v) => this.Invoke("ToggleHexView", c, v) })

        ctrl.DefineProp("On", { call: (c, event, cb) => (c.Events.Has(event) ? c.Events[event].Push(cb) : c.Events[event] := [cb]) })
        ctrl.DefineProp("UpdateBounds", { call: (c, x := "", y := "", w := "", h := "") => CodeBox._Move(c, x, y, w, h) })
        ctrl.DefineProp("ExportHTML", { call: (c) => this.Invoke("ExportHTML", c) })
        ctrl.DefineProp("Undo", { call: (c) => this.Invoke("Undo", c) })
        ctrl.DefineProp("Redo", { call: (c) => this.Invoke("Redo", c) })
        ctrl.DefineProp("Beautify", { call: (c) => this.Invoke("Format", c) })
        CodeBoxFocus(c) {
            cr := Buffer(8, 0)
            SendMessage(0x0434, 0, cr.Ptr, c.Hwnd)
            selStart := NumGet(cr, 0, "Int")
            selEnd := NumGet(cr, 4, "Int")
            caretPos := SendMessage(0x0464, 0, 0, c.Hwnd)
            DllCall("user32\SetFocus", "Ptr", c.Hwnd)
            ControlFocus(c.Hwnd)
            CodeBox._SetSelDirectional(c.Hwnd, selStart, selEnd, caretPos)
        }
        ctrl.DefineProp("Focus", { call: CodeBoxFocus })
        ctrl.CopyHidden := false
        ctrl._ZoomPct := 100

        ctrl.DefineProp("ZoomLevel", { get: c => c._ZoomPct, set: (c, v) => CodeBox._ZoomTo(c, v) })
        ctrl.DefineProp("ZoomIn", { call: (c) => CodeBox._ApplyZoom(c, 10) })
        ctrl.DefineProp("ZoomOut", { call: (c) => CodeBox._ApplyZoom(c, -10) })
        ctrl.DefineProp("ZoomReset", { call: (c) => CodeBox._ZoomTo(c, 100) })

        ctrl.CodeBoxLang := language, ctrl.CodeBoxTheme := theme

        this._Instances[ctrl.Hwnd] := ctrl
        this._SubCtrls[ctrl.LineNumCtrl.Hwnd] := ctrl

        this.Emit("OnThemeChange", ctrl)

        this._SetCodeFont(ctrl, "Consolas", 10), this._SetCodeFont(ctrl.LineNumCtrl, "Consolas", 10)

        SendMessage(0x00D3, 3, 0x00050005, ctrl.Hwnd)
        SendMessage(0x0448, 0, 0, ctrl.Hwnd)

        this._SetText(ctrl, text)
        this._Move(ctrl, px, py, pw, ph)

        SendMessage(0x0445, 0, 0x10001 | 0x08 | 0x0400 | 0x00080000, ctrl.Hwnd)
        ctrl.OnCommand(0x0300, ObjBindMethod(this, "_OnChange"))
        ctrl.OnNotify(0x0702, ObjBindMethod(this, "_OnSelectionChange"))
        ctrl.OnCommand(0x0602, ObjBindMethod(this, "_OnScroll"))
        ctrl.OnCommand(0x0400, ObjBindMethod(this, "_OnScroll"))

        ; Native subclassing for robust event capture and standard fixes
        if (!this._SubclassProcCallback) {
            this._SubclassProcCallback := CallbackCreate(CodeBox_SubclassProc, , 6)
        }
        DllCall("comctl32\SetWindowSubclass", "Ptr", ctrl.Hwnd, "Ptr", this._SubclassProcCallback, "Ptr", ctrl.Hwnd, "Ptr", 0)

        this.Emit("OnControlCreated", ctrl)
        return ctrl

    }

    static _OnKeyDown(wParam, lParam, msg, hwnd) {
        if !this._Instances.Has(hwnd) || (WinGetStyle(hwnd) & 0x800)
            return

        ctrl := this._Instances[hwnd]
        
        ; --- Hardened Anti-Snap for ALL Keystrokes (Backspace, Enter, etc) ---
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        if (startSel != endSel) {
            caretLine := SendMessage(0x0436, 0, -1, ctrl.Hwnd)
            startSelLine := SendMessage(0x00C9, startSel, 0, ctrl.Hwnd)
            if (caretLine == startSelLine) {
                lastChar := CodeBox._GetTextRange(ctrl.Hwnd, endSel - 1, endSel)
                if (lastChar == "`r" || lastChar == "`n") {
                    delEnd := endSel - 1
                    if (CodeBox._GetTextRange(ctrl.Hwnd, delEnd - 1, delEnd) == "`r")
                        delEnd--
                    CodeBox._SetSel(ctrl.Hwnd, startSel, delEnd)
                    endSel := delEnd ; Update for subsequent logic
                }
            }
        }
        ; ---------------------------------------------------------------------

        if this._DebounceTimers.Has(hwnd) && (wParam == 0x10 || GetKeyState("Shift", "P")) {
            SetTimer(this._DebounceTimers[hwnd], -400)
        }
        this._Fire(ctrl, "KeyDown", wParam)

        ; Ctrl+= / Ctrl+- / Ctrl+0 zoom shortcuts
        if (GetKeyState("Ctrl")) {
            if (wParam == 0xBB || wParam == 0x6B) { ; = or Numpad+
                this._ApplyZoom(ctrl, 10)
                return 1
            } else if (wParam == 0xBD || wParam == 0x6D) { ; - or Numpad-
                this._ApplyZoom(ctrl, -10)
                return 1
            } else if (wParam == 0x30 || wParam == 0x60) { ; 0 or Numpad0
                this._ZoomTo(ctrl, 100)
                return 1
            }
        }

            ; Fix native RichEdit bug where deleting a multi-line selection fails to remove the trailing newlines
            if (wParam == 8 || wParam == 46) {
                if (startSel != endSel) {
                    if !this.Emit("OnKeyDown", ctrl, wParam) {
                        this.Emit("PushHistory", ctrl, wParam == 8 ? "Backspace" : "Delete")
                        this._InsertText(ctrl.Hwnd, "")
                    }
                    return 1
                }
            }

        if this.Emit("OnKeyDown", ctrl, wParam)
            return 1
    }

    static _OnChar(wParam, lParam, msg, hwnd) {
        if !this._Instances.Has(hwnd) || (WinGetStyle(hwnd) & 0x800)
            return

        ; Block Ctrl+Z (26) and Ctrl+Y (25) from reaching native RichEdit undo buffer
        ; This prevents zooming from being undone natively, since we use custom history.
        if (wParam == 26 || wParam == 25)
            return 1

        ctrl := this._Instances[hwnd]
        char := Chr(wParam)
        this._Fire(ctrl, "Type", char)

        if this.Emit("OnChar", ctrl, wParam)
            return 1
    }

    static _OnLButtonDown(wParam, lParam, msg, hwnd) {
        if this._SubCtrls.Has(hwnd) {
            ctrl := this._SubCtrls[hwnd]
            DllCall("user32\SetFocus", "Ptr", ctrl.Hwnd)
            if this._DebounceTimers.Has(ctrl.Hwnd) {
                SetTimer(this._DebounceTimers[ctrl.Hwnd], -400)
            }
            if this.Emit("OnLButtonDown", ctrl, wParam, lParam, true, hwnd)
                return 1
            return 0
        }
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            
            x := lParam & 0xFFFF
            if (x > 0x7FFF)
                x -= 0x10000
            y := (lParam >> 16) & 0xFFFF
            if (y > 0x7FFF)
                y -= 0x10000
            pt := Buffer(8, 0), NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
            ctrl._AnchorCharIdx := SendMessage(0x00D7, 0, pt.Ptr, hwnd) ; EM_CHARFROMPOS
            
            if this._DebounceTimers.Has(hwnd) {
                SetTimer(this._DebounceTimers[hwnd], -400)
            }
            if this.Emit("OnLButtonDown", ctrl, wParam, lParam, false, hwnd)
                return 1
            this._Fire(ctrl, "Click")
        }
    }

    static _OnLButtonUp(wParam, lParam, msg, hwnd) {
        if this._SubCtrls.Has(hwnd) {
            ctrl := this._SubCtrls[hwnd]
            if this.Emit("OnLButtonUp", ctrl, wParam, lParam, true, hwnd)
                return 1
            return 0
        }
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]

            ; Fix RichEdit Smart Paragraph Selection Snapping
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, hwnd)
            startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
            if (startSel != endSel) {
                x := lParam & 0xFFFF
                if (x > 0x7FFF)
                    x -= 0x10000
                y := (lParam >> 16) & 0xFFFF
                if (y > 0x7FFF)
                    y -= 0x10000
                pt := Buffer(8, 0), NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
                releaseIdx := SendMessage(0x00D7, 0, pt.Ptr, hwnd)

                releaseLine := SendMessage(0x00C9, releaseIdx, 0, hwnd)
                startSelLine := SendMessage(0x00C9, startSel, 0, hwnd)
                endSelLine := SendMessage(0x00C9, endSel, 0, hwnd)

                anchorIdx := ctrl.HasProp("_AnchorCharIdx") ? ctrl._AnchorCharIdx : releaseIdx
                anchorLine := SendMessage(0x00C9, anchorIdx, 0, hwnd)

                caretLine := SendMessage(0x0436, 0, -1, hwnd)

                ; Defer anti-snap logic until AFTER RichEdit processes WM_LBUTTONUP
                antiSnap() {
                    if !DllCall("IsWindow", "Ptr", hwnd)
                        return
                    cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, hwnd)
                    startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
                    
                    startSelLine := SendMessage(0x00C9, startSel, 0, hwnd)
                    endSelLine := SendMessage(0x00C9, endSel, 0, hwnd)
                    caretLine := SendMessage(0x0436, 0, -1, hwnd)
                    
                    getLineEnd(lIdx) {
                        lStart := SendMessage(0x00BB, lIdx, 0, hwnd)
                        lEnd := lStart + SendMessage(0x00C1, lStart, 0, hwnd)
                        while (lEnd > lStart) {
                            ch := CodeBox._GetTextRange(hwnd, lEnd - 1, lEnd)
                            if (ch == "`r" || ch == "`n")
                                lEnd--
                            else
                                break
                        }
                        return lEnd
                    }
                    
                    newStart := startSel
                    newEnd := endSel

                    if (caretLine == startSelLine) {
                        if (startSelLine > releaseLine)
                            newStart := getLineEnd(releaseLine)
                        
                        lineStart := SendMessage(0x00BB, endSelLine, 0, hwnd)
                        if (endSel == lineStart && endSelLine > 0)
                            newEnd := getLineEnd(endSelLine - 1)
                        else if (endSelLine > anchorLine)
                            newEnd := getLineEnd(anchorLine)
                        
                        if (newStart != startSel || newEnd != endSel)
                            CodeBox._SetSelDirectional(hwnd, newStart, newEnd, newStart)
                    }
                }
                SetTimer(antiSnap, -10)
            }

            if this._DebounceTimers.Has(hwnd) {
                SetTimer(this._DebounceTimers[hwnd], -400)
            }
            if this.Emit("OnLButtonUp", ctrl, wParam, lParam, false, hwnd)
                return 1
            this._Fire(ctrl, "SelectEnd")
        }
    }

    static _OnSetCursor(wParam, lParam, msg, hwnd) {
        if this._SubCtrls.Has(hwnd) {
            ctrl := this._SubCtrls[hwnd]
            if this.Emit("OnSetCursor", ctrl, wParam, lParam, true, hwnd)
                return 1
            return 0
        }
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            if this.Emit("OnSetCursor", ctrl, wParam, lParam, false, hwnd)
                return 1
            if ((lParam & 0xFFFF) == 1) {
                DllCall("SetCursor", "Ptr", this._CursorIBeam)
                return 1
            }
        }
    }

    static _OnMouseMove(wParam, lParam, msg, hwnd) {
        if this._SubCtrls.Has(hwnd) {
            ctrl := this._SubCtrls[hwnd]
            if this.Emit("OnMouseMove", ctrl, wParam, lParam, true, hwnd)
                return 1
            return 0
        }
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            if this.Emit("OnMouseMove", ctrl, wParam, lParam, false, hwnd)
                return 1
        }
    }

    static _OnMouseWheel(wParam, lParam, msg, hwnd) {
        ctrl := this._SubCtrls.Has(hwnd) ? this._SubCtrls[hwnd]
              : this._Instances.Has(hwnd) ? this._Instances[hwnd]
              : ""
        if !ctrl
            return

        ; Extract signed wheel delta (high word of wParam)
        delta := (wParam >> 16) & 0xFFFF
        if (delta > 0x7FFF)
            delta -= 0x10000

        ; Ctrl+Wheel = Zoom
        if (GetKeyState("Ctrl")) {
            this._ApplyZoom(ctrl, delta > 0 ? 10 : -10)
            return 1
        }

        ; Scroll ~3 lines per notch (120 = one notch). Get line height from first char.
        ptChar := Buffer(8, 0)
        SendMessage(0x0426, ptChar.Ptr, 0, ctrl.Hwnd) ; EM_POSFROMCHAR char 0
        ptChar2 := Buffer(8, 0)
        lineIdx1 := SendMessage(0x00BB, 1, 0, ctrl.Hwnd) ; EM_LINEINDEX line 1
        if (lineIdx1 > 0)
            SendMessage(0x0426, ptChar2.Ptr, lineIdx1, ctrl.Hwnd)
        lineH := Abs(NumGet(ptChar2, 4, "Int") - NumGet(ptChar, 4, "Int"))
        if (lineH < 8)
            lineH := 20 ; fallback

        scrollPx := Round((-delta / 120) * lineH * 3)

        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS

        si := Buffer(28, 0), NumPut("UInt", 28, si, 0), NumPut("UInt", 0x17, si, 4)
        DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 1, "Ptr", si) ; SB_VERT
        vMax := NumGet(si, 12, "Int"), vPage := NumGet(si, 16, "UInt")
        
        newY := Max(0, Min(NumGet(pt, 4, "Int") + scrollPx, Max(0, vMax - vPage)))
        NumPut("Int", newY, pt, 4)
        SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd) ; EM_SETSCROLLPOS

        this.Emit("OnScroll", ctrl)
        return 1
    }

    static _OnMouseHWheel(wParam, lParam, msg, hwnd) {
        ctrl := this._SubCtrls.Has(hwnd) ? this._SubCtrls[hwnd]
              : this._Instances.Has(hwnd) ? this._Instances[hwnd]
              : ""
        if !ctrl
            return

        delta := (wParam >> 16) & 0xFFFF
        if (delta > 0x7FFF)
            delta -= 0x10000

        scrollPx := Round((delta / 120) * 40)

        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS

        si := Buffer(28, 0), NumPut("UInt", 28, si, 0), NumPut("UInt", 0x17, si, 4)
        DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 0, "Ptr", si) ; SB_HORZ
        hMax := NumGet(si, 12, "Int"), hPage := NumGet(si, 16, "UInt")

        newX := Max(0, Min(NumGet(pt, 0, "Int") + scrollPx, Max(0, hMax - hPage)))
        NumPut("Int", newX, pt, 0)
        SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd) ; EM_SETSCROLLPOS

        this.Emit("OnScroll", ctrl)
        return 1
    }

    static _OnGestureNotify(wParam, lParam, msg, hwnd) {
        ctrl := this._SubCtrls.Has(hwnd) ? this._SubCtrls[hwnd]
              : this._Instances.Has(hwnd) ? this._Instances[hwnd]
              : ""
        if !ctrl
            return

        ; Tell Windows we want to receive zoom (pinch) gestures
        ; GESTURECONFIG struct: dwID=0 (all), dwWant=1 (GC_ALLGESTURES), dwBlock=0
        gc := Buffer(12, 0)
        NumPut("UInt", 0, gc, 0)  ; dwID = 0 (all gestures)
        NumPut("UInt", 1, gc, 4)  ; dwWant = GC_ALLGESTURES
        NumPut("UInt", 0, gc, 8)  ; dwBlock = 0
        DllCall("SetGestureConfig", "Ptr", hwnd, "UInt", 0, "UInt", 1, "Ptr", gc.Ptr, "UInt", 12)
        return 0
    }

    static _OnGesture(wParam, lParam, msg, hwnd) {
        ctrl := this._SubCtrls.Has(hwnd) ? this._SubCtrls[hwnd]
              : this._Instances.Has(hwnd) ? this._Instances[hwnd]
              : ""
        if !ctrl
            return

        ; Decode GESTUREINFO struct
        ; Size: 32 on 32-bit, 48 on 64-bit
        giSize := (A_PtrSize == 8) ? 48 : 32
        gi := Buffer(giSize, 0)
        NumPut("UInt", giSize, gi, 0)
        if !DllCall("GetGestureInfo", "Ptr", lParam, "Ptr", gi.Ptr)
            return

        dwFlags := NumGet(gi, 4, "UInt")
        dwID := NumGet(gi, 8, "UInt")
        ullArguments := NumGet(gi, (A_PtrSize == 8) ? 32 : 24, "Int64")

        ; GID_ZOOM = 3
        if (dwID == 3) {
            GF_BEGIN := 1
            if (dwFlags & GF_BEGIN) {
                ctrl._GestureZoomStart := ullArguments
                DllCall("CloseGestureInfoHandle", "Ptr", lParam)
                return 1
            }

            if ctrl.HasProp("_GestureZoomStart") && ctrl._GestureZoomStart > 0 {
                ratio := ullArguments / ctrl._GestureZoomStart
                if (ratio > 1.05) {
                    this._ApplyZoom(ctrl, 10)
                    ctrl._GestureZoomStart := ullArguments
                } else if (ratio < 0.95) {
                    this._ApplyZoom(ctrl, -10)
                    ctrl._GestureZoomStart := ullArguments
                }
            }
            DllCall("CloseGestureInfoHandle", "Ptr", lParam)
            return 1
        }

        ; GID_PAN = 4 — treat as scroll
        if (dwID == 4) {
            ; Let default handling occur for pan
            return
        }
    }

    static _ApplyZoom(ctrl, deltaPct) {
        ; deltaPct: +10 to zoom in 10%, -10 to zoom out 10%
        if !ctrl.HasProp("_ZoomPct")
            ctrl._ZoomPct := 100

        ctrl._ZoomPct := Max(50, Min(500, ctrl._ZoomPct + deltaPct))
        pct := ctrl._ZoomPct

        ; EM_SETZOOM uses numerator/denominator. We use pct/100 simplified.
        ; RichEdit requires both to be between 1 and 64, so we scale to fit.
        if (pct == 100) {
            ; Reset: passing 0/0 clears zoom
            SendMessage(0x04E1, 0, 0, ctrl.Hwnd)
        } else {
            ; Find best num/den that fits in 1-64 range
            num := pct, den := 100
            ; Simplify by GCD
            a := num, b := den
            while (b != 0) {
                t := Mod(a, b), a := b, b := t
            }
            num := num // a, den := den // a

            ; Scale down if either exceeds 64
            while (num > 64 || den > 64) {
                num := Max(1, num // 2), den := Max(1, den // 2)
            }

            SendMessage(0x04E1, num, den, ctrl.Hwnd)
        }

        ; Force line numbers and scrollbar to resync
        this.Emit("OnScroll", ctrl)
        this.Emit("OnZoom", ctrl, pct)
        this._Fire(ctrl, "Zoom", pct)
    }

    static _ZoomTo(ctrl, pct) {
        ctrl._ZoomPct := 100 ; Reset base so delta math works
        this._ApplyZoom(ctrl, pct - 100)
    }

    static _OnSelectionChange(ctrl, lParam) {
        if (ctrl.HasProp("SuppressSelChangeEvent") && ctrl.SuppressSelChangeEvent)
            return
        hwnd := ctrl.Hwnd
        if this._DebounceTimers.Has(hwnd) && (GetKeyState("LButton", "P") || GetKeyState("Shift", "P")) {
            SetTimer(this._DebounceTimers[hwnd], -400)
        }
        this.Emit("OnSelectionChange", ctrl)
    }

    static _OnScroll(ctrl, *) {
        if ctrl.IsHighlighting
            return
        this.Emit("OnScroll", ctrl)
    }

    static _OnChange(ctrl, *) {
        if ctrl.IsHighlighting || ctrl._HexView
            return
        this._Fire(ctrl, "Change", this._GetText(ctrl))
        hwnd := ctrl.Hwnd
        if !this._DebounceTimers.Has(hwnd) {
            timerCallback(*) {
                if (GetKeyState("LButton", "P") || GetKeyState("Shift", "P")) {
                    SetTimer(this._DebounceTimers[hwnd], -200)
                } else {
                    this.Emit("OnChange", ctrl)
                }
            }
            this._DebounceTimers[hwnd] := timerCallback
        }
        SetTimer(this._DebounceTimers[hwnd], -400)
    }

    static _OnSetFocus(wParam, lParam, msg, hwnd) {
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            if ctrl.HasProp("CodeBoxTheme") {
                this.Emit("OnThemeChange", ctrl)
            }
        }
    }

    static _OnContextMenu(wParam, lParam, msg, hwnd) {
        targetHwnd := hwnd
        if !this._Instances.Has(targetHwnd) && this._Instances.Has(wParam) {
            targetHwnd := wParam
        }
        if this._Instances.Has(targetHwnd) {
            ctrl := this._Instances[targetHwnd]
            x := lParam & 0xFFFF
            y := (lParam >> 16) & 0xFFFF
            if (x > 32767)
                x -= 65536
            if (y > 32767)
                y -= 65536
            
            ; Postpone context menu display to let the subclass callback return instantly and prevent re-entrancy crashes!
            SetTimer(() => this._ShowContextMenuAsync(ctrl, x, y), -1)
            return 0
        }
    }

    static _ShowContextMenuAsync(ctrl, x, y) {
        this._Fire(ctrl, "ContextMenu", x, y)
        this.Emit("OnContextMenu", ctrl, x, y)
    }

    static _OnDestroy(wParam, lParam, msg, hwnd) {
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            this.Emit("OnDestroy", ctrl)
            if this._DebounceTimers.Has(hwnd)
                SetTimer(this._DebounceTimers[hwnd], 0), this._DebounceTimers.Delete(hwnd)
            
            if (this._SubclassProcCallback) {
                DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", this._SubclassProcCallback, "Ptr", hwnd)
            }
            
            this._Instances.Delete(hwnd)
        }
        if this._SubCtrls.Has(hwnd)
            this._SubCtrls.Delete(hwnd)
    }



    static _OnShowWindow(wParam, lParam, msg, hwnd) {
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            this.Emit("OnShowWindow", ctrl, wParam)
        }
    }

    static _OnWindowPosChanged(wParam, lParam, msg, hwnd) {
        if this._Instances.Has(hwnd) {
            ctrl := this._Instances[hwnd]
            this.Emit("OnWindowPosChanged", ctrl)
        }
    }

    static _Move(ctrl, x := "", y := "", w := "", h := "") {
        if (x != "")
            ctrl._x := x, ctrl._y := y, ctrl._w := w, ctrl._h := h
        cx := ctrl._x, cy := ctrl._y, cw := ctrl._w, ch := ctrl._h
        zRatio := (ctrl.HasProp("ZoomNum") && ctrl.ZoomNum > 0 && ctrl.ZoomDen > 0) ? (ctrl.ZoomNum / ctrl.ZoomDen) : 1.0
        lnW := ctrl._LineNums ? Max(45, Floor(45 * zRatio)) : 0
        if ctrl._LineNums
            ctrl.LineNumCtrl.Move(cx, cy, lnW, ch)
        ctrl.Move(cx + lnW, cy, cw - lnW, ch)
    }

    static _Fire(ctrl, event, args*) {
        if ctrl.Events.Has(event)
            for cb in ctrl.Events[event]
                try cb(ctrl, args*)
    }

    static _GetText(ctrl) {
        len := SendMessage(0x000E, 0, 0, ctrl.Hwnd)
        if (len == 0)
            return ""
        buf := Buffer((len + 1) * 2, 0), SendMessage(0x000D, len + 1, buf.Ptr, ctrl.Hwnd)
        return StrReplace(StrGet(buf), "`r`n", "`n")
    }

    static _SetText(ctrl, text, triggerHighlight := true) {
        if (ctrl._HexView) {
            ctrl.OriginalText := text
            text := CodeBox.Invoke("ToHex", text) || text
        }
        ctrl.IsHighlighting := true
        textStr := StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "`r`n")
        SendMessage(0x000C, 0, StrPtr(textStr), ctrl.Hwnd)
        SendMessage(0x00B1, -1, 0, ctrl.Hwnd)
        this._SetSel(ctrl.Hwnd, 0, 0)

        if (ctrl.HasProp("_ZoomPct") && ctrl._ZoomPct != 100)
            this._ApplyZoom(ctrl, 0)

        ctrl.History := []
        ctrl.HistoryIndex := 0
        ctrl.LastHistoryText := ""
        this.Emit("PushHistory", ctrl, "Initial Load")

        ctrl.IsHighlighting := false
        if triggerHighlight {
            this.Emit("OnChange", ctrl)
            SendMessage(0x00B1, -1, 0, ctrl.Hwnd)
            this._SetSel(ctrl.Hwnd, 0, 0)
        }
    }

    static _GetTextRange(hwnd, start, end) {
        if (start >= end)
            return ""
        ; TEXTRANGE uses 8 bytes for CHARRANGE + A_PtrSize for the pointer.
        ; On 64-bit, the pointer aligns perfectly at offset 8 (total 16 bytes).
        ; On 32-bit, the pointer is at offset 8 (total 12 bytes).
        tr := Buffer(8 + A_PtrSize, 0), NumPut("Int", start, tr, 0), NumPut("Int", end, tr, 4)
        buf := Buffer((end - start) * 4 + 2, 0), NumPut("Ptr", buf.Ptr, tr, 8)
        SendMessage(0x044B, 0, tr.Ptr, hwnd)
        return StrGet(buf, "UTF-16")
    }

    static _InsertText(hwnd, text) {
        text := StrReplace(text, "`r", "`n")
        SendMessage(0x00C2, 1, StrPtr(text), hwnd)
    }

    static _SetSel(hwnd, start, end) {
        SendMessage(0x00B1, start, end, hwnd)
    }

    static _SetSelDirectional(hwnd, startSel, endSel, caretPos) {
        if (caretPos == startSel) {
            SendMessage(0x00B1, endSel, startSel, hwnd)
        } else {
            SendMessage(0x00B1, startSel, endSel, hwnd)
        }
    }

    static _SetFormat(hwnd, colorRGB, isDefault := false, bold := false, underline := 0, backColorRGB := -1) {
        bgr := ((colorRGB & 0xFF0000) >> 16) | (colorRGB & 0x00FF00) | ((colorRGB & 0x0000FF) << 16)
        cf2 := Buffer(116, 0), NumPut("UInt", 116, cf2, 0)
        mask := 0x40000000 | 0x00000001 | 0x00000004
        effects := (bold ? 1 : 0) | (underline ? 4 : 0)
        
        if (backColorRGB != -1) {
            mask |= 0x04000000 ; CFM_BACKCOLOR
            if (backColorRGB == -2) {
                effects |= 0x04000000 ; CFE_AUTOBACKCOLOR
            } else {
                bgBgr := ((backColorRGB & 0xFF0000) >> 16) | (backColorRGB & 0x00FF00) | ((backColorRGB & 0x0000FF) << 16)
                NumPut("UInt", bgBgr, cf2, 96) ; crBackColor (Offset 96 due to 4-byte struct alignment in Unicode CHARFORMAT2)
            }
        } else if (isDefault) {
            mask |= 0x04000000 ; CFM_BACKCOLOR
            effects |= 0x04000000 ; CFE_AUTOBACKCOLOR
        }
            
        NumPut("UInt", mask, cf2, 4), NumPut("UInt", effects, cf2, 8), NumPut("UInt", bgr, cf2, 20)
        SendMessage(0x0444, isDefault ? 4 : 1, cf2.Ptr, hwnd)
    }

    static _SetCodeFont(ctrl, fontName, fontSize) {
        cf2 := Buffer(116, 0), NumPut("UInt", 116, cf2, 0), NumPut("UInt", 0x20000000 | 0x80000000, cf2, 4)
        NumPut("Int", fontSize * 20, cf2, 12), StrPut(fontName, cf2.Ptr + 26, 32, "UTF-16")
        SendMessage(0x0444, 4, cf2.Ptr, IsObject(ctrl) ? ctrl.Hwnd : ctrl)
    }

    static _ColorToHex(c) {
        return Format("#{:06X}", c)
    }
}

CodeBox_SubclassProc(hwnd, msg, wParam, lParam, id, refData) {

    ; 1. Fix cursor flickering (WM_SETCURSOR)
    if (msg == 0x0020) { ; WM_SETCURSOR
        if ((lParam & 0xFFFF) == 1) { ; HTCLIENT
            DllCall("SetCursor", "Ptr", CodeBox._CursorIBeam)
            return 1
        }
    }
    
    ; 2. Intercept context menu triggers (WM_CONTEXTMENU)
    if (msg == 0x007B) { ; WM_CONTEXTMENU
        CodeBox._OnContextMenu(wParam, lParam, msg, hwnd)
        return 0
    }

    return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}