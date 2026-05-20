class CodeBox_Highlighter {
    static _DocCache := Map()
    static _Timers := Map()
    static _ChunkTimers := Map()

    static OnRegisterUI(ctrl, guiObj, &x, &y, maxW) {
        this.ToolbarText := guiObj.Add("Text", "x" x " y" (y+3) " w55 BackgroundTrans", "Syntax:")
        x += 55
        
        langs := []
        idx := 1, i := 1
        for k, v in CodeBox.Syntaxes {
            langs.Push(k)
            if (k == ctrl.CodeBoxLang)
                idx := i
            i++
        }
        
        this.ToolbarDDL := guiObj.Add("DropDownList", "x" x " y" y " w90 Choose" idx " Background2D2D30 cWhite", langs)
        onChange(*) {
            ctrl.Language := this.ToolbarDDL.Text
            try {
                fn := %"GetExampleText"%
                CodeBox._SetText(ctrl, fn(this.ToolbarDDL.Text), true)
            } catch {

            }
        }
        this.ToolbarDDL.OnEvent("Change", onChange)
        x += 100
    }

    static OnDisable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := false
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := false
        ctrl.IsHighlighting := true 
        this._StopTimers(ctrl.Hwnd)
    }

    static OnEnable(ctrl) {
        if this.HasProp("ToolbarText")
            this.ToolbarText.Visible := true
        if this.HasProp("ToolbarDDL")
            this.ToolbarDDL.Visible := true
        ctrl.IsHighlighting := false
        this.Highlight(ctrl, true)
    }

    static OnDestroy(ctrl) {
        hwnd := ctrl.Hwnd
        this._StopTimers(hwnd)
        if this._DocCache.Has(hwnd)
            this._DocCache.Delete(hwnd)
    }

    static _StopTimers(hwnd) {
        if this._Timers.Has(hwnd) {
            SetTimer(this._Timers[hwnd], 0)
            this._Timers.Delete(hwnd)
        }
        if this._ChunkTimers.Has(hwnd) {
            SetTimer(this._ChunkTimers[hwnd], 0)
            this._ChunkTimers.Delete(hwnd)
        }
    }

    static OnChange(ctrl) => this.QueueHighlight(ctrl, true)
    static OnLanguageChange(ctrl) => this.QueueHighlight(ctrl, true)
    static OnThemeChange(ctrl) => this.QueueHighlight(ctrl, true)
    static OnScroll(ctrl) => this.QueueHighlight(ctrl, false)
    static Highlight(ctrl, force := true) => this.QueueHighlight(ctrl, force)

    ; 1. Debounce Scheduler (Locks typing latency to ~0ms)
    static QueueHighlight(ctrl, force := true) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        if !this._Timers.Has(hwnd)
            this._Timers[hwnd] := ObjBindMethod(this, "DoHighlight", ctrl)

        ctrl._ForceNextHighlight := force || (ctrl.HasProp("_ForceNextHighlight") ? ctrl._ForceNextHighlight : false)
        SetTimer(this._Timers[hwnd], -15) ; Fast yield bounce
    }

    ; Grabs the native C++ COM Object (Text Object Model) for direct memory formatting
    static GetITextDocument(hwnd) {
        if this._DocCache.Has(hwnd)
            return this._DocCache[hwnd]

        IRichEditOle := Buffer(A_PtrSize, 0)
        if SendMessage(0x043C, 0, IRichEditOle.Ptr, hwnd) { ; EM_GETOLEINTERFACE
            pOle := NumGet(IRichEditOle, 0, "Ptr")
            if pOle {
                try {
                    ; Query for ITextDocument
                    pDoc := ComObjQuery(pOle, "{8CC497C0-A1DF-11CE-8098-00AA0047BE5D}")
                    if pDoc {
                        ; Cast to IDispatch (Type 9) to enable dot-notation methods
                        docObj := ComObjQuery(pDoc, "{00020400-0000-0000-C000-000000000046}")
                        if docObj {
                            this._DocCache[hwnd] := docObj
                            return docObj
                        }
                    }
                } finally {
                    ObjRelease(pOle)
                }
            }
        }
        return ""
    }

    static RGBtoBGR(rgb) => ((rgb & 0xFF0000) >> 16) | (rgb & 0x00FF00) | ((rgb & 0x0000FF) << 16)
