#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "%A_ScriptDir%\lib\CodeBox.ahk"
#Include "%A_ScriptDir%\lib\CodeBox_Data.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Highlighter.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Theming.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Selection.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Scrollbars.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_MarkdownView.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_LineNumbers.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Folding.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_History.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Suggest.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Beautify.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_HexView.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_ExportHTML.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_SmartTyping.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_ClipboardManager.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_PluginManager.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_FindReplace.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_BracketMatcher.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_ContextMenu.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_INIEditor.ahk"

; Register Plugins!
CodeBox.DebugLogPath := A_ScriptDir "\codebox_debug.log" ; Toggleable debug log
CodeBox.RegisterPlugin("Highlighter", CodeBox_Highlighter)
CodeBox.RegisterPlugin("Theming", CodeBox_Theming)
CodeBox.RegisterPlugin("Selection", CodeBox_Selection)
CodeBox.RegisterPlugin("Scrollbars", CodeBox_Scrollbars)
CodeBox.RegisterPlugin("MarkdownView", CodeBox_MarkdownView)
CodeBox.RegisterPlugin("LineNumbers", CodeBox_LineNumbers)
CodeBox.RegisterPlugin("Folding", CodeBox_Folding)
CodeBox.RegisterPlugin("History", CodeBox_History)
CodeBox.RegisterPlugin("Suggest", CodeBox_Suggest)
CodeBox.RegisterPlugin("Beautify", CodeBox_Beautify)
CodeBox.RegisterPlugin("HexView", CodeBox_HexView)
CodeBox.RegisterPlugin("ExportHTML", CodeBox_ExportHTML)
CodeBox.RegisterPlugin("SmartTyping", CodeBox_SmartTyping)
CodeBox.RegisterPlugin("ClipboardManager", CodeBox_ClipboardManager)
CodeBox.RegisterPlugin("PluginManager", CodeBox_PluginManager)
CodeBox.RegisterPlugin("FindReplace", CodeBox_FindReplace)
CodeBox.RegisterPlugin("BracketMatcher", CodeBox_BracketMatcher)
CodeBox.RegisterPlugin("ContextMenu", CodeBox_ContextMenu)
CodeBox.RegisterPlugin("INIEditor", CodeBox_INIEditor)

; ==============================================================================
; DEMONSTRATION SHOWCASE GUI
; ==============================================================================

