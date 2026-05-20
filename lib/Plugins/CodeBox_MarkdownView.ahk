class CodeBox_MarkdownView {
    static OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu) {
        ctrl._MdViewMenu := viewMenu
        viewMenu.Add("Toggle Markdown Preview`tCtrl+K", (*) => CodeBox.Invoke("ToggleMarkdownView", ctrl, !ctrl.HasProp("_MdView") ? true : !ctrl._MdView))
        if (StrLower(ctrl.CodeBoxLang) != "md") {
            try viewMenu.Disable("Toggle Markdown Preview")
        }
    }

    static OnLanguageChange(ctrl) {
        if (ctrl.HasProp("_MdViewMenu")) {
            if (StrLower(ctrl.CodeBoxLang) == "md") {
                try ctrl._MdViewMenu.Enable("Toggle Markdown Preview`tCtrl+K")
            } else {
                try ctrl._MdViewMenu.Disable("Toggle Markdown Preview`tCtrl+K")
                if (ctrl.HasProp("_MdView") && ctrl._MdView)
                    this.ToggleMarkdownView(ctrl, false)
            }
        }
    }

    static OnDisable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := false
        if (ctrl.HasProp("_MdView") && ctrl._MdView)
            this.ToggleMarkdownView(ctrl, false)
    }
    static OnEnable(ctrl) {
        if this.HasProp("ToolbarBtn")
            this.ToolbarBtn.Visible := true
    }

    static OnKeyDown(ctrl, wParam) {
        if (wParam == 75 && GetKeyState("Ctrl") && StrLower(ctrl.CodeBoxLang) == "md") {
            CodeBox.Invoke("ToggleMarkdownView", ctrl, !ctrl.HasProp("_MdView") ? true : !ctrl._MdView)
            return 1
        }
        return 0
    }

    static OnThemeChange(ctrl) {
        if (ctrl.HasProp("_MdView") && ctrl._MdView && ctrl.HasProp("MdActiveX")) {
            mdText := CodeBox._GetText(ctrl)
            htmlText := this.MarkdownToHTML(mdText, ctrl.CodeBoxTheme)
            document := ctrl.MdActiveX.Value.Document
            document.open()
            document.write(htmlText)
            document.close()
        }
    }

    static ToggleMarkdownView(ctrl, v) {
        ctrl._MdView := v
        guiObj := ctrl.Gui
        
        if v {
            ctrl.IsHighlighting := true
            
            ; Get current text
            mdText := CodeBox._GetText(ctrl)
            
            ; Convert to HTML
            htmlText := this.MarkdownToHTML(mdText, ctrl.CodeBoxTheme)
            
            ; Create ActiveX if not exists
            if !ctrl.HasProp("MdActiveX") {
                ctrl.MdActiveX := guiObj.Add("ActiveX", "x" ctrl._x " y" ctrl._y " w" ctrl._w " h" ctrl._h, "Shell.Explorer")
                ctrl.MdActiveX.Value.Navigate("about:blank")
                while ctrl.MdActiveX.Value.ReadyState < 4
                    Sleep 10
            }
            
            ; Hide RichEdit, show ActiveX
            DllCall("ShowWindow", "Ptr", ctrl.Hwnd, "Int", 0) ; SW_HIDE
            if ctrl.HasProp("LineNumCtrl")
                ctrl.LineNumCtrl.Visible := false
            if ctrl.HasProp("ScrollTrack") {
                ctrl.ScrollTrack.Visible := false
                ctrl.ScrollThumb.Visible := false
                ctrl.HScrollTrack.Visible := false
                ctrl.HScrollThumb.Visible := false
            }
            ctrl.MdActiveX.Visible := true
            
            ; Suppress script errors completely
            try ctrl.MdActiveX.Value.Silent := true
            
            ; Write HTML
            document := ctrl.MdActiveX.Value.Document
            document.open()
            document.write(htmlText)
            document.close()
            
        } else {
            if ctrl.HasProp("MdActiveX") {
                ctrl.MdActiveX.Visible := false
            }
            DllCall("ShowWindow", "Ptr", ctrl.Hwnd, "Int", 5) ; SW_SHOW
            if ctrl.HasProp("LineNumCtrl") && ctrl._LineNums
                ctrl.LineNumCtrl.Visible := true
            if ctrl.HasProp("ScrollTrack") {
                CodeBox_Scrollbars.UpdateScrollbar(ctrl)
            }
            ctrl.IsHighlighting := false
            CodeBox.Emit("OnChange", ctrl)
        }
    }

    static OnWindowPosChanged(ctrl) {
        if (ctrl.HasProp("_MdView") && ctrl._MdView && ctrl.HasProp("MdActiveX")) {
            ctrl.MdActiveX.Move(ctrl._x, ctrl._y, ctrl._w, ctrl._h)
        }
    }

    static MarkdownToHTML(mdText, themeName) {
        ; 1. Generate Theme CSS
        theme := CodeBox.Themes.Has(themeName) ? CodeBox.Themes[themeName] : CodeBox.Themes["Dark"]
        bg := CodeBox._ColorToHex(theme["Background"])
        fg := CodeBox._ColorToHex(theme["Foreground"])
        acc := CodeBox._ColorToHex(theme.Has("Keyword") ? theme["Keyword"] : 0x007ACC)
        link := CodeBox._ColorToHex(theme.Has("Attribute") ? theme["Attribute"] : 0x007ACC)
        codeBg := CodeBox._ColorToHex(theme.Has("SelectionBg") ? theme["SelectionBg"] : 0x333333)

        css := "body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: " bg "; color: " fg "; padding: 20px; line-height: 1.6; border: none; margin: 0; }`n"
        css .= "h1, h2, h3, h4, h5, h6 { color: " acc "; margin-top: 1.5em; margin-bottom: 0.5em; font-weight: 600; }`n"
        css .= "h1 { border-bottom: 1px solid " codeBg "; padding-bottom: .3em; }`n"
        css .= "h2 { border-bottom: 1px solid " codeBg "; padding-bottom: .3em; }`n"
        css .= "a { color: " link "; text-decoration: none; }`n"
        css .= "a:hover { text-decoration: underline; }`n"
        css .= "code { background-color: " codeBg "; padding: 2px 5px; border-radius: 4px; font-family: Consolas, monospace; font-size: 0.9em; }`n"
        css .= "pre { background-color: " codeBg "; padding: 15px; border-radius: 6px; overflow-x: auto; }`n"
        css .= "pre code { background-color: transparent; padding: 0; }`n"
        css .= "blockquote { border-left: 4px solid " acc "; margin: 0; padding-left: 15px; color: #888; font-style: italic; }`n"
        css .= "table { border-collapse: collapse; width: 100%; margin-bottom: 15px; }`n"
        css .= "th, td { border: 1px solid " codeBg "; padding: 8px 12px; text-align: left; }`n"
        css .= "th { background-color: " codeBg "; }`n"
        css .= "hr { border: 0; border-top: 2px solid " codeBg "; margin: 20px 0; }`n"
        css .= "img { max-width: 100%; border-radius: 4px; }`n"
        css .= "ul, ol { margin-top: 0; margin-bottom: 10px; padding-left: 20px; }`n"

        html := mdText

        ; Pre-process code blocks so they don't get messed up by other formatting
        codeBlocks := Map()
        blockIndex := 0
        while (match := RegExMatch(html, "(?s)\x60{3}([^\r\n]*)\r?\n(.*?)\x60{3}", &m)) {
            blockIndex++
            lang := m[1]
            code := m[2]
            code := StrReplace(code, "&", "&amp;")
            code := StrReplace(code, "<", "&lt;")
            code := StrReplace(code, ">", "&gt;")
            placeholder := "@@CODEBLOCK_" blockIndex "@@"
            html := SubStr(html, 1, match - 1) . placeholder . SubStr(html, match + m.Len[0])
            codeBlocks[placeholder] := "<pre><code class=`"language-" lang "`">" code "</code></pre>"
        }

        ; Normalize newlines
        html := StrReplace(StrReplace(html, "`r`n", "`n"), "`r", "`n")
        
        ; Replace < > in regular text
        html := StrReplace(html, "<", "&lt;")
        html := StrReplace(html, ">", "&gt;")

        ; Blockquotes
        html := RegExReplace(html, "(?m)^[ \t]*>\s?(.*)", "<blockquote>$1</blockquote>")
        html := RegExReplace(html, "(?s)</blockquote>\n<blockquote>", "<br>")

        ; Headers
        html := RegExReplace(html, "(?m)^######\s+(.*)", "<h6>$1</h6>")
        html := RegExReplace(html, "(?m)^#####\s+(.*)", "<h5>$1</h5>")
        html := RegExReplace(html, "(?m)^####\s+(.*)", "<h4>$1</h4>")
        html := RegExReplace(html, "(?m)^###\s+(.*)", "<h3>$1</h3>")
        html := RegExReplace(html, "(?m)^##\s+(.*)", "<h2>$1</h2>")
        html := RegExReplace(html, "(?m)^#\s+(.*)", "<h1>$1</h1>")

        ; Horizontal Rules
        html := RegExReplace(html, "(?m)^[-*_]{3,}\s*$", "<hr>")

        ; Bold and Italics
        html := RegExReplace(html, "(?s)\*\*(.*?)\*\*", "<strong>$1</strong>")
        html := RegExReplace(html, "(?s)__(.*?)__", "<strong>$1</strong>")
        html := RegExReplace(html, "(?s)(?<!\*)\*(?!\*)([^\*]+)(?<!\*)\*(?!\*)", "<em>$1</em>")
        html := RegExReplace(html, "(?s)(?<!_)_(?!_)([^_]+)(?<!_)_(?!_)", "<em>$1</em>")

        ; Inline Code
        html := RegExReplace(html, "(?s)(?<!\x60)\x60([^\x60]+)\x60(?!\x60)", "<code>$1</code>")

        ; Images
        html := RegExReplace(html, "!\[([^\]]*)\]\(([^\)]+)\)", "<img src=`"$2`" alt=`"$1`" />")
        
        ; Links
        html := RegExReplace(html, "\[([^\]]+)\]\(([^\)]+)\)", "<a href=`"$2`">$1</a>")

        ; Unordered Lists
        html := RegExReplace(html, "(?m)^[ \t]*[-\*\+]\s+(.*)", "<ul><li>$1</li></ul>")
        html := RegExReplace(html, "(?s)</ul>\n<ul>", "`n")

        ; Ordered Lists
        html := RegExReplace(html, "(?m)^[ \t]*\d+\.\s+(.*)", "<ol><li>$1</li></ol>")
        html := RegExReplace(html, "(?s)</ol>\n<ol>", "`n")

        ; Tables (Simple implementation)
        lines := StrSplit(html, "`n")
        inTable := false
        outLines := []
        for line in lines {
            if (RegExMatch(line, "^[ \t]*\|.*\|$")) {
                if (!inTable) {
                    inTable := true
                    outLines.Push("<table>")
                }
                
                ; Is it a separator line? |---|---|
                if (RegExMatch(line, "^[ \t]*\|[\s\-\|:]+\|$")) {
                    continue
                }

                ; Strip leading/trailing |
                rowContent := RegExReplace(line, "^[ \t]*\|(.*)\|[ \t]*$", "$1")
                cells := StrSplit(rowContent, "|")
                
                tr := "<tr>"
                tag := (outLines.Length > 0 && outLines[outLines.Length] == "<table>") ? "th" : "td"
                for cell in cells {
                    tr .= "<" tag ">" Trim(cell) "</" tag ">"
                }
                tr .= "</tr>"
                outLines.Push(tr)
            } else {
                if (inTable) {
                    inTable := false
                    outLines.Push("</table>")
                }
                outLines.Push(line)
            }
        }
        if (inTable)
            outLines.Push("</table>")

        html := ""
        for line in outLines {
            html .= line "`n"
        }

        ; Paragraphs (wrap lines not starting with < in <p>)
        outLines := StrSplit(html, "`n")
        html := ""
        for line in outLines {
            tLine := Trim(line)
            if (tLine == "" || RegExMatch(tLine, "^<\/?(h[1-6]|ul|ol|li|table|tr|th|td|blockquote|hr|pre|div)")) {
                html .= line "`n"
                continue
            }
            if (!RegExMatch(tLine, "^<")) {
                html .= "<p>" tLine "</p>`n"
            } else {
                html .= line "`n"
            }
        }

        ; Re-inject code blocks
        for placeholder, block in codeBlocks {
            html := StrReplace(html, placeholder, block)
        }

        ; Wrap in standard HTML5 with X-UA-Compatible to force modern rendering if IE is used
        finalHTML := "<!DOCTYPE html><html><head><meta charset='UTF-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>" css "</style></head><body>" html "</body></html>"

        return finalHTML
    }
}
