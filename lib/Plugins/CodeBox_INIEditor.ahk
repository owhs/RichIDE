class CodeBox_INIEditor {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        this.ToolsMenu := toolsMenu
        toolsMenu.Add("Visual INI Editor", (*) => this.ShowVisualEditor(ctrl))
        if (StrLower(ctrl.CodeBoxLang) != "ini")
            toolsMenu.Disable("Visual INI Editor")
    }

    static OnLanguageChange(ctrl) {
        if this.HasProp("ToolsMenu") {
            if (StrLower(ctrl.CodeBoxLang) == "ini")
                this.ToolsMenu.Enable("Visual INI Editor")
            else
                this.ToolsMenu.Disable("Visual INI Editor")
        }
    }

    static ShowVisualEditor(ctrl) {
        if (StrLower(ctrl.CodeBoxLang) != "ini") {
            MsgBox("The visual INI editor can only be used when the current syntax is set to INI.", "INI Editor", 48)
            return
        }

        text := CodeBox._GetText(ctrl)
        originalText := text
        
        ; Parse INI
        lines := StrSplit(text, "`n", "`r")
        sections := []
        currentSection := ""
        sectionKeys := Map()
        
        for i, line in lines {
            trimLine := Trim(line)
            if (trimLine == "" || SubStr(trimLine, 1, 1) == ";" || SubStr(trimLine, 1, 1) == "#")
                continue
                
            if RegExMatch(trimLine, "^\[(.*?)\]$", &m) {
                currentSection := m[1]
                sections.Push(currentSection)
                sectionKeys[currentSection] := []
            } else if RegExMatch(trimLine, "^(.*?)=(.*)$", &m) {
                if (currentSection == "") {
                    currentSection := "Global"
                    if !sectionKeys.Has("Global") {
                        sections.InsertAt(1, "Global")
                        sectionKeys["Global"] := []
                    }
                }
                key := Trim(m[1])
                val := Trim(m[2])
                sectionKeys[currentSection].Push({key: key, val: val, lineIdx: i})
            }
        }
        
        if (sections.Length == 0) {
            MsgBox("No valid INI sections or keys found to edit.", "INI Editor", 48)
            return
        }

        guiObj := Gui("+ToolWindow +Owner" ctrl.Gui.Hwnd, "Visual INI Editor")
        guiObj.BackColor := "1E1E1E"
        guiObj.SetFont("s9 cWhite", "Segoe UI")
        
        SendMessage(0x00CF, 1, 0, ctrl.Hwnd) ; EM_SETREADONLY = TRUE

        guiObj.OnEvent("Close", (*) => (SendMessage(0x00CF, 0, 0, ctrl.Hwnd), guiObj.Destroy()))
        
        controls := []
        
        HighlightLine(lineIdx, *) {
            lineStartChar := SendMessage(0x00BB, lineIdx - 1, 0, ctrl.Hwnd)
            lineLen := SendMessage(0x00C1, lineStartChar, 0, ctrl.Hwnd)
            CodeBox._SetSel(ctrl.Hwnd, lineStartChar, lineStartChar + lineLen)
            SendMessage(0x00B7, 0, 0, ctrl.Hwnd) ; EM_SCROLLCARET
        }
        
        LiveUpdate(c, *) {
            line := lines[c.lineIdx]
            newVal := ""
            if (c.type == "bool") {
                newVal := c.ctrl.Value ? (c.style == "num" ? "1" : "true") : (c.style == "num" ? "0" : "false")
            } else {
                newVal := c.ctrl.Text
            }
            newLineText := RegExReplace(line, "^(.*?=\s*).*$", "$1" newVal)
            lines[c.lineIdx] := newLineText
            
            lineStartChar := SendMessage(0x00BB, c.lineIdx - 1, 0, ctrl.Hwnd)
            lineLen := SendMessage(0x00C1, lineStartChar, 0, ctrl.Hwnd)
            
            SendMessage(0x00CF, 0, 0, ctrl.Hwnd) ; Disable ReadOnly
            CodeBox._SetSel(ctrl.Hwnd, lineStartChar, lineStartChar + lineLen)
            SendMessage(0x00C2, 1, StrPtr(newLineText), ctrl.Hwnd) ; EM_REPLACESEL
            CodeBox._SetSel(ctrl.Hwnd, lineStartChar, lineStartChar + StrLen(newLineText))
            SendMessage(0x00CF, 1, 0, ctrl.Hwnd) ; Re-enable ReadOnly
        }
        
        yPos := 10
        for sec in sections {
            guiObj.SetFont("s10 Bold c569CD6")
            guiObj.Add("Text", "x15 y" yPos " w300", "[" sec "]")
            yPos += 25
            guiObj.SetFont("s9 Norm cWhite")
            
            for item in sectionKeys[sec] {
                guiObj.Add("Text", "x30 y" (yPos + 4) " w120 c9CDCFE", item.key ":")
                
                val := item.val
                
                if (val == "true" || val == "false" || val == "1" || val == "0") {
                    chk := guiObj.Add("CheckBox", "x150 y" yPos " w150 Checked" (val == "true" || val == "1"), val)
                    style := (val == "1" || val == "0") ? "num" : "bool"
                    chk.OnEvent("Click", ((c, s, *) => c.Text := c.Value ? (s=="num" ? "1" : "true") : (s=="num" ? "0" : "false")).Bind(chk, style))
                    chk.OnEvent("Focus", HighlightLine.Bind(item.lineIdx))
                    cItem := {type: "bool", ctrl: chk, lineIdx: item.lineIdx, key: item.key, style: style}
                    controls.Push(cItem)
                    chk.OnEvent("Click", LiveUpdate.Bind(cItem))
                } else if RegExMatch(val, "i)^0x[0-9A-F]{6}$") || RegExMatch(val, "i)^#[0-9A-F]{6}$") {
                    edt := guiObj.Add("Edit", "x150 y" yPos " w100 Background333333 cWhite", val)
                    edt.OnEvent("Focus", HighlightLine.Bind(item.lineIdx))
                    btn := guiObj.Add("Button", "x255 y" yPos " w45", "Color")
                    cItem := {type: "color", ctrl: edt, lineIdx: item.lineIdx, key: item.key}
                    controls.Push(cItem)
                    edt.OnEvent("Change", LiveUpdate.Bind(cItem))
                    
                    PickColor(e, lineIndex, cObj, *) {
                        HighlightLine(lineIndex)
                        clr := 0
                        if RegExMatch(e.Text, "i)^#([0-9A-F]{6})$", &m) || RegExMatch(e.Text, "i)^0x([0-9A-F]{6})$", &m) {
                            clr := Integer("0x" m[1])
                            clr := ((clr & 0xFF0000) >> 16) | (clr & 0x00FF00) | ((clr & 0x0000FF) << 16)
                        }
                        
                        static custColors := Buffer(64, 0)
                        cc := Buffer(A_PtrSize == 8 ? 72 : 36, 0)
                        NumPut("UInt", cc.Size, cc, 0)
                        NumPut("Ptr", guiObj.Hwnd, cc, A_PtrSize)
                        NumPut("UInt", clr, cc, A_PtrSize == 8 ? 24 : 12)
                        NumPut("Ptr", custColors.Ptr, cc, A_PtrSize == 8 ? 32 : 16)
                        NumPut("UInt", 0x103, cc, A_PtrSize == 8 ? 40 : 20) ; CC_ANYCOLOR | CC_RGBINIT | CC_FULLOPEN
                        
                        if DllCall("comdlg32\ChooseColor", "Ptr", cc) {
                            res := NumGet(cc, A_PtrSize == 8 ? 24 : 12, "UInt")
                            res := ((res & 0xFF0000) >> 16) | (res & 0x00FF00) | ((res & 0x0000FF) << 16)
                            prefix := SubStr(e.Text, 1, 1) == "#" ? "#" : "0x"
                            e.Value := prefix Format("{:06X}", res)
                            LiveUpdate(cObj)
                        }
                    }
                    btn.OnEvent("Click", PickColor.Bind(edt, item.lineIdx, cItem))
                } else if IsNumber(val) {
                    edt := guiObj.Add("Edit", "x150 y" yPos " w150 Background333333 cWhite Number", val)
                    edt.OnEvent("Focus", HighlightLine.Bind(item.lineIdx))
                    guiObj.Add("UpDown", "Range-999999-999999", val)
                    cItem := {type: "number", ctrl: edt, lineIdx: item.lineIdx, key: item.key}
                    controls.Push(cItem)
                    edt.OnEvent("Change", LiveUpdate.Bind(cItem))
                } else {
                    edt := guiObj.Add("Edit", "x150 y" yPos " w150 Background333333 cWhite", val)
                    edt.OnEvent("Focus", HighlightLine.Bind(item.lineIdx))
                    cItem := {type: "string", ctrl: edt, lineIdx: item.lineIdx, key: item.key}
                    controls.Push(cItem)
                    edt.OnEvent("Change", LiveUpdate.Bind(cItem))
                }
                
                yPos += 30
            }
            yPos += 10
        }
        
        btnCancel := guiObj.Add("Button", "x45 y" yPos " w100 h30", "Cancel")
        btnApply := guiObj.Add("Button", "x155 y" yPos " w100 h30 Default", "Apply")
        
        btnCancel.OnEvent("Click", (*) => this.CancelChanges(ctrl, originalText, guiObj))
        btnApply.OnEvent("Click", (*) => this.ApplyChanges(ctrl, guiObj))
        
        guiObj.Show("AutoSize")
    }

    static CancelChanges(ctrl, originalText, guiObj) {
        SendMessage(0x00CF, 0, 0, ctrl.Hwnd) ; Disable ReadOnly
        CodeBox._SetText(ctrl, originalText, true) ; Restore old text
        guiObj.Destroy()
    }

    static ApplyChanges(ctrl, guiObj) {
        SendMessage(0x00CF, 0, 0, ctrl.Hwnd) ; Disable ReadOnly
        CodeBox.Emit("PushHistory", ctrl, "Visual INI Edit")
        guiObj.Destroy()
    }
}