Showcase() {
    guiObj := Gui("+Resize +MinSize850x600", "CodeBox RichIDE")
    guiObj.BackColor := "1E1E1E"
    guiObj.MarginX := 15, guiObj.MarginY := 15
    guiObj.SetFont("s10 cWhite", "Segoe UI")

    ; --- MenuBar Setup ---
    mainMenu := MenuBar()
    fileMenu := Menu()
    editMenu := Menu()
    viewMenu := Menu()
    toolsMenu := Menu()

    guiObj.ShowTooltips := false

    viewMenu.Add("Debug Zoom", (*) => DebugZoom(box))
    viewMenu.Add()
    viewMenu.Add("Zoom In`tCtrl+=", (*) => box.ZoomIn())
    viewMenu.Add("Zoom Out`tCtrl+-", (*) => box.ZoomOut())
    viewMenu.Add("Reset Zoom`tCtrl+0", (*) => box.ZoomReset())
    viewMenu.Add()
    viewMenu.Add("Show Events log", (*) => ToggleEventPanel())
    viewMenu.Add("Show Event Tooltips", (ItemName, ItemPos, MyMenu) => (
        guiObj.ShowTooltips := !guiObj.ShowTooltips,
        MyMenu.ToggleCheck(ItemName)
    ))

    toolsMenu.Add("Show Active Hotkeys", (*) => ShowHotkeyHelper(box))

    mainMenu.Add("&File", fileMenu)
    mainMenu.Add("&Edit", editMenu)
    mainMenu.Add("&View", viewMenu)
    mainMenu.Add("&Tools", toolsMenu)
    guiObj.MenuBar := mainMenu

    ; --- Toolbar Setup ---
    nextX := 15
    nextY := 14
    maxW := 820

    chkWrap := guiObj.Add("CheckBox", "x" nextX " y" (nextY + 3) " Checked cWhite", "Wrap")
    nextX += 70

    ; --- The Core Engine ---
    box := CodeBox.Add(guiObj, "x15 y55 w820 h480", GetExampleText("ahk2"), "ahk2", "Dark")

    ; Let plugins register their menus and toolbar UI components!
    CodeBox.Emit("OnRegisterMenu", box, fileMenu, editMenu, viewMenu, toolsMenu)
    CodeBox.Emit("OnRegisterUI", box, guiObj, &nextX, &nextY, maxW)

    ; --- Zoom Controls in Toolbar ---
    nextX += 15
    btnZoomOut := guiObj.Add("Button", "x" nextX " y" (nextY) " w24 h24 +0x8000", "−")
    btnZoomOut.SetFont("s12 Bold", "Segoe UI")
    nextX += 26
    zoomLabel := guiObj.Add("Text", "x" nextX " y" (nextY + 4) " w45 h20 Center cWhite", "100%")
    zoomLabel.SetFont("s9", "Segoe UI")
    nextX += 47
    btnZoomIn := guiObj.Add("Button", "x" nextX " y" (nextY) " w24 h24 +0x8000", "+")
    btnZoomIn.SetFont("s12 Bold", "Segoe UI")
    nextX += 26
    btnZoomReset := guiObj.Add("Button", "x" nextX " y" (nextY) " w40 h24 +0x8000", "Reset")
    btnZoomReset.SetFont("s8", "Segoe UI")
    nextX += 45

    btnZoomIn.OnEvent("Click", (*) => (box.ZoomIn(), box.Focus()))
    btnZoomOut.OnEvent("Click", (*) => (box.ZoomOut(), box.Focus()))
    btnZoomReset.OnEvent("Click", (*) => (box.ZoomReset(), box.Focus()))

    box.On("Zoom", (ctrl, pct) => zoomLabel.Text := pct "%")

    ; Calculate final Y position for the main CodeBox editor so it sits below the toolbar
    finalY := nextY + 32

    ; Add a subtle 1px separator line below the toolbar
    sepLine := guiObj.Add("Text", "x0 y" (finalY + 4) " w9999 h1 Background333333")

    box.UpdateBounds(15, finalY + 15, 820, 550 - (finalY + 15))

    ; Toolbar Interactions
    chkWrap.OnEvent("Click", (*) => (box.WordWrap := chkWrap.Value, box.Focus()))

    DebugZoom(box) {
        ctrl := CodeBox._Instances[box.Hwnd]
        nb1 := Buffer(4, 0), db1 := Buffer(4, 0)
        SendMessage(0x04E0, nb1.Ptr, db1.Ptr, , "ahk_id " ctrl.Hwnd)
        n1 := NumGet(nb1, "UInt"), d1 := NumGet(db1, "UInt")

        nb2 := Buffer(4, 0), db2 := Buffer(4, 0)
        SendMessage(0x04E0, nb2.Ptr, db2.Ptr, , "ahk_id " ctrl.LineNumCtrl.Hwnd)
        n2 := NumGet(nb2, "UInt"), d2 := NumGet(db2, "UInt")

        MsgBox("MainCtrl Zoom: " n1 " / " d1 "`nGutter Zoom: " n2 " / " d2 "`nStored zRatio: " (ctrl.HasProp("ZoomNum") ? ctrl.ZoomNum : 0) " / " (ctrl.HasProp("ZoomDen") ? ctrl.ZoomDen : 0), "Zoom State Debug", 64)
    }

    ; --- Robust Native Callbacks ---
    sb := guiObj.Add("StatusBar", "Background007ACC cWhite", " Ready. (Highlight text and press Ctrl+M to Fold to memory!)")
    sb.SetFont("s9", "Segoe UI")

    globalEventLog := []

    LogVerboseEvent(eventName, details, showPopup := false) {
        timeStr := FormatTime(, "HH:mm:ss")

        cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, box.Hwnd)
        startSel := NumGet(cr, 0, "Int"), endSel := NumGet(cr, 4, "Int")
        charRange := startSel ":" endSel

        lineIdx := SendMessage(0x0436, 0, startSel, box.Hwnd) + 1

        DllCall("GetCursorPos", "Ptr", pt := Buffer(8))
        DllCall("ScreenToClient", "Ptr", box.Hwnd, "Ptr", pt)
        mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
        mousePos := "(" mx ", " my ")"

        ev := { timeStr: timeStr, eventName: eventName, lineIdx: lineIdx, charRange: charRange, mousePos: mousePos, details: details }
        globalEventLog.InsertAt(1, ev)
        if (globalEventLog.Length > 500)
            globalEventLog.Pop()

        filter := eventFilter.Text
        if (filter == "All Events" || filter == eventName) {
            eventPanel.Insert(1, "", timeStr, eventName, lineIdx, charRange, mousePos, details)
        }
        sb.SetText(" " eventName ": " details)

        if showPopup && guiObj.ShowTooltips {
            if (eventName == "Error")
                ttText := "⚠ Syntax Error Evaluated: " details
            else if (eventName == "Type")
                ttText := "Typed " details
            else
                ttText := eventName ": " details

            ToolTip(ttText, , , 3)
            SetTimer(() => ToolTip(, , , 3), -1500)
        }
    }

    box.On("Change", (ctrl) => LogVerboseEvent("Change", "Document modified. Length: " StrLen(ctrl.Text)))
    box.On("Type", (ctrl, char) => (char == Chr(8) || char == "`r" || char == "`n") ? "" : LogVerboseEvent("Type", char, true))
    box.On("KeyDown", (ctrl, key) => (key == 46) ? LogVerboseEvent("Key", "Delete", true) : (key == 8) ? LogVerboseEvent("Key", "Backspace", true) : (key == 13) ? LogVerboseEvent("Key", "Enter", true) : "")
    box.On("Error", (ctrl, err) => LogVerboseEvent("Error", err, true))
    box.On("Suggest", (ctrl, word) => LogVerboseEvent("Suggest", word, true))
    box.On("Fold", (ctrl, action) => LogVerboseEvent("Fold", action, true))
    box.On("Click", (ctrl) => LogVerboseEvent("Select", "Drag/Select Start"))
    box.On("SelectEnd", (ctrl) => LogVerboseEvent("Select", "Drag/Select End"))
    box.On("ShowHistoryClicked", (*) => ToggleHistoryPanel())
    box.On("ContextMenu", (ctrl, x, y) => LogVerboseEvent("ContextMenu", "Right-click at (" x ", " y ")", true))
    box.On("ContextMenuOpen", (ctrl) => LogVerboseEvent("ContextMenuOpen", "Context menu opened", true))
    box.On("ContextMenuClose", (ctrl) => LogVerboseEvent("ContextMenuClose", "Context menu closed", true))
    box.On("ContextMenuClick", (ctrl, label) => LogVerboseEvent("ContextMenuClick", "Selected: " label, true))


    histPanel := guiObj.Add("ListView", "x845 y55 w200 h480 Background333333 cWhite -Multi", ["Action", "Length"])
    histPanel.Visible := false
    histPanel.ModifyCol(1, 120)
    histPanel.ModifyCol(2, 50)
    histPanel.OnEvent("DoubleClick", RestoreHistoryItem)

    eventFilter := guiObj.Add("DropDownList", "x15 y550 w120 Choose1 Background333333 cWhite", ["All Events", "Type", "Key", "Select", "Change", "Error", "Suggest", "Fold", "ContextMenu"])
    eventFilter.Visible := false
    eventFilter.OnEvent("Change", (*) => RebuildEventPanel())

    eventSearch := guiObj.Add("Edit", "x145 y550 w180 h26 Background333333 cWhite", "")
    eventSearch.Visible := false
    eventSearch.OnEvent("Change", (*) => RebuildEventPanel())
    SendMessage(0x1501, 1, StrPtr("Filter by details..."), eventSearch.Hwnd)

    eventPanel := guiObj.Add("ListView", "x15 y580 w820 h70 Background333333 cWhite -Multi", ["Time", "Event", "Line", "CharRange", "MousePos", "Details"])
    eventPanel.Visible := false
    eventPanel.ModifyCol(1, 60)
    eventPanel.ModifyCol(2, 70)
    eventPanel.ModifyCol(3, 50)
    eventPanel.ModifyCol(4, 80)
    eventPanel.ModifyCol(5, 80)
    eventPanel.ModifyCol(6, 400)

    RebuildEventPanel() {
        eventPanel.Delete()
        filter := eventFilter.Text
        search := eventSearch.Text
        for ev in globalEventLog {
            match := false
            if (filter == "All Events")
                match := true
            else if (filter == "ContextMenu" && SubStr(ev.eventName, 1, 11) == "ContextMenu")
                match := true
            else if (filter == ev.eventName)
                match := true
                
            if match {
                if (search == "" || InStr(ev.eventName, search) || InStr(ev.details, search)) {
                    eventPanel.Add("", ev.timeStr, ev.eventName, ev.lineIdx, ev.charRange, ev.mousePos, ev.details)
                }
            }
        }
    }

    ToggleEventPanel(*) {
        eventPanel.Visible := !eventPanel.Visible
        eventFilter.Visible := eventPanel.Visible
        eventSearch.Visible := eventPanel.Visible
        guiObj.GetClientPos(, , &cw, &ch)
        Gui_Size(guiObj, 0, cw, ch)
    }

    ToggleHistoryPanel(*) {
        histPanel.Visible := !histPanel.Visible
        if histPanel.Visible {
            guiObj.Opt("+MinSize1060x600")
            guiObj.GetPos(, , &w)
            if (w < 1060)
                guiObj.Move(, , 1060)
        } else {
            guiObj.Opt("+MinSize850x600")
        }
        guiObj.GetClientPos(, , &cw, &ch)
        Gui_Size(guiObj, 0, cw, ch)
    }

    RestoreHistoryItem(ctrl, info) {
        if (info == 0)
            return
        box.HistoryIndex := info
        state := box.History[info]
        box.LastHistoryText := state.text
        CodeBox.Invoke("RestoreState", box, state)
        box.Focus()
    }

    box.On("HistoryChange", UpdateHistoryPanel)
    UpdateHistoryPanel(ctrl, history, index) {
        histPanel.Delete()
        for i, state in history {
            histPanel.Add(i == index ? "Select" : "", state.action, StrLen(state.text))
        }
        if index > 0
            histPanel.Modify(index, "Vis")
    }

    ; Auto-Scale Redraw Hook
    guiObj.OnEvent("Size", Gui_Size)
    Gui_Size(gui, minMax, width, height) {
        if (minMax = -1)
            return

        sb.GetPos(, &sbY) ; Get exact Y position of the status bar

        boxW := histPanel.Visible ? width - 30 - 210 : width - 30
        boxH := eventPanel.Visible ? sbY - (finalY + 15) - 150 : sbY - (finalY + 15)

        box.UpdateBounds(15, finalY + 15, boxW, boxH)
        if histPanel.Visible
            histPanel.Move(15 + boxW + 10, finalY + 15, 200, boxH)
        if eventPanel.Visible {
            eventFilter.Move(15, sbY - 140, 120, 26)
            eventSearch.Move(145, sbY - 140, 180, 26)
            eventPanel.Move(15, sbY - 110, boxW, 110)
        }
    }

    guiObj.OnEvent("Close", (*) => ExitApp())
    guiObj.Show("w1200")
}

