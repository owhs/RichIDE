class CodeBox_Folding {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        foldMenu := Menu()
        foldMenu.Add("Toggle Fold Current Line`tCtrl+M", (*) => CodeBox.Invoke("ToggleFoldCurrentLine", ctrl))
        foldMenu.Add()
        foldMenu.Add("Fold Current Block`tCtrl+Shift+[", (*) => CodeBox.Invoke("FoldCurrentBlock", ctrl, true))
        foldMenu.Add("Unfold Current Block`tCtrl+Shift+]", (*) => CodeBox.Invoke("FoldCurrentBlock", ctrl, false))
        foldMenu.Add()
        foldMenu.Add("Toggle Fold Level 1`tCtrl+1", (*) => CodeBox.Invoke("FoldLevel", ctrl, 1))
        foldMenu.Add("Toggle Fold Level 2`tCtrl+2", (*) => CodeBox.Invoke("FoldLevel", ctrl, 2))
        foldMenu.Add("Toggle Fold Level 3`tCtrl+3", (*) => CodeBox.Invoke("FoldLevel", ctrl, 3))
        foldMenu.Add("Toggle Fold Level 4`tCtrl+4", (*) => CodeBox.Invoke("FoldLevel", ctrl, 4))
        
        viewMenu.Add("Code Folding", foldMenu)
    }

    static ToggleFoldCurrentLine(ctrl) {
        CodeBox.Emit("PushHistory", ctrl, "Code Fold")
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int")
        lineIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
        this.ToggleFoldLine(ctrl, lineIdx)
    }

    static OnKeyDown(ctrl, wParam) {
        if (ctrl.HasProp("IsPreviewing") && ctrl.IsPreviewing)
            return 0

        if (wParam == 77 && GetKeyState("Ctrl", "P") && !GetKeyState("Shift", "P")) {
            this.ToggleFoldCurrentLine(ctrl)
            return 1
        }

        if (wParam >= 48 && wParam <= 57 && GetKeyState("Ctrl", "P") && !GetKeyState("Shift", "P")) {
            targetDepth := (wParam == 48) ? 10 : (wParam - 48)
            this.FoldLevel(ctrl, targetDepth)
            return 1
        }

        if (wParam == 219 && GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P")) {
            this.FoldCurrentBlock(ctrl, true)
            return 1
        }

        if (wParam == 221 && GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P")) {
            this.FoldCurrentBlock(ctrl, false)
            return 1
        }

        return 0
    }

    static ToggleFoldLine(ctrl, visualLine) {
        charIdx := SendMessage(0x00BB, visualLine, 0, ctrl.Hwnd)
        if (charIdx == -1)
            return

        fullText := CodeBox._GetText(ctrl)
        nextCharIdx := SendMessage(0x00BB, visualLine + 1, 0, ctrl.Hwnd)
        if (nextCharIdx == -1)
            nextCharIdx := StrLen(fullText)

        lineChunk := SubStr(fullText, charIdx + 1, nextCharIdx - charIdx)
        StrReplace(lineChunk, "`n", "`n", , &lineNlCount)

        if (lineNlCount > 1) {
            this.SetHidden(ctrl, charIdx, nextCharIdx, false)
            return
        }

        if !RegExMatch(lineChunk, "i)\{|#region")
            return

        if RegExMatch(lineChunk, "i)#region") {
            endPos := RegExMatch(fullText, "i)#endregion", &m, charIdx + 1)
            if endPos {
                lineEnd := InStr(fullText, "`n", , charIdx + 1)
                if !lineEnd
                    lineEnd := StrLen(fullText)

                endLineEnd := InStr(fullText, "`n", , endPos)
                if !endLineEnd
                    endLineEnd := StrLen(fullText)

                if (endLineEnd > lineEnd)
                    this.SetHidden(ctrl, lineEnd - 1, endLineEnd, true)
            }
            return
        }

        startPos := InStr(lineChunk, "{")
        if startPos {
            blockStart := charIdx + startPos
            depth := 0
            blockEnd := 0
            inString := false
            loop parse SubStr(fullText, blockStart), "" {
                if (A_LoopField == '"' || A_LoopField == "'") {
                    if (!inString)
                        inString := A_LoopField
                    else if (inString == A_LoopField)
                        inString := false
                }
                if inString
                    continue

                if (A_LoopField == "{")
                    depth++
                else if (A_LoopField == "}") {
                    depth--
                    if (depth == 0) {
                        blockEnd := blockStart + A_Index - 1
                        break
                    }
                }
            }

            if blockEnd {
                lineEnd := InStr(fullText, "`n", , charIdx + 1)
                if !lineEnd
                    lineEnd := StrLen(fullText)

                if (blockEnd > lineEnd)
                    this.SetHidden(ctrl, lineEnd - 1, blockEnd - 1, true)
            }
        }
    }


    static GetFoldState(ctrl) {
        folds := []
        text := CodeBox._GetText(ctrl)
        len := StrLen(text)
        cf2 := Buffer(116, 0)
        
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        origStart := NumGet(cr, 0, "Int"), origEnd := NumGet(cr, 4, "Int")
        caretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
        ctrl.SuppressSelChangeEvent := true
        
        pos := 1
        inFold := false
        startFold := 0
        
        while (pos := InStr(text, "`n", , pos)) {
            charIdx := pos - 1
            CodeBox._SetSel(ctrl.Hwnd, charIdx, charIdx + 1)
            NumPut("UInt", 116, cf2, 0)
            SendMessage(0x043A, 1, cf2.Ptr, ctrl.Hwnd)
            isHidden := ((NumGet(cf2, 4, "UInt") & 0x0100) && (NumGet(cf2, 8, "UInt") & 0x0100))
            
            if (isHidden && !inFold) {
                inFold := true
                startFold := charIdx
            } else if (!isHidden && inFold) {
                inFold := false
                folds.Push({s: startFold, e: charIdx})
            }
            pos++
        }
        if (inFold) {
            folds.Push({s: startFold, e: len})
        }
        
        CodeBox._SetSelDirectional(ctrl.Hwnd, origStart, origEnd, caretPos)
        ctrl.SuppressSelChangeEvent := false
        return folds
    }

    static RestoreFoldState(ctrl, folds) {
        if !folds || folds.Length == 0
            return
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        for f in folds {
            this.SetHidden(ctrl, f.s, f.e, true)
        }
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
    }

    static FoldCurrentBlock(ctrl, hide) {
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        caretPos := NumGet(cr, 0, "Int")
        fullText := CodeBox._GetText(ctrl)
        len := StrLen(fullText)
        
        if (caretPos < 1)
            caretPos := 1
            
        depth := 1
        startIdx := caretPos
        
        if (SubStr(fullText, caretPos, 1) == "}")
            startIdx--
        else if (SubStr(fullText, caretPos, 1) == "{")
            depth := 0
            
        while (startIdx > 0 && depth > 0) {
            c := SubStr(fullText, startIdx, 1)
            if (c == "}")
                depth++
            else if (c == "{")
                depth--
            if (depth == 0)
                break
            startIdx--
        }
        
        if (startIdx <= 0 || depth > 0)
            return
            
        depth := 0
        endIdx := startIdx
        while (endIdx <= len) {
            c := SubStr(fullText, endIdx, 1)
            if (c == "{")
                depth++
            else if (c == "}") {
                depth--
                if (depth == 0)
                    break
            }
            endIdx++
        }
        
        if (endIdx > len || depth > 0)
            return
            
        lineEnd := InStr(fullText, "`n", , startIdx)
        if (!lineEnd || lineEnd > endIdx)
            return
            
        CodeBox.Emit("PushHistory", ctrl, hide ? "Fold Block" : "Unfold Block")
        this.SetHidden(ctrl, lineEnd - 1, endIdx - 1, hide)
    }

    static FoldLevel(ctrl, targetDepth) {
        fullText := CodeBox._GetText(ctrl)
        len := StrLen(fullText)
        rangesToProcess := []
        depth := 0
        inString := false
        idx := 1
        
        while (idx <= len) {
            c := SubStr(fullText, idx, 1)
            if (c == '"' || c == "'") {
                if (!inString)
                    inString := c
                else if (inString == c)
                    inString := false
                idx++
                continue
            }
            if inString {
                idx++
                continue
            }
            if (c == "{") {
                depth++
                if (depth == targetDepth) {
                    startFold := idx
                    innerDepth := 0
                    innerInStr := false
                    endIdx := idx
                    
                    while (endIdx <= len) {
                        ic := SubStr(fullText, endIdx, 1)
                        if (ic == '"' || ic == "'") {
                            if (!innerInStr)
                                innerInStr := ic
                            else if (innerInStr == ic)
                                innerInStr := false
                        } else if (!innerInStr) {
                            if (ic == "{")
                                innerDepth++
                            else if (ic == "}") {
                                innerDepth--
                                if (innerDepth == 0)
                                    break
                            }
                        }
                        endIdx++
                    }
                    if (innerDepth == 0) {
                        lineEnd := InStr(fullText, "`n", , startFold)
                        if (lineEnd && lineEnd < endIdx)
                            rangesToProcess.Push({s: lineEnd - 1, e: endIdx - 1})
                    }
                    idx := endIdx
                    depth-- 
                }
            } else if (c == "}") {
                depth--
            }
            idx++
        }
        
        if (rangesToProcess.Length == 0)
            return
            
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        origStart := NumGet(cr, 0, "Int"), origEnd := NumGet(cr, 4, "Int")
        caretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
        ctrl.SuppressSelChangeEvent := true
            
        CodeBox._SetSel(ctrl.Hwnd, rangesToProcess[1].s, rangesToProcess[1].s + 1)
        cf2 := Buffer(116, 0), NumPut("UInt", 116, cf2, 0)
        SendMessage(0x043A, 1, cf2.Ptr, ctrl.Hwnd)
        hideAction := !((NumGet(cf2, 4, "UInt") & 0x0100) && (NumGet(cf2, 8, "UInt") & 0x0100))
        
        CodeBox._SetSelDirectional(ctrl.Hwnd, origStart, origEnd, caretPos)
        ctrl.SuppressSelChangeEvent := false
        
        CodeBox.Emit("PushHistory", ctrl, (hideAction ? "Fold" : "Unfold") " Level " targetDepth)
        
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        for r in rangesToProcess {
            this.SetHidden(ctrl, r.s, r.e, hideAction)
        }
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
    }

    static SetHidden(ctrl, startSel, endSel, hide) {
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        origStart := NumGet(cr, 0, "Int"), origEnd := NumGet(cr, 4, "Int")
        caretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
        
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        ctrl.SuppressSelChangeEvent := true
        
        cf2 := Buffer(116, 0), NumPut("UInt", 116, cf2, 0)
        CodeBox._SetSel(ctrl.Hwnd, startSel, endSel)
        NumPut("UInt", 0x0100, cf2, 4), NumPut("UInt", hide ? 0x0100 : 0, cf2, 8)
        SendMessage(0x0444, 1, cf2.Ptr, ctrl.Hwnd)
        
        CodeBox._SetSelDirectional(ctrl.Hwnd, origStart, origEnd, caretPos)
        ctrl.SuppressSelChangeEvent := false
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        ctrl.ForceLineUpdate := true
        ctrl.ForceMiniUpdate := true
        CodeBox.Emit("OnScroll", ctrl)
        CodeBox._Fire(ctrl, "Fold", hide ? "Folded Block" : "Unfolded Block")
    }
}
