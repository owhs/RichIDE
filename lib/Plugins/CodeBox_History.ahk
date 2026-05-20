class CodeBox_History {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        viewMenu.Add("Show History", (*) => CodeBox._Fire(ctrl, "ShowHistoryClicked"))
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
        if (ctrl.HasProp("IsPreviewing") && ctrl.IsPreviewing)
            return 0

        if (wParam == 90 && GetKeyState("Ctrl", "P")) {
            this.Undo(ctrl)
            return 1
        }
        if (wParam == 89 && GetKeyState("Ctrl", "P")) {
            this.Redo(ctrl)
            return 1
        }
        return 0
    }

    static PushHistory(ctrl, action := "Edit", text := "", selStart := -1, selEnd := -1) {
        if (ctrl.HasProp("IsPreviewing") && ctrl.IsPreviewing)
            return

        if !ctrl.HasProp("History") {
            ctrl.History := []
            ctrl.HistoryIndex := 0
        }

        if (text == "")
            text := CodeBox._GetText(ctrl)

        if (selStart == -1) {
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            selStart := NumGet(cr, 0, "Int"), selEnd := NumGet(cr, 4, "Int")
        }

        if (ctrl.HistoryIndex > 0 && ctrl.HistoryIndex <= ctrl.History.Length) {
            if (ctrl.History[ctrl.HistoryIndex].text == text)
                return
        }

        if (ctrl.HistoryIndex < ctrl.History.Length) {
            ctrl.History.RemoveAt(ctrl.HistoryIndex + 1, ctrl.History.Length - ctrl.HistoryIndex)
        }

        foldState := []
        if IsSet(CodeBox_Folding) {
            try foldState := CodeBox_Folding.GetFoldState(ctrl)
        }

        ctrl.History.Push({ text: text, selStart: selStart, selEnd: selEnd, action: action, foldState: foldState })
        ctrl.HistoryIndex := ctrl.History.Length
        CodeBox._Fire(ctrl, "HistoryChange", ctrl.History, ctrl.HistoryIndex)
    }

    static Undo(ctrl) {
        if CodeBox._DebounceTimers.Has(ctrl.Hwnd) {
            SetTimer(CodeBox._DebounceTimers[ctrl.Hwnd], 0)
            CodeBox.Emit("OnChange", ctrl)
        }

        if (ctrl.HistoryIndex > 1) {
            ctrl.HistoryIndex--
            state := ctrl.History[ctrl.HistoryIndex]
            ctrl.LastHistoryText := state.text
            this.RestoreState(ctrl, state)
        }
    }

    static Redo(ctrl) {
        if (ctrl.HistoryIndex < ctrl.History.Length) {
            ctrl.HistoryIndex++
            state := ctrl.History[ctrl.HistoryIndex]
            ctrl.LastHistoryText := state.text
            this.RestoreState(ctrl, state)
        }
    }

    static RestoreState(ctrl, state) {
        ctrl.IsHighlighting := true
        textStr := StrReplace(StrReplace(state.text, "`r`n", "`n"), "`n", "`r`n")

        SendMessage(0x000B, 0, 0, ctrl.Hwnd)
        SendMessage(0x000C, 0, StrPtr(textStr), ctrl.Hwnd)
        CodeBox._SetSel(ctrl.Hwnd, state.selStart, state.selEnd)

        if IsSet(CodeBox_Folding) && state.HasOwnProp("foldState") {
            try CodeBox_Folding.RestoreFoldState(ctrl, state.foldState)
        }

        SendMessage(0x000B, 1, 0, ctrl.Hwnd)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 0)

        ctrl.IsHighlighting := false
        CodeBox.Emit("OnChange", ctrl)
        CodeBox._Fire(ctrl, "HistoryChange", ctrl.History, ctrl.HistoryIndex)
    }
}