GetExampleText(lang) {
    lang := StrLower(lang)
    if lang == "ahk2"
        return "; AutoHotkey v2 Example`n#Requires AutoHotkey v2.0`n`nclass IDE_Demo {`n    static Run() {`n        MsgBox(`"CodeBox is awesome!`")`n        MsgBox, `"v1 style warning`" `; Warning`n        if (var === true)`n            MsgBox () `; Error`n        %legacyVar% := 1 `; Error`n        return true`n    }`n}"
    if lang == "cs"
        return "// C# Example`nusing System;`n`npublic class Test {`n    public static void Main() {`n        Console.WriteLine(`"Hello from C#!`");`n        int count = 100;`n        class = 5; // Error`n    }`n}"
    if lang == "js"
        return "/* JavaScript Example */`nconst active = true;`n`nfunction process() {`n    console.log('Running process...');`n    if (active == true) // Warning`n        return active;`n    const obj = { name: 'test', } // Warning`n}"
    if lang == "python"
        return "# Python Example`ndef test():`n    print(`"Python is fun`")`n    return True`n`nclass Box:`n    def __init__(self):`n        self.name = `"CodeBox`"`n        print `"Legacy Print!`" # Error`n        pass"
    if lang == "xml"
        return "`n<Window xmlns=`"http://example.com`">`n    <Grid Background=`"White`">`n        <Button Content=`"Click Me`" />`n    </Grid>`n</Window>"
    if lang == "html"
        return "<!DOCTYPE html>`n<html>`n<head>`n    <title>CodeBox Example</title>`n</head>`n<body>`n    <!-- Hello World -->`n    <div class=`"container`">`n        <h1>Welcome to RichIDE!</h1>`n    </div>`n</body>`n</html>"
    if lang == "bat"
        return "@echo off`n:: Batch script example`nsetlocal enabledelayedexpansion`n`nset MY_VAR=CodeBox`necho Welcome to %MY_VAR%!`n`nfor %%i in (1 2 3) do (`n    echo Iteration %%i`n)`n`npause"
    if lang == "sql"
        return "-- SQL Example`nSELECT id, name, created_at`nFROM users`nWHERE status = 'active'`nORDER BY created_at DESC;`n`n/* Block Comment Example */`nUPDATE users SET status = 'inactive' WHERE id = 123;"
    if lang == "ps1"
        return "<#`nPowerShell Script Example`n#>`nparam (`n    [string]$Name = `"CodeBox`"`n)`n`nfunction Get-Greeting {`n    param([string]$target)`n    return `"Hello, $target!`"`n}`n`n$msg = Get-Greeting -target $Name`nWrite-Host $msg"
    if lang == "json"
        return "{`n    `"name`": `"CodeBox`",`n    `"version`": 3.0,`n    `"active`": true,`n    `"features`": [`n        `"Syntax`",`n        `"Themes`",`n    ]`n}"
    if lang == "ini"
        return "; INI Example`n[Settings]`nTheme=Dark`nLanguage=AHK2`n`n[Editor]`nShowLineNumbers=true`nWordWrap=1`nFontSize=12`nHighlightColor=#569CD6"
    if lang == "css"
        return "/* CSS Example */`nbody {`n    background-color: #1E1E1E;`n    color: #FFFFFF;`n    margin: 0;`n}`n`n.btn:hover {`n    background-color: #007ACC;`n    color: `; /* Error */`n}"
    if lang == "csv"
        return "Name,Age,Job`nAlice,30,Engineer`nBob,25,Designer"
    if lang == "tsv"
        return "Name`tAge`tJob`nAlice`t30`tEngineer`nBob`t25`tDesigner"
    if lang == "md"
        return "# Markdown Example`n`n> This is a **robust** *blockquote*!`n`n``````ahk2`n; Code block`nMsgBox(`"Hello`")`n```````n`nHere is some ``inline code`` and a [Link](http://example.com).`n`n- List Item 1`n- List Item 2`n`n| Feature | Status |`n|---|---|`n| Parsing | Native |`n| JS | None |`n`n---"
    return "Plain text example..."
}

ShowHotkeyHelper(box) {
    if WinExist("Hotkey Helper") {
        WinActivate("Hotkey Helper")
        return
    }

    hkGui := Gui("+ToolWindow +Owner" box.Gui.Hwnd, "Hotkey Helper")
    hkGui.BackColor := "1E1E1E"
    hkGui.SetFont("s9 cWhite", "Segoe UI")
    
    lv := hkGui.Add("ListView", "w380 h350 Background333333 cWhite -Multi NoSortHdr", ["Hotkey", "Action", "State"])
    lv.ModifyCol(1, 100)
    lv.ModifyCol(2, 180)
    lv.ModifyCol(3, 80)
    
    hotkeys := [
        { hk: "Ctrl+Shift+F", desc: "Format Code", check: (ctrl) => !(ctrl.HasProp("IsPreviewing") && ctrl.IsPreviewing) },
        { hk: "Ctrl+Z", desc: "Undo", check: (ctrl) => (ctrl.HasProp("HistoryIndex") && ctrl.HistoryIndex > 1) },
        { hk: "Ctrl+Y", desc: "Redo", check: (ctrl) => (ctrl.HasProp("HistoryIndex") && ctrl.HistoryIndex < (ctrl.HasProp("History") ? ctrl.History.Length : 0)) },
        { hk: "Ctrl+F", desc: "Find", check: (ctrl) => true },
        { hk: "Ctrl+H", desc: "Replace", check: (ctrl) => true },
        { hk: "Ctrl+/", desc: "Toggle Line Comment", check: (ctrl) => true },
        { hk: "Ctrl+Shift+/", desc: "Toggle Block Comment", check: (ctrl) => (ctrl.CodeBoxLang ~= "^(ahk2|ini|js|cs|cpp|c|java|php|go|rust|css|python|ruby|ps1|yaml|sql|html|xml|md)$") },
        { hk: "Ctrl+K", desc: "Toggle Markdown View", check: (ctrl) => (ctrl.CodeBoxLang == "md") },
        { hk: "Ctrl+M", desc: "Fold Current", check: (ctrl) => true },
        { hk: "Ctrl+Shift+[", desc: "Fold Block", check: (ctrl) => true },
        { hk: "Ctrl+Shift+]", desc: "Unfold Block", check: (ctrl) => true },
        { hk: "Ctrl+1...0", desc: "Fold All Level 1-10", check: (ctrl) => true },
        { hk: "F3", desc: "Find Next", check: (ctrl) => (ctrl.HasProp("FindState") && ctrl.FindState.Query != "") },
        { hk: "Shift+F3", desc: "Find Prev", check: (ctrl) => (ctrl.HasProp("FindState") && ctrl.FindState.Query != "") },
        { hk: "Tab", desc: "Indent", check: (ctrl) => true },
        { hk: "Shift+Tab", desc: "Unindent", check: (ctrl) => true }
    ]
    
    for item in hotkeys {
        lv.Add("", item.hk, item.desc, "Active")
    }
    
    UpdateList() {
        if !WinExist(hkGui.Hwnd) {
            SetTimer(UpdateList, 0)
            return
        }
        for i, item in hotkeys {
            isActive := item.check.Call(box)
            if (isActive)
                lv.Modify(i, "", item.hk, item.desc, "Active")
            else
                lv.Modify(i, "", item.hk, item.desc, "Disabled")
        }
    }
    
    SetTimer(UpdateList, 200)
    hkGui.Show("NoActivate")
}

Showcase()