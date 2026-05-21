# CodeBox IDE Keyboard Shortcuts

This document lists all of the powerful keyboard shortcuts built natively into the RichIDE plugins.

## General Editing & Smart Typing
- `Tab`: Smart Indent (or multi-line indent if text is selected).
- `Shift+Tab`: Multi-line Unindent.
- `Enter`: Smart Auto-Indent based on language semantics.
- `Backspace`: Smart Auto-Close deletion (automatically deletes matching trailing brace/quote).
- `Ctrl + /`: Toggle Line Comment (dynamically uses `//`, `;`, `#`, `--`, `::`, or `<!--` based on the active language).
- `Ctrl + Shift + /`: Toggle Block Comment.

## Code Folding
- `Ctrl + M`: Toggle folding for the current line / block.
- `Ctrl + Shift + [`: Fold the current block (even if cursor is inside it).
- `Ctrl + Shift + ]`: Unfold the current block.
- `Ctrl + 1` through `Ctrl + 0`: Instantly fold all blocks globally at depth 1 through 10.

## Formatter & Beautifier
- `Ctrl + Shift + F`: Run the intelligent code beautifier to auto-format your code based on language semantics.

## History & Undo
- `Ctrl + Z`: Undo (natively restores exact fold states and selection without jumpiness).
- `Ctrl + Y`: Redo.

## Search & Replace
- `Ctrl + F`: Open Find Bar.
- `Ctrl + H`: Open Replace Bar.
- `F3`: Find Next Match.
- `Shift + F3`: Find Previous Match.

## Clipboard
- `Ctrl + C`: Smart Copy (optionally excludes folded text from being copied).
- `Ctrl + X`: Smart Cut.

## Markdown
- `Ctrl + K`: Toggle rich Markdown Preview View (only works when syntax is set to `md`).
