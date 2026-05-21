#Requires AutoHotkey v2.0

class CodeBox_LineHighlighter {
    static Name := "LineHighlighter"
    
    ; ☢️ NUCLEAR MODE ☢️
    ; Brute-forces native COM rendering and coordinate hashing every 15ms
    static NuclearMode := false

    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarChk := guiObj.Add("CheckBox", "x" x " y" (y+3) " cWhite Checked", "Highlight Line")
        this.ToolbarChk.OnEvent("Click", (c, *) => (
            ctrl.LineHighlighterEnabled := c.Value,
            c.Value ? this.QueueUpdate(ctrl, true) : this.HideHighlight(ctrl),
            ctrl.Focus()
        ))
        x += 105
        
        ; Developer keybind hook: MyCodeBox.ToggleNuclearHighlight()
        ctrl.DefineProp("ToggleNuclearHighlight", { call: (c) => this.ToggleNuclearMode(c) })
    }

    static OnEnable(ctrl) {
        ctrl.LineHighlighterEnabled := true
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Value := 1
        this.QueueUpdate(ctrl, true)
    }

    static OnDisable(ctrl) {
        ctrl.LineHighlighterEnabled := false
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Value := 0
        this.HideHighlight(ctrl)
    }

    static OnDestroy(ctrl) {
        if ctrl.HasProp("HLTimer")
            SetTimer(ctrl.HLTimer, 0)
        if ctrl.HasProp("NuclearTimer")
            SetTimer(ctrl.NuclearTimer, 0)
            
        this.HideHighlight(ctrl)
        
        if ctrl.HasProp("HLFiller")
            ctrl.HLFiller.Destroy()
        if ctrl.HasProp("HLGutterFiller")
            ctrl.HLGutterFiller.Destroy()
    }

    ; ====================================================================================
    ; ULTRA-FAST EVENT HOOKS 
    ; ====================================================================================
    static OnSelectionChange(ctrl, *)  => (this.NuclearMode ? "" : this.QueueUpdate(ctrl))
    static OnScroll(ctrl, *)           => (this.NuclearMode ? "" : this.QueueUpdate(ctrl))
    static OnChange(ctrl, *)           => (this.NuclearMode ? "" : this.QueueUpdate(ctrl))
    static OnWindowPosChanged(ctrl, *) => (this.NuclearMode ? "" : this.QueueUpdate(ctrl, true))
    static OnZoom(ctrl, *)             => (this.NuclearMode ? "" : this.QueueUpdate(ctrl, true))
    
    ; Listens for CodeBox_Highlighter finishing its async chunks so we never lose our highlight
    static OnHighlight(ctrl, *) {
        if !this.NuclearMode
            this.QueueUpdate(ctrl, true)
    }
    
    static OnThemeChange(ctrl, *) {
        if ctrl.HasProp("LastHLColor")
            ctrl.DeleteProp("LastHLColor")
        if !this.NuclearMode
            this.QueueUpdate(ctrl, true)
    }

    static QueueUpdate(ctrl, force := false) {
        if !DllCall("IsWindow", "Ptr", ctrl.Hwnd) || (ctrl.HasProp("LineHighlighterEnabled") && !ctrl.LineHighlighterEnabled)
            return

        if !ctrl.HasProp("HLTimer")
            ctrl.HLTimer := ObjBindMethod(this, "UpdateHighlight", ctrl, false)
            
        ctrl.HLForceNext := force || (ctrl.HasProp("HLForceNext") && ctrl.HLForceNext)
        SetTimer(ctrl.HLTimer, -5) ; Instantly yield to OS thread for 0.0ms typing latency
    }

    ; ====================================================================================
    ; ☢️ NUCLEAR MODE ☢️ 
    ; ====================================================================================
    static ToggleNuclearMode(ctrl) {
        this.NuclearMode := !this.NuclearMode
        if (this.NuclearMode) {
            if !ctrl.HasProp("NuclearTimer")
                ctrl.NuclearTimer := ObjBindMethod(this, "NuclearUpdate", ctrl)
            SetTimer(ctrl.NuclearTimer, 15)
            ToolTip("☢️ GOD-TIER COM HIGHLIGHTER: NUCLEAR MODE ON ☢️")
        } else {
            if ctrl.HasProp("NuclearTimer")
                SetTimer(ctrl.NuclearTimer, 0)
            ToolTip("☢️ GOD-TIER COM HIGHLIGHTER: NUCLEAR MODE OFF ☢️")
            this.QueueUpdate(ctrl, true)
        }
        SetTimer(() => ToolTip(), -2000)
        return this.NuclearMode
    }

    static NuclearUpdate(ctrl) {
        if !DllCall("IsWindow", "Ptr", ctrl.Hwnd) || !ctrl.LineHighlighterEnabled {
            if ctrl.HasProp("NuclearTimer")
                SetTimer(ctrl.NuclearTimer, 0)
            return
        }
        ctrl.HLForceNext := true
        this.UpdateHighlight(ctrl, true)
    }

    ; ====================================================================================
    ; GOD-TIER NATIVE HYBRID RENDERER
    ; ====================================================================================
    static UpdateHighlight(ctrl, isNuclear := false) {
        if !DllCall("IsWindow", "Ptr", ctrl.Hwnd)
            return
            
        force := isNuclear || (ctrl.HasProp("HLForceNext") && ctrl.HLForceNext)
        ctrl.HLForceNext := false

        ; 1. Only show if editor is actively focused
        focused := DllCall("GetFocus", "Ptr")
        if (focused != ctrl.Hwnd && (!ctrl.HasProp("LineNumCtrl") || focused != ctrl.LineNumCtrl.Hwnd))
            return this.HideHighlight(ctrl)

        ; 2. "doesn't run when selecting / highlighting text"
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")
        if (startSel != endSel)
            return this.HideHighlight(ctrl)

        lineIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd) ; EM_EXLINEFROMCHAR
        
        themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        hlColor := themeC.Has("LineHighlight") ? themeC["LineHighlight"] : 0x2A2D2E
        hlBGR := this.RGBtoBGR(hlColor)
        bgBGR := this.RGBtoBGR(themeC["Background"])

        doc := CodeBox_Highlighter.GetITextDocument(ctrl.Hwnd)
        if !doc
            return

        ; ==============================================================================
        ; PHASE 1: NATIVE COM TEXT BACKGROUND (Flawless syntax color preservation)
        ; ==============================================================================
        if (force || !ctrl.HasProp("LastHLLine") || ctrl.LastHLLine != lineIdx) {
            
            ; Natively wipe previous line's background
            if (ctrl.HasProp("LastHLLine") && ctrl.LastHLLine != -1 && ctrl.LastHLLine != lineIdx) {
                oldStart := SendMessage(0x00BB, ctrl.LastHLLine, 0, ctrl.Hwnd)
                oldLen := SendMessage(0x00C1, oldStart, 0, ctrl.Hwnd)
                if (oldStart >= 0) {
                    ctrl.IsHighlighting := true
                    doc.Freeze()
                    rngOld := doc.Range(oldStart, oldStart + oldLen)
                    rngOld.Font.BackColor := bgBGR
                    doc.Unfreeze()
                    ctrl.IsHighlighting := false
                }
            }
            
            ; Natively apply new line's background
            charStart := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)
            charLen := SendMessage(0x00C1, charStart, 0, ctrl.Hwnd)
            if (charStart >= 0) {
                ctrl.IsHighlighting := true
                doc.Freeze()
                rngNew := doc.Range(charStart, charStart + charLen)
                rngNew.Font.BackColor := hlBGR
                doc.Unfreeze()
                ctrl.IsHighlighting := false
            }
            ctrl.LastHLLine := lineIdx
        }

        ; ==============================================================================
        ; PHASE 2: NATIVE GUTTER BACKGROUND 
        ; ==============================================================================
        hasGutter := (ctrl.LineNumbers && ctrl.HasProp("LineNumCtrl") && DllCall("IsWindowVisible", "Ptr", ctrl.LineNumCtrl.Hwnd))
        if hasGutter {
            docG := CodeBox_Highlighter.GetITextDocument(ctrl.LineNumCtrl.Hwnd)
            if docG {
                if (force || !ctrl.HasProp("LastHLGutterLine") || ctrl.LastHLGutterLine != lineIdx) {
                    
                    ; Temporarily disable ReadOnly so TOM doesn't throw Access Denied
                    SendMessage(0x00CF, 0, 0, ctrl.LineNumCtrl.Hwnd)
                    
                    if (ctrl.HasProp("LastHLGutterLine") && ctrl.LastHLGutterLine != -1 && ctrl.LastHLGutterLine != lineIdx) {
                        oldStartG := SendMessage(0x00BB, ctrl.LastHLGutterLine, 0, ctrl.LineNumCtrl.Hwnd)
                        oldLenG := SendMessage(0x00C1, oldStartG, 0, ctrl.LineNumCtrl.Hwnd)
                        if (oldStartG >= 0) {
                            ctrl.IsHighlighting := true
                            docG.Freeze()
                            rngOldG := docG.Range(oldStartG, oldStartG + oldLenG)
                            rngOldG.Font.BackColor := bgBGR
                            docG.Unfreeze()
                            ctrl.IsHighlighting := false
                        }
                    }
                    
                    charStartG := SendMessage(0x00BB, lineIdx, 0, ctrl.LineNumCtrl.Hwnd)
                    charLenG := SendMessage(0x00C1, charStartG, 0, ctrl.LineNumCtrl.Hwnd)
                    if (charStartG >= 0) {
                        ctrl.IsHighlighting := true
                        docG.Freeze()
                        rngNewG := docG.Range(charStartG, charStartG + charLenG)
                        rngNewG.Font.BackColor := hlBGR
                        docG.Unfreeze()
                        ctrl.IsHighlighting := false
                    }
                    
                    ; Re-enable ReadOnly
                    SendMessage(0x00CF, 1, 0, ctrl.LineNumCtrl.Hwnd)
                    
                    ctrl.LastHLGutterLine := lineIdx
                }
            }
        }

        ; ==============================================================================
        ; PHASE 3: THE PHANTOM WHITESPACE FILLER
        ; ==============================================================================
        charStart := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)
        charLen := SendMessage(0x00C1, charStart, 0, ctrl.Hwnd)
        endChar := charStart + charLen - 1
        if (endChar < charStart)
            endChar := charStart
            
        ptEnd := Buffer(8, 0)
        SendMessage(0x0426, ptEnd.Ptr, endChar, ctrl.Hwnd) ; EM_POSFROMCHAR
        
        ; Add 4 pixel padding to ensure the text overhang is never accidentally clipped
        endX := NumGet(ptEnd, 0, "Int") + 4 
        
        ; If line is completely empty, start fill at left margin
        if (charLen <= 1) { 
            chunk := CodeBox._GetTextRange(ctrl.Hwnd, charStart, charStart + 1)
            if (chunk == "`r" || chunk == "`n" || chunk == "")
                endX := 0
        }
        
        ptStart := Buffer(8, 0)
        SendMessage(0x0426, ptStart.Ptr, charStart, ctrl.Hwnd)
        lineY := NumGet(ptStart, 4, "Int")
        
        rect := Buffer(16, 0), DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", rect)
        cw := NumGet(rect, 8, "Int"), ch := NumGet(rect, 12, "Int")
        fillW := cw - endX
        
        ; Calculate Wrap-Aware Line Height
        nextLineChar := SendMessage(0x00BB, lineIdx + 1, 0, ctrl.Hwnd)
        if (nextLineChar > charStart) {
            ptNext := Buffer(8, 0), SendMessage(0x0426, ptNext.Ptr, nextLineChar, ctrl.Hwnd)
            nextY := NumGet(ptNext, 4, "Int")
            lineH := (nextY > lineY) ? (nextY - lineY) : 20
        } else {
            char1 := SendMessage(0x00BB, 1, 0, ctrl.Hwnd)
            if (char1 > 0) {
                pt0 := Buffer(8, 0), pt1 := Buffer(8, 0)
                SendMessage(0x0426, pt0.Ptr, 0, ctrl.Hwnd)
                SendMessage(0x0426, pt1.Ptr, char1, ctrl.Hwnd)
                lineH := NumGet(pt1, 4, "Int") - NumGet(pt0, 4, "Int")
            } else {
                dpi := DllCall("user32\GetDpiForWindow", "Ptr", ctrl.Hwnd, "UInt")
                zRatio := ctrl.HasProp("ZoomNum") && ctrl.HasProp("ZoomDen") && ctrl.ZoomDen > 0 ? ctrl.ZoomNum / ctrl.ZoomDen : 1.0
                lineH := Round(16 * zRatio * (dpi / 96))
            }
        }
        if (lineH <= 0)
            lineH := 20

        ; Viewport Culling & Math Slicing (Prevents toolbar bleeding when scrolling)
        drawY := lineY
        drawH := lineH
        if (drawY < 0) {
            drawH += drawY, drawY := 0
        }
        if (drawY + drawH > ch) {
            drawH := ch - drawY
        }
        
        if (drawH <= 0 || fillW <= 0) {
            if ctrl.HasProp("HLFiller") && ctrl.HLFiller.Visible
                ctrl.HLFiller.Visible := false
        } else {
            ptMap := Buffer(8, 0)
            NumPut("Int", endX, ptMap, 0), NumPut("Int", drawY, ptMap, 4)
            DllCall("MapWindowPoints", "Ptr", ctrl.Hwnd, "Ptr", ctrl.Gui.Hwnd, "Ptr", ptMap, "UInt", 1)
            guiX := NumGet(ptMap, 0, "Int"), guiY := NumGet(ptMap, 4, "Int")
            
            if !ctrl.HasProp("HLFiller")
                ctrl.HLFiller := ctrl.Gui.Add("Text", "+Disabled +E0x20 -Border Background" Format("{:06X}", hlColor))
            
            if (!ctrl.HasProp("LastHLColor") || ctrl.LastHLColor != hlColor)
                ctrl.HLFiller.Opt("Background" Format("{:06X}", hlColor))
                
            DllCall("SetWindowPos", "Ptr", ctrl.HLFiller.Hwnd, "Ptr", 0, "Int", guiX, "Int", guiY, "Int", fillW, "Int", drawH, "UInt", 0x0010)
            if !ctrl.HLFiller.Visible
                ctrl.HLFiller.Visible := true
            DllCall("InvalidateRect", "Ptr", ctrl.HLFiller.Hwnd, "Ptr", 0, "Int", 1)
        }

        ; ==============================================================================
        ; PHASE 4: GUTTER WHITESPACE FILLER
        ; ==============================================================================
        if hasGutter {
            charStartG := SendMessage(0x00BB, lineIdx, 0, ctrl.LineNumCtrl.Hwnd)
            charLenG := SendMessage(0x00C1, charStartG, 0, ctrl.LineNumCtrl.Hwnd)
            endCharG := charStartG + charLenG - 1
            if (endCharG < charStartG)
                endCharG := charStartG
                
            ptEndG := Buffer(8, 0), SendMessage(0x0426, ptEndG.Ptr, endCharG, ctrl.LineNumCtrl.Hwnd)
            endXG := NumGet(ptEndG, 0, "Int") + 4
            
            if (charLenG <= 1)
                endXG := 0
                
            rectG := Buffer(16, 0), DllCall("GetClientRect", "Ptr", ctrl.LineNumCtrl.Hwnd, "Ptr", rectG)
            cwG := NumGet(rectG, 8, "Int")
            fillWG := cwG - endXG
            
            if (drawH <= 0 || fillWG <= 0) {
                if ctrl.HasProp("HLGutterFiller") && ctrl.HLGutterFiller.Visible
                    ctrl.HLGutterFiller.Visible := false
            } else {
                ptMapG := Buffer(8, 0)
                NumPut("Int", endXG, ptMapG, 0), NumPut("Int", drawY, ptMapG, 4)
                DllCall("MapWindowPoints", "Ptr", ctrl.LineNumCtrl.Hwnd, "Ptr", ctrl.Gui.Hwnd, "Ptr", ptMapG, "UInt", 1)
                guiXG := NumGet(ptMapG, 0, "Int"), guiYG := NumGet(ptMapG, 4, "Int")
                
                if !ctrl.HasProp("HLGutterFiller")
                    ctrl.HLGutterFiller := ctrl.Gui.Add("Text", "+Disabled +E0x20 -Border Background" Format("{:06X}", hlColor))
                
                if (!ctrl.HasProp("LastHLColor") || ctrl.LastHLColor != hlColor)
                    ctrl.HLGutterFiller.Opt("Background" Format("{:06X}", hlColor))
                    
                DllCall("SetWindowPos", "Ptr", ctrl.HLGutterFiller.Hwnd, "Ptr", 0, "Int", guiXG, "Int", guiYG, "Int", fillWG, "Int", drawH, "UInt", 0x0010)
                if !ctrl.HLGutterFiller.Visible
                    ctrl.HLGutterFiller.Visible := true
                DllCall("InvalidateRect", "Ptr", ctrl.HLGutterFiller.Hwnd, "Ptr", 0, "Int", 1)
            }
        }
        
        ctrl.LastHLColor := hlColor
    }

    static HideHighlight(ctrl) {
        themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        bgBGR := this.RGBtoBGR(themeC["Background"])

        ; Erase Main COM Formatting
        if (ctrl.HasProp("LastHLLine") && ctrl.LastHLLine != -1) {
            doc := CodeBox_Highlighter.GetITextDocument(ctrl.Hwnd)
            if doc {
                startChar := SendMessage(0x00BB, ctrl.LastHLLine, 0, ctrl.Hwnd)
                lenChar := SendMessage(0x00C1, startChar, 0, ctrl.Hwnd)
                if (startChar >= 0) {
                    ctrl.IsHighlighting := true
                    doc.Freeze()
                    rng := doc.Range(startChar, startChar + lenChar)
                    rng.Font.BackColor := bgBGR
                    doc.Unfreeze()
                    ctrl.IsHighlighting := false
                }
            }
            ctrl.LastHLLine := -1
        }
        
        ; Erase Gutter COM Formatting
        if (ctrl.HasProp("LastHLGutterLine") && ctrl.LastHLGutterLine != -1 && ctrl.HasProp("LineNumCtrl")) {
            docG := CodeBox_Highlighter.GetITextDocument(ctrl.LineNumCtrl.Hwnd)
            if docG {
                startCharG := SendMessage(0x00BB, ctrl.LastHLGutterLine, 0, ctrl.LineNumCtrl.Hwnd)
                lenCharG := SendMessage(0x00C1, startCharG, 0, ctrl.LineNumCtrl.Hwnd)
                if (startCharG >= 0) {
                    ctrl.IsHighlighting := true
                    SendMessage(0x00CF, 0, 0, ctrl.LineNumCtrl.Hwnd)
                    docG.Freeze()
                    rngG := docG.Range(startCharG, startCharG + lenCharG)
                    rngG.Font.BackColor := bgBGR
                    docG.Unfreeze()
                    SendMessage(0x00CF, 1, 0, ctrl.LineNumCtrl.Hwnd)
                    ctrl.IsHighlighting := false
                }
            }
            ctrl.LastHLGutterLine := -1
        }

        if ctrl.HasProp("HLFiller") && ctrl.HLFiller.Visible
            ctrl.HLFiller.Visible := false
            
        if ctrl.HasProp("HLGutterFiller") && ctrl.HLGutterFiller.Visible
            ctrl.HLGutterFiller.Visible := false
    }

    static RGBtoBGR(rgb) => ((rgb & 0xFF0000) >> 16) | (rgb & 0x00FF00) | ((rgb & 0x0000FF) << 16)
}