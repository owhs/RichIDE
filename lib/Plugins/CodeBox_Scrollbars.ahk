class CodeBox_Scrollbars {
    static OnControlCreated(ctrl) {
        global CodeBox
        guiObj := ctrl.Gui
        if !guiObj {
            hParent := DllCall("GetParent", "Ptr", ctrl.Hwnd, "Ptr")
            guiObj := GuiFromHwnd(hParent)
        }

        ; Keep scrollbar styles fully intact so Windows natively calculates ranges and zoom perfectly.
        ; SetWindowRgn will be used to crop them out visually with zero flickering.

        ctrl.ScrollWidth := 14

        ; Expand the internal RichEdit margin so text mathematically CANNOT hide under our ghost track
        rightMargin := ctrl.ScrollWidth + 5
        SendMessage(0x00D3, 3, 5 | (rightMargin << 16), ctrl.Hwnd) ; EM_SETMARGINS

        ; Spawn pure AutoHotkey overlay controls (+0x0100 is SS_NOTIFY to capture mouse hooks natively)
        ctrl.ScrollTrack := guiObj.Add("Text", "Hidden +0x0100 -E0x200")
        ctrl.ScrollThumb := guiObj.Add("Text", "Hidden +0x0100 -E0x200")
        ctrl.HScrollTrack := guiObj.Add("Text", "Hidden +0x0100 -E0x200")
        ctrl.HScrollThumb := guiObj.Add("Text", "Hidden +0x0100 -E0x200")

        ; Hook directly into CodeBox internal message engine so custom Mouse hooks work flawlessly
        CodeBox._SubCtrls[ctrl.ScrollTrack.Hwnd] := ctrl
        CodeBox._SubCtrls[ctrl.ScrollThumb.Hwnd] := ctrl
        CodeBox._SubCtrls[ctrl.HScrollTrack.Hwnd] := ctrl
        CodeBox._SubCtrls[ctrl.HScrollThumb.Hwnd] := ctrl

        ctrl.IsScrollThumbDragging := false
        ctrl.IsScrollThumbHovered := false
        ctrl.IsHScrollThumbDragging := false
        ctrl.IsHScrollThumbHovered := false

        ; Inject our math directly into bounds resizing wrapper
        if !ctrl.HasProp("origUpdateBounds_SB") {
            ctrl.origUpdateBounds_SB := ctrl.GetOwnPropDesc("UpdateBounds").call
            ctrl.DefineProp("UpdateBounds", { call: (c, px := "", py := "", pw := "", ph := "") => (
                c.origUpdateBounds_SB(px, py, pw, ph),
                CodeBox_Scrollbars.UpdateScrollbar(c)
            ) })
        }

        ; User request: Standalone God Tier programmatic scroll callers
        ctrl.DefineProp("ScrollToLine", { call: (c, lineIdx, smooth := true) => CodeBox_Scrollbars.ScrollToLine(c, lineIdx, smooth) })
        ctrl.DefineProp("ScrollTo", { call: (c, yPos) => CodeBox_Scrollbars.SetScrollPos(c, -1, yPos) })

        this.OnThemeChange(ctrl)
    }

    static OnEnable(ctrl) {
        if ctrl.HasProp("ScrollTrack") {
            ctrl.ScrollTrack.Visible := true, ctrl.ScrollThumb.Visible := true
            ctrl.HScrollTrack.Visible := true, ctrl.HScrollThumb.Visible := true
        }
        this.UpdateScrollbar(ctrl)
    }

    static OnDisable(ctrl) {
        if ctrl.HasProp("ScrollTrack") {
            ctrl.ScrollTrack.Visible := false, ctrl.ScrollThumb.Visible := false
            ctrl.HScrollTrack.Visible := false, ctrl.HScrollThumb.Visible := false
        }
    }

    static OnShowWindow(ctrl, wParam) {
        if ctrl.HasProp("ScrollTrack") {
            visible := wParam ? true : false
            if (!visible) {
                ctrl.ScrollTrack.Visible := false
                ctrl.ScrollThumb.Visible := false
                ctrl.HScrollTrack.Visible := false
                ctrl.HScrollThumb.Visible := false
            } else {
                this.UpdateScrollbar(ctrl)
            }
        }
    }

    static OnWindowPosChanged(ctrl) {
        if (ctrl.HasProp("_UpdatingScrollbar") && ctrl._UpdatingScrollbar)
            return
        this.UpdateScrollbar(ctrl)
    }

    static OnThemeChange(ctrl) {
        global CodeBox
        if !ctrl.HasProp("ScrollTrack")
            return

        theme := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? CodeBox.Themes[ctrl.CodeBoxTheme] : CodeBox.Themes["Dark"]
        bg := theme.Has("Background") ? theme["Background"] : 0x1E1E1E
        sel := theme.Has("SelectionBg") ? theme["SelectionBg"] : 0x264F78

        ; THEME INJECTION: The highlight selection matching fix.
        ; We pull the selection highlight color and dynamically blend it directly into the ghost scroll state!
        ctrl.ScrollTrackColor := CodeBox._ColorToHex(this.BlendColor(bg, 0x000000, 0.15))
        ctrl.ScrollThumbColor := CodeBox._ColorToHex(this.BlendColor(bg, 0xFFFFFF, 0.15))
        ctrl.ScrollThumbHoverColor := CodeBox._ColorToHex(this.BlendColor(sel, 0xFFFFFF, 0.20)) ; Selection Color Base Glow
        ctrl.ScrollThumbDragColor := CodeBox._ColorToHex(sel)                                   ; Pure Selection Color Snap

        ctrl.ScrollTrack.Opt("Background" StrReplace(ctrl.ScrollTrackColor, "#", ""))
        ctrl.ScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbColor, "#", ""))
        ctrl.HScrollTrack.Opt("Background" StrReplace(ctrl.ScrollTrackColor, "#", ""))
        ctrl.HScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbColor, "#", ""))
        ctrl.ScrollTrack.Redraw()
        ctrl.ScrollThumb.Redraw()
        ctrl.HScrollTrack.Redraw()
        ctrl.HScrollThumb.Redraw()

        this.UpdateScrollbar(ctrl)
    }

    static BlendColor(c1, c2, factor) {
        r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
        r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
        r := Round(r1 + (r2 - r1) * factor)
        g := Round(g1 + (g2 - g1) * factor)
        b := Round(b1 + (b2 - b1) * factor)
        return (r << 16) | (g << 8) | b
    }

    static OnChange(ctrl) => this.UpdateScrollbar(ctrl)
    static OnScroll(ctrl) => this.UpdateScrollbar(ctrl)
    static OnHighlight(ctrl) => this.UpdateScrollbar(ctrl)

    static OnDestroy(ctrl) {
        if ctrl.HasProp("HoverTimer")
            SetTimer(ctrl.HoverTimer, 0)
        if ctrl.HasProp("SmoothScrollTimer")
            SetTimer(ctrl.SmoothScrollTimer, 0)
    }

    static GetMaxLineWidth(ctrl) {
        txt := ctrl.Text
        maxLen := 0
        longestLine := ""
        loop parse, txt, "`n", "`r" {
            if (StrLen(A_LoopField) > maxLen) {
                maxLen := StrLen(A_LoopField)
                longestLine := A_LoopField
            }
        }
        if (maxLen == 0)
            return 0
            
        hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
        hFont := DllCall("SendMessage", "Ptr", ctrl.Hwnd, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_GETFONT
        hOldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
        
        size := Buffer(8, 0)
        DllCall("gdi32\GetTextExtentPoint32W", "Ptr", hdc, "Str", longestLine, "Int", StrLen(longestLine), "Ptr", size)
        
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldFont)
        DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)
        
        width := NumGet(size, 0, "Int")
        
        ; Apply RichEdit Zoom Ratio (EM_GETZOOM)
        numVal := Buffer(4, 0), denVal := Buffer(4, 0)
        if DllCall("SendMessage", "Ptr", ctrl.Hwnd, "UInt", 0x04E0, "Ptr", numVal.Ptr, "Ptr", denVal.Ptr) {
            zoomNum := NumGet(numVal, 0, "Int")
            zoomDen := NumGet(denVal, 0, "Int")
            if (zoomNum > 0 && zoomDen > 0)
                width := (width * zoomNum) // zoomDen
        }
        
        return width
    }

    static UpdateScrollbar(ctrl) {
        global CodeBox
        if (!ctrl.HasProp("ScrollTrack") || !CodeBox.IsPluginEnabled("Scrollbars"))
            return
 
        ; Re-entrancy guard: ShowScrollBar triggers non-client recalc which can fire scroll events
        if (ctrl.HasProp("_UpdatingScrollbar") && ctrl._UpdatingScrollbar)
            return
        ctrl._UpdatingScrollbar := true
 
        ctrl.GetPos(&cx, &cy, &cw, &ch)
 
        ; --- Retrieve Vertical Scroll Info ---
        siMainV := Buffer(28, 0), NumPut("UInt", 28, siMainV, 0), NumPut("UInt", 0x17, siMainV, 4)
        if DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 1, "Ptr", siMainV) {
            vMax := NumGet(siMainV, 12, "Int")
            vPage := NumGet(siMainV, 16, "UInt")
            sY := NumGet(siMainV, 20, "Int")
        } else {
            vMax := 0, vPage := 100, sY := 0
        }
 
        ; --- Retrieve Horizontal Scroll Info ---
        siMainH := Buffer(28, 0), NumPut("UInt", 28, siMainH, 0), NumPut("UInt", 0x17, siMainH, 4)
        if DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 0, "Ptr", siMainH) {
            hMax := NumGet(siMainH, 12, "Int")
            hPage := NumGet(siMainH, 16, "UInt")
            sX := NumGet(siMainH, 20, "Int")
        } else {
            hMax := 0, hPage := 100, sX := 0
        }
 
        maxLineWidth := this.GetMaxLineWidth(ctrl)
        showH := (!ctrl._WordWrap && maxLineWidth > (cw - 25))
        showV := (vMax > vPage && vPage > 0)
 
        sw := ctrl.ScrollWidth
        tx := cx + cw - sw
        ty := cy
        th := ch - (showH ? sw : 0)
 
        hx := cx
        hy := cy + ch - sw
        hw := cw - (showV ? sw : 0)
        hh := sw
 
        ; ---------------- VERTICAL ----------------
        if (!showV) {
            if ctrl.ScrollTrack.Visible {
                ctrl.ScrollTrack.Visible := false
                ctrl.ScrollThumb.Visible := false
            }
        } else {
            thumbH := Max(35, (vPage / vMax) * th)
            maxScrollY := vMax - vPage
            clampedSy := Min(Max(0, sY), maxScrollY)
 
            thumbY := ty + (clampedSy / maxScrollY) * (th - thumbH)
 
            ctrl.ScrollTrack.GetPos(&currTx, &currTy, &currTw, &currTh)
            if (currTx != tx || currTy != ty || currTw != sw || currTh != th) {
                ctrl.ScrollTrack.Move(tx, ty, sw, th)
                DllCall("SetWindowPos", "Ptr", ctrl.ScrollTrack.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
 
            ctrl.ScrollThumb.GetPos(&currSx, &currSy, &currSw, &currSh)
            if (currSx != tx || Abs(currSy - thumbY) > 0.5 || currSw != sw || Abs(currSh - thumbH) > 0.5) {
                ctrl.ScrollThumb.Move(tx, thumbY, sw, thumbH)
                DllCall("SetWindowPos", "Ptr", ctrl.ScrollThumb.Hwnd, "Ptr", ctrl.ScrollTrack.Hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
 
            if !ctrl.ScrollTrack.Visible {
                ctrl.ScrollTrack.Visible := true
                ctrl.ScrollThumb.Visible := true
            }
        }
 
        ; ---------------- HORIZONTAL ----------------
        if (!showH) {
            if ctrl.HScrollTrack.Visible {
                ctrl.HScrollTrack.Visible := false
                ctrl.HScrollThumb.Visible := false
            }
        } else {
            thumbW := Max(35, (hPage / hMax) * hw)
            maxScrollX := hMax - hPage
            clampedSx := Min(Max(0, sX), maxScrollX)
 
            thumbX := hx + (clampedSx / maxScrollX) * (hw - thumbW)
 
            ctrl.HScrollTrack.GetPos(&currHx, &currHy, &currHw, &currHh)
            if (currHx != hx || currHy != hy || currHw != hw || currHh != hh) {
                ctrl.HScrollTrack.Move(hx, hy, hw, hh)
                DllCall("SetWindowPos", "Ptr", ctrl.HScrollTrack.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
 
            ctrl.HScrollThumb.GetPos(&currHTx, &currHTy, &currHTw, &currHTh)
            if (Abs(currHTx - thumbX) > 0.5 || currHTy != hy || Abs(currHTw - thumbW) > 0.5 || currHTh != hh) {
                ctrl.HScrollThumb.Move(thumbX, hy, thumbW, hh)
                DllCall("SetWindowPos", "Ptr", ctrl.HScrollThumb.Hwnd, "Ptr", ctrl.HScrollTrack.Hwnd, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            }
 
            if !ctrl.HScrollTrack.Visible {
                ctrl.HScrollTrack.Visible := true
                ctrl.HScrollThumb.Visible := true
            }
        }
        
        ; Dynamic Win32 region clipping to completely crop out the native scrollbars.
        ; The native scrollbars are 17px tall/wide. By setting the window region to exclude
        ; the bottom 17px and right 17px when shown, they are physically cropped and 
        ; 100% invisible, yet fully computed and functional underneath!
        clipW := showV ? cw - 17 : cw
        clipH := showH ? ch - 17 : ch
        
        if (!ctrl.HasProp("_PrevClipW") || !ctrl.HasProp("_PrevClipH") || ctrl._PrevClipW != clipW || ctrl._PrevClipH != clipH) {
            ctrl._PrevClipW := clipW
            ctrl._PrevClipH := clipH
            hRgn := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0, "Int", clipW, "Int", clipH, "Ptr")
            DllCall("user32\SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", hRgn, "Int", 1)
        }

        ctrl._UpdatingScrollbar := false
    }

    static OnLButtonDown(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        global CodeBox
        if (!isSubCtrl || !CodeBox.IsPluginEnabled("Scrollbars"))
            return 0

        if (hwnd == ctrl.ScrollThumb.Hwnd) {
            if ctrl.HasProp("SmoothScrollTimer")
                SetTimer(ctrl.SmoothScrollTimer, 0)

            DllCall("SetCapture", "Ptr", hwnd) ; Hardware state capture lock
            ctrl.IsScrollThumbDragging := true

            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            ctrl.DragStartY := NumGet(pt, 4, "Int")

            sp := Buffer(8, 0)
            SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)
            ctrl.DragStartScrollY := NumGet(sp, 4, "Int")

            ctrl.ScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbDragColor, "#", ""))
            ctrl.ScrollThumb.Redraw()
            return 1

        } else if (hwnd == ctrl.ScrollTrack.Hwnd) {
            ; Track clicks calculate ratio offsets directly into the native block
            y := (lParam >> 16) & 0xFFFF
            ctrl.ScrollTrack.GetPos(, , &tw, &th)
            ctrl.ScrollThumb.GetPos(, , , &thH)

            totalH := this.GetTotalHeight(ctrl)
            ctrl.GetPos(, , &cw, &ch)

            clickYRatio := (y - (thH / 2)) / (th - thH)
            clickYRatio := Max(0, Min(1, clickYRatio))

            this.SetScrollPos(ctrl, -1, clickYRatio * (totalH - ch))
            this.UpdateScrollbar(ctrl)

            ; Auto trigger drag lock on track jump
            DllCall("SetCapture", "Ptr", ctrl.ScrollThumb.Hwnd)
            ctrl.IsScrollThumbDragging := true

            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            ctrl.DragStartY := NumGet(pt, 4, "Int")

            sp := Buffer(8, 0)
            SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)
            ctrl.DragStartScrollY := NumGet(sp, 4, "Int")

            ctrl.ScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbDragColor, "#", ""))
            ctrl.ScrollThumb.Redraw()
            return 1
        } else if (hwnd == ctrl.HScrollThumb.Hwnd) {
            DllCall("SetCapture", "Ptr", hwnd)
            ctrl.IsHScrollThumbDragging := true

            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            ctrl.DragStartX := NumGet(pt, 0, "Int")

            sp := Buffer(8, 0)
            SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)
            ctrl.DragStartScrollX := NumGet(sp, 0, "Int")

            ctrl.HScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbDragColor, "#", ""))
            ctrl.HScrollThumb.Redraw()
            return 1

        } else if (hwnd == ctrl.HScrollTrack.Hwnd) {
            x := lParam & 0xFFFF
            ctrl.HScrollTrack.GetPos(, , &tw, &th)
            ctrl.HScrollThumb.GetPos(, , &twW, &thH)

            siMainH := Buffer(28, 0), NumPut("UInt", 28, siMainH, 0), NumPut("UInt", 0x17, siMainH, 4)
            DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 0, "Ptr", siMainH)
            hMax := NumGet(siMainH, 12, "Int")
            hPage := NumGet(siMainH, 16, "UInt")

            clickXRatio := (x - (twW / 2)) / Max(1, tw - twW)
            clickXRatio := Max(0, Min(1, clickXRatio))

            this.SetScrollPos(ctrl, clickXRatio * Max(1, hMax - hPage), -1)
            this.UpdateScrollbar(ctrl)

            DllCall("SetCapture", "Ptr", ctrl.HScrollThumb.Hwnd)
            ctrl.IsHScrollThumbDragging := true

            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            ctrl.DragStartX := NumGet(pt, 0, "Int")

            sp := Buffer(8, 0)
            SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)
            ctrl.DragStartScrollX := NumGet(sp, 0, "Int")

            ctrl.HScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbDragColor, "#", ""))
            ctrl.HScrollThumb.Redraw()
            return 1
        }
        return 0
    }

    static OnLButtonUp(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        if (ctrl.HasProp("IsScrollThumbDragging") && ctrl.IsScrollThumbDragging) {
            DllCall("ReleaseCapture")
            ctrl.IsScrollThumbDragging := false

            color := (ctrl.HasProp("IsScrollThumbHovered") && ctrl.IsScrollThumbHovered)
                ? ctrl.ScrollThumbHoverColor : ctrl.ScrollThumbColor

            ctrl.ScrollThumb.Opt("Background" StrReplace(color, "#", ""))
            ctrl.ScrollThumb.Redraw()
            return 1
        }
        if (ctrl.HasProp("IsHScrollThumbDragging") && ctrl.IsHScrollThumbDragging) {
            DllCall("ReleaseCapture")
            ctrl.IsHScrollThumbDragging := false

            color := (ctrl.HasProp("IsHScrollThumbHovered") && ctrl.IsHScrollThumbHovered)
                ? ctrl.ScrollThumbHoverColor : ctrl.ScrollThumbColor

            ctrl.HScrollThumb.Opt("Background" StrReplace(color, "#", ""))
            ctrl.HScrollThumb.Redraw()
            return 1
        }
        return 0
    }

    static OnMouseMove(ctrl, wParam, lParam, isSubCtrl, hwnd) {
        global CodeBox
        if (!CodeBox.IsPluginEnabled("Scrollbars"))
            return 0

        if (ctrl.HasProp("IsScrollThumbDragging") && ctrl.IsScrollThumbDragging) {
            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            currentY := NumGet(pt, 4, "Int")

            totalH := this.GetTotalHeight(ctrl)
            ctrl.GetPos(, , &cw, &ch)

            thumbH := Max(35, (ch / totalH) * ch)
            scrollCapacity := totalH - ch
            thumbCapacity := ch - thumbH

            if (thumbCapacity > 0) {
                scrollDelta := ((currentY - ctrl.DragStartY) / thumbCapacity) * scrollCapacity
                this.SetScrollPos(ctrl, -1, ctrl.DragStartScrollY + scrollDelta)
                this.UpdateScrollbar(ctrl)
            }
            return 1
        }
        
        if (ctrl.HasProp("IsHScrollThumbDragging") && ctrl.IsHScrollThumbDragging) {
            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            currentX := NumGet(pt, 0, "Int")

            siMainH := Buffer(28, 0), NumPut("UInt", 28, siMainH, 0), NumPut("UInt", 0x17, siMainH, 4)
            DllCall("GetScrollInfo", "Ptr", ctrl.Hwnd, "Int", 0, "Ptr", siMainH)
            hMax := NumGet(siMainH, 12, "Int")
            hPage := NumGet(siMainH, 16, "UInt")

            ctrl.HScrollTrack.GetPos(, , &tw)
            ctrl.HScrollThumb.GetPos(, , &twW)

            scrollCapacity := hMax - hPage
            thumbCapacity := tw - twW

            if (thumbCapacity > 0) {
                scrollDelta := ((currentX - ctrl.DragStartX) / thumbCapacity) * scrollCapacity
                this.SetScrollPos(ctrl, ctrl.DragStartScrollX + scrollDelta, -1)
                this.UpdateScrollbar(ctrl)
            }
            return 1
        }

        ; Hover check bindings — light up thumb when mouse is over thumb OR track
        if (isSubCtrl && (hwnd == ctrl.ScrollThumb.Hwnd || hwnd == ctrl.ScrollTrack.Hwnd)) {
            if !(ctrl.HasProp("IsScrollThumbHovered") && ctrl.IsScrollThumbHovered) {
                ctrl.IsScrollThumbHovered := true
                ctrl.ScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbHoverColor, "#", ""))
                ctrl.ScrollThumb.Redraw()

                if !ctrl.HasProp("HoverTimer")
                    ctrl.HoverTimer := ObjBindMethod(this, "CheckHover", ctrl)
                SetTimer(ctrl.HoverTimer, 50)
            }
        } else if (isSubCtrl && (hwnd == ctrl.HScrollThumb.Hwnd || hwnd == ctrl.HScrollTrack.Hwnd)) {
            if !(ctrl.HasProp("IsHScrollThumbHovered") && ctrl.IsHScrollThumbHovered) {
                ctrl.IsHScrollThumbHovered := true
                ctrl.HScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbHoverColor, "#", ""))
                ctrl.HScrollThumb.Redraw()

                if !ctrl.HasProp("HoverTimerH")
                    ctrl.HoverTimerH := ObjBindMethod(this, "CheckHoverH", ctrl)
                SetTimer(ctrl.HoverTimerH, 50)
            }
        }
        return 0
    }

    static CheckHover(ctrl) {
        if (!ctrl.HasProp("IsScrollThumbHovered") || !ctrl.IsScrollThumbHovered)
            return

        MouseGetPos(,,, &hwndUnder, 2)

        if (hwndUnder != ctrl.ScrollThumb.Hwnd && hwndUnder != ctrl.ScrollTrack.Hwnd && !ctrl.IsScrollThumbDragging) {
            ctrl.IsScrollThumbHovered := false
            ctrl.ScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbColor, "#", ""))
            ctrl.ScrollThumb.Redraw()
            SetTimer(ctrl.HoverTimer, 0)
        }
    }

    static CheckHoverH(ctrl) {
        if (!ctrl.HasProp("IsHScrollThumbHovered") || !ctrl.IsHScrollThumbHovered)
            return

        MouseGetPos(,,, &hwndUnder, 2)

        if (hwndUnder != ctrl.HScrollThumb.Hwnd && hwndUnder != ctrl.HScrollTrack.Hwnd && !ctrl.IsHScrollThumbDragging) {
            ctrl.IsHScrollThumbHovered := false
            ctrl.HScrollThumb.Opt("Background" StrReplace(ctrl.ScrollThumbColor, "#", ""))
            ctrl.HScrollThumb.Redraw()
            SetTimer(ctrl.HoverTimerH, 0)
        }
    }

    static SetScrollPos(ctrl, x, y) {
        global CodeBox
        pt := Buffer(8, 0)
        SendMessage(0x04DD, 0, pt.Ptr, ctrl.Hwnd) ; EM_GETSCROLLPOS

        if (x != -1)
            NumPut("Int", x, pt, 0)
        if (y != -1)
            NumPut("Int", Max(0, y), pt, 4)

        SendMessage(0x04DE, 0, pt.Ptr, ctrl.Hwnd) ; EM_SETSCROLLPOS
        CodeBox.Emit("OnScroll", ctrl)
    }

    ; Programmatic Standalone line jump attached natively to the Codebox UI instance
    static ScrollToLine(ctrl, lineIdx, smooth := true) {
        charIdx := SendMessage(0x00BB, lineIdx - 1, 0, ctrl.Hwnd)
        if (charIdx == -1)
            return

        pt := Buffer(8, 0)
        SendMessage(0x0426, pt.Ptr, charIdx, ctrl.Hwnd) ; EM_POSFROMCHAR

        sp := Buffer(8, 0)
        SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)

        ; Map current offset vs target inner relative offset
        targetY := NumGet(sp, 4, "Int") + NumGet(pt, 4, "Int")

        if (smooth) {
            if ctrl.HasProp("SmoothScrollTimer")
                SetTimer(ctrl.SmoothScrollTimer, 0)

            ctrl.TargetScrollY := targetY
            ctrl.SmoothScrollTimer := ObjBindMethod(this, "ProcessSmoothScroll", ctrl)
            SetTimer(ctrl.SmoothScrollTimer, 16) ; ~60fps step trigger
        } else {
            this.SetScrollPos(ctrl, -1, targetY)
            this.UpdateScrollbar(ctrl)
        }
    }

    static ProcessSmoothScroll(ctrl) {
        sp := Buffer(8, 0)
        SendMessage(0x04DD, 0, sp.Ptr, ctrl.Hwnd)
        currentY := NumGet(sp, 4, "Int")

        diff := ctrl.TargetScrollY - currentY
        if (Abs(diff) < 3) {
            this.SetScrollPos(ctrl, -1, ctrl.TargetScrollY)
            this.UpdateScrollbar(ctrl)
            SetTimer(ctrl.SmoothScrollTimer, 0)
            return
        }

        this.SetScrollPos(ctrl, -1, currentY + (diff * 0.25)) ; 25% smooth lerp slide
        this.UpdateScrollbar(ctrl)
    }
}