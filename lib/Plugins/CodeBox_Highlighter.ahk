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
        this.ToolbarDDL.OnEvent("Change", (*) => (ctrl.Language := this.ToolbarDDL.Text, CodeBox._SetText(ctrl, GetExampleText(this.ToolbarDDL.Text), true)))
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
        this.Highlight(ctrl)
    }
    static OnLanguageChange(ctrl) {
        this.Highlight(ctrl)
    }
    static OnThemeChange(ctrl) {
        this.Highlight(ctrl)
    }

    static Highlight(ctrl) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        ctrl.IsHighlighting := true
        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        pt := Buffer(8, 0), SendMessage(0x04DD, 0, pt.Ptr, hwnd)

        DllCall("HideCaret", "Ptr", hwnd)
        SendMessage(0x000B, 0, 0, hwnd)
        SendMessage(0x0445, 0, 0, hwnd)

        len := SendMessage(0x000E, 0, 0, hwnd)
        if (len > 0) {
            ; GETTEXTEX contains pointers. On 64-bit, 4 bytes of padding are added before pointers, totaling 32 bytes. On 32-bit it is 20 bytes.
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
                    CodeBox._SetSel(hwnd, match - 1, match - 1 + m.Len[0])
                    CodeBox._SetFormat(hwnd, color, false, b, u)



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

        CodeBox._SetSel(hwnd, startSel, endSel)
        SendMessage(0x04DE, 0, pt.Ptr, hwnd)
        SendMessage(0x0445, 0, 0x10001 | 0x08 | 0x0400, hwnd)
        SendMessage(0x000B, 1, 0, hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)
        DllCall("ShowCaret", "Ptr", hwnd)



        ctrl.IsHighlighting := false
        CodeBox.Emit("OnHighlight", ctrl)
    }
}
