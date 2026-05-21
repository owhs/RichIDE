class CodeBox_SmartTyping {
    static OnChar(ctrl, wParam) {
        char := Chr(wParam)
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        if (char == "}" || char == "]" || char == ")") {
            lineStart := SendMessage(0x00BB, SendMessage(0x0436, 0, startSel, ctrl.Hwnd), 0, ctrl.Hwnd)
            lineText := CodeBox._GetTextRange(ctrl.Hwnd, lineStart, startSel)
            if RegExMatch(lineText, "^ +$") && StrLen(lineText) >= 4 {
                CodeBox._SetSel(ctrl.Hwnd, startSel - 4, startSel)
                CodeBox._InsertText(ctrl.Hwnd, "")
                startSel -= 4
                endSel -= 4
            }
        }

        if ctrl.AutoClose && InStr("}])`"'", char) && (startSel == endSel) {
            if (CodeBox._GetTextRange(ctrl.Hwnd, startSel, startSel + 1) == char) {
                CodeBox._SetSel(ctrl.Hwnd, startSel + 1, startSel + 1)
                return 1
            }
        }

        pairs := Map("{", "}", "[", "]", "(", ")", '"', '"', "'", "'")
        if ctrl.AutoClose && pairs.Has(char) {
            CodeBox.Emit("PushHistory", ctrl, "Auto Close")
            if (startSel != endSel) {
                selText := CodeBox._GetTextRange(ctrl.Hwnd, startSel, endSel)
                CodeBox._InsertText(ctrl.Hwnd, char selText pairs[char])
                CodeBox._SetSel(ctrl.Hwnd, startSel + 1, startSel + 1 + StrLen(selText))
                return 1
            } else {
                if ((char == "'" || char == '"') && RegExMatch(CodeBox._GetTextRange(ctrl.Hwnd, startSel - 1, startSel), "[a-zA-Z0-9_]"))
                    return 0
                CodeBox._InsertText(ctrl.Hwnd, char pairs[char])
                CodeBox._SetSel(ctrl.Hwnd, startSel + 1, startSel + 1)
                return 1
            }
        }
        return 0
    }

    static OnKeyDown(ctrl, wParam) {
        if (wParam == 191 && GetKeyState("Ctrl", "P")) {
            this.ToggleComment(ctrl, GetKeyState("Shift", "P"))
            return 1
        }
        if (wParam == 9 && !GetKeyState("Ctrl", "P")) {
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
            lineStartIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
            lineEndIdx := SendMessage(0x0436, 0, endSel, ctrl.Hwnd)

            if (lineEndIdx > lineStartIdx && endSel == SendMessage(0x00BB, lineEndIdx, 0, ctrl.Hwnd))
                lineEndIdx--

            if (lineEndIdx > lineStartIdx || GetKeyState("Shift", "P")) {
                CodeBox.Emit("PushHistory", ctrl, "Multi-line Indent")
                startChar := SendMessage(0x00BB, lineStartIdx, 0, ctrl.Hwnd)
                lastLineStart := SendMessage(0x00BB, lineEndIdx, 0, ctrl.Hwnd)
                lastLineLen := SendMessage(0x00C1, lastLineStart, 0, ctrl.Hwnd)
                text := CodeBox._GetTextRange(ctrl.Hwnd, startChar, lastLineStart + lastLineLen)
                newText := GetKeyState("Shift", "P") ? RegExReplace(text, "(?m)^(?: {1,4}|\t)", "") : RegExReplace(text, "(?m)^", "    ")
                CodeBox._SetSel(ctrl.Hwnd, startChar, lastLineStart + lastLineLen)
                CodeBox._InsertText(ctrl.Hwnd, newText)
                CodeBox._SetSel(ctrl.Hwnd, startChar, startChar + StrLen(newText))
                return 1
            }
            if !GetKeyState("Shift", "P") {
                CodeBox.Emit("PushHistory", ctrl, "Indent")
                CodeBox._InsertText(ctrl.Hwnd, "    ")
                return 1
            }
        }
        else if (wParam == 13) {
            CodeBox.Emit("PushHistory", ctrl, "Smart Indent")
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int")

            if (!ctrl.AutoIndent) {
                CodeBox._InsertText(ctrl.Hwnd, "`n")
                return 1
            }
            lineStart := SendMessage(0x00BB, SendMessage(0x0436, 0, startSel, ctrl.Hwnd), 0, ctrl.Hwnd)
            lineText := CodeBox._GetTextRange(ctrl.Hwnd, lineStart, startSel)
            RegExMatch(lineText, "^\s*", &m), insertStr := "`n" m[0]
            
            lineIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
            if (lineIdx > 0) {
                prevLineStart := SendMessage(0x00BB, lineIdx - 1, 0, ctrl.Hwnd)
                prevLineLen := SendMessage(0x00C1, prevLineStart, 0, ctrl.Hwnd)
                prevLineText := CodeBox._GetTextRange(ctrl.Hwnd, prevLineStart, prevLineStart + prevLineLen)
                
                if RegExMatch(prevLineText, "i)^\s*(if|else|loop|while|for|try|catch|finally)\b[^{]*$") && !RegExMatch(lineText, "^\s*\{") {
                    RegExMatch(prevLineText, "^\s*", &prevM)
                    insertStr := "`n" prevM[0]
                }
            }

            if RegExMatch(lineText, "[\{\[\(:]\s*$") || RegExMatch(lineText, "i)^\s*(if|else|loop|while|for|try|catch|finally)\b[^{]*$") {
                insertStr .= "    "
                nextChar := CodeBox._GetTextRange(ctrl.Hwnd, startSel, startSel + 1)
                lastChar := SubStr(Trim(lineText), -1)
                pairs := Map("{", "}", "[", "]", "(", ")")
                if pairs.Has(lastChar) && nextChar == pairs[lastChar] {
                    CodeBox._InsertText(ctrl.Hwnd, insertStr "`n" m[0])
                    CodeBox._SetSel(ctrl.Hwnd, startSel + StrLen(insertStr), startSel + StrLen(insertStr))
                    return 1
                }
            }
            CodeBox._InsertText(ctrl.Hwnd, insertStr)
            CodeBox._SetSel(ctrl.Hwnd, startSel + StrLen(insertStr), startSel + StrLen(insertStr))
            return 1
        }
        else if (wParam == 8 && ctrl.AutoClose) {
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
            if (startSel == endSel && startSel > 0) {
                prev := CodeBox._GetTextRange(ctrl.Hwnd, startSel - 1, startSel)
                next := CodeBox._GetTextRange(ctrl.Hwnd, startSel, startSel + 1)
                pairs := Map("{", "}", "[", "]", "(", ")", '"', '"', "'", "'")
                if pairs.Has(prev) && pairs[prev] == next {
                    CodeBox.Emit("PushHistory", ctrl, "Delete")
                    CodeBox._SetSel(ctrl.Hwnd, startSel - 1, startSel + 1)
                    CodeBox._InsertText(ctrl.Hwnd, "")
                    return 1
                }
            }
        }
        return 0
    }

    static ToggleComment(ctrl, isBlock) {
        lang := StrLower(ctrl.CodeBoxLang)
        lineSym := ""
        blockStart := "", blockEnd := ""

        if (lang ~= "^(ahk2|ini)$") {
            lineSym := ";"
            blockStart := "/*", blockEnd := "*/"
        } else if (lang ~= "^(js|cs|cpp|c|java|php|go|rust|css)$") {
            lineSym := "//"
            blockStart := "/*", blockEnd := "*/"
        } else if (lang ~= "^(python|ruby|ps1|yaml)$") {
            lineSym := "#"
            blockStart := (lang == "ps1") ? "<#" : (lang == "python") ? '"""' : ""
            blockEnd := (lang == "ps1") ? "#>" : (lang == "python") ? '"""' : ""
        } else if (lang ~= "^(bat|cmd)$") {
            lineSym := "::"
        } else if (lang ~= "^(sql)$") {
            lineSym := "--"
            blockStart := "/*", blockEnd := "*/"
        } else if (lang ~= "^(html|xml|md)$") {
            lineSym := "<!--"
            blockStart := "<!--", blockEnd := "-->"
        } else {
            lineSym := "//"
        }

        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        CodeBox.Emit("PushHistory", ctrl, "Toggle Comment")

        if (isBlock && blockStart != "") {
            text := CodeBox._GetTextRange(ctrl.Hwnd, startSel, endSel)
            if (SubStr(text, 1, StrLen(blockStart)) == blockStart && SubStr(text, -StrLen(blockEnd)) == blockEnd) {
                newText := SubStr(text, StrLen(blockStart) + 1, StrLen(text) - StrLen(blockStart) - StrLen(blockEnd))
                CodeBox._InsertText(ctrl.Hwnd, newText)
                CodeBox._SetSel(ctrl.Hwnd, startSel, startSel + StrLen(newText))
            } else {
                newText := blockStart text blockEnd
                CodeBox._InsertText(ctrl.Hwnd, newText)
                CodeBox._SetSel(ctrl.Hwnd, startSel, startSel + StrLen(newText))
            }
            return
        }

        lineStartIdx := SendMessage(0x0436, 0, startSel, ctrl.Hwnd)
        lineEndIdx := SendMessage(0x0436, 0, endSel, ctrl.Hwnd)

        if (lineEndIdx > lineStartIdx && endSel == SendMessage(0x00BB, lineEndIdx, 0, ctrl.Hwnd))
            lineEndIdx--

        startChar := SendMessage(0x00BB, lineStartIdx, 0, ctrl.Hwnd)
        lastLineStart := SendMessage(0x00BB, lineEndIdx, 0, ctrl.Hwnd)
        lastLineLen := SendMessage(0x00C1, lastLineStart, 0, ctrl.Hwnd)

        text := CodeBox._GetTextRange(ctrl.Hwnd, startChar, lastLineStart + lastLineLen)
        lines := StrSplit(text, "`n")

        allCommented := true
        for line in lines {
            if (Trim(line) != "") {
                if (lineSym == "<!--") {
                    if !RegExMatch(line, "^\s*<!--.*?-->\s*$") {
                        allCommented := false
                        break
                    }
                } else if (SubStr(Trim(line), 1, StrLen(lineSym)) != lineSym) {
                    allCommented := false
                    break
                }
            }
        }

        newText := ""
        for i, line in lines {
            if (Trim(line) == "") {
                newText .= line "`n"
                continue
            }
            if (allCommented) {
                if (lineSym == "<!--")
                    newText .= RegExReplace(line, "^(\s*)<!--\s?(.*?)\s?-->\s*$", "$1$2") "`n"
                else
                    newText .= RegExReplace(line, "^(\s*)\Q" lineSym "\E\s?", "$1") "`n"
            } else {
                if (lineSym == "<!--")
                    newText .= RegExReplace(line, "^(\s*)(.*)", "$1<!-- $2 -->") "`n"
                else
                    newText .= RegExReplace(line, "^(\s*)(.*)", "$1" lineSym " $2") "`n"
            }
        }
        newText := SubStr(newText, 1, -1)

        CodeBox._SetSel(ctrl.Hwnd, startChar, lastLineStart + lastLineLen)
        CodeBox._InsertText(ctrl.Hwnd, newText)
        CodeBox._SetSel(ctrl.Hwnd, startChar, startChar + StrLen(newText))
    }
}
