class CodeBox_PluginManager {
    static IniPath := A_ScriptDir "\CodeBox_Plugins.ini"

    static OnInit() {
        for p in CodeBox.Plugins {
            if (p.name == "PluginManager")
                continue
            try {
                state := IniRead(this.IniPath, "Plugins", p.name, p.enabled ? "1" : "0")
                p.enabled := (state == "1")
            }
        }
    }

    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        toolsMenu.Add("Manage Plugins", (*) => CodeBox.Invoke("ShowPluginManager", ctrl))
    }
    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := false
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := true
    }

    static OnContextMenu(ctrl, x, y) {
        ; Return false to let CodeBox_ContextMenu handle the actual right-click menu,
        ; but wait! If we want to inject into the menu, we should intercept OnContextMenu,
        ; but AHK Menus are tricky to share between plugins.
        ; Alternatively, the user can just open the manager via the toolbar.
        ; We will implement ShowPluginManager instead.
        return 0
    }

    static ShowPluginManager(ctrl) {
        if this.HasProp("ManagerGui") && DllCall("IsWindow", "Ptr", this.ManagerGui.Hwnd) {
            this.ManagerGui.Show()
            return
        }
        
        guiObj := Gui("+ToolWindow +Owner" DllCall("GetAncestor", "Ptr", ctrl.Hwnd, "UInt", 2), "Plugin Manager")
        guiObj.BackColor := "252526"
        guiObj.SetFont("s10 cWhite", "Segoe UI")
        
        guiObj.Add("Text", "x10 y10 w280", "Toggle Plugins On/Off instantly:")
        
        lv := guiObj.Add("ListView", "x10 y35 w280 h300 -Hdr Checked Background333333 cWhite", ["Plugin"])
        lv.ModifyCol(1, 260)
        
        for p in CodeBox.Plugins {
            if (p.name == "PluginManager")
                continue ; Don't let user disable the plugin manager itself!
                
            idx := lv.Add(p.enabled ? "Check" : "", " " p.name)
        }
        
        lv.OnEvent("ItemCheck", ObjBindMethod(this, "OnItemCheck"))
        
        this.ManagerGui := guiObj
        guiObj.Show("w300 h350")
    }

    static OnItemCheck(lv, item, checked) {
        pluginName := Trim(lv.GetText(item, 1))
        
        if !checked {
            for p in CodeBox.Plugins {
                if (p.name == pluginName && p.class.HasProp("OnDisable")) {
                    for hwnd, ctrl in CodeBox._Instances
                        p.class.OnDisable(ctrl)
                }
            }
        }

        CodeBox.TogglePlugin(pluginName, checked)
        
        try IniWrite(checked ? "1" : "0", this.IniPath, "Plugins", pluginName)
        
        if checked {
            for p in CodeBox.Plugins {
                if (p.name == pluginName && p.class.HasProp("OnEnable")) {
                    for hwnd, ctrl in CodeBox._Instances
                        p.class.OnEnable(ctrl)
                }
            }
        }
        
        ; Deep reload state
        for hwnd, ctrl in CodeBox._Instances {
            cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, ctrl.Hwnd)
            startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
            
            CodeBox.Emit("OnThemeChange", ctrl)
            ctrl.Text := ctrl.Text ; Force re-render of plain text without old highlighting
            CodeBox._SetSel(ctrl.Hwnd, startSel, endSel)
            
            ctrl.ForceLineUpdate := true
            ctrl.ForceMiniUpdate := true
            CodeBox.Emit("OnScroll", ctrl)
            CodeBox.Emit("OnChange", ctrl)
        }
    }

    static OnDestroy(ctrl) {
        if this.HasProp("ManagerGui") && DllCall("IsWindow", "Ptr", this.ManagerGui.Hwnd) {
            this.ManagerGui.Destroy()
            this.DeleteProp("ManagerGui")
        }
    }
}