; ====================================================================================
    ; 2. INSTANT VIEWPORT FORMATTER ($O(1)$ Math)
    ; ====================================================================================
    static DoHighlight(ctrl) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd)
            return

        ; Yield to system selection drawing to prevent UI fighting
        if (GetKeyState("LButton", "P") || GetKeyState("Shift", "P")) {
            SetTimer(this._Timers[hwnd], -50)
            return
        }

        if (ctrl.HasProp("IsHighlighting") && ctrl.IsHighlighting) {
            SetTimer(this._Timers[hwnd], -15)
            return
        }

        force := ctrl.HasProp("_ForceNextHighlight") ? ctrl._ForceNextHighlight : false
        ctrl._ForceNextHighlight := false

        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if (totalLen <= 0) {
            ctrl.LastHighlightStart := 0
            ctrl.LastHighlightEnd := 0
            return
        }

        doc := this.GetITextDocument(hwnd)
        if !doc
            return

        ; Mathematically calculate screen bounding box constraints
        firstLine := SendMessage(0x00CE, 0, 0, hwnd)
        rect := Buffer(16, 0), DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr)
        pt := Buffer(8, 0), NumPut("Int", NumGet(rect, 12, "Int"), pt, 4)
        lastChar := SendMessage(0x04D9, 0, pt.Ptr, hwnd)
        if (lastChar < 0 || lastChar > totalLen)
            lastChar := totalLen
            
        lastLine := SendMessage(0x0436, 0, lastChar, hwnd)
        if (lastLine < firstLine)
            lastLine := firstLine + 50

        pad := 150 ; Safety padding outside viewport for seamless fast-scrolling
        padStartLine := Max(0, firstLine - pad)
        padEndLine := lastLine + pad
        
        padStartChar := SendMessage(0x00BB, padStartLine, 0, hwnd)
        if (padStartChar < 0)
            padStartChar := 0
        padEndChar := SendMessage(0x00BB, padEndLine + 1, 0, hwnd)
        if (padEndChar < 0 || padEndChar > totalLen)
            padEndChar := totalLen

        ; If purely scrolling within the cached safety padding, skip expensive operations entirely
        if (!force && ctrl.HasProp("LastHighlightStart") && ctrl.HasProp("LastHighlightEnd")
            && padStartChar >= ctrl.LastHighlightStart && padEndChar <= ctrl.LastHighlightEnd) {
            return
        }

        ; Full History Payload ONLY runs when forced (Paste/Delete)
        if (force) {
            len := totalLen
            GETTEXTEX := Buffer(A_PtrSize == 8 ? 32 : 20, 0)
            NumPut("UInt", (len + 1) * 2, GETTEXTEX, 0), NumPut("UInt", 1200, GETTEXTEX, 8)
            buf := Buffer((len + 1) * 2, 0)
            SendMessage(0x045E, GETTEXTEX.Ptr, buf.Ptr, hwnd)
            fullText := StrReplace(StrGet(buf, len, "UTF-16"), "`r", "`n")

            if (!ctrl.HasProp("LastHistoryText") || ctrl.LastHistoryText != fullText) {
                cr := Buffer(8, 0), SendMessage(0x0434, 0, cr.Ptr, hwnd)
                CodeBox.Emit("PushHistory", ctrl, "Edit", fullText, NumGet(cr, 0, "Int"), NumGet(cr, 4, "Int"))
                ctrl.LastHistoryText := fullText
            }
        }

        ctrl.IsHighlighting := true
        ctrl.LastHighlightStart := padStartChar
        ctrl.LastHighlightEnd := padEndChar

        ; Expand search window 15,000 chars back so multi-line block comments resolve cleanly
        lookback := 15000
        fetchStart := Max(0, padStartChar - lookback)
        fetchEnd := Min(totalLen, padEndChar + 5000)

        chunkText := CodeBox._GetTextRange(hwnd, fetchStart, fetchEnd)
        chunkText := StrReplace(chunkText, "`r", "`n")

        themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        rules := CodeBox.Syntaxes.Has(StrLower(ctrl.CodeBoxLang)) ? CodeBox.Syntaxes[StrLower(ctrl.CodeBoxLang)] : []
        
        defColorBGR := this.RGBtoBGR(themeC["Foreground"])
        bgBGR := this.RGBtoBGR(themeC["Background"])

        try {
            doc.Freeze() ; Immediately suspends UI rendering locks
            rng := doc.Range(padStartChar, padEndChar)
            rng.Font.ForeColor := defColorBGR
            rng.Font.BackColor := bgBGR ; Strips formatting carried over from pasted RTF
            rng.Font.Bold := 0
            rng.Font.Underline := 0

            firedErr := Map()
            ctrl.ErrorLines := Map()
            ctrl.WarningLines := Map()

            for rule in rules {
                pos := 1
                colorBGR := this.RGBtoBGR(themeC.Has(rule.c) ? themeC[rule.c] : themeC["Foreground"])
                b := rule.HasOwnProp("b") && rule.b ? -1 : 0 ; -1 represents COM Variant_True
                u := rule.HasOwnProp("u") ? rule.u : 0       ; Native mapping (8 = tomWave squiggles)
                isDefaultColor := (colorBGR == defColorBGR)
                isErr := (rule.c == "Error"), isWarn := (rule.c == "Warning")

                while (match := RegExMatch(chunkText, rule.p, &m, pos)) {
                    if (m.Len[0] == 0) {
                        pos := match + 1
                        continue
                    }
                    
                    globalStart := fetchStart + match - 1
                    globalEnd := globalStart + m.Len[0]
                    
                    ; Perfect mathematical alignment: Only format if the match crosses our rendered viewport
                    if (globalEnd > padStartChar && globalStart < padEndChar) {
                        fmtStart := Max(padStartChar, globalStart)
                        fmtEnd := Min(padEndChar, globalEnd)
                        
                        mRng := doc.Range(fmtStart, fmtEnd)
                        if !isDefaultColor
                            mRng.Font.ForeColor := colorBGR
                        if b
                            mRng.Font.Bold := b
                        if u
                            mRng.Font.Underline := u

                        if (isErr || isWarn) {
                            sub := SubStr(chunkText, 1, match)
                            StrReplace(sub, "`n", "`n", , &nlCount)
                            lineNum := SendMessage(0x0436, 0, fetchStart, hwnd) + nlCount + 1
                            if isErr {
                                ctrl.ErrorLines[lineNum] := rule.HasOwnProp("msg") ? rule.msg : "Invalid syntax: " m[0]
                                if !firedErr.Has(m[0]) {
                                    firedErr[m[0]] := 1
                                    CodeBox._Fire(ctrl, "Error", m[0])
                                }
                            } else {
                                ctrl.WarningLines[lineNum] := rule.HasOwnProp("msg") ? rule.msg : "Potential issue: " m[0]
                            }
                        }
                    }
                    pos := match + m.Len[0]
                }
            }
        } finally {
            doc.Unfreeze()
            ctrl.IsHighlighting := false
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0) ; Forces Windows to clear stale selection pixels
            CodeBox.Emit("OnHighlight", ctrl)
        }
        
        if force
            this.StartChunking(ctrl)
    }

    ; ====================================================================================
    ; 3. ASYNCHRONOUS COOPERATIVE CHUNKING (Silently processes off-screen text while idle)
    ; ====================================================================================
    static StartChunking(ctrl) {
        hwnd := ctrl.Hwnd
        if !this._ChunkTimers.Has(hwnd)
            this._ChunkTimers[hwnd] := ObjBindMethod(this, "ProcessChunk", ctrl)
            
        ctrl.ChunkPos := 0
        SetTimer(this._ChunkTimers[hwnd], 50)
    }

    static ProcessChunk(ctrl) {
        hwnd := ctrl.Hwnd
        if !DllCall("IsWindow", "Ptr", hwnd) {
            SetTimer(this._ChunkTimers[hwnd], 0)
            return
        }

        ; Yield aggressively to the OS thread if the user starts interacting in ANY way
        if (GetKeyState("LButton", "P") || GetKeyState("Shift", "P") || GetKeyState("Up", "P") || GetKeyState("Down", "P") || GetKeyState("Left", "P") || GetKeyState("Right", "P")) {
            return
        }

        if (ctrl.HasProp("IsHighlighting") && ctrl.IsHighlighting)
            return

        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if (totalLen <= 0 || !ctrl.HasProp("ChunkPos") || ctrl.ChunkPos >= totalLen) {
            SetTimer(this._ChunkTimers[hwnd], 0)
            return
        }

        doc := this.GetITextDocument(hwnd)
        if !doc {
            SetTimer(this._ChunkTimers[hwnd], 0)
            return
        }

        chunkSize := 10000
        startChar := ctrl.ChunkPos
        endChar := Min(startChar + chunkSize, totalLen)

        ; Intelligent Skip: Do not re-parse the chunk if it already sits inside the formatted Viewport
        if (ctrl.HasProp("LastHighlightStart") && ctrl.HasProp("LastHighlightEnd")) {
            if (endChar > ctrl.LastHighlightStart && startChar < ctrl.LastHighlightEnd) {
                ctrl.ChunkPos := ctrl.LastHighlightEnd
                return
            }
        }

        ctrl.IsHighlighting := true

        try {
            lookback := 15000
            fetchStart := Max(0, startChar - lookback)
            chunkText := CodeBox._GetTextRange(hwnd, fetchStart, endChar)
            chunkText := StrReplace(chunkText, "`r", "`n")

            themeC := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
            rules := CodeBox.Syntaxes.Has(StrLower(ctrl.CodeBoxLang)) ? CodeBox.Syntaxes[StrLower(ctrl.CodeBoxLang)] : []
            
            defColorBGR := this.RGBtoBGR(themeC["Foreground"])
            bgBGR := this.RGBtoBGR(themeC["Background"])

            doc.Freeze()
            rng := doc.Range(startChar, endChar)
            rng.Font.ForeColor := defColorBGR
            rng.Font.BackColor := bgBGR ; Strips formatting carried over from pasted RTF
            rng.Font.Bold := 0
            rng.Font.Underline := 0

            for rule in rules {
                pos := 1
                colorBGR := this.RGBtoBGR(themeC.Has(rule.c) ? themeC[rule.c] : themeC["Foreground"])
                b := rule.HasOwnProp("b") && rule.b ? -1 : 0
                u := rule.HasOwnProp("u") ? rule.u : 0
                isDefaultColor := (colorBGR == defColorBGR)

                while (match := RegExMatch(chunkText, rule.p, &m, pos)) {
                    if (m.Len[0] == 0) {
                        pos := match + 1
                        continue
                    }
                    
                    globalStart := fetchStart + match - 1
                    globalEnd := globalStart + m.Len[0]
                    
                    if (globalEnd > startChar && globalStart < endChar) {
                        mRng := doc.Range(Max(startChar, globalStart), Min(endChar, globalEnd))
                        if !isDefaultColor
                            mRng.Font.ForeColor := colorBGR
                        if b
                            mRng.Font.Bold := b
                        if u
                            mRng.Font.Underline := u
                    }
                    pos := match + m.Len[0]
                }
            }
        } finally {
            doc.Unfreeze()
            ctrl.IsHighlighting := false
            ctrl.ChunkPos := endChar
        }
    }
}