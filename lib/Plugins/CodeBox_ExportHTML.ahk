class CodeBox_ExportHTML {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        fileMenu.Add("Export as HTML", (*) => (
            A_Clipboard := CodeBox.Invoke("ExportHTML", ctrl),
            MsgBox("Exported HTML pre-formatted block natively copied to Clipboard!", "Success", 64)
        ))
    }
    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := true
    }

    static ExportHTML(ctrl) {
        text := CodeBox._GetText(ctrl)
        theme := CodeBox.Themes[ctrl.CodeBoxTheme]
        rules := CodeBox.Syntaxes.Has(StrLower(ctrl.CodeBoxLang)) ? CodeBox.Syntaxes[StrLower(ctrl.CodeBoxLang)] : []

        formats := []
        loop StrLen(text)
            formats.Push({ c: theme["Foreground"], b: 0, u: 0 })

        for rule in rules {
            pos := 1, color := theme.Has(rule.c) ? theme[rule.c] : theme["Foreground"]
            bold := rule.HasOwnProp("b") ? rule.b : false, underline := rule.HasOwnProp("u") ? rule.u : false
            while (match := RegExMatch(text, rule.p, &m, pos)) {
                if (m.Len[0] == 0) {
                    pos := match + 1
                    continue
                }
                loop m.Len[0]
                    formats[match + A_Index - 1] := { c: color, b: bold, u: underline }
                pos := match + m.Len[0]
            }
        }

        html := "<pre style='background-color:" CodeBox._ColorToHex(theme["Background"]) "; color:" CodeBox._ColorToHex(theme["Foreground"]) "; padding:15px; font-family:Consolas, monospace; line-height: 1.4; white-space: pre-wrap;'>"
        lastFmt := ""
        loop StrLen(text) {
            c := SubStr(text, A_Index, 1), f := formats[A_Index], fStr := f.c "_" f.b "_" f.u
            if (fStr != lastFmt) {
                if (A_Index > 1)
                    html .= "</span>"
                html .= "<span style='color:" CodeBox._ColorToHex(f.c) (f.b ? "; font-weight:bold" : "") (f.u ? "; text-decoration:underline wavy red" : "") "'>"
                lastFmt := fStr
            }
            html .= c == "<" ? "&lt;" : c == ">" ? "&gt;" : c == "&" ? "&amp;" : c
        }
        if (StrLen(text) > 0)
            html .= "</span>"
        return html "</pre>"
    }
}
