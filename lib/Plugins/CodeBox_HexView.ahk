class CodeBox_HexView {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        viewMenu.Add("Toggle Hex View", (*) => CodeBox.Invoke("ToggleHexView", ctrl, !ctrl._HexView))
    }
    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := true
    }

    static ToggleHexView(ctrl, v) {
        ctrl._HexView := v
        ctrl.IsHighlighting := true
        if v {
            ctrl.OriginalText := CodeBox._GetText(ctrl)
            ctrl.OriginalLang := ctrl.CodeBoxLang
            ctrl.CodeBoxLang := "hex"
            CodeBox._SetText(ctrl, ctrl.OriginalText, false)
            SendMessage(0x00CC, 1, 0, ctrl.Hwnd)
        } else {
            SendMessage(0x00CC, 0, 0, ctrl.Hwnd)
            ctrl.CodeBoxLang := ctrl.OriginalLang
            CodeBox._SetText(ctrl, ctrl.OriginalText, false)
        }
        ctrl.IsHighlighting := false
        CodeBox.Emit("OnChange", ctrl)
    }

    static ToHex(str) {
        buf := Buffer(StrPut(str, "UTF-8") - 1)
        StrPut(str, buf, "UTF-8")
        out := ""
        loop buf.Size {
            offset := A_Index - 1
            if (Mod(offset, 16) == 0)
                out .= Format("{:08X}  ", offset)
            out .= Format("{:02X} ", NumGet(buf, offset, "UChar"))

            if (Mod(offset, 16) == 15 || A_Index == buf.Size) {
                pad := 15 - Mod(offset, 16)
                loop pad
                    out .= "   "
                out .= " | "
                loop (16 - pad) {
                    b := NumGet(buf, offset - (15 - pad) + A_Index - 1, "UChar")
                    out .= (b >= 32 && b <= 126) ? Chr(b) : "."
                }
                out .= "`n"
            }
        }
        return out
    }
}
