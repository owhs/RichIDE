class CodeBox_LineNumbers {
    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarChk := guiObj.Add("CheckBox", "x" x " y" (y+3) " cWhite Checked", "Lines")
        this.ToolbarChk.OnEvent("Click", (c, *) => (ctrl.LineNumbers := c.Value, ctrl.Focus()))
        x += 65
    }

    static OnDisable(ctrl) {
        ctrl.LineNumbers := false
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Visible := false
    }
    static OnEnable(ctrl) {
        ctrl.LineNumbers := true
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Visible := true
    }

    static OnScroll(ctrl) {
        this.Sync(ctrl)
    }
    static OnHighlight(ctrl) {
        this.Sync(ctrl)
    }

    static OnLButtonDown(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        if (isSubCtrl && hwnd == ctrl.LineNumCtrl.Hwnd && CodeBox.IsPluginEnabled("Folding")) {
            x := lParam & 0xFFFF
            ctrl.LineNumCtrl.GetPos(, , &w)
            if (x > w - 20) {
                y := (lParam >> 16) & 0xFFFF
                pt := Buffer(8, 0), NumPut("Int", 1, pt, 0), NumPut("Int", y, pt, 4)
                charIdx := SendMessage(0x0427, 0, pt.Ptr, ctrl.Hwnd)
                lineIdx := SendMessage(0x0436, 0, charIdx, ctrl.Hwnd)
                CodeBox.Invoke("ToggleFoldLine", ctrl, lineIdx)
                return 1
            }
        }
        return 0
    }

    static OnSetCursor(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        if (isSubCtrl && hwnd == ctrl.LineNumCtrl.Hwnd) {
            DllCall("GetCursorPos", "Ptr", pt := Buffer(8))
            DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt)
            x := NumGet(pt, 0, "Int")
            ctrl.LineNumCtrl.GetPos(, , &w)
            hCursor := (CodeBox.IsPluginEnabled("Folding") && x > w - 20) ? CodeBox._CursorHand : CodeBox._CursorArrow
            DllCall("SetCursor", "Ptr", hCursor)
            return 1
        }
        return 0
    }

    static OnMouseMove(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        if (isSubCtrl && hwnd == ctrl.LineNumCtrl.Hwnd) {
            x := lParam & 0xFFFF
            y := (lParam >> 16) & 0xFFFF
            ctrl.LineNumCtrl.GetPos(, , &w)
            hCursor := (CodeBox.IsPluginEnabled("Folding") && x > w - 20) ? CodeBox._CursorHand : CodeBox._CursorArrow
            DllCall("SetCursor", "Ptr", hCursor)
            
            pt := Buffer(8, 0), NumPut("Int", 1, pt, 0), NumPut("Int", y, pt, 4)
            charIdx := SendMessage(0x0427, 0, pt.Ptr, ctrl.Hwnd)
            vLine := SendMessage(0x0436, 0, charIdx, ctrl.Hwnd)
            
            ttText := ""
            if (ctrl.HasProp("VisualErrors") && ctrl.VisualErrors.Has(vLine))
                ttText := "Error: " ctrl.VisualErrors[vLine]
            else if (ctrl.HasProp("VisualWarnings") && ctrl.VisualWarnings.Has(vLine))
                ttText := "Warning: " ctrl.VisualWarnings[vLine]
            
            if (ttText != (ctrl.HasProp("LastTT") ? ctrl.LastTT : "")) {
                ToolTip(ttText)
                ctrl.LastTT := ttText
            }
            return 1
        }
        if (!isSubCtrl && ctrl.HasProp("LastTT") && ctrl.LastTT != "") {
            ToolTip()
            ctrl.LastTT := ""
        }
        return 0
    }

    static Sync(ctrl) {
        if !ctrl._LineNums
            return

        numBuf := Buffer(4, 0), denBuf := Buffer(4, 0)
        res := SendMessage(0x04E0, numBuf.Ptr, denBuf.Ptr, , "ahk_id " ctrl.Hwnd)
        if (res) {
            num := NumGet(numBuf, "UInt"), den := NumGet(denBuf, "UInt")
        } else {
            num := 0, den := 0
        }

        lastNum := ctrl.HasProp("ZoomNum") ? ctrl.ZoomNum : 0
        lastDen := ctrl.HasProp("ZoomDen") ? ctrl.ZoomDen : 0

        if (num != lastNum || den != lastDen) {
            zRatio := (num && den) ? num / den : 1.0
            CodeBox._SetCodeFont(ctrl.LineNumCtrl, "Consolas", 10 * zRatio)

            ctrl.ZoomNum := num, ctrl.ZoomDen := den
            ctrl.ForceLineUpdate := true
            CodeBox._Move(ctrl)
        }

        visualLines := SendMessage(0x00BA, 0, 0, ctrl.Hwnd)
        needsTextUpdate := !(ctrl.HasProp("LastVisualLines") && ctrl.LastVisualLines == visualLines && !ctrl.HasProp("ForceLineUpdate"))

        fullText := CodeBox._GetText(ctrl)
        str := ""
        logicalLine := 1
        lastCharIdx := 0
        errVisuals := Map(), warnVisuals := Map()

        loop visualLines {
            charIdx := SendMessage(0x00BB, A_Index - 1, 0, ctrl.Hwnd)
            nextCharIdx := SendMessage(0x00BB, A_Index, 0, ctrl.Hwnd)
            if (nextCharIdx == -1)
                nextCharIdx := StrLen(fullText)

            chunk := SubStr(fullText, lastCharIdx + 1, charIdx - lastCharIdx)
            StrReplace(chunk, "`n", "`n", , &nlCount)
            logicalLine += nlCount
            lastCharIdx := charIdx

            if needsTextUpdate {
                lineChunk := SubStr(fullText, charIdx + 1, nextCharIdx - charIdx)
                StrReplace(lineChunk, "`n", "`n", , &lineNlCount)

                arrow := Chr(160) Chr(160)
                if CodeBox.IsPluginEnabled("Folding") {
                    if (lineNlCount > 1)
                        arrow := Chr(160) "+"
                    else if RegExMatch(lineChunk, "i)\{|#region")
                        arrow := Chr(160) "-"
                }

                if (nlCount > 0 || A_Index == 1)
                    str .= logicalLine arrow "`n"
                else
                    str .= "•" Chr(160) Chr(160) "`n"
            }

            if (ctrl.HasProp("ErrorLines") && ctrl.ErrorLines.Has(logicalLine))
                errVisuals[A_Index - 1] := ctrl.ErrorLines[logicalLine]
            else if (ctrl.HasProp("WarningLines") && ctrl.WarningLines.Has(logicalLine))
                warnVisuals[A_Index - 1] := ctrl.WarningLines[logicalLine]
        }

        if needsTextUpdate {
            SendMessage(0x000B, 0, 0, ctrl.LineNumCtrl.Hwnd)
            textStr := StrReplace(StrReplace(str, "`r`n", "`n"), "`n", "`r`n")
            SendMessage(0x000C, 0, StrPtr(textStr), ctrl.LineNumCtrl.Hwnd)

            theme := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
            CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, 0, -1)
            CodeBox._SetFormat(ctrl.LineNumCtrl.Hwnd, theme["Comment"], true, false, 0)

            ; PARAFORMAT2 has no pointers; it is strictly 188 bytes on both 32-bit and 64-bit architectures.
            pf2 := Buffer(188, 0), NumPut("UInt", 188, pf2, 0), NumPut("UInt", 0x00000008, pf2, 4), NumPut("UShort", 2, pf2, 24)
            SendMessage(0x0447, 0, pf2.Ptr, ctrl.LineNumCtrl.Hwnd)
        }

        SendMessage(0x000B, 0, 0, ctrl.LineNumCtrl.Hwnd)

        theme := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, 0, -1)
        CodeBox._SetFormat(ctrl.LineNumCtrl.Hwnd, theme["Comment"], false, false, 0)

        ctrl.VisualErrors := errVisuals
        ctrl.VisualWarnings := warnVisuals

        for vIdx, _ in errVisuals {
            char1 := SendMessage(0x00BB, vIdx, 0, ctrl.LineNumCtrl.Hwnd)
            len := SendMessage(0x00C1, char1, 0, ctrl.LineNumCtrl.Hwnd)
            CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, char1, char1 + len)
            CodeBox._SetFormat(ctrl.LineNumCtrl.Hwnd, 0xFF453A, false, false, 0)
        }
        for vIdx, _ in warnVisuals {
            char1 := SendMessage(0x00BB, vIdx, 0, ctrl.LineNumCtrl.Hwnd)
            len := SendMessage(0x00C1, char1, 0, ctrl.LineNumCtrl.Hwnd)
            CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, char1, char1 + len)
            CodeBox._SetFormat(ctrl.LineNumCtrl.Hwnd, 0xFFD60A, false, false, 0)
        }

        CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, 0, 0)
        CodeBox._SetSel(ctrl.LineNumCtrl.Hwnd, 0, 0)

        SendMessage(0x000B, 1, 0, ctrl.LineNumCtrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.LineNumCtrl.Hwnd, "Ptr", 0, "Int", 0)

        ctrl.LastVisualLines := visualLines
        if ctrl.HasProp("ForceLineUpdate")
            ctrl.DeleteProp("ForceLineUpdate")

        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd)
        NumPut("Int", 0, pt, 0)
        SendMessage(0x04DE, 0, pt.Ptr, ctrl.LineNumCtrl.Hwnd)
    }
}
