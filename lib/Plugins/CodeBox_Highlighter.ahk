class CodeBox_Highlighter {
    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarText := guiObj.Add("Text", "x" x " y" (y+3) " w55 BackgroundTrans", "Syntax:")
        x += 55
        
        langs := []
        idx := 1, i := 1
        for k, v in CodeBox.Syntaxes {
            langs.Push(k)
            if (k == ctrl.CodeBoxLang)
                idx := i
            i++
        }
        
        this.ToolbarDDL := guiObj.Add("DropDownList", "x" x " y" y " w90 Choose" idx " Background2D2D30 cWhite", langs)
        onChange(*) {
            ctrl.Language := this.ToolbarDDL.Text
            try {
                fn := %"GetExampleText"%
                CodeBox._SetText(ctrl, fn(this.ToolbarDDL.Text), true)
            }
        }
        this.ToolbarDDL.OnEvent("Change", onChange)
        x += 100
    }

    static OnDisable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := false
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := false
        ctrl.IsHighlighting := true ; Disables highlighting loop
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := true
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := true
        ctrl.IsHighlighting := false
        CodeBox.Emit("OnChange", ctrl)
    }

    static OnChange(ctrl) {
        this.Highlight(ctrl, true)
    }
    static OnLanguageChange(ctrl) {
        this.Highlight(ctrl, true)
    }
    static OnThemeChange(ctrl) {
        this.Highlight(ctrl, true)
    }
    static OnScroll(ctrl) {
        this.Highlight(ctrl, false)
    }

    static Highlight(ctrl, force := true) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        ; Prevent highlighting while drag-selecting or Shift-selecting to avoid disrupting Win32 selection
        if (GetKeyState("LButton", "P") || GetKeyState("Shift", "P")) {
            return
        }

        if (ctrl.HasProp("IsHighlighting") && ctrl.IsHighlighting)
            return

        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if (totalLen <= 0) {
            ctrl.LastHighlightStart := 0
            ctrl.LastHighlightEnd := 0
            return
        }

        ; Get visible viewport range
        firstLine := SendMessage(0x00CE, 0, 0, hwnd) ; EM_GETFIRSTVISIBLELINE
        
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr)
        h := NumGet(rect, 12, "Int")
        
        pt := Buffer(8, 0)
        NumPut("Int", 0, pt, 0)
        NumPut("Int", h, pt, 4)
        lastChar := SendMessage(0x04D9, 0, pt.Ptr, hwnd) ; EM_CHARFROMPOS
        if (lastChar < 0 || lastChar > totalLen)
            lastChar := totalLen
            
        lastLine := SendMessage(0x0436, 0, lastChar, hwnd) ; EM_EXLINEFROMCHAR
        if (lastLine < firstLine)
            lastLine := firstLine + 50
            
        ; Current visible character boundaries (without padding)
        visibleStart := SendMessage(0x00BB, firstLine, 0, hwnd) ; EM_LINEINDEX
        if (visibleStart < 0)
            visibleStart := 0
        visibleEnd := SendMessage(0x00BB, lastLine + 1, 0, hwnd)
        if (visibleEnd < 0 || visibleEnd > totalLen)
            visibleEnd := totalLen

        ; If not forcing, and visible range is fully within last highlighted range, do nothing
        if (!force && ctrl.HasProp("LastHighlightStart") && ctrl.HasProp("LastHighlightEnd")
            && visibleStart >= ctrl.LastHighlightStart && visibleEnd <= ctrl.LastHighlightEnd) {
            return
        }

        ctrl.IsHighlighting := true
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        caretPos := SendMessage(0x0464, 0, 0, hwnd)
        ptScroll := Buffer(8, 0), SendMessage(0x04DD, 0, ptScroll.Ptr, hwnd)

        SendMessage(0x000B, 0, 0, hwnd)
        SendMessage(0x0445, 0, 0, hwnd)

        try {
            len := totalLen
            if (len > 0) {
                ; GETTEXTEX contains pointers. On 64-bit, 32 bytes; 32-bit, 20 bytes.
                GETTEXTEX := Buffer(A_PtrSize == 8 ? 32 : 20, 0), NumPut("UInt", (len + 1) * 2, GETTEXTEX, 0), NumPut("UInt", 1200, GETTEXTEX, 8)
                buf := Buffer((len + 1) * 2, 0)
                SendMessage(0x045E, GETTEXTEX.Ptr, buf.Ptr, hwnd)
                text := StrReplace(StrGet(buf, len, "UTF-16"), "`r", "`n")

                if (!ctrl.HasProp("LastHistoryText") || ctrl.LastHistoryText != text) {
                    CodeBox.Emit("PushHistory", ctrl, "Edit", text, startSel, endSel)
                    ctrl.LastHistoryText := text
                }

                themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
                rules := CodeBox.Syntaxes.Has(StrLower(ctrl.CodeBoxLang)) ? CodeBox.Syntaxes[StrLower(ctrl.CodeBoxLang)] : []

                ; Add padding of 50 lines above and below
                pad := 50
                padStartLine := Max(0, firstLine - pad)
                padEndLine := lastLine + pad
                
                padStartChar := SendMessage(0x00BB, padStartLine, 0, hwnd)
                if (padStartChar < 0)
                    padStartChar := 0
                padEndChar := SendMessage(0x00BB, padEndLine + 1, 0, hwnd)
                if (padEndChar < 0 || padEndChar > totalLen)
                    padEndChar := totalLen
                    
                ; Cache the padded range
                ctrl.LastHighlightStart := padStartChar
                ctrl.LastHighlightEnd := padEndChar

                CodeBox._SetSel(hwnd, 0, -1)
                CodeBox._SetFormat(hwnd, themeC["Foreground"], true)
                CodeBox._SetFormat(hwnd, themeC["Foreground"], false, false, 0, -2)

                firedErr := Map()
                ctrl.ErrorLines := Map(), ctrl.WarningLines := Map()
                for rule in rules {
                    pos := 1, color := themeC.Has(rule.c) ? themeC[rule.c] : themeC["Foreground"]
                    b := rule.HasOwnProp("b") ? rule.b : 0, u := rule.HasOwnProp("u") ? rule.u : 0
                    while (match := RegExMatch(text, rule.p, &m, pos)) {
                        if (m.Len[0] == 0) {
                            pos := match + 1
                            continue
                        }
                        
                        matchStart := match - 1
                        matchEnd := match - 1 + m.Len[0]
                        
                        ; Only apply formatting to overlapping matches
                        if (matchEnd > padStartChar && matchStart < padEndChar) {
                            CodeBox._SetSel(hwnd, matchStart, matchEnd)
                            CodeBox._SetFormat(hwnd, color, false, b, u)
                        }

                        if (rule.c == "Error" || rule.c == "Warning") {
                            sub := SubStr(text, 1, match)
                            StrReplace(sub, "`n", "`n", , &nlCount)
                            lineNum := nlCount + 1
                            if (rule.c == "Error") {
                                ctrl.ErrorLines[lineNum] := rule.HasOwnProp("msg") ? rule.msg : "Invalid syntax: " m[0]
                                if !firedErr.Has(m[0])
                                    firedErr[m[0]] := 1, CodeBox._Fire(ctrl, "Error", m[0])
                            } else {
                                ctrl.WarningLines[lineNum] := rule.HasOwnProp("msg") ? rule.msg : "Potential issue: " m[0]
                            }
                        }
                        pos := match + m.Len[0]
                    }
                }
            }
        } finally {
            CodeBox._SetSelDirectional(hwnd, startSel, endSel, caretPos)
            SendMessage(0x04DE, 0, ptScroll.Ptr, hwnd)
            SendMessage(0x0445, 0, 0x10001 | 0x08 | 0x0400 | 0x00080000, hwnd)
            SendMessage(0x000B, 1, 0, hwnd)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)

            ctrl.IsHighlighting := false
            CodeBox.Emit("OnHighlight", ctrl)
        }
    }
}
