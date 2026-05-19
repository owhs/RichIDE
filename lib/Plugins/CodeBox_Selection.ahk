class CodeBox_Selection {
    static _HooksInstalled := false
    static _Brushes := Map()
    static _LastActiveCtrl := ""

    static OnInit() {
        if this._HooksInstalled
            return

        hMod := DllCall("GetModuleHandle", "Str", "msftedit.dll", "Ptr")
        if !hMod
            return

        this._OrigGetSysColor := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "USER32.dll", "Ptr"), "AStr", "GetSysColor", "Ptr")
        this._OrigGetSysColorBrush := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "USER32.dll", "Ptr"), "AStr", "GetSysColorBrush", "Ptr")

        this._GetSysColorCB := CallbackCreate(ObjBindMethod(this, "_GetSysColorHook"), "Fast", 1)
        this._GetSysColorBrushCB := CallbackCreate(ObjBindMethod(this, "_GetSysColorBrushHook"), "Fast", 1)

        this._HookIAT(hMod, "GetSysColor", this._GetSysColorCB)
        this._HookIAT(hMod, "GetSysColorBrush", this._GetSysColorBrushCB)
        this._HooksInstalled := true
    }

    static OnEnable(ctrl) {
        this.OnInit()
        this.OnThemeChange(ctrl)
    }
    static OnDisable(ctrl) => this.OnThemeChange(ctrl)

    static RGBtoBGR(rgb) => ((rgb & 0xFF0000) >> 16) | (rgb & 0x00FF00) | ((rgb & 0x0000FF) << 16)

    static _GetActiveCtrl() {
        hwnd := DllCall("GetFocus", "Ptr")
        if CodeBox._Instances.Has(hwnd)
            return CodeBox._Instances[hwnd]
        if CodeBox._SubCtrls.Has(hwnd)
            return CodeBox._SubCtrls[hwnd]

        return this._LastActiveCtrl
    }

    static _GetSysColorHook(nIndex, *) {
        if (!CodeBox.IsPluginEnabled("Selection"))
            return DllCall(this._OrigGetSysColor, "Int", nIndex, "UInt")

        if (nIndex == 13 || nIndex == 14) {
            ctrl := this._GetActiveCtrl()
            if (ctrl) {
                themeName := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? ctrl.CodeBoxTheme : "Dark"
                theme := CodeBox.Themes[themeName]

                if (nIndex == 13 && theme.Has("SelectionBg"))
                    return this.RGBtoBGR(theme["SelectionBg"])
                if (nIndex == 14 && theme.Has("SelectionFg"))
                    return this.RGBtoBGR(theme["SelectionFg"])
            }
        }
        return DllCall(this._OrigGetSysColor, "Int", nIndex, "UInt")
    }

    static _GetSysColorBrushHook(nIndex, *) {
        if (!CodeBox.IsPluginEnabled("Selection"))
            return DllCall(this._OrigGetSysColorBrush, "Int", nIndex, "Ptr")

        if (nIndex == 13 || nIndex == 14) {
            ctrl := this._GetActiveCtrl()
            if (ctrl) {
                themeName := CodeBox.Themes.Has(ctrl.CodeBoxTheme) ? ctrl.CodeBoxTheme : "Dark"
                theme := CodeBox.Themes[themeName]

                colorRGB := (nIndex == 13 && theme.Has("SelectionBg")) ? theme["SelectionBg"] : ((nIndex == 14 && theme.Has("SelectionFg")) ? theme["SelectionFg"] : -1)

                if (colorRGB != -1) {
                    bgr := this.RGBtoBGR(colorRGB)
                    if !this._Brushes.Has(bgr)
                        this._Brushes[bgr] := DllCall("Gdi32.dll\CreateSolidBrush", "UInt", bgr, "Ptr")
                    return this._Brushes[bgr]
                }
            }
        }
        return DllCall(this._OrigGetSysColorBrush, "Int", nIndex, "Ptr")
    }

    static _HookIAT(hModule, targetFunction, hookCallback) {
        if (!hModule)
            return

        dosHeader := hModule
        if (NumGet(dosHeader, 0, "UShort") != 0x5A4D)
            return

        ntHeaders := dosHeader + NumGet(dosHeader, 0x3C, "Int")
        if (NumGet(ntHeaders, 0, "UInt") != 0x4550)
            return

        magic := NumGet(ntHeaders, 24, "UShort")
        importDirOffset := (magic == 0x20B) ? 112 : 96

        this._ProcessImportDescriptor(dosHeader, ntHeaders, importDirOffset, 1, targetFunction, hookCallback, magic)
        this._ProcessImportDescriptor(dosHeader, ntHeaders, importDirOffset, 13, targetFunction, hookCallback, magic)
    }

    static _ProcessImportDescriptor(dosHeader, ntHeaders, importDirOffset, dirIndex, targetFunction, hookCallback, magic) {
        dataDirRVA := NumGet(ntHeaders, 24 + importDirOffset + (dirIndex * 8), "UInt")
        if (!dataDirRVA)
            return

        importDesc := dosHeader + dataDirRVA
        isDelay := (dirIndex == 13)

        while (NumGet(importDesc, isDelay ? 4 : 12, "UInt")) {
            firstThunk := dosHeader + NumGet(importDesc, isDelay ? 12 : 16, "UInt")
            originalFirstThunk := NumGet(importDesc, isDelay ? 16 : 0, "UInt")
            if (!originalFirstThunk)
                originalFirstThunk := NumGet(importDesc, isDelay ? 12 : 16, "UInt")

            origThunk := dosHeader + originalFirstThunk
            ptrSize := A_PtrSize

            while (NumGet(origThunk, 0, "UPtr") != 0) {
                thunkData := NumGet(origThunk, 0, "UPtr")
                isOrdinal := ((thunkData >> ((magic == 0x20B) ? 63 : 31)) & 1)

                if (!isOrdinal) {
                    nameData := dosHeader + (thunkData & ((magic == 0x20B) ? 0x7FFFFFFFFFFFFFFF : 0x7FFFFFFF))
                    if (StrGet(nameData + 2, "UTF-8") == targetFunction) {
                        oldProtect := 0
                        DllCall("VirtualProtect", "Ptr", firstThunk, "Ptr", ptrSize, "UInt", 0x40, "UInt*", &oldProtect)
                        NumPut("UPtr", hookCallback, firstThunk, 0)
                        DllCall("VirtualProtect", "Ptr", firstThunk, "Ptr", ptrSize, "UInt", oldProtect, "UInt*", &oldProtect)
                    }
                }
                origThunk += ptrSize
                firstThunk += ptrSize
            }
            importDesc += isDelay ? 32 : 20
        }
    }

    static OnThemeChange(ctrl) {
        this._LastActiveCtrl := ctrl
        SendMessage(0x0015, 0, 0, ctrl.Hwnd)
        if ctrl.HasProp("LineNumCtrl")
            SendMessage(0x0015, 0, 0, ctrl.LineNumCtrl.Hwnd)
        if ctrl.HasProp("MinimapCtrl")
            SendMessage(0x0015, 0, 0, ctrl.MinimapCtrl.Hwnd)
    }

    static OnDestroy(ctrl) {
        if (this._LastActiveCtrl == ctrl)
            this._LastActiveCtrl := ""
    }
}