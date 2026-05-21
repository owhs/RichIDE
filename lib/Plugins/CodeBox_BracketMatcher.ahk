class CodeBox_BracketMatcher {
    static IsMatching := false
    static WndProcCallback := ""
    static ToolbarBtn := ""
    static _LeaveTimer := ""
    static ShowingTooltip := false
    static _MouseMoveBound := ""

    static OnControlCreated(ctrl) {
        ctrl.BracketPairs := Map()
        ctrl.PrevBracketPositions := ""
        ctrl.PrevCaretPos := ""
        this.RebuildBracketPairs(ctrl)

        ; Register mouse move hook for toolbar tooltip
        if (!this._MouseMoveBound) {
            this._MouseMoveBound := ObjBindMethod(this, "_OnMouseMove")
            OnMessage(0x0200, this._MouseMoveBound)
        }
    }

    static OnChange(ctrl) {
        this.ClearHighlight(ctrl)
        this.RebuildBracketPairs(ctrl)
    }

    static OnChar(ctrl, wParam) {
        this.ClearHighlight(ctrl)
    }

    static OnLButtonDown(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        this.ClearHighlight(ctrl)
    }

    static OnLButtonUp(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        if (CodeBox.IsPluginEnabled("BracketMatcher")) {
            this.IsMatching := true
            try {
                this.MatchBrackets(ctrl)
            } finally {
                this.IsMatching := false
            }
        }
    }

    static OnSelectionChange(ctrl) {
        if this.IsMatching
            return

        ; If user is actively selecting via Shift or dragging, bypass matching immediately without modifying selection
        if (GetKeyState("Shift", "P") || GetKeyState("LButton", "P")) {
            return
        }

        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")

        ; Robust caret-position guard: Only trigger match evaluation if caret position actually changed
        if (ctrl.HasProp("PrevCaretPos") && ctrl.PrevCaretPos && ctrl.PrevCaretPos.start == startSel && ctrl.PrevCaretPos.end == endSel)
            return

        ctrl.PrevCaretPos := {start: startSel, end: endSel}

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
                ; The highlighter wiped out our formatting, so forget previous positions
                ctrl.PrevBracketPositions := ""
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
                ctrl.PrevBracketPositions := ""
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

        ; 2. Get selection range
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")

        ; If it's a selection range rather than a single caret, don't match
        if (startSel != endSel) {
            this.ClearHighlight(ctrl)
            return
        }

        pos := startSel
        len := SendMessage(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH

        if (!ctrl.HasProp("BracketPairs") || !ctrl.BracketPairs) {
            this.ClearHighlight(ctrl)
            return
        }

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
            ; Check if these exact positions are already highlighted
            if (ctrl.HasProp("PrevBracketPositions") && ctrl.PrevBracketPositions 
                && ((ctrl.PrevBracketPositions[1] == targetPos && ctrl.PrevBracketPositions[2] == matchPos)
                || (ctrl.PrevBracketPositions[1] == matchPos && ctrl.PrevBracketPositions[2] == targetPos))) {
                ; Already highlighted! Do absolutely nothing!
                return
            }

            ; If different brackets were highlighted, clear them first
            this.ClearHighlight(ctrl)

            ; Get current scroll position to restore
            pt := Buffer(8, 0)
            SendMessage(0x04DD, 0, pt.Ptr, hwnd) ; EM_GETSCROLLPOS
            
            this.ApplyHighlight(ctrl, targetPos, matchPos)
        } else {
            ; No match at caret, clear any existing highlight
            this.ClearHighlight(ctrl)
        }
    }

    static ApplyHighlight(ctrl, pos1, pos2) {
        hwnd := ctrl.Hwnd
        
        themeName := ctrl.CodeBoxTheme
        if (themeName == "Light") {
            bracketBg := 0xB4D6FA
        } else if (themeName == "Matrix") {
            bracketBg := 0x008822
        } else if (themeName == "Hacker") {
            bracketBg := 0x880000
        } else {
            bracketBg := 0x1A5380
        }

        doc := CodeBox_Highlighter.GetITextDocument(hwnd)
        if !doc
            return

        bgBgr := ((bracketBg & 0xFF0000) >> 16) | (bracketBg & 0x00FF00) | ((bracketBg & 0x0000FF) << 16)

        try {
            rng1 := doc.Range(pos1, pos1 + 1)
            rng1.Font.Bold := -1
            rng1.Font.BackColor := bgBgr

            rng2 := doc.Range(pos2, pos2 + 1)
            rng2.Font.Bold := -1
            rng2.Font.BackColor := bgBgr

            ctrl.PrevBracketPositions := [pos1, pos2]
        } catch {
        }
    }

    static ClearHighlight(ctrl) {
        if (!ctrl.HasProp("PrevBracketPositions") || !ctrl.PrevBracketPositions)
            return

        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        positions := ctrl.PrevBracketPositions
        ctrl.PrevBracketPositions := ""

        doc := CodeBox_Highlighter.GetITextDocument(hwnd)
        if !doc
            return

        themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        bgBgr := ((themeC["Background"] & 0xFF0000) >> 16) | (themeC["Background"] & 0x00FF00) | ((themeC["Background"] & 0x0000FF) << 16)

        try {
            len := SendMessage(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH
            for pos in positions {
                if (pos >= 0 && pos < len) {
                    rng := doc.Range(pos, pos + 1)
                    rng.Font.Bold := 0
                    rng.Font.BackColor := bgBgr
                }
            }
        } catch {
        }
    }

    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarBtn := guiObj.Add("Button", "x" x " y" y " w110 h24 Background2D2D30 cWhite +0x8000", "Jump to Bracket")
        this.ToolbarBtn.OnEvent("Click", (*) => this.JumpToMatchingBracket(ctrl))
        x += 120
    }

    static _OnMouseMove(wParam, lParam, msg, hwnd) {
        if (this.ToolbarBtn && hwnd == this.ToolbarBtn.Hwnd) {
            if (!this.ShowingTooltip) {
                this.ShowingTooltip := true
                ToolTip("Jump to matching bracket (Ctrl+])")
                if (!this._LeaveTimer)
                    this._LeaveTimer := () => this.CheckMouseLeave()
                SetTimer(this._LeaveTimer, 100)
            }
        }
    }

    static CheckMouseLeave() {
        if (!this.ToolbarBtn) {
            ToolTip()
            this.ShowingTooltip := false
            if (this._LeaveTimer)
                SetTimer(this._LeaveTimer, 0)
            return
        }
        MouseGetPos ,, &win, &ctrlHwnd, 2
        if (ctrlHwnd != this.ToolbarBtn.Hwnd) {
            ToolTip()
            this.ShowingTooltip := false
            if (this._LeaveTimer)
                SetTimer(this._LeaveTimer, 0)
        }
    }

    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn") && this.ToolbarBtn {
            try this.ToolbarBtn.Visible := false
        }
    }

    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn") && this.ToolbarBtn {
            try this.ToolbarBtn.Visible := true
        }
    }

    static OnKeyDown(ctrl, wParam) {
        ; Clear highlight immediately on Shift key, Ctrl+A (Select All), or Shift-modified navigation
        if (wParam == 0x10 || (wParam == 0x41 && GetKeyState("Ctrl")) || GetKeyState("Shift")) {
            this.ClearHighlight(ctrl)
        }

        ; Check for Ctrl+] shortcut (VK_OEM_6 = 0xDD)
        if (wParam == 0xDD && GetKeyState("Ctrl")) {
            this.JumpToMatchingBracket(ctrl)
            return 1
        }
        ; Clear highlight on backspace or delete before text changes
        if (wParam == 8 || wParam == 46) {
            this.ClearHighlight(ctrl)
        }
        return 0
    }

    static JumpToMatchingBracket(ctrl) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int")
        endSel := NumGet(cr, 4, "Int")

        if (startSel != endSel)
            return

        pos := startSel
        len := SendMessage(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH

        if (!ctrl.HasProp("BracketPairs") || !ctrl.BracketPairs)
            return

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
            ; Determine destination cursor position
            destPos := (pos == targetPos) ? matchPos : matchPos + 1
            
            ; Ensure the control has focus so EM_SCROLLCARET works perfectly
            DllCall("user32\SetFocus", "Ptr", hwnd)
            
            ; Set selection (jump caret)
            CodeBox._SetSel(hwnd, destPos, destPos)
            
            ; Scroll caret into view
            SendMessage(0x00B7, 0, 0, hwnd) ; EM_SCROLLCARET
        }
    }
}
