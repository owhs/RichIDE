class CodeBox_ContextMenu {
    static Items := []
    static Sections := ["errors", "navigation", "undo_redo", "clipboard", "selection", "formatting", "plugins"]

    static OnInit() {
        ; Pre-register default items
        
        ; Errors section
        this.RegisterItem("errors", "Fix: {ErrorText}", (ctx) => MsgBox("Error details:`n`n" ctx.errorText, "CodeBox Error", 0x30), (ctx) => ctx.hasError, "shell32.dll", 78, 10)
        
        ; Navigation section
        this.RegisterItem("navigation", "Jump to Matching Bracket", (ctx) => this.JumpToBracket(ctx), (ctx) => ctx.isBracket, "shell32.dll", 226, 10)
        this.RegisterItem("navigation", "Go to Definition", (ctx) => this.GoToDefinition(ctx), (ctx) => (ctx.word != ""), "shell32.dll", 269, 20)
        this.RegisterItem("navigation", "Find All References", (ctx) => this.FindAllReferences(ctx), (ctx) => (ctx.word != ""), "shell32.dll", 23, 30)
        
        ; Undo/Redo section
        this.RegisterItem("undo_redo", "Undo`tCtrl+Z", (ctx) => CodeBox.Invoke("Undo", ctx.ctrl), (*) => true, "shell32.dll", 256, 10)
        this.RegisterItem("undo_redo", "Redo`tCtrl+Y", (ctx) => CodeBox.Invoke("Redo", ctx.ctrl), (*) => true, "shell32.dll", 257, 20)
        
        ; Clipboard section
        this.RegisterItem("clipboard", "Cut`tCtrl+X", (ctx) => Send("^x"), (*) => true, "shell32.dll", 260, 10)
        this.RegisterItem("clipboard", "Copy`tCtrl+C", (ctx) => Send("^c"), (*) => true, "shell32.dll", 135, 20)
        this.RegisterItem("clipboard", "Paste`tCtrl+V", (ctx) => Send("^v"), (*) => true, "shell32.dll", 261, 30)
        
        ; Selection section
        this.RegisterItem("selection", "Select All`tCtrl+A", (ctx) => CodeBox._SetSel(ctx.ctrl.Hwnd, 0, -1), (*) => true, "shell32.dll", 259, 10)
        
        ; Formatting section
        this.RegisterItem("formatting", "Format Document`tShift+Alt+F", (ctx) => CodeBox.Invoke("Format", ctx.ctrl), (*) => true, "shell32.dll", 136, 10)
        
        ; Plugins section
        this.RegisterItem("plugins", "Manage Plugins...", (ctx) => CodeBox.Invoke("ShowPluginManager", ctx.ctrl), (*) => true, "shell32.dll", 22, 10)
        
        ; Register static window message handlers for premium themed menus
        OnMessage(0x0006, ObjBindMethod(this, "OnMessage_WM_ACTIVATE"))
        OnMessage(0x0200, ObjBindMethod(this, "OnMessage_WM_MOUSEMOVE"))
        OnMessage(0x0202, ObjBindMethod(this, "OnMessage_WM_LBUTTONUP"))
        this._CheckMousePosFn := ObjBindMethod(this, "CheckMousePos")
    }

    static RegisterItem(section, label, callback, condition := "", iconFile := "", iconIndex := 0, order := 100) {
        item := {
            section: section,
            label: label,
            callback: callback,
            condition: condition,
            iconFile: iconFile,
            iconIndex: iconIndex,
            order: order
        }
        this.Items.Push(item)
    }

    static JumpToBracket(ctx) {
        for p in CodeBox.Plugins {
            if (p.name == "BracketMatcher" && p.enabled) {
                try p.class.JumpToMatchingBracket(ctx.ctrl)
                return
            }
        }
    }

    static GoToDefinition(ctx) {
        text := ctx.ctrl.Text
        word := ctx.word
        pos := InStr(text, "class " word)
        if (!pos)
            pos := InStr(text, word " := class")
        if (!pos)
            pos := InStr(text, word "(")
        if (pos) {
            CodeBox._SetSel(ctx.ctrl.Hwnd, pos - 1, pos - 1)
            SendMessage(0x00B7, 0, 0, ctx.ctrl.Hwnd) ; EM_SCROLLCARET
        } else {
            MsgBox("Definition for '" word "' not found in this file.", "Go to Definition", 0x40)
        }
    }

    static FindAllReferences(ctx) {
        word := ctx.word
        occurrences := 0
        pos := 1
        text := ctx.ctrl.Text
        while (pos := InStr(text, word, false, pos)) {
            occurrences++
            pos += StrLen(word)
        }
        MsgBox("Found " occurrences " references to '" word "' in this file.", "Find References", 0x40)
    }

    static ActiveMenuGui := ""
    static MenuItems := []
    static HighlightedIndex := 0
    static ActiveCtrl := ""
    static ActiveCtx := ""
    static MenuHeight := 0
    static SavedSelStart := ""
    static SavedSelEnd := ""
    static SavedCaretPos := ""
    static _CheckMousePosFn := ""

    static OnContextMenu(ctrl, x, y) {
        hwnd := ctrl.Hwnd
        
        ; Get character under cursor
        charIndex := -1
        if (x == -1 && y == -1) {
            ; Triggered by keyboard, use current selection
            charIndex := SendMessage(0x0464, 0, 0, hwnd) ; EM_GETCARETINDEX
            ; Get cursor screen position to show menu there
            pt := Buffer(8, 0)
            DllCall("GetCursorPos", "Ptr", pt.Ptr)
            x := NumGet(pt, 0, "Int")
            y := NumGet(pt, 4, "Int")
        } else {
            ; Convert screen to client coordinates
            pt := Buffer(8, 0)
            NumPut("Int", x, pt, 0)
            NumPut("Int", y, pt, 4)
            DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt.Ptr)
            ; For RichEdit, EM_CHARFROMPOS takes a pointer to a POINT structure in lParam.
            ; Since ScreenToClient converts in-place, pt already contains the client coordinates.
            charIndex := SendMessage(0x00D7, 0, pt.Ptr, hwnd) ; EM_CHARFROMPOS
        }

        ; Extract word/character under cursor
        text := ctrl.Text
        len := StrLen(text)
        word := ""
        char := ""
        
        if (charIndex >= 0 && charIndex < len) {
            char := SubStr(text, charIndex + 1, 1)
            
            ; Get word around charIndex
            start := charIndex
            while (start >= 0) {
                c := SubStr(text, start + 1, 1)
                if !(c ~= "[a-zA-Z0-9_]")
                    break
                start--
            }
            start++
            
            end := charIndex
            while (end < len) {
                c := SubStr(text, end + 1, 1)
                if !(c ~= "[a-zA-Z0-9_]")
                    break
                end++
            }
            word := SubStr(text, start + 1, end - start)
        }

        logicalLine := SendMessage(0x00C7, charIndex, 0, hwnd) + 1 ; EM_LINEFROMCHAR is 0-based
        
        ; Construct context
        ctx := {
            ctrl: ctrl,
            charIndex: charIndex,
            word: word,
            char: char,
            lineNum: logicalLine,
            hasError: ctrl.HasProp("ErrorLines") && ctrl.ErrorLines.Has(logicalLine),
            errorText: (ctrl.HasProp("ErrorLines") && ctrl.ErrorLines.Has(logicalLine)) ? ctrl.ErrorLines[logicalLine] : "",
            isBracket: (char != "" && InStr("(){}[]", char) > 0),
            isWhitespace: (char == " " || char == "`t" || char == "`r" || char == "`n" || char == "")
        }

        ; Query RichEdit Undo/Redo/Selection/Clipboard status
        canUndo := SendMessage(0x00C6, 0, 0, hwnd) ; EM_CANUNDO
        canRedo := SendMessage(0x0455, 0, 0, hwnd) ; EM_CANREDO
        
        cr := Buffer(8, 0)
        SendMessage(0x0434, 0, cr.Ptr, hwnd) ; EM_EXGETSEL
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        hasSelection := (startSel != endSel)
        
        this.SavedSelStart := startSel
        this.SavedSelEnd := endSel
        this.SavedCaretPos := SendMessage(0x0464, 0, 0, hwnd)
        
        hasClipboard := (A_Clipboard != "")

        ; Create standard fallback menu
        m := Menu()
        
        ; Sort registered items by section and then order
        groupedItems := Map()
        for s in this.Sections {
            groupedItems[s] := []
        }
        
        for item in this.Items {
            sec := item.section
            if !groupedItems.Has(sec)
                groupedItems[sec] := []
            
            ; Evaluate condition
            showItem := true
            if (item.condition is Func) {
                try {
                    showItem := item.condition(ctx)
                } catch {
                    showItem := false
                }
            }
            
            if (showItem) {
                groupedItems[sec].Push(item)
            }
        }
        
        ; Sort items in each group by order
        for sec, list in groupedItems {
            ; Simple insertion sort by order
            loop list.Length {
                i := A_Index
                j := i
                while (j > 1 && list[j].order < list[j - 1].order) {
                    temp := list[j]
                    list[j] := list[j - 1]
                    list[j - 1] := temp
                    j--
                }
            }
        }

        ; Build the fallback menu items
        menuEmpty := true
        firstSection := true
        
        for sec in this.Sections {
            list := groupedItems[sec]
            if (list.Length == 0)
                continue
                
            if (!firstSection) {
                m.Add() ; Add separator between sections
            }
            firstSection := false
            
            for item in list {
                ; Format dynamic labels (e.g. for errors)
                displayLabel := item.label
                if (InStr(displayLabel, "{ErrorText}") && ctx.hasError) {
                    errTxt := ctx.errorText
                    if (StrLen(errTxt) > 40)
                        errTxt := SubStr(errTxt, 1, 37) "..."
                    displayLabel := StrReplace(displayLabel, "{ErrorText}", errTxt)
                }
                
                ; Create dispatch callback
                dispatch := this._CreateMenuDispatch(ctrl, displayLabel, item.callback, ctx)
                
                m.Add(displayLabel, dispatch)
                menuEmpty := false
                
                ; Disable options based on state
                if (sec == "undo_redo") {
                    if (InStr(item.label, "Undo") && !canUndo)
                        m.Disable(displayLabel)
                    if (InStr(item.label, "Redo") && !canRedo)
                        m.Disable(displayLabel)
                } else if (sec == "clipboard") {
                    if (InStr(item.label, "Cut") && !hasSelection)
                        m.Disable(displayLabel)
                    if (InStr(item.label, "Copy") && !hasSelection)
                        m.Disable(displayLabel)
                    if (InStr(item.label, "Paste") && !hasClipboard)
                        m.Disable(displayLabel)
                }
                
                ; Apply icon
                if (item.iconFile != "") {
                    try {
                        m.SetIcon(displayLabel, item.iconFile, item.iconIndex, 16)
                    }
                }
            }
        }
        
        if (menuEmpty)
            return 0

        ; Check if themes are enabled in the editor and if the theme exists
        themesEnabled := ctrl.HasProp("CodeBoxTheme") && CodeBox.HasProp("Themes") && CodeBox.Themes.Has(ctrl.CodeBoxTheme)
        
        if (themesEnabled) {
            ; Show premium themed dynamic menu
            this.ShowPremiumMenu(ctrl, x, y, groupedItems, ctx, canUndo, canRedo, hasSelection, hasClipboard)
        } else {
            ; Fire Open Event
            CodeBox.Emit("ContextMenuOpen", ctrl)
            
            ; Show native Win32 menu (fallback)
            try {
                CoordMode("Menu", "Screen")
                m.Show(x, y)
            }
            
            ; Fire Close Event (synchronous after menu returns)
            CodeBox.Emit("ContextMenuClose", ctrl)
        }
        
        return 1
    }

    static _CreateMenuDispatch(ctrl, labelStr, itemCallback, ctx) {
        dispatch(*) {
            CodeBox.Emit("ContextMenuClick", ctrl, labelStr)
            try itemCallback(ctx)
        }
        return dispatch
    }

    static ShowPremiumMenu(ctrl, x, y, groupedItems, ctx, canUndo, canRedo, hasSelection, hasClipboard) {
        ; Clear any existing open menu first
        this.CloseMenu()
        
        themeName := ctrl.HasProp("CodeBoxTheme") ? ctrl.CodeBoxTheme : "Dark"
        theme := CodeBox.Themes.Has(themeName) ? CodeBox.Themes[themeName] : CodeBox.Themes["Dark"]
        
        bgColor := this.GetHexColor(theme["Background"])
        fgColor := this.GetHexColor(theme["Foreground"])
        selectBg := this.GetHexColor(theme["SelectionBg"])
        selectFg := this.GetHexColor(theme["SelectionFg"])
        
        if (themeName == "Light") {
            dimmedFgColor := "888888"
            separatorColor := "E5E5E5"
            disabledFgColor := "CCCCCC"
        } else {
            dimmedFgColor := "888888"
            separatorColor := "333333"
            disabledFgColor := "555555"
        }
        
        menuItems := []
        currentY := 6 ; Padding top
        
        firstSection := true
        for sec in this.Sections {
            list := groupedItems[sec]
            if (list.Length == 0)
                continue
                
            if (!firstSection) {
                menuItems.Push({
                    type: "separator",
                    y: currentY,
                    height: 9
                })
                currentY += 9
            }
            firstSection := false
            
            for item in list {
                parts := StrSplit(item.label, "`t")
                cleanLabel := parts[1]
                shortcut := parts.Length > 1 ? parts[2] : ""
                
                displayLabel := cleanLabel
                if (InStr(displayLabel, "{ErrorText}") && ctx.hasError) {
                    errTxt := ctx.errorText
                    if (StrLen(errTxt) > 40)
                        errTxt := SubStr(errTxt, 1, 37) "..."
                    displayLabel := StrReplace(displayLabel, "{ErrorText}", errTxt)
                }
                
                isEnabled := true
                if (sec == "undo_redo") {
                    if (InStr(item.label, "Undo") && !canUndo)
                        isEnabled := false
                    if (InStr(item.label, "Redo") && !canRedo)
                        isEnabled := false
                } else if (sec == "clipboard") {
                    if (InStr(item.label, "Cut") && !hasSelection)
                        isEnabled := false
                    if (InStr(item.label, "Copy") && !hasSelection)
                        isEnabled := false
                    if (InStr(item.label, "Paste") && !hasClipboard)
                        isEnabled := false
                }
                
                menuItems.Push({
                    type: "item",
                    label: displayLabel,
                    cleanLabel: displayLabel,
                    shortcut: shortcut,
                    callback: item.callback,
                    iconFile: item.iconFile,
                    iconIndex: item.iconIndex,
                    enabled: isEnabled,
                    y: currentY,
                    height: 28
                })
                currentY += 28
            }
        }
        
        totalHeight := currentY + 6
        this.MenuHeight := totalHeight
        this.MenuItems := menuItems
        this.ActiveCtrl := ctrl
        this.ActiveCtx := ctx
        
        mGui := Gui("-Caption +ToolWindow +AlwaysOnTop +Border")
        mGui.BackColor := bgColor
        mGui.SetFont("s9 c" fgColor, "Segoe UI")
        this.ActiveMenuGui := mGui
        
        for idx, item in menuItems {
            if (item.type == "separator") {
                mGui.Add("Text", "x10 y" (item.y + 4) " w220 h1 Background" separatorColor)
            } else {
                item.bgCtrl := mGui.Add("Text", "x4 y" item.y " w232 h28 +BackgroundTrans")
                
                if (item.iconFile != "") {
                    try {
                        iconOpt := "x12 y" (item.y + 6) " w16 h16 +BackgroundTrans"
                        if (item.iconIndex != "")
                            iconOpt .= " *Icon" item.iconIndex
                        item.iconCtrl := mGui.Add("Picture", iconOpt, item.iconFile)
                    }
                }
                
                itemTextCol := item.enabled ? fgColor : disabledFgColor
                item.labelCtrl := mGui.Add("Text", "x38 y" (item.y + 5) " w130 h18 +BackgroundTrans c" itemTextCol, item.cleanLabel)
                
                if (item.shortcut != "") {
                    shortcutCol := item.enabled ? dimmedFgColor : disabledFgColor
                    item.shortcutCtrl := mGui.Add("Text", "x168 y" (item.y + 5) " w60 h18 +Right +BackgroundTrans c" shortcutCol, item.shortcut)
                }
                
            }
        }
        
        hwnd := mGui.Hwnd
        currentStyle := DllCall("user32\GetClassLong" (A_PtrSize == 8 ? "Ptr" : "") "W", "Ptr", hwnd, "Int", -26, "Ptr")
        DllCall("user32\SetClassLong" (A_PtrSize == 8 ? "Ptr" : "") "W", "Ptr", hwnd, "Int", -26, "Ptr", currentStyle | 0x00020000, "Ptr")
        
        MonitorGetWorkArea(, &left, &top, &right, &bottom)
        if (x + 240 > right)
            x := right - 240
        if (y + totalHeight > bottom)
            y := bottom - totalHeight
        if (x < left)
            x := left
        if (y < top)
            y := top
            
        CodeBox.Emit("ContextMenuOpen", ctrl)
        mGui.Show("x" x " y" y " w240 h" totalHeight)
        
        if (this._CheckMousePosFn != "") {
            SetTimer(this._CheckMousePosFn, 50)
        }
        
        return 1
    }



    static TriggerItem(index) {
        item := this.MenuItems[index]
        ctrl := this.ActiveCtrl
        ctx := this.ActiveCtx
        callback := item.callback
        label := item.label
        
        this.CloseMenu()
        
        CodeBox.Emit("ContextMenuClick", ctrl, label)
        try callback(ctx)
    }

    static CloseMenu() {
        if (this.ActiveMenuGui) {
            ctrl := this.ActiveCtrl
            savedSelStart := this.SavedSelStart
            savedSelEnd := this.SavedSelEnd
            savedCaretPos := this.SavedCaretPos
            
            if (this._CheckMousePosFn != "") {
                SetTimer(this._CheckMousePosFn, 0)
            }
            
            try this.ActiveMenuGui.Destroy()
            this.ActiveMenuGui := ""
            this.MenuItems := []
            this.HighlightedIndex := 0
            
            if (ctrl && HasProp(ctrl, "Hwnd") && WinExist("ahk_id " ctrl.Hwnd)) {
                DllCall("user32\SetFocus", "Ptr", ctrl.Hwnd)
                if (savedSelStart !== "") {
                    CodeBox._SetSelDirectional(ctrl.Hwnd, savedSelStart, savedSelEnd, savedCaretPos)
                }
            }
            
            CodeBox.Emit("ContextMenuClose", ctrl)
        }
    }

    static GetHexColor(val) {
        return Format("{:06X}", val)
    }

    static HighlightItem(index) {
        if (index == this.HighlightedIndex)
            return
            
        themeName := this.ActiveCtrl.HasProp("CodeBoxTheme") ? this.ActiveCtrl.CodeBoxTheme : "Dark"
        theme := CodeBox.Themes.Has(themeName) ? CodeBox.Themes[themeName] : CodeBox.Themes["Dark"]
        
        bgColor := this.GetHexColor(theme["Background"])
        fgColor := this.GetHexColor(theme["Foreground"])
        selectBg := this.GetHexColor(theme["SelectionBg"])
        selectFg := this.GetHexColor(theme["SelectionFg"])
        
        if (themeName == "Light") {
            dimmedFgColor := "888888"
            disabledFgColor := "CCCCCC"
        } else {
            dimmedFgColor := "888888"
            disabledFgColor := "555555"
        }
        
        if (this.HighlightedIndex > 0 && this.HighlightedIndex <= this.MenuItems.Length) {
            oldItem := this.MenuItems[this.HighlightedIndex]
            if (oldItem.type == "item") {
                try {
                    oldItem.bgCtrl.Opt("Background" bgColor)
                    oldItemTextCol := oldItem.enabled ? fgColor : disabledFgColor
                    oldItem.labelCtrl.SetFont("c" oldItemTextCol)
                    if oldItem.HasProp("shortcutCtrl") {
                        oldShortcutCol := oldItem.enabled ? dimmedFgColor : disabledFgColor
                        oldItem.shortcutCtrl.SetFont("c" oldShortcutCol)
                    }
                    this.Redraw(oldItem.bgCtrl)
                    this.Redraw(oldItem.labelCtrl)
                    if oldItem.HasProp("shortcutCtrl")
                        this.Redraw(oldItem.shortcutCtrl)
                }
            }
        }
        
        this.HighlightedIndex := index
        
        if (index > 0 && index <= this.MenuItems.Length) {
            newItem := this.MenuItems[index]
            if (newItem.type == "item" && newItem.enabled) {
                try {
                    newItem.bgCtrl.Opt("Background" selectBg)
                    newItem.labelCtrl.SetFont("c" selectFg)
                    if newItem.HasProp("shortcutCtrl")
                        newItem.shortcutCtrl.SetFont("c" selectFg)
                    this.Redraw(newItem.bgCtrl)
                    this.Redraw(newItem.labelCtrl)
                    if newItem.HasProp("shortcutCtrl")
                        this.Redraw(newItem.shortcutCtrl)
                }
            }
        }
    }

    static Redraw(ctrl) {
        DllCall("RedrawWindow", "Ptr", ctrl.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0105)
    }

    static HighlightItemAtY(mouseY) {
        hoveredIdx := 0
        if (mouseY >= 0 && mouseY <= this.MenuHeight) {
            for idx, item in this.MenuItems {
                if (item.type == "separator" || !item.enabled)
                    continue
                if (mouseY >= item.y && mouseY < item.y + 28) {
                    hoveredIdx := idx
                    break
                }
            }
        }
        this.HighlightItem(hoveredIdx)
    }

    static NavigateMenu(direction) {
        len := this.MenuItems.Length
        if (len == 0)
            return
            
        start := this.HighlightedIndex > 0 ? this.HighlightedIndex : (direction > 0 ? 0 : len + 1)
        curr := start
        
        loop len {
            curr += direction
            if (curr > len)
                curr := 1
            if (curr < 1)
                curr := len
                
            item := this.MenuItems[curr]
            if (item.type == "item" && item.enabled) {
                this.HighlightItem(curr)
                return
            }
        }
    }
    
    static TriggerActiveItem() {
        if (this.HighlightedIndex > 0) {
            this.TriggerItem(this.HighlightedIndex)
        }
    }

    static OnMessage_WM_ACTIVATE(wParam, lParam, msg, hwnd) {
        if (this.ActiveMenuGui && hwnd == this.ActiveMenuGui.Hwnd && wParam == 0) {
            SetTimer(() => this.CloseMenu(), -10)
        }
    }

    static OnMessage_WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
        if (this.ActiveMenuGui && (hwnd == this.ActiveMenuGui.Hwnd || DllCall("user32\GetParent", "Ptr", hwnd) == this.ActiveMenuGui.Hwnd)) {
            ; Get coordinates relative to the menu GUI
            pt := Buffer(8, 0)
            DllCall("user32\GetCursorPos", "Ptr", pt.Ptr)
            DllCall("user32\ScreenToClient", "Ptr", this.ActiveMenuGui.Hwnd, "Ptr", pt.Ptr)
            mouseY := NumGet(pt, 4, "Int")
            
            this.HighlightItemAtY(mouseY)
        }
    }
 
    static OnMessage_WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
        if (this.ActiveMenuGui && (hwnd == this.ActiveMenuGui.Hwnd || DllCall("user32\GetParent", "Ptr", hwnd) == this.ActiveMenuGui.Hwnd)) {
            if (this.HighlightedIndex > 0 && this.HighlightedIndex <= this.MenuItems.Length) {
                this.TriggerItem(this.HighlightedIndex)
            }
        }
    }
 
    static CheckMousePos() {
        if (!this.ActiveMenuGui) {
            if (this._CheckMousePosFn != "") {
                SetTimer(this._CheckMousePosFn, 0)
            }
            return
        }
        
        ; Get mouse coordinates relative to the menu GUI
        pt := Buffer(8, 0)
        DllCall("user32\GetCursorPos", "Ptr", pt.Ptr)
        DllCall("user32\ScreenToClient", "Ptr", this.ActiveMenuGui.Hwnd, "Ptr", pt.Ptr)
        mouseX := NumGet(pt, 0, "Int")
        mouseY := NumGet(pt, 4, "Int")
        
        ; Get GUI size
        rect := Buffer(16, 0)
        DllCall("user32\GetClientRect", "Ptr", this.ActiveMenuGui.Hwnd, "Ptr", rect.Ptr)
        w := NumGet(rect, 8, "Int")
        h := NumGet(rect, 12, "Int")
        
        if (mouseX < 0 || mouseY < 0 || mouseX > w || mouseY > h) {
            this.HighlightItem(0)
        }
    }
}

#HotIf CodeBox_ContextMenu.ActiveMenuGui && WinActive("ahk_id " CodeBox_ContextMenu.ActiveMenuGui.Hwnd)
Up::CodeBox_ContextMenu.NavigateMenu(-1)
Down::CodeBox_ContextMenu.NavigateMenu(1)
Enter::CodeBox_ContextMenu.TriggerActiveItem()
Escape::CodeBox_ContextMenu.CloseMenu()
#HotIf
