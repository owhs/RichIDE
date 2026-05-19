class CodeBox_Suggest {
    static OnDisable(ctrl) {
        this.OnDestroy(ctrl)
    }

    static OnDestroy(ctrl) {
        if ctrl.HasProp("SuggestGui") && ctrl.SuggestGui
            ctrl.SuggestGui.Destroy()
    }

    static OnChar(ctrl, wParam) {
        if (ctrl.HasProp("SuppressNextChar") && ctrl.SuppressNextChar) {
            ctrl.SuppressNextChar := false
            if (wParam == 13 || wParam == 9)
                return 1
        }
        
        char := Chr(wParam)
        if !ctrl.HasProp("SuggestTimer")
            ctrl.SuggestTimer := () => this.OnSuggestCheck(ctrl)

        if RegExMatch(char, "[a-zA-Z0-9_]")
            SetTimer(ctrl.SuggestTimer, -100)
        else if (wParam != 8)
            this.OnSuggestHide(ctrl)
            
        return 0
    }

    static OnSuggestCheck(ctrl) {
        if !ctrl.AutoSuggest || ctrl._HexView
            return

        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        endSel := NumGet(cr, 4, "Int"), lineIdx := SendMessage(0x0436, 0, endSel, ctrl.Hwnd)
        lineStart := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)

        textBeforeCaret := CodeBox._GetTextRange(ctrl.Hwnd, lineStart, endSel)
        if RegExMatch(textBeforeCaret, "([a-zA-Z_]\w*)$", &m) {
            prefix := m[1]
            if (StrLen(prefix) >= 1) {
                if !CodeBox._KeywordCache.Has(ctrl.CodeBoxLang) {
                    words := Map()
                    if CodeBox.Syntaxes.Has(ctrl.CodeBoxLang) {
                        for rule in CodeBox.Syntaxes[ctrl.CodeBoxLang] {
                            if InStr(rule.c, "Keyword") || InStr(rule.c, "Type") || InStr(rule.c, "Function") {
                                if RegExMatch(rule.p, "\((.*?)\)", &mm) {
                                    for w in StrSplit(mm[1], "|") {
                                        clean := RegExReplace(w, "[^\w]", "")
                                        if (StrLen(clean) >= 1)
                                            words[clean] := rule.c
                                    }
                                }
                            }
                        }
                    }
                    CodeBox._KeywordCache[ctrl.CodeBoxLang] := words
                }

                matches := [], prefixL := StrLower(prefix)
                for w, type in CodeBox._KeywordCache[ctrl.CodeBoxLang] {
                    if (InStr(StrLower(w), prefixL) == 1 && w != prefix)
                        matches.Push({ Word: w, Type: type })
                }

                if matches.Length > 0 {
                    this.InitGui(ctrl)
                    ctrl.SuggestPrefixLen := StrLen(prefix)
                    theme := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
                    bgH := StrReplace(CodeBox._ColorToHex(theme["Background"]), "#", "")
                    fgH := StrReplace(CodeBox._ColorToHex(theme["Foreground"]), "#", "")
                    borderH := StrReplace(CodeBox._ColorToHex(theme.Has("Punctuation") ? theme["Punctuation"] : 0x444444), "#", "")

                    ctrl.SuggestGui.BackColor := borderH
                    ctrl.SuggestList.Opt("Background" bgH " c" fgH)
                    ctrl.SuggestList.Delete()

                    for mItem in matches {
                        typeSymbol := mItem.Type == "Function" ? "ƒ" : mItem.Type == "Keyword" ? "♦" : "■"
                        ctrl.SuggestList.Add("", typeSymbol "  " mItem.Type, mItem.Word)
                    }

                    ctrl.SuggestList.Modify(1, "Select Focus Vis")

                    pt := Buffer(8), SendMessage(0x0426, pt.Ptr, endSel, ctrl.Hwnd)
                    px := NumGet(pt, 0, "Int"), py := NumGet(pt, 4, "Int")

                    pt64 := Buffer(8), NumPut("Int", px, pt64, 0), NumPut("Int", py, pt64, 4)
                    DllCall("ClientToScreen", "Ptr", ctrl.Hwnd, "Ptr", pt64)
                    sx := NumGet(pt64, 0, "Int"), sy := NumGet(pt64, 4, "Int")

                    listHeight := Min(matches.Length * 18 + 4, 150)
                    ctrl.SuggestList.Move(1, 1, 248, listHeight)
                    ctrl.SuggestGui.Show("NoActivate x" sx " y" (sy + 20) " w250 h" (listHeight + 2))
                    ctrl.SuggestActive := true
                    return
                }
            }
        }
        this.OnSuggestHide(ctrl)
    }

    static InitGui(ctrl) {
        if ctrl.HasProp("SuggestGui")
            return
        ctrl.SuggestGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +Owner" DllCall("GetAncestor", "Ptr", ctrl.Hwnd, "UInt", 2))
        ctrl.SuggestGui.MarginX := 0, ctrl.SuggestGui.MarginY := 0
        ctrl.SuggestList := ctrl.SuggestGui.Add("ListView", "x1 y1 w248 h148 -Hdr -Multi +Count10 -E0x200 Background252526 cWhite", ["Type", "Word"])
        ctrl.SuggestList.SetFont("s10", "Consolas")
        ctrl.SuggestList.ModifyCol(1, 80)
        ctrl.SuggestList.ModifyCol(2, 160)
        ctrl.SuggestList.OnEvent("DoubleClick", (*) => this.Commit(ctrl))
        ctrl.SuggestActive := false
    }

    static OnSuggestHide(ctrl) {
        if ctrl.HasProp("SuggestGui") && ctrl.SuggestActive
            ctrl.SuggestGui.Hide(), ctrl.SuggestActive := false
    }

    static Commit(ctrl) {
        if !ctrl.SuggestActive || !DllCall("IsWindowVisible", "Ptr", ctrl.SuggestGui.Hwnd)
            return

        idx := ctrl.SuggestList.GetNext(0, "F")
        if (idx == 0)
            return

        val := ctrl.SuggestList.GetText(idx, 2)
        this.OnSuggestHide(ctrl)
        if !val
            return

        ctrl.SuppressNextChar := true

        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        endSel := NumGet(cr, 4, "Int")
        
        lineIdx := SendMessage(0x0436, 0, endSel, ctrl.Hwnd)
        lineStart := SendMessage(0x00BB, lineIdx, 0, ctrl.Hwnd)
        textBeforeCaret := CodeBox._GetTextRange(ctrl.Hwnd, lineStart, endSel)
        
        prefixLen := 0
        if RegExMatch(textBeforeCaret, "([a-zA-Z_]\w*)$", &m)
            prefixLen := StrLen(m[1])

        CodeBox._SetSel(ctrl.Hwnd, endSel - prefixLen, endSel)
        CodeBox._InsertText(ctrl.Hwnd, val)
        CodeBox._SetSel(ctrl.Hwnd, endSel - prefixLen + StrLen(val), endSel - prefixLen + StrLen(val))
        CodeBox._Fire(ctrl, "Suggest", val)
        ControlFocus(ctrl.Hwnd)
    }

    static OnKeyDown(ctrl, wParam) {
        if ctrl.HasProp("SuggestActive") && ctrl.SuggestActive && DllCall("IsWindowVisible", "Ptr", ctrl.SuggestGui.Hwnd) {
            if (wParam == 38) { ; Up
                idx := ctrl.SuggestList.GetNext(0, "F")
                if (idx > 1)
                    ctrl.SuggestList.Modify(idx - 1, "Select Focus Vis")
                else if (idx == 0)
                    ctrl.SuggestList.Modify(ctrl.SuggestList.GetCount(), "Select Focus Vis")
                return 1
            }
            if (wParam == 40) { ; Down
                idx := ctrl.SuggestList.GetNext(0, "F")
                if (idx < ctrl.SuggestList.GetCount())
                    ctrl.SuggestList.Modify(idx > 0 ? idx + 1 : 1, "Select Focus Vis")
                else
                    ctrl.SuggestList.Modify(1, "Select Focus Vis")
                return 1
            }
            if (wParam == 9 || wParam == 13) { ; Tab/Enter
                this.Commit(ctrl)
                return 1
            }
            if (wParam == 27) { ; Esc
                this.OnSuggestHide(ctrl)
                return 1
            }
            if (wParam == 8) { ; Backspace
                if !ctrl.HasProp("SuggestTimer")
                    ctrl.SuggestTimer := () => CodeBox.Emit("OnSuggestCheck", ctrl)
                SetTimer(ctrl.SuggestTimer, -100)
            }
        }
        return 0
    }
}
