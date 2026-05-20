class CodeBox_FindReplace {
    static DlgGui := ""
    static ActiveCtrl := ""
    static SearchMatches := []
    static MatchIndex := 0
    static LastSearchQuery := ""
    static ShowingMatchesList := false
    static LastRegex := 0
    static LastCase := 0
    static LastWhole := 0
    static LastReplaceQuery := ""
    static LastHighlight := 0
    static IsHighlightingAll := false
    static ShowingHelpTooltip := false
    static LastPreview := 0
    static IsPreviewing := false
    static OriginalText := ""
    static OriginalSelStart := 0
    static OriginalSelEnd := 0
    static OriginalCaretPos := 0
    static OriginalScrollPos := Buffer(8, 0)

    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        editMenu.Add("Find`tCtrl+F", (*) => this.ShowPanel(ctrl, false))
        editMenu.Add("Replace`tCtrl+H", (*) => this.ShowPanel(ctrl, true))
        editMenu.Add("Find Next`tF3", (*) => this.FindNext(ctrl))
        editMenu.Add("Find Previous`tShift+F3", (*) => this.FindPrev(ctrl))
    }

    static OnKeyDown(ctrl, wParam) {
        if GetKeyState("Ctrl", "P") {
            if (wParam == 70) { ; Ctrl+F
                this.ShowPanel(ctrl, false)
                return 1
            } else if (wParam == 72) { ; Ctrl+H
                this.ShowPanel(ctrl, true)
                return 1
            }
        } else if (wParam == 114) { ; F3
            if GetKeyState("Shift", "P")
                this.FindPrev(ctrl)
            else
                this.FindNext(ctrl)
            return 1
        }
        return 0
    }

    static OnThemeChange(ctrl) {
        if (this.DlgGui && this.ActiveCtrl.Hwnd == ctrl.Hwnd) {
            ; Recreate dialog to perfectly match new theme colors
            this.DlgGui.GetPos(&x, &y)
            isReplace := this.IsReplaceMode
            this.DestroyDialog()
            this.ShowPanel(ctrl, isReplace, x, y)
        }
    }

    static OnDestroy(ctrl) {
        if (this.ActiveCtrl && this.ActiveCtrl.Hwnd == ctrl.Hwnd) {
            this.DestroyDialog()
        }
    }

    static IsReplaceMode {
        get {
            if !this.DlgGui
                return false
            try {
                ; If replace edit box is visible, we're in replace mode
                return ControlGetVisible(this.ReplaceEdit)
            } catch {
                return false
            }
        }
    }

    static DestroyDialog() {
        if this.DlgGui {
            if this.HasProp("HoverTimer") && this.HoverTimer {
                SetTimer(this.HoverTimer, 0)
                this.HoverTimer := ""
            }
            ToolTip(,,, 2) ; Clear tooltip
            this.ShowingHelpTooltip := false
            ctrl := this.ActiveCtrl
            if (this.IsPreviewing && ctrl && DllCall("IsWindow", "Ptr", ctrl.Hwnd)) {
                this.RestoreOriginal(ctrl)
            }
            try this.DlgGui.Destroy()
            this.DlgGui := ""
            this.ShowingMatchesList := false
            if (ctrl && DllCall("IsWindow", "Ptr", ctrl.Hwnd)) {
                CodeBox_Highlighter.Highlight(ctrl)
            }
        }
    }

    static ShowPanel(ctrl, isReplaceMode := false, posX := "", posY := "") {
        this.ActiveCtrl := ctrl
 
        ; Capture current selection in editor as search default
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        defaultSearch := ""
        hasNewlines := false
        if (startSel != endSel && (endSel - startSel) < 1000) {
            defaultSearch := CodeBox._GetTextRange(ctrl.Hwnd, startSel, endSel)
            ; Normalize carriage returns from RichEdit control (\r\n and lone \r to standard \n)
            defaultSearch := StrReplace(defaultSearch, "`r`n", "`n")
            defaultSearch := StrReplace(defaultSearch, "`r", "`n")
            
            if (InStr(defaultSearch, "`n")) {
                hasNewlines := true
                defaultSearch := StrReplace(defaultSearch, "`n", "\n")
                defaultSearch := StrReplace(defaultSearch, "`t", "\t")
            }
        }
 
        if this.DlgGui {
            ; Just focus and update default search text if needed
            this.DlgGui.Opt("+AlwaysOnTop")
            this.DlgGui.Show("NoActivate")
            if (defaultSearch != "") {
                this.FindEdit.Value := defaultSearch
            }
            ControlFocus(this.FindEdit)
            this.RunSearch()
            return
        }
 
        ; Create beautifully styled non-modal window matching theme colors
        themeName := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? ctrl.CodeBoxTheme : "Dark"
        theme := CodeBox.Themes[themeName]
 
        bgColorHex := Format("{:06X}", theme["Background"])
        fgColorHex := Format("{:06X}", theme["Foreground"])
        commentColorHex := Format("{:06X}", theme["Comment"])
        errColorHex := Format("{:06X}", theme["Error"])
        warnColorHex := Format("{:06X}", theme["Warning"])
 
        ; Use slightly offset backgrounds for buttons and inputs
        inputBgColorHex := (themeName == "Light") ? "F0F0F0" : "2D2D30"
        btnBgColorHex := (themeName == "Light") ? "E5E5E5" : "3E3E42"
 
        this.DlgGui := Gui("+ToolWindow +AlwaysOnTop -MaximizeBox -MinimizeBox +Owner" ctrl.Gui.Hwnd, isReplaceMode ? "Find & Replace" : "Find")
        this.DlgGui.BackColor := bgColorHex
        this.DlgGui.SetFont("s9 c" fgColorHex, "Segoe UI")
 
        ; Row 1: Find Input
        this.DlgGui.Add("Text", "x15 y15 w50 h22 BackgroundTrans", "Find:")
        this.FindEdit := this.DlgGui.Add("Edit", "x70 y12 w435 h24 Background" inputBgColorHex " c" fgColorHex " -WantReturn", defaultSearch == "" ? this.LastSearchQuery : defaultSearch)
        
        ; Row 2: Replace Input
        this.ReplaceTextLabel := this.DlgGui.Add("Text", "x15 y45 w50 h22 BackgroundTrans", "Replace:")
        this.ReplaceEdit := this.DlgGui.Add("Edit", "x70 y42 w435 h24 Background" inputBgColorHex " c" fgColorHex " -WantReturn", this.LastReplaceQuery)
 
        ; Row 3: Checkboxes Row (spacious layout below edit inputs)
        this.OptRegex := this.DlgGui.Add("CheckBox", "x70 y75 w60 h20 c" fgColorHex " Checked" this.LastRegex, "Regex")
        this.BtnRegexHelp := this.DlgGui.Add("Text", "x130 y75 w15 h20 BackgroundTrans c" commentColorHex, "(?)")
        this.OptCase := this.DlgGui.Add("CheckBox", "x150 y75 w90 h20 c" fgColorHex " Checked" this.LastCase, "Match Case")
        this.OptWhole := this.DlgGui.Add("CheckBox", "x245 y75 w90 h20 c" fgColorHex " Checked" this.LastWhole, "Whole Word")
        this.OptHighlight := this.DlgGui.Add("CheckBox", "x340 y75 w80 h20 c" fgColorHex " Checked" this.LastHighlight, "Highlight")
        this.OptPreview := this.DlgGui.Add("CheckBox", "x425 y75 w80 h20 c" fgColorHex " Checked" this.LastPreview, "Preview")
 
        ; Row 4: Action Buttons (premium styling and sizes)
        this.BtnFindNext := this.DlgGui.Add("Button", "x70 y105 w80 h26 Background" btnBgColorHex " c" fgColorHex, "Find Next")
        this.BtnFindPrev := this.DlgGui.Add("Button", "x155 y105 w80 h26 Background" btnBgColorHex " c" fgColorHex, "Find Prev")
        this.BtnReplace := this.DlgGui.Add("Button", "x240 y105 w75 h26 Background" btnBgColorHex " c" fgColorHex, "Replace")
        this.BtnReplaceAll := this.DlgGui.Add("Button", "x320 y105 w95 h26 Background" btnBgColorHex " c" fgColorHex, "Replace All")
        this.BtnFindAll := this.DlgGui.Add("Button", "x420 y105 w85 h26 Background" btnBgColorHex " c" fgColorHex, "Find All")
 
        ; Row 5: Status Indicator (Real-time Count & Regex Validator)
        this.StatusText := this.DlgGui.Add("Text", "x15 y140 w490 h20 BackgroundTrans c" commentColorHex, "Type to search...")
 
        ; Row 6: Find All Matches Drawer (collapsible)
        this.MatchesList := this.DlgGui.Add("ListView", "x15 y165 w490 h130 Background" inputBgColorHex " c" fgColorHex " Grid -Multi +Report", ["Line", "Col", "Snippet"])
        this.MatchesList.ModifyCol(1, 40)
        this.MatchesList.ModifyCol(2, 40)
        this.MatchesList.ModifyCol(3, 390)
        this.MatchesList.Visible := false
 
        ; Event Registrations
        this.FindEdit.OnEvent("Change", (*) => (this.RunSearch(), this.IsPreviewing ? this.UpdatePreview(ctrl) : ""))
        this.ReplaceEdit.OnEvent("Change", (*) => (this.LastReplaceQuery := this.ReplaceEdit.Value, this.IsPreviewing ? this.UpdatePreview(ctrl) : ""))
        this.OptRegex.OnEvent("Click", (*) => (this.LastRegex := this.OptRegex.Value, this.RunSearch(), this.IsPreviewing ? this.UpdatePreview(ctrl) : ""))
        this.OptCase.OnEvent("Click", (*) => (this.LastCase := this.OptCase.Value, this.RunSearch(), this.IsPreviewing ? this.UpdatePreview(ctrl) : ""))
        this.OptWhole.OnEvent("Click", (*) => (this.LastWhole := this.OptWhole.Value, this.RunSearch(), this.IsPreviewing ? this.UpdatePreview(ctrl) : ""))
        this.OptHighlight.OnEvent("Click", (*) => (this.LastHighlight := this.OptHighlight.Value, this.OnHighlightToggle(ctrl)))
        this.OptPreview.OnEvent("Click", (*) => (this.LastPreview := this.OptPreview.Value, this.OnPreviewToggle(ctrl)))
 
        this.BtnFindNext.OnEvent("Click", (*) => this.FindNext(ctrl))
        this.BtnFindPrev.OnEvent("Click", (*) => this.FindPrev(ctrl))
        this.BtnReplace.OnEvent("Click", (*) => this.ReplaceSingle(ctrl))
        this.BtnReplaceAll.OnEvent("Click", (*) => this.ReplaceAll(ctrl))
        this.BtnFindAll.OnEvent("Click", (*) => this.ToggleMatchesList(ctrl))
 
        this.MatchesList.OnEvent("DoubleClick", (lv, row) => this.OnMatchItemClick(ctrl, row))
 
        ; Handle dialog closure
        this.DlgGui.OnEvent("Close", (*) => this.DestroyDialog())
        this.DlgGui.OnEvent("Escape", (*) => this.DestroyDialog())
 
        ; Connect Enter and Shift+Enter keypress inside Find input
        this.FindEdit.OnEvent("Focus", (*) => (this.DlgGui.Default := this.BtnFindNext))
 
        ; Start the hover check timer for the Regex Help Tooltip
        this.ShowingHelpTooltip := false
        this.HoverTimer := ObjBindMethod(this, "_CheckHover")
        SetTimer(this.HoverTimer, 200)
 
        ; Layout toggle based on mode
        if (!isReplaceMode) {
            ; Hide Replace labels and inputs, move buttons and checkboxes up!
            this.ReplaceTextLabel.Visible := false
            this.ReplaceEdit.Visible := false
            this.OptPreview.Visible := false
            
            this.OptRegex.Move(70, 45, 60)
            this.BtnRegexHelp.Move(130, 45, 15)
            this.OptCase.Move(150, 45, 90)
            this.OptWhole.Move(245, 45, 90)
            this.OptHighlight.Move(340, 45, 80)
 
            this.BtnFindNext.Move(70, 75, 80)
            this.BtnFindPrev.Move(155, 75, 80)
            this.BtnReplace.Visible := false
            this.BtnReplaceAll.Visible := false
            this.BtnFindAll.Move(240, 75, 85)
 
            this.StatusText.Move(15, 110, 490)
            this.MatchesList.Move(15, 135, 490, 130)
            
            showH := 135
        } else {
            showH := 165
        }
 
        ; Positioning
        posOptions := "w520 h" showH
        if (posX != "" && posY != "") {
            posOptions .= " x" posX " y" posY
        }
        
        this.DlgGui.Show(posOptions)
        ControlFocus(this.FindEdit)
        this.RunSearch()
    }

    static ToggleMatchesList(ctrl) {
        if !this.DlgGui
            return
        
        this.ShowingMatchesList := !this.ShowingMatchesList
        isReplace := this.IsReplaceMode

        if (this.ShowingMatchesList) {
            this.MatchesList.Visible := true
            h := isReplace ? 310 : 280
            this.DlgGui.Move(,,, h)
            this.PopulateMatchesList(ctrl)
        } else {
            this.MatchesList.Visible := false
            h := isReplace ? 165 : 135
            this.DlgGui.Move(,,, h)
        }
    }

    static RunSearch() {
        if !this.DlgGui || !this.ActiveCtrl
            return

        findText := this.FindEdit.Value
        this.LastSearchQuery := findText

        if (findText == "") {
            this.SearchMatches := []
            this.MatchIndex := 0
            this.UpdateStatus("Type something to search...", "Comment")
            if (this.ShowingMatchesList)
                this.MatchesList.Delete()
            if (this.LastHighlight && !this.ActiveCtrl.IsHighlighting && !this.IsHighlightingAll) {
                CodeBox_Highlighter.Highlight(this.ActiveCtrl)
            }
            return
        }

        text := this.IsPreviewing ? this.OriginalText : this.GetSearchText(this.ActiveCtrl)
        matches := []
        isRegex := this.OptRegex.Value
        isCase := this.OptCase.Value
        isWhole := this.OptWhole.Value

        pattern := findText

        if (!isRegex) {
            ; Parse the find text and translate escapes \n, \t, \r, \\ to support multi-line standard search
            parsed := ""
            len := StrLen(findText)
            i := 1
            while (i <= len) {
                char := SubStr(findText, i, 1)
                if (char == "\") {
                    if (i == len) {
                        parsed .= "\"
                        break
                    }
                    nextChar := SubStr(findText, i + 1, 1)
                    if (nextChar == "n") {
                        parsed .= "`n"
                        i += 2
                    } else if (nextChar == "t") {
                        parsed .= "`t"
                        i += 2
                    } else if (nextChar == "r") {
                        parsed .= "`r"
                        i += 2
                    } else if (nextChar == "\") {
                        parsed .= "\"
                        i += 2
                    } else {
                        parsed .= "\" . nextChar
                        i += 2
                    }
                } else {
                    parsed .= char
                    i += 1
                }
            }
            ; Escape regex meta-characters for standard search on the parsed pattern
            pattern := RegExReplace(parsed, "([\\.*?+\[\]{}()|^$])", "\$1")
        }

        if (isWhole) {
            pattern := "\b" pattern "\b"
        }

        ; Prefix regex options
        regexOptions := isCase ? "" : "i"
        finalPattern := regexOptions "m)" pattern

        try {
            pos := 1
            while (mPos := RegExMatch(text, finalPattern, &m, pos)) {
                if (m.Len[0] == 0) {
                    pos := mPos + 1
                    continue
                }

                if (this.IsPreviewing) {
                    ; Pure in-memory calculation based on OriginalText
                    leftSub := SubStr(text, 1, mPos - 1)
                    StrReplace(leftSub, "`n", "`n", , &lineIdx)
                    
                    ; Find the start of the current line in text
                    lineStartPos := InStr(leftSub, "`n", , -1) ; last newline
                    if (lineStartPos == 0)
                        colIdx := mPos
                    else
                        colIdx := mPos - lineStartPos
                    
                    ; Find the end of the current line
                    lineEndPos := InStr(text, "`n", , mPos)
                    if (lineEndPos == 0)
                        lineLen := StrLen(text) - (lineStartPos == 0 ? 0 : lineStartPos)
                    else
                        lineLen := lineEndPos - (lineStartPos == 0 ? 1 : lineStartPos)
                        
                    lineStartIdx := lineStartPos == 0 ? 1 : lineStartPos + 1
                    lineText := SubStr(text, lineStartIdx, lineLen)
                    lineText := Trim(StrReplace(StrReplace(lineText, "`r", ""), "`n", ""))
                } else {
                    ; Standard RichEdit calculations
                    lineIdx := SendMessage(0x0436, 0, mPos - 1, this.ActiveCtrl.Hwnd)
                    lineStartIdx := SendMessage(0x00BB, lineIdx, 0, this.ActiveCtrl.Hwnd)
                    colIdx := mPos - 1 - lineStartIdx + 1

                    lineLen := SendMessage(0x00C1, lineStartIdx, 0, this.ActiveCtrl.Hwnd)
                    lineText := CodeBox._GetTextRange(this.ActiveCtrl.Hwnd, lineStartIdx, lineStartIdx + lineLen)
                    lineText := Trim(StrReplace(StrReplace(lineText, "`r", ""), "`n", ""))
                }

                matches.Push({
                    start: mPos - 1,
                    end: mPos - 1 + m.Len[0],
                    len: m.Len[0],
                    line: lineIdx + 1,
                    col: colIdx,
                    snippet: lineText,
                    matchObj: m
                })

                pos := mPos + m.Len[0]
            }

            this.SearchMatches := matches
            this.MatchIndex := (matches.Length > 0) ? 1 : 0

            if (matches.Length == 0) {
                this.UpdateStatus("No matches found", "Warning")
            } else {
                this.UpdateStatus("✓ " matches.Length " matches found", "Keyword")
            }

            if (this.ShowingMatchesList) {
                this.PopulateMatchesList(this.ActiveCtrl)
            }
        } catch Error as err {
            this.SearchMatches := []
            this.MatchIndex := 0
            this.UpdateStatus("⚠ Invalid Regex: " err.Message, "Error")
            if (this.ShowingMatchesList)
                this.MatchesList.Delete()
        }

        if (this.LastHighlight && !this.ActiveCtrl.IsHighlighting && !this.IsHighlightingAll) {
            CodeBox_Highlighter.Highlight(this.ActiveCtrl)
        }
    }

    static PopulateMatchesList(ctrl) {
        this.MatchesList.Delete()
        for idx, m in this.SearchMatches {
            this.MatchesList.Add("", m.line, m.col, m.snippet)
        }
    }

    static OnMatchItemClick(ctrl, row) {
        if (row <= 0 || row > this.SearchMatches.Length)
            return

        this.MatchIndex := row
        this.SelectMatch(ctrl, this.SearchMatches[row])
    }

    static SelectMatch(ctrl, m) {
        ControlFocus(ctrl.Hwnd)
        CodeBox._SetSel(ctrl.Hwnd, m.start, m.end)
        SendMessage(0x04B7, 0, 0, ctrl.Hwnd) ; EM_SCROLLCARET
        
        ; Broadcast select action
        CodeBox.Emit("OnScroll", ctrl)
    }

    static FindNext(ctrl) {
        this.ActiveCtrl := ctrl
        if (this.SearchMatches.Length == 0) {
            this.RunSearch()
            if (this.SearchMatches.Length == 0)
                return
        }

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        ; Find the first match that sits after the current selection start
        nextIdx := 0
        for idx, m in this.SearchMatches {
            if (m.start > startSel) {
                nextIdx := idx
                break
            }
        }

        if (nextIdx == 0) {
            ; Wrap search around to the very first match
            nextIdx := 1
            ToolTip("Wrapped search")
            SetTimer(() => ToolTip(), -1500)
        }

        this.MatchIndex := nextIdx
        this.SelectMatch(ctrl, this.SearchMatches[nextIdx])
    }

    static FindPrev(ctrl) {
        this.ActiveCtrl := ctrl
        if (this.SearchMatches.Length == 0) {
            this.RunSearch()
            if (this.SearchMatches.Length == 0)
                return
        }

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        ; Find the first match that sits before the current selection start
        prevIdx := 0
        loop this.SearchMatches.Length {
            idx := this.SearchMatches.Length - A_Index + 1
            m := this.SearchMatches[idx]
            if (m.start < startSel) {
                prevIdx := idx
                break
            }
        }

        if (prevIdx == 0) {
            ; Wrap search to the very last match
            prevIdx := this.SearchMatches.Length
            ToolTip("Wrapped search")
            SetTimer(() => ToolTip(), -1500)
        }

        this.MatchIndex := prevIdx
        this.SelectMatch(ctrl, this.SearchMatches[prevIdx])
    }

    static ReplaceSingle(ctrl) {
        this.ActiveCtrl := ctrl
        if !this.DlgGui
            return

        if (this.IsPreviewing) {
            this.ReplaceAll(ctrl)
            return
        }

        if (this.SearchMatches.Length == 0) {
            this.RunSearch()
            if (this.SearchMatches.Length == 0)
                return
        }

        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")

        ; Verify if current selection is exactly a match
        currentMatch := ""
        for idx, m in this.SearchMatches {
            if (m.start == startSel && m.end == endSel) {
                currentMatch := m
                this.MatchIndex := idx
                break
            }
        }

        replaceText := this.ReplaceEdit.Value

        CodeBox.Emit("PushHistory", ctrl, "Replace")

        if (currentMatch != "") {
            formattedReplace := this.GetReplacementText(replaceText, currentMatch.matchObj)
            CodeBox._InsertText(ctrl.Hwnd, formattedReplace)
            ; Refresh search bounds and advance selection to next match
            this.RunSearch()
            this.FindNext(ctrl)
        } else {
            ; If cursor is not sitting on a match, highlight the next match first
            this.FindNext(ctrl)
        }
    }

    static ReplaceAll(ctrl) {
        this.ActiveCtrl := ctrl
        if !this.DlgGui
            return

        if (this.IsPreviewing) {
            count := this.SearchMatches.Length
            
            ; Disable preview flags and make editable
            this.IsPreviewing := false
            ctrl.IsPreviewing := false
            SendMessage(0x00CF, 0, 0, ctrl.Hwnd)
            
            ; Push history
            CodeBox.Emit("PushHistory", ctrl, "Replace All")
            
            ; Update UI checkbox
            this.OptPreview.Value := 0
            this.LastPreview := 0
            
            ; Refresh search bounds on the new committed text
            this.RunSearch()
            
            MsgBox("Successfully replaced " count " occurrences (committed preview).", "Success", 64)
            return
        }

        this.RunSearch()
        if (this.SearchMatches.Length == 0) {
            MsgBox("No matches found to replace.", "Replace All", 48)
            return
        }

        replaceText := this.ReplaceEdit.Value
        count := this.SearchMatches.Length

        CodeBox.Emit("PushHistory", ctrl, "Replace All")

        ; Turn off rendering updates to prevent flickering
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)

        ; Loop backwards so replacement index offsets do not invalidate subsequent matches
        loop this.SearchMatches.Length {
            idx := this.SearchMatches.Length - A_Index + 1
            m := this.SearchMatches[idx]
            formattedReplace := this.GetReplacementText(replaceText, m.matchObj)
            CodeBox._SetSel(ctrl.Hwnd, m.start, m.end)
            CodeBox._InsertText(ctrl.Hwnd, formattedReplace)
        }

        ; Re-enable drawing
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        ; Reset selection to beginning
        CodeBox._SetSel(ctrl.Hwnd, 0, 0)

        ; Trigger highlight and search refresh
        CodeBox.Emit("OnChange", ctrl)
        this.RunSearch()

        MsgBox("Successfully replaced " count " occurrences.", "Success", 64)
    }

    static UpdateStatus(text, colorName) {
        if !this.DlgGui
            return

        themeName := CodeBox.Themes.Has(this.ActiveCtrl.CodeBoxTheme) ? this.ActiveCtrl.CodeBoxTheme : "Dark"
        theme := CodeBox.Themes[themeName]
        colorHex := Format("{:06X}", theme.Has(colorName) ? theme[colorName] : theme["Foreground"])

        this.StatusText.SetFont("c" colorHex)
        this.StatusText.Value := text
    }

    static GetSearchText(ctrl) {
        len := SendMessage(0x000E, 0, 0, ctrl.Hwnd)
        if (len == 0)
            return ""
        GETTEXTEX := Buffer(A_PtrSize == 8 ? 32 : 20, 0), NumPut("UInt", (len + 1) * 2, GETTEXTEX, 0), NumPut("UInt", 1200, GETTEXTEX, 8)
        buf := Buffer((len + 1) * 2, 0)
        SendMessage(0x045E, GETTEXTEX.Ptr, buf.Ptr, ctrl.Hwnd)
        return StrReplace(StrGet(buf, len, "UTF-16"), "`r", "`n")
    }

    static OnHighlightToggle(ctrl) {
        if (ctrl && DllCall("IsWindow", "Ptr", ctrl.Hwnd)) {
            CodeBox_Highlighter.Highlight(ctrl)
        }
    }

    static OnHighlight(ctrl) {
        if (!this.DlgGui || !this.ActiveCtrl || this.ActiveCtrl.Hwnd != ctrl.Hwnd)
            return

        ; If highlight is disabled or search query is too short, do nothing
        ; This ensures that standard syntax highlighting remains clean and unmodified
        if (!this.LastHighlight || StrLen(this.LastSearchQuery) < 3)
            return

        if this.IsHighlightingAll
            return

        this.IsHighlightingAll := true

        ; Update matches to ensure they are in sync with any recent edits
        this.RunSearch()

        if (this.SearchMatches.Length == 0) {
            this.IsHighlightingAll := false
            return
        }

        ; Determine colors based on active theme
        themeName := ctrl.CodeBoxTheme
        
        ; Vibrant search highlight colors
        if (themeName == "Matrix") {
            bgColor := 0x00FF41 ; Bright Matrix green
            fgColor := 0x000000 ; Black
        } else if (themeName == "Hacker") {
            bgColor := 0xFF0000 ; Bright Hacker red
            fgColor := 0xFFFFFF ; White text
        } else { ; Dark, Light, or any other theme
            bgColor := 0xFFFF00 ; Bright yellow
            fgColor := 0x000000 ; Black
        }

        ; Save current selection and scroll position so cursor doesn't jump
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd) ; EM_GETSEL
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        caretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
        
        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS

        SendMessage(0x000B, 0, 0, ctrl.Hwnd) ; WM_SETREDRAW = false
        SendMessage(0x0445, 0, 0, ctrl.Hwnd) ; EM_SETOPTIONS (ECOOP_SET, 0)

        try {
            ; Loop through all matches and apply our custom formatting using proven API
            for m in this.SearchMatches {
                CodeBox._SetSel(ctrl.Hwnd, m.start, m.end)
                CodeBox._SetFormat(ctrl.Hwnd, fgColor, false, false, 0, bgColor)
            }
        } finally {
            ; Restore selection and scroll position
            CodeBox._SetSelDirectional(ctrl.Hwnd, startSel, endSel, caretPos)
            SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd) ; EM_SETSCROLLPOS

            ; Restore options and unfreeze control redraw
            SendMessage(0x0445, 0, 0x10001 | 0x08 | 0x0400 | 0x00080000, ctrl.Hwnd) ; EM_SETOPTIONS (ECOOP_SET, standard)
            SendMessage(0x000B, 1, 0, ctrl.Hwnd) ; WM_SETREDRAW = true
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

            this.IsHighlightingAll := false
        }
    }

    static _CheckHover() {
        if !this.DlgGui
            return
        
        try {
            if (!this.HasProp("BtnRegexHelp") || !this.BtnRegexHelp || !this.HasProp("OptRegex") || !this.OptRegex)
                return
            MouseGetPos ,, &win, &ctrlHwnd, 2
            if (win == this.DlgGui.Hwnd) {
                if (ctrlHwnd == this.BtnRegexHelp.Hwnd || ctrlHwnd == this.OptRegex.Hwnd) {
                    if (!this.ShowingHelpTooltip) {
                        this.ShowingHelpTooltip := true
                        ToolTip(this.GetRegexHelpText(),,, 2)
                    }
                    return
                }
            }
        }
        if (this.ShowingHelpTooltip) {
            ToolTip(,,, 2)
            this.ShowingHelpTooltip := false
        }
    }

    static GetRegexHelpText() {
        return "Find & Replace Quick Guide:`n"
             . "-------------------------------------------`n"
             . "Search Patterns (Regex Mode):`n"
             . "  .          - Any character except newline`n"
             . "  \d, \w, \s - Digit, Word-char, Whitespace`n"
             . "  *, +, ?    - Quantifiers (0+, 1+, 0-1)`n"
             . "  ^ / $      - Start / End of a line`n"
             . "  (?s)       - Prefix regex to match across lines (DotAll)`n"
             . "  \b, [a-z]  - Word boundary, Character class`n`n"
             . "Multi-line Escapes (Always supported):`n"
             . "  \n, \t, \r - Newline, Tab, Carriage return`n"
             . "  \\, \$     - Literal backslash, Literal dollar`n`n"
             . "Replacement Variables (Regex Mode):`n"
             . "  $0         - Replaces with the entire match`n"
             . "  $1, $2...  - Replaces with captured subpattern`n"
             . "  $$         - Replaces with literal '$'"
    }

    static OnPreviewToggle(ctrl) {
        if (this.OptPreview.Value) {
            ; Turn preview ON
            if (!this.IsPreviewing) {
                this.IsPreviewing := true
                ctrl.IsPreviewing := true
                
                ; 1. Save original text
                this.OriginalText := this.GetSearchText(ctrl)
                
                ; 2. Save original selection
                cr := Buffer(8, 0)
                SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd) ; EM_GETSEL
                this.OriginalSelStart := NumGet(cr, 0, "Int")
                this.OriginalSelEnd := NumGet(cr, 4, "Int")
                this.OriginalCaretPos := SendMessage(0x0464, 0, 0, ctrl.Hwnd)
                
                ; 3. Save original scroll position
                this.OriginalScrollPos := Buffer(8, 0)
                SendMessage(0x04DD, 0, this.OriginalScrollPos.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS
            }
            
            ; 4. Update the preview text in the editor
            this.UpdatePreview(ctrl)
        } else {
            ; Turn preview OFF
            if (this.IsPreviewing) {
                this.RestoreOriginal(ctrl)
            }
        }
    }

    static UpdatePreview(ctrl) {
        if !this.IsPreviewing
            return

        ; Freeze drawing to avoid flickering
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        
        ; Save current scroll position to restore later
        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS

        ; Temporarily make editable to set text cleanly
        SendMessage(0x00CF, 0, 0, ctrl.Hwnd) ; EM_SETREADONLY = false
        
        ; Perform replacements in memory
        replaceText := this.ReplaceEdit.Value
        previewText := this.OriginalText
        
        loop this.SearchMatches.Length {
            idx := this.SearchMatches.Length - A_Index + 1
            m := this.SearchMatches[idx]
            leftPart := SubStr(previewText, 1, m.start)
            rightPart := SubStr(previewText, m.end + 1)
            formattedReplace := this.GetReplacementText(replaceText, m.matchObj)
            previewText := leftPart . formattedReplace . rightPart
        }
        
        ; Update editor text
        ; Convert to CR+LF for RichEdit
        textStr := StrReplace(StrReplace(previewText, "`r`n", "`n"), "`n", "`r`n")
        SendMessage(0x000C, 0, StrPtr(textStr), ctrl.Hwnd) ; WM_SETTEXT
        
        ; Force highlight and syntax parsing on the previewed text
        CodeBox_Highlighter.Highlight(ctrl)
        
        ; Make it read-only again
        SendMessage(0x00CF, 1, 0, ctrl.Hwnd) ; EM_SETREADONLY = true
        
        ; Restore scroll position
        SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd) ; EM_SETSCROLLPOS

        ; Restore drawing
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)
    }

    static RestoreOriginal(ctrl) {
        if (!this.IsPreviewing)
            return

        ; Freeze drawing
        SendMessage(0x000B, 0, 0, ctrl.Hwnd)

        ; Make editable
        SendMessage(0x00CF, 0, 0, ctrl.Hwnd) ; EM_SETREADONLY = false

        ; Restore original text
        textStr := StrReplace(StrReplace(this.OriginalText, "`r`n", "`n"), "`n", "`r`n")
        SendMessage(0x000C, 0, StrPtr(textStr), ctrl.Hwnd)

        ; Run highlighter
        CodeBox_Highlighter.Highlight(ctrl)

        ; Restore original selection and scroll position
        CodeBox._SetSelDirectional(ctrl.Hwnd, this.OriginalSelStart, this.OriginalSelEnd, this.OriginalCaretPos)
        SendMessage(0x04DE, 0, this.OriginalScrollPos.Ptr, ctrl.Hwnd)

        ; Restore drawing
        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        ; Reset flags
        this.IsPreviewing := false
        ctrl.IsPreviewing := false
    }

    static GetReplacementText(replaceText, m := "") {
        result := ""
        len := StrLen(replaceText)
        isRegex := this.OptRegex.Value && m
        
        i := 1
        while (i <= len) {
            char := SubStr(replaceText, i, 1)
            if (char == "\") {
                if (i == len) {
                    result .= "\"
                    break
                }
                nextChar := SubStr(replaceText, i + 1, 1)
                if (nextChar == "n") {
                    result .= "`n"
                    i += 2
                } else if (nextChar == "t") {
                    result .= "`t"
                    i += 2
                } else if (nextChar == "r") {
                    result .= "`r"
                    i += 2
                } else if (nextChar == "\") {
                    result .= "\"
                    i += 2
                } else if (nextChar == "$") {
                    result .= "$"
                    i += 2
                } else {
                    result .= "\" . nextChar
                    i += 2
                }
            } else if (char == "$" && isRegex) {
                if (i == len) {
                    result .= "$"
                    break
                }
                nextChar := SubStr(replaceText, i + 1, 1)
                if (nextChar == "$") {
                    result .= "$"
                    i += 2
                } else if (nextChar >= "0" && nextChar <= "9") {
                    numStr := nextChar
                    digitsLen := 1
                    while (i + 1 + digitsLen <= len) {
                        nextDigit := SubStr(replaceText, i + 1 + digitsLen, 1)
                        if (nextDigit >= "0" && nextDigit <= "9") {
                            numStr .= nextDigit
                            digitsLen++
                        } else {
                            break
                        }
                    }
                    
                    groupNum := Integer(numStr)
                    if (groupNum == 0) {
                        result .= m[0]
                        i += 1 + digitsLen
                    } else if (groupNum <= m.Count) {
                        result .= m[groupNum]
                        i += 1 + digitsLen
                    } else {
                        foundGroup := false
                        loop digitsLen {
                            checkLen := digitsLen - A_Index
                            if (checkLen == 0)
                                break
                            prefixStr := SubStr(numStr, 1, checkLen)
                            prefixNum := Integer(prefixStr)
                            if (prefixNum <= m.Count) {
                                result .= m[prefixNum] . SubStr(numStr, checkLen + 1)
                                i += 1 + digitsLen
                                foundGroup := true
                                break
                            }
                        }
                        if (!foundGroup) {
                            result .= "$" . numStr
                            i += 1 + digitsLen
                        }
                    }
                } else {
                    result .= "$"
                    i += 1
                }
            } else {
                result .= char
                i += 1
            }
        }
        return result
    }
}

