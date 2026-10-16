#Include "HotkeySettings.ahk"
#Include "ColorPicker.ahk"

class ColorSettingsGui extends HotkeySettingsGui {
    InitColorPickers() {
        this.colorFields := []
        this.colorRefreshTimer := ObjBindMethod(this, "RefreshColorPickers")
        for name in ["DisableFromGroupsColor", "QuickGroupColor"]
            this.AddColorPicker(name, "Thumbnails Interactions")
        for name in ["ThumbnailTextColor", "ClientHighligtColor", "InactiveClientBorderColor", "ThumbnailBackgroundColor"]
            this.AddColorPicker(name, "Thumbnails Visuals")
        for event in this.monitoredEventsTexts
            this.AddColorPicker("C" event, "Monitored Events")
        for name in ["CBorderColor", "CTextColor", "IABorderColor"]
            this.AddColorPicker(name, "Custom Colors", true)
        this.MainFrame["ShowAllBorders"].OnEvent("Click", (*) => this.RefreshColorPickers())
        this.RefreshColorPickers()
    }

    AddColorPicker(name, group, multiline := false) {
        field := this.MainFrame[name]
        if multiline {
            field.GetPos(&x, &y, &w, &h)
            field.Move(,, w - 30)
            picker := this.MainFrame.Add("Button", Format("x{} y{} w26 h26", x + w - 26, y - 1), Chr(0x2026))
            this.MainFrame.Group[group].Push(picker)
            picker.Visible := field.Visible
        } else
            picker := this.MainFrame["Preview" name]
        helper := {field: field, picker: picker, multiline: multiline}
        picker.ToolTip := multiline ? "Choose a color for the selected line (click that line first)." : "Choose a color."
        picker.OnEvent("Click", (*) => this.PickSettingsColor(helper))
        field.OnEvent("Change", (*) => this.ScheduleColorPickers())
        this.colorFields.Push(helper)
    }

    ScheduleColorPickers(*) {
        if this.HasOwnProp("colorRefreshTimer")
            SetTimer(this.colorRefreshTimer, -100)
    }

    RefreshColorPickers(*) {
        if !this.HasOwnProp("colorFields")
            return
        for helper in this.colorFields
            helper.picker.Enabled := helper.field.Enabled
    }

    StopColorPickers() {
        if this.HasOwnProp("colorRefreshTimer")
            SetTimer(this.colorRefreshTimer, 0)
    }

    PickSettingsColor(helper) {
        if !helper.field.Enabled
            return
        this.CancelHotkeyRecording()
        row := 1
        value := helper.field.Value
        if helper.multiline {
            start := Buffer(4, 0)
            SendMessage(0xB0, start.Ptr, 0, helper.field) ; EM_GETSEL
            row := SendMessage(0xC9, NumGet(start, 0, "UInt"), 0, helper.field) + 1
            lines := StrSplit(value, "`n", "`r")
            value := row <= lines.Length ? lines[row] : ""
            value := RegExReplace(value, ".*:\s*", "") ; Numbered custom-color rows.
        }
        try color := this.OpenSettingsColorDialog(ColorPicker.Normalize(value))
        catch as err {
            MsgBox(err.Message "`n" err.Extra, "Color picker", "Icon! Owner" this.S_Gui.Hwnd)
            return
        }
        if color = ""
            return
        if helper.multiline {
            lines := StrSplit(helper.field.Value, "`n", "`r")
            line := row <= lines.Length ? lines[row] : ""
            prefix := RegExMatch(line, "^(.*:\s*)", &m) ? m[1] : ""
            helper.field.Value := HotkeyBindings.ReplaceLine(helper.field.Value, row, prefix color)
        } else
            helper.field.Value := color
        id := DllCall("GetDlgCtrlID", "Ptr", helper.field.Hwnd, "Int")
        PostMessage(0x111, (0x300 << 16) | (id & 0xFFFF), helper.field.Hwnd,, "ahk_id " helper.field.Gui.Hwnd)
        helper.field.Focus()
        this.ScheduleColorPickers()
    }

    OpenSettingsColorDialog(initial) => ColorPicker.Show(this.S_Gui.Hwnd, initial)
}
