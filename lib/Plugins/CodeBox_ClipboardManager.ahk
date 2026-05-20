class CodeBox_ClipboardManager {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        ctrl.CopyHidden := true
        editMenu.Add("Include Hidden in Copy", (ItemName, ItemPos, MyMenu) => (
            ctrl.CopyHidden := !ctrl.CopyHidden,
            MyMenu.ToggleCheck(ItemName)
        ))
        editMenu.Check("Include Hidden in Copy")
    }
    static OnDisable(ctrl) {
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarChk")
            this.ToolbarChk.Visible := true
    }

    static OnKeyDown(ctrl, wParam) {
        if ((wParam == 67 || wParam == 88) && GetKeyState("Ctrl")) {
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
            
            if (startSel == endSel)
                return 0
                
            copyHidden := ctrl.HasProp("CopyHidden") ? ctrl.CopyHidden : true

            if (copyHidden) {
                outText := CodeBox._GetTextRange(ctrl.Hwnd, startSel, endSel)
            } else {
                outText := this.GetVisibleText(ctrl, startSel, endSel)
            }
            
            outText := StrReplace(StrReplace(outText, "`r`n", "`n"), "`r", "`n")
            
            isMultiLine := InStr(outText, "`n") > 0
            if (isMultiLine && !(SubStr(outText, -1) == "`n")) {
                nextChar := CodeBox._GetTextRange(ctrl.Hwnd, endSel, endSel + 1)
                if (nextChar == "`r" || nextChar == "`n") {
                    outText .= "`n"
                }
            }
            
            A_Clipboard := StrReplace(outText, "`n", "`r`n")
            
            if (wParam == 88) {
                CodeBox._InsertText(ctrl.Hwnd, "")
            }
            return 1
        }

        if ((wParam == 86 && GetKeyState("Ctrl")) || (wParam == 45 && GetKeyState("Shift"))) {
            clipText := A_Clipboard
            if (clipText == "")
                return 1 ; Block pasting of non-text data like images

            ; Normalize clipboard text newlines for uniform boundary checking
            clipTextNormalized := StrReplace(StrReplace(clipText, "`r`n", "`n"), "`r", "`n")
            
            if (SubStr(clipTextNormalized, -1) == "`n") {
                cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
                startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
                
                nextChar := CodeBox._GetTextRange(ctrl.Hwnd, endSel, endSel + 1)
                if (nextChar == "`r" || nextChar == "`n") {
                    ; Strip the trailing newline from the pasted text to prevent duplication
                    clipTextNormalized := SubStr(clipTextNormalized, 1, -1)
                }
            }
            
            CodeBox._InsertText(ctrl.Hwnd, clipTextNormalized)
            return 1
        }
        return 0
    }

    static GetVisibleText(ctrl, startSel, endSel) {
        cf2 := Buffer(116, 0)
        NumPut("UInt", 116, cf2, 0)
        SendMessage(0x043A, 1, cf2.Ptr, ctrl.Hwnd) ; EM_GETCHARFORMAT of current selection
        
        fullText := CodeBox._GetTextRange(ctrl.Hwnd, startSel, endSel)
        
        ; If the hidden attribute is uniform across the selection and not hidden, bypass sub-selections
        if ((NumGet(cf2, 4, "UInt") & 0x0100) && !(NumGet(cf2, 8, "UInt") & 0x0100)) {
            return fullText
        }
        
        ; Fallback for folded blocks
        caretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
        ctrl.SuppressSelChangeEvent := true
        
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        out := ""
        
        i := startSel
        while (i < endSel) {
            chunkEnd := Min(i + 64, endSel)
            
            NumPut("UInt", 116, cf2, 0)
            CodeBox._SetSel(ctrl.Hwnd, i, chunkEnd)
            SendMessage(0x043A, 1, cf2.Ptr, ctrl.Hwnd)
            
            if (NumGet(cf2, 4, "UInt") & 0x0100) {
                if !(NumGet(cf2, 8, "UInt") & 0x0100)
                    out .= CodeBox._GetTextRange(ctrl.Hwnd, i, chunkEnd)
                i := chunkEnd
                continue
            }
            
            j := i
            while (j < chunkEnd) {
                NumPut("UInt", 116, cf2, 0)
                CodeBox._SetSel(ctrl.Hwnd, j, j + 1)
                SendMessage(0x043A, 1, cf2.Ptr, ctrl.Hwnd)
                if !(NumGet(cf2, 8, "UInt") & 0x0100)
                    out .= CodeBox._GetTextRange(ctrl.Hwnd, j, j + 1)
                j++
            }
            i := chunkEnd
        }
        
        CodeBox._SetSelDirectional(ctrl.Hwnd, startSel, endSel, caretPos)
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        ctrl.SuppressSelChangeEvent := false
        return out
    }
}
