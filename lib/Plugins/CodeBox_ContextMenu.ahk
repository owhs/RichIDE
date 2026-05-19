class CodeBox_ContextMenu {
    static OnContextMenu(ctrl, x, y) {
        m := Menu()
        m.Add("Copy", (*) => Send("^c"))
        m.Add("Paste", (*) => Send("^v"))
        m.Add()
        m.Add("Select All", (*) => CodeBox._SetSel(ctrl.Hwnd, 0, -1))
        m.Add()
        m.Add("Format Document", (*) => CodeBox.Invoke("Format", ctrl))
        m.Add("Undo", (*) => CodeBox.Invoke("Undo", ctrl))
        m.Add("Redo", (*) => CodeBox.Invoke("Redo", ctrl))
        m.Add()
        m.Add("Manage Plugins...", (*) => CodeBox.Invoke("ShowPluginManager", ctrl))
        
        ; Convert screen coordinates to window coords or show at cursor if -1
        if (x == -1 && y == -1)
            m.Show()
        else
            m.Show(x, y)
        return 1
    }
}
