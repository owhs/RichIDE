#Requires AutoHotkey v2.0
#SingleInstance Force

; Include CodeBox and all plugins
#Include "%A_ScriptDir%\lib\CodeBox.ahk"
#Include "%A_ScriptDir%\lib\CodeBox_Data.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Highlighter.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Theming.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Selection.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Scrollbars.ahk"
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

; Register all plugins
CodeBox.RegisterPlugin("Highlighter", CodeBox_Highlighter)
CodeBox.RegisterPlugin("Theming", CodeBox_Theming)
CodeBox.RegisterPlugin("Selection", CodeBox_Selection)
CodeBox.RegisterPlugin("Scrollbars", CodeBox_Scrollbars)
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

; Initial demonstration code to load into the editor
demoCode := '
(
; AutoHotkey v2 Minimal CodeBox Example
#Requires AutoHotkey v2.0

class Hello {
    static SayWorld() {
        MsgBox("Hello from CodeBox!")
    }
}
)'

; Create a resizable GUI container
mainGui := Gui("+Resize", "CodeBox Minimal")
mainGui.BackColor := "1E1E1E"

; Setup responsive resizing (makes CodeBox fill the entire GUI window)
mainGui.OnEvent("Size", (guiObj, minMax, w, h) => box.UpdateBounds(0, 0, w, h))

; Add the CodeBox editor control
box := CodeBox.Add(mainGui, "x0 y0 w600 h400", demoCode, "ahk2", "Dark")

; Display the window
mainGui.Show("w600 h400")
