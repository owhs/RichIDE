# CodeBox RichIDE

CodeBox is an advanced, modular, event-driven Rich Text Editor control for AutoHotkey v2. It provides a comprehensive, IDE-like experience directly inside your AHK GUIs, completely powered by a flexible plugin architecture.

## Features at a Glance
- Syntax Highlighting for multiple languages (AHK, JS, Python, C#, HTML, XML, CSS, etc.)
- Theme Support (Dark/Light mode with easy color extensibility)
- Line Numbers & Gutter
- Code Folding
- Auto-completion & Smart Typing
- Zoom & Custom Scrollbar support
- Custom Context Menus & Clipboard management
- History tracking (Undo/Redo)
- Export to HTML

## Usage

Integrating CodeBox into your AutoHotkey v2 project is incredibly straightforward.

1. **Include CodeBox and Plugins:** Include the core library, the data module, and any plugins you wish to use.
2. **Register Plugins:** Before initializing CodeBox, register your included plugins using `CodeBox.RegisterPlugin()`.
3. **Add the Control:** Call `CodeBox.Add(guiObj, options, text, language, theme)` to embed the editor into your GUI.

### Example Setup

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

; Include Core
#Include "%A_ScriptDir%\lib\CodeBox.ahk"
#Include "%A_ScriptDir%\lib\CodeBox_Data.ahk"

; Include desired plugins
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_Highlighter.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_LineNumbers.ahk"
#Include "%A_ScriptDir%\lib\Plugins\CodeBox_SmartTyping.ahk"
; ... include others as needed

; Register Plugins
CodeBox.RegisterPlugin("Highlighter", CodeBox_Highlighter)
CodeBox.RegisterPlugin("LineNumbers", CodeBox_LineNumbers)
CodeBox.RegisterPlugin("SmartTyping", CodeBox_SmartTyping)

; Create GUI and Add CodeBox
MyGui := Gui("+Resize", "My IDE")
MyGui.BackColor := "1E1E1E"

box := CodeBox.Add(MyGui, "x10 y10 w800 h600", "MsgBox('Hello World!')", "ahk2", "Dark")

MyGui.Show("w820 h620")
```

## Existing Plugins Functionality

CodeBox's power comes entirely from its plugins. The core is extremely lightweight. Below is the functionality provided by the existing plugin suite:

*   **`CodeBox_Highlighter`**: The core syntax highlighting engine. Parses code using Regular Expressions defined in `CodeBox_Data.ahk` and colorizes the rich text control asynchronously to avoid UI blocking.
*   **`CodeBox_Theming`**: Manages the application of color palettes across the main editor, line numbers, and other UI elements.
*   **`CodeBox_Selection`**: Enhances text selection, handling visual highlights for double-clicks, line selection, and ensuring smooth rendering during drag operations.
*   **`CodeBox_Scrollbars`**: Replaces the native Windows scrollbars with custom, theme-aware, smooth-scrolling scrollbars that seamlessly integrate into the editor UI.
*   **`CodeBox_LineNumbers`**: Injects a gutter to the left of the editor, accurately computing text wrapping and zooming to display synchronized line numbers.
*   **`CodeBox_Folding`**: Enables collapsing and expanding of code blocks (e.g., classes, functions, or brace-enclosed regions) by clicking in the gutter or using keyboard shortcuts.
*   **`CodeBox_History`**: A robust Undo/Redo stack that saves editor states (text and selection ranges) intelligently, completely replacing the standard Windows rich edit history.
*   **`CodeBox_FindReplace`**: An advanced, theme-aware floating Find & Replace dialog triggered via `Ctrl+F` and `Ctrl+H`. Supports standard literal search and powerful Regular Expression (regex) pattern matching across multiple lines. Features real-time syntax previewing (which automatically toggles read-only states in the editor during search previewing), support for escaped characters (`\n`, `\t`, `\r`, `\\`, `\$`), and robust regex capture group replacement variables (`$0` for the full match, and `$1` to `$99` for sub-pattern references).
*   **`CodeBox_BracketMatcher`**: A premium matching brace/bracket/parenthesis visual highlighter that improves nest statement readability on caret movements. Uses state-aware scanning to skip string literals and comment blocks across all supported languages, employs targeted `CHARFORMAT2` background and bold masking to preserve syntax highlighting foreground colors, and integrates seamlessly with light, dark, Hacker, and Matrix themes.
*   **`CodeBox_Suggest`**: Auto-complete and suggestion popup engine. Listens to typed characters and displays relevant keywords or variable names based on the current context.
*   **`CodeBox_Beautify`**: A code formatter/beautifier that standardizes indentation, spacing, and bracket placement for supported languages.
*   **`CodeBox_HexView`**: A toggleable overlay mode that displays the raw hexadecimal representation of the document's characters.
*   **`CodeBox_ExportHTML`**: Converts the current syntax-highlighted code into a formatted HTML string (and copies it to the clipboard) preserving colors and fonts for web display.
*   **`CodeBox_SmartTyping`**: Provides quality-of-life IDE features like auto-closing brackets (`{` auto-inserts `}`), auto-indentation on new lines, and smart deletion.
*   **`CodeBox_ClipboardManager`**: Overrides native copy, cut, and paste to handle rich text stripping, multi-line pasting, and interacting with the system clipboard securely.
*   **`CodeBox_ContextMenu`**: Provides a custom, theme-aware right-click menu tailored for coding (Cut, Copy, Paste, Format, Export, etc.) replacing the default system menu.
*   **`CodeBox_MarkdownView`**: A robust, JavaScript-free toggleable preview window that perfectly renders Markdown (with table support) and dynamically injects your IDE theme colors into the CSS.
*   **`CodeBox_PluginManager`**: An embedded UI tool (accessible via menu or toolbar) that allows users to toggle plugins on and off instantly at runtime without restarting the application.

## Plugin Architecture & Making Plugins

CodeBox uses a highly modular, event-driven architecture. Instead of the core editor explicitly calling plugin methods, it broadcasts **Events** using `CodeBox.Emit()` and delegates specific commands using `CodeBox.Invoke()`.

This makes developing new plugins incredibly simple: you define a class with appropriately named static methods, register it, and the core will automatically call your hooks at the right time.

### Hooking (Available Event Hooks)

If your plugin class contains any of these static methods, they will be automatically invoked by the CodeBox event loop.

#### Lifecycle Events
- **`OnInit()`**: Called once when the entire CodeBox framework is first initialized.
- **`OnControlCreated(ctrl)`**: Called every time a new CodeBox control is added to a GUI.
- **`OnLanguageChange(ctrl)`**: Triggered when `ctrl.Language` is updated.
- **`OnThemeChange(ctrl)`**: Triggered when `ctrl.Theme` is updated.
- **`OnHighlight(ctrl)`**: Emitted *after* the text has been completely syntax-highlighted.
- **`OnDestroy(ctrl)`**: Emitted right before the control is destroyed. Use this to clean up timers and GUIs.
- **`OnShowWindow(ctrl, wParam)`**: Emitted when the control's visibility is toggled.
- **`OnWindowPosChanged(ctrl)`**: Emitted when the control's size or position is updated.
- **`OnRegisterMenu(ctrl, fileMenu, editMenu, viewMenu, toolsMenu)`**: Emitted on setup, allowing plugins to inject their own menu items into the IDE's menu bar.
- **`OnRegisterUI(ctrl, guiObj, &x, &y, maxW)`**: Emitted on setup, allowing plugins to add toolbar icons or other GUI elements.

#### User Interaction Events
To prevent the core CodeBox from continuing to process an input event, simply return `1` (or any truthy value) from your hook.

- **`OnKeyDown(ctrl, wParam)`**: Fired when a key is pressed. (e.g., intercept `wParam == 90` for `Ctrl+Z` Undo). Return `1` to consume.
- **`OnChar(ctrl, wParam)`**: Fired when a character is typed. Perfect for auto-closing braces. Return `1` to consume.
- **`OnChange(ctrl)`**: Fired when the text content changes (debounced by default).
- **`OnSelectionChange(ctrl)`**: Emitted when the user selects text or moves the caret position.
- **`OnScroll(ctrl)`**: Fired during vertical/horizontal scrolling or mouse wheel usage. 
- **`OnZoom(ctrl, pct)`**: Emitted when the user zooms in or out of the editor.
- **`OnSuggestCheck(ctrl)`**: Emitted when the user types a character and the auto-suggest engine should evaluate the context.
- **`OnSuggestHide(ctrl)`**: Emitted when the auto-suggest window should be closed.
- **`OnContextMenu(ctrl, x, y)`**: Emitted when the user right-clicks.
- **`OnLButtonDown(ctrl, wParam, lParam, isSubCtrl, hwnd)`**: Emitted on left click down.
- **`OnLButtonUp(ctrl, wParam, lParam, isSubCtrl, hwnd)`**: Emitted on left click up.
- **`OnMouseMove(ctrl, wParam, lParam, isSubCtrl, hwnd)`**: Emitted when the mouse moves.
- **`OnSetCursor(ctrl, wParam, lParam, isSubCtrl, hwnd)`**: Emitted when the cursor is updated.

#### Data Manipulation Commands (Invoke)
Some commands are single-target. `CodeBox.Invoke()` will stop at the first plugin that implements the method and return its result.
- **`PushHistory(ctrl, action, text, startSel, endSel)`**: Instructs the history engine to save the state.
- **`Undo(ctrl)`** / **`Redo(ctrl)`**: Triggers a history state reversion.
- **`ToggleFoldLine(ctrl, lineIdx)`**: Instructs the folding engine to toggle the block at `lineIdx`.
- **`Format(ctrl)`**: Triggers the Beautify engine.
- **`ToggleHexView(ctrl, state)`**: Triggers the HexView overlay mode.
- **`ExportHTML(ctrl)`**: Triggers the ExportHTML plugin to serialize the document.

### Example: Creating a Custom Plugin

Here is an example of a simple plugin that intercepts `Ctrl+S` to save the file and blocks the keystroke from reaching the editor:

```ahk
class CodeBox_AutoSave {
    static OnKeyDown(ctrl, wParam) {
        ; 83 is the 'S' key. Check if Ctrl is held down.
        if (wParam == 83 && GetKeyState("Ctrl", "P")) {
            text := CodeBox._GetText(ctrl)
            FileAppend(text, "C:\backup.txt")
            ToolTip("Saved!")
            SetTimer(() => ToolTip(), -2000)
            
            ; Return 1 to tell the core that we handled this key, 
            ; preventing further processing.
            return 1
        }
        return 0
    }
}
```

Simply include this file and call `CodeBox.RegisterPlugin("AutoSave", CodeBox_AutoSave)` before adding your CodeBox control!
