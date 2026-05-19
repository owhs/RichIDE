class CodeBox_Beautify {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        editMenu.Add("Format Code`tF", (*) => CodeBox.Invoke("Format", ctrl))
    }
    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := true
    }

    static OnKeyDown(ctrl, wParam) {
        if (wParam == 70 && GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P")) {
            this.Format(ctrl)
            return 1
        }
        return 0
    }

    static Format(ctrl) {
        text := CodeBox._GetText(ctrl)
        lang := StrLower(ctrl.CodeBoxLang)

        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        lineIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
        lineStartChar := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)
        colIdx := startSel - lineStartChar

        newText := ""
        lines := StrSplit(text, "`n")
        indent := 0
        indentNext := 0

        for i, line in lines {
            line := Trim(line)
            if (line == "") {
                newText .= "`n"
                continue
            }

            cleanLine := RegExReplace(line, '(".*?"|`'`'.*?`'`'|//.*|/\*.*?\*/|;.*)')

            if RegExMatch(cleanLine, "^[\}\]\)]") {
                indent := Max(0, indent - 1)
                indentNext := 0
            }

            pad := ""
            loop (indent + indentNext)
                pad .= "    "

            newText .= pad line "`n"

            if (indentNext > 0)
                indentNext--

            openCount := 0, closeCount := 0
            RegExReplace(cleanLine, "[\{\[\(]", "", &openCount)
            RegExReplace(cleanLine, "[\}\]\)]", "", &closeCount)

            indent += (openCount - closeCount)

            if RegExMatch(cleanLine, "i)^(if|else|loop|while|for|try|catch|finally)\b") && !RegExMatch(cleanLine, "\{\s*$") {
                indentNext := 1
            }

            if (indent < 0)
                indent := 0
        }

        newText := SubStr(newText, 1, -1)
        if (newText == text || newText == "")
            return

        CodeBox.Emit("PushHistory", ctrl, "Beautify", newText, startSel, endSel)

        pt := Buffer(8, 0), SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd)
        SendMessage(0x0445, 0, 0, ctrl.Hwnd)
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)

        textStr := StrReplace(StrReplace(newText, "`r`n", "`n"), "`n", "`r`n")
        CodeBox._SetSel(ctrl.Hwnd, 0, -1)
        SendMessage(0x00C2, 1, StrPtr(textStr), ctrl.Hwnd)

        newLineStartChar := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)
        if (newLineStartChar == -1)
            newSel := StrLen(newText)
        else {
            newLineLen := SendMessage(0x00C1, newLineStartChar, 0, ctrl.Hwnd)
            newSel := newLineStartChar + Min(colIdx, newLineLen)
        }

        CodeBox._SetSel(ctrl.Hwnd, newSel, newSel)
        SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd)

        SendMessage(0x0445, 0, 0x10001 | 0x08 | 0x0400, ctrl.Hwnd)
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        CodeBox.Emit("OnChange", ctrl)
    }
}
