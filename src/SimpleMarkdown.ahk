; Small offline Markdown reader using the Windows Rich Edit control.
; Supports ATX headings, bullets, inline bold and inline code; other text is literal.
class SimpleMarkdown {
    static module := 0

    static Add(window, options) {
        if !this.module {
            this.module := DllCall("LoadLibraryW", "Str", "Msftedit.dll", "Ptr")
            if !this.module
                throw OSError()
        }
        ; Multiline, read-only, selectable, word-wrapped and vertically scrollable.
        control := window.AddCustom("ClassRICHEDIT50W +0x210944 +E0x200 " options)
        SendMessage(0x435, 0, 0x7FFFFFFF, control) ; EM_EXLIMITTEXT
        return control
    }

    static SetText(control, markdown) {
        rtf := this.ToRtf(markdown)
        encoded := Buffer(StrPut(rtf, "UTF-8"))
        StrPut(rtf, encoded, "UTF-8")
        settings := Buffer(8, 0)
        NumPut("UInt", 65001, settings, 4) ; SETTEXTEX.codepage = UTF-8
        ; EM_SETTEXTEX recognizes the RTF header and renders the document.
        ; https://learn.microsoft.com/windows/win32/controls/em-settextex
        if !SendMessage(0x461, settings.Ptr, encoded.Ptr, control)
            throw Error("Could not load the Markdown document into the reader.")
        this.ScrollToStart(control)
    }

    static ScrollToStart(control) {
        SendMessage(0xB1, 0, 0, control) ; EM_SETSEL
        SendMessage(0x115, 6, 0, control) ; WM_VSCROLL / SB_TOP
    }

    static ToRtf(markdown) {
        rtf := "{\rtf1\ansi\deff0\uc1{\fonttbl{\f0 Segoe UI;}{\f1 Consolas;}}\viewkind4 "
        lines := StrSplit(StrReplace(markdown, "`r"), "`n")
        for index, line in lines {
            paragraph := "\pard\ql\f0\fs22\sa80 "
            if RegExMatch(line, "^ {0,3}(#{1,6})[ \t]+(.*)$", &heading) {
                size := [40, 34, 28, 25, 23, 22][StrLen(heading[1])]
                paragraph := "\pard\ql\f0\sb180\sa100\keepn\b\fs" size " "
                content := this.Inline(RegExReplace(heading[2], "[ \t]+#+[ \t]*$", ""))
            } else if RegExMatch(line, "^\s*[-*+][ \t]+(.*)$", &bullet) {
                paragraph := "\pard\ql\f0\fs22\li320\fi-220\tx320\sa80 "
                content := "\u8226?\tab " this.Inline(bullet[1])
            } else
                content := this.Inline(line)
            ; Group each paragraph so font/weight never leak to following text.
            rtf .= "{" paragraph content (index < lines.Length ? "\par " : "") "}"
        }
        return rtf "}"
    }

    static Inline(text) {
        result := ""
        position := 1
        ; Code spans take precedence, so Markdown inside code remains literal.
        while found := RegExMatch(text, "``([^``]+)``|\*\*(.+?)\*\*", &match, position) {
            result .= this.Escape(SubStr(text, position, found - position))
            if SubStr(match[0], 1, 1) = "``"
                result .= "{\f1 " this.Escape(match[1]) "}"
            else
                result .= "{\b " this.Escape(match[2]) "}"
            position := found + match.Len
        }
        return result this.Escape(SubStr(text, position))
    }

    static Escape(text) {
        escaped := ""
        utf16 := Buffer(StrPut(text, "UTF-16") * 2)
        StrPut(text, utf16, "UTF-16")
        Loop StrLen(text) {
            unit := NumGet(utf16, (A_Index - 1) * 2, "UShort")
            if unit = 92 || unit = 123 || unit = 125
                escaped .= "\" Chr(unit)
            else if unit = 9
                escaped .= "\tab "
            else if unit > 127
                escaped .= "\u" (unit > 32767 ? unit - 65536 : unit) "?"
            else
                escaped .= Chr(unit)
        }
        return escaped
    }
}
