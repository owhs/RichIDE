class CodeBox_BracketMatcher {
    static IsMatching := false

    static OnControlCreated(ctrl) {
        ctrl.BracketPairs := Map()
        ctrl.PrevBracketPositions := ""
        this.RebuildBracketPairs(ctrl)
    }

    static OnChange(ctrl) {
        this.RebuildBracketPairs(ctrl)
    }

    static OnSelectionChange(ctrl) {
        if this.IsMatching
            return
        this.IsMatching := true
        try {
            if (!CodeBox.IsPluginEnabled("BracketMatcher")) {
                this.ClearHighlight(ctrl)
                return
            }
            this.MatchBrackets(ctrl)
        } finally {
            this.IsMatching := false
        }
    }

    static OnHighlight(ctrl) {
        ; Re-evaluate match after syntax highlighting resets formatting
        if this.IsMatching
            return
        this.IsMatching := true
        try {
            if (CodeBox.IsPluginEnabled("BracketMatcher")) {
                this.MatchBrackets(ctrl)
            }
        } finally {
            this.IsMatching := false
        }
    }

    static OnThemeChange(ctrl) {
        if this.IsMatching
            return
        this.IsMatching := true
        try {
            if (CodeBox.IsPluginEnabled("BracketMatcher")) {
                this.MatchBrackets(ctrl)
            }
        } finally {
            this.IsMatching := false
        }
    }

    static OnDestroy(ctrl) {
        if (ctrl.HasProp("PrevBracketPositions") && ctrl.PrevBracketPositions) {
            try this.ClearHighlight(ctrl)
        }
    }

    static RebuildBracketPairs(ctrl) {
        try {
            text := CodeBox._GetText(ctrl)
            ctrl.BracketPairs := this.ParseBrackets(text, ctrl.CodeBoxLang)
        } catch {
            ctrl.BracketPairs := Map()
        }
    }

    static ParseBrackets(text, lang := "ahk2") {
        pairs := Map()
        stack := []
        
        len := StrLen(text)
        state := "normal"
        i := 1
        
        while (i <= len) {
            char := SubStr(text, i, 1)
            nextChar := i < len ? SubStr(text, i + 1, 1) : ""
            
            ; Handle string escape sequences
            if (char == "\" || char == "``") {
                if (state == "string_double" || state == "string_single" || state == "string_backtick") {
                    ; Skip the escaped character
                    i += 2
                    continue
                }
            }
            
            if (state == "normal") {
                if (char == "/" && nextChar == "/") {
                    state := "comment_single"
                    i += 2
                    continue
                } else if (char == "/" && nextChar == "*") {
                    state := "comment_multi"
                    i += 2
                    continue
                } else if (char == ";" && (lang == "ahk" || lang == "ahk2" || lang == "ini")) {
                    state := "comment_single"
                    i++
                    continue
                } else if (char == "#" && (lang == "python" || lang == "yaml" || lang == "perl" || lang == "ruby" || lang == "shell")) {
                    state := "comment_single"
                    i++
                    continue
                } else if (char == "<" && SubStr(text, i, 4) == "<!--") {
                    state := "comment_html"
                    i += 4
                    continue
                } else if (char == '"') {
                    state := "string_double"
                } else if (char == "'") {
                    state := "string_single"
                } else if (char == "``" && lang == "js") { ; template literals in JS
                    state := "string_backtick"
                } else if (char == "(" || char == "[" || char == "{") {
                    stack.Push({type: char, pos: i - 1})
                } else if (char == ")" || char == "]" || char == "}") {
                    if (stack.Length > 0) {
                        pop := stack[stack.Length]
                        if ((char == ")" && pop.type == "(") || (char == "]" && pop.type == "[") || (char == "}" && pop.type == "{")) {
                            pairs[pop.pos] := i - 1
                            pairs[i - 1] := pop.pos
                            stack.Pop()
                        }
                    }
                }
            } else if (state == "comment_single") {
                if (char == "`n") {
                    state := "normal"
                }
            } else if (state == "comment_multi") {
                if (char == "*" && nextChar == "/") {
                    state := "normal"
                    i += 2
                    continue
                }
            } else if (state == "comment_html") {
                if (char == "-" && SubStr(text, i, 3) == "-->") {
                    state := "normal"
                    i += 3
                    continue
                }
            } else if (state == "string_double") {
                if (char == '"') {
                    state := "normal"
                }
            } else if (state == "string_single") {
                if (char == "'") {
                    state := "normal"
                }
            } else if (state == "string_backtick") {
                if (char == "``") {
                    state := "normal"
                }
            }
            
            i++
        }
        
        return pairs
    }

    static MatchBrackets(ctrl) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        ; 1. Clear previous highlights
        this.ClearHighlight(ctrl)

        if (!CodeBox.IsPluginEnabled("BracketMatcher"))
            return

        ; 2. Get selection range
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")

        ; If it's a selection range rather than a single caret, don't match
        if (startSel != endSel)
            return

        pos := startSel
        len := SendMessage(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH

        if (!ctrl.HasProp("BracketPairs") || !ctrl.BracketPairs)
            return

        ; 3. Check bracket at caret position (prefer right of caret, then left of caret)
        targetPos := -1
        matchPos := -1

        if (pos < len && ctrl.BracketPairs.Has(pos)) {
            targetPos := pos
            matchPos := ctrl.BracketPairs[pos]
        } else if (pos > 0 && ctrl.BracketPairs.Has(pos - 1)) {
            targetPos := pos - 1
            matchPos := ctrl.BracketPairs[pos - 1]
        }

        if (targetPos != -1 && matchPos != -1) {
            ; Get current scroll position to restore
            pt := Buffer(8, 0)
            SendMessage(0x04DD, 0, pt.Ptr, hwnd) ; EM_GETSCROLLPOS
            
            this.ApplyHighlight(ctrl, targetPos, matchPos, startSel, endSel, pt)
        }
    }

    static ApplyHighlight(ctrl, pos1, pos2, startSel, endSel, pt) {
        hwnd := ctrl.Hwnd
        
        ; Determine bracket background color based on theme
        themeName := ctrl.CodeBoxTheme
        if (themeName == "Light") {
            bracketBg := 0xD3D3D3 ; Light gray
        } else if (themeName == "Matrix") {
            bracketBg := 0x004400 ; Dark green
        } else if (themeName == "Hacker") {
            bracketBg := 0x440000 ; Dark red
        } else {
            bracketBg := 0x3E3E3E ; Medium gray (VS Code-like style)
        }

        DllCall("HideCaret", "Ptr", hwnd)
        SendMessage(0x000B, 0, 0, hwnd) ; Freeze window redraw

        ; Format first bracket
        CodeBox._SetSel(hwnd, pos1, pos1 + 1)
        this.SetBracketFormat(hwnd, true, bracketBg)

        ; Format second bracket
        CodeBox._SetSel(hwnd, pos2, pos2 + 1)
        this.SetBracketFormat(hwnd, true, bracketBg)

        ; Save positions so we can clear them later
        ctrl.PrevBracketPositions := [pos1, pos2]

        ; Restore selection and scroll
        CodeBox._SetSel(hwnd, startSel, endSel)
        SendMessage(0x04DE, 0, pt.Ptr, hwnd) ; EM_SETSCROLLPOS

        SendMessage(0x000B, 1, 0, hwnd) ; Re-enable window redraw
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
        DllCall("ShowCaret", "Ptr", hwnd)
    }

    static ClearHighlight(ctrl) {
        if (!ctrl.HasProp("PrevBracketPositions") || !ctrl.PrevBracketPositions)
            return

        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        positions := ctrl.PrevBracketPositions
        ctrl.PrevBracketPositions := ""

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd)
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")

        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, hwnd)

        DllCall("HideCaret", "Ptr", hwnd)
        SendMessage(0x000B, 0, 0, hwnd)

        for pos in positions {
            CodeBox._SetSel(hwnd, pos, pos + 1)
            this.SetBracketFormat(hwnd, false, -2) ; Revert background and bold formatting
        }

        CodeBox._SetSel(hwnd, startSel, endSel)
        SendMessage(0x04DE, 0, pt.Ptr, hwnd)

        SendMessage(0x000B, 1, 0, hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
        DllCall("ShowCaret", "Ptr", hwnd)
    }

    static SetBracketFormat(hwnd, bold, backColorRGB) {
        cf2 := Buffer(116, 0)
        NumPut("UInt", 116, cf2, 0) ; cbSize
        NumPut("UInt", 0x04000000 | 0x00000001, cf2, 4) ; dwMask = CFM_BACKCOLOR | CFM_BOLD
        
        effects := (bold ? 1 : 0)
        if (backColorRGB == -2) {
            effects |= 0x04000000 ; CFE_AUTOBACKCOLOR
        } else {
            bgBgr := ((backColorRGB & 0xFF0000) >> 16) | (backColorRGB & 0x00FF00) | ((backColorRGB & 0x0000FF) << 16)
            NumPut("UInt", bgBgr, cf2, 96) ; crBackColor
        }
        NumPut("UInt", effects, cf2, 8) ; dwEffects
        
        SendMessage(0x0444, 1, cf2.Ptr, hwnd) ; EM_SETCHARFORMAT with SCF_SELECTION
    }
}
