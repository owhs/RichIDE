class CodeBox_Folding {
    static OnKeyDown(ctrl, wParam) {
        if (wParam == 77 && GetKeyState("Ctrl", "P")) {
            CodeBox.Emit("PushHistory", ctrl, "Code Fold")
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int")
            lineIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
            this.ToggleFoldLine(ctrl, lineIdx)
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

    static SetHidden(ctrl, startSel, endSel, hide) {
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        cf2 := Buffer(116, 0), NumPut("UInt", 116, cf2, 0)
        CodeBox._SetSel(ctrl.Hwnd, startSel, endSel)
        NumPut("UInt", 0x0100, cf2, 4), NumPut("UInt", hide ? 0x0100 : 0, cf2, 8)
        SendMessage(0x0444, 1, cf2.Ptr, ctrl.Hwnd)
        CodeBox._SetSel(ctrl.Hwnd, startSel, startSel)
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        ctrl.ForceLineUpdate := true
        ctrl.ForceMiniUpdate := true
        CodeBox.Emit("OnScroll", ctrl)
        CodeBox._Fire(ctrl, "Fold", hide ? "Folded Block" : "Unfolded Block")
    }
}
