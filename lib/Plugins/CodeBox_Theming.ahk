class CodeBox_Theming {
    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarText := guiObj.Add("Text", "x" x " y" (y+3) " w55 BackgroundTrans", "Theme:")
        x += 55
        
        themes := []
        idx := 1, i := 1
        for k, v in CodeBox.Themes {
            themes.Push(k)
            if (k == ctrl.CodeBoxTheme)
                idx := i
            i++
        }
        
        this.ToolbarDDL := guiObj.Add("DropDownList", "x" x " y" y " w90 Choose" idx " Background2D2D30 cWhite", themes)
        this.ToolbarDDL.OnEvent("Change", (*) => (ctrl.Theme := this.ToolbarDDL.Text))
        x += 100
    }

    static OnDisable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := false
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := true
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := true
        CodeBox.Emit("OnThemeChange", ctrl)
    }

    static OnThemeChange(ctrl) {
        themeName := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? ctrl.CodeBoxTheme : "Dark"
        ctrl.CodeBoxTheme := themeName
        theme := CodeBox.Themes[themeName]
        bg := theme["Background"]
        
        bgr := ((bg & 0xFF0000) >> 16) | (bg & 0x00FF00) | ((bg & 0x0000FF) << 16)
        SendMessage(0x0443, 0, bgr, ctrl.Hwnd)
        if ctrl.HasProp("LineNumCtrl")
            SendMessage(0x0443, 0, bgr, ctrl.LineNumCtrl.Hwnd)
        if ctrl.HasProp("MinimapCtrl")
            SendMessage(0x0443, 0, bgr, ctrl.MinimapCtrl.Hwnd)
            
        ctrl.ForceLineUpdate := true
        ctrl.ForceMiniUpdate := true
    }
}
