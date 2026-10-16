class ColorSettingsFixture extends CombatEventsFixture {
    __New() {
        super.__New()
        this.ProfileOverride()
        this.SetState()
        this.NeedRestart := 0
        this.saves := 0
        this.dialogs := 0
        this.nextColor := ""
        this.Save_Settings_Delay_Timer := (*) => this.saves++
        this.S_Gui := Gui()
        this.CreateMainFrame()
        this.CustomColors_Ctrl()
        this.ThumbnailsInteractions_Ctrl()
        this.ThumbnailsVisuals_Ctrl()
        this.MonitoredEvents_Ctrl()
        this.InitColorPickers()
    }
    OpenSettingsColorDialog(initial) {
        this.dialogs++
        this.initialColor := initial
        return this.nextColor
    }
    Find(name) {
        for helper in this.colorFields
            if helper.field.Name = name
                return helper
        throw Error("Missing color picker: " name)
    }
    ClickPicker(helper) {
        id := DllCall("GetDlgCtrlID", "Ptr", helper.picker.Hwnd, "Int")
        PostMessage(0x111, id & 0xFFFF, helper.picker.Hwnd,, "ahk_id " helper.picker.Gui.Hwnd)
        Sleep(30)
    }
    Dispose() {
        this.StopColorPickers()
        SetTimer(this.Save_Settings_Delay_Timer, 0)
        this.MainFrame.Destroy()
        this.S_Gui.Destroy()
    }
}

TestRunner.Register("Color picker accepts existing Hex and RGB formats without reversing red and blue", ColorPickerFormatsTest)
ColorPickerFormatsTest() {
    for pair in [["#12ab34", "12AB34"], ["0x123456", "123456"], ["123456", "123456"],
        ["255, 0, 16", "FF0010"], ["rgb(12, 34, 56)", "0C2238"], ["0", "000000"],
        [" FF00FF ", "FF00FF"], ["", "FFFFFF"], ["invalid", "FFFFFF"]]
        AssertEqual(pair[2], ColorPicker.Normalize(pair[1]))
    AssertEqual(0x563412, ColorPicker.SwapChannels(0x123456))
    AssertEqual(0xA12B34, ColorPicker.SwapChannels(ColorPicker.SwapChannels(0xA12B34)))
}

TestRunner.Register("Every color field has a clickable swatch or compact list picker within its panel", ColorPickersLayoutTest)
ColorPickersLayoutTest() {
    app := ColorSettingsFixture()
    try {
        AssertEqual(27, app.colorFields.Length)
        for helper in app.colorFields {
            helper.field.GetPos(&x, &y, &w, &h)
            helper.picker.GetPos(&px, &py, &pw, &ph)
            AssertTrue(x + w <= px && px + pw <= app.contentW, helper.field.Name " picker exceeds its row.")
            AssertTrue(helper.picker.ToolTip != "")
            AssertFalse(helper.picker.Visible, "Pickers must start hidden with their settings group.")
            if helper.multiline {
                AssertEqual(26, pw)
                AssertEqual(26, ph)
                AssertEqual(y - 1, py)
                AssertEqual(app.editExW - 30, w)
                found := false
                for control in app.MainFrame.Group["Custom Colors"]
                    if control = helper.picker
                        found := true
                AssertTrue(found, "List pickers must follow group visibility and profile overrides.")
            } else {
                AssertEqual(app.MainFrame["Preview" helper.field.Name], helper.picker)
                AssertTrue(ControlGetStyle(helper.picker) & 0x100, "Clickable Text swatches need SS_NOTIFY.")
            }
        }
        helper := app.Find("InactiveClientBorderColor")
        helper.field.Enabled := false
        app.RefreshColorPickers()
        AssertFalse(helper.picker.Enabled)
        app.PickSettingsColor(helper)
        AssertEqual(0, app.dialogs, "Disabled fields must not open a picker or modify settings.")
        helper.field.Enabled := true
        app.RefreshColorPickers()
        AssertTrue(helper.picker.Enabled)
    } finally {
        app.Dispose()
    }
}

TestRunner.Register("Swatch selections update every scalar and event color through existing saves and survive export", ColorPickerScalarSaveTest)
ColorPickerScalarSaveTest() {
    app := ColorSettingsFixture()
    path := A_Temp "\EVE-X-Preview-picked-colors-" A_TickCount ".json"
    try {
        app.nextColor := "12AB34"
        for helper in app.colorFields {
            if helper.multiline
                continue
            app.ClickPicker(helper)
            AssertEqual("12AB34", helper.field.Value)
            if SubStr(helper.field.Name, 1, 1) = "C" && helper.field.Name != "ClientHighligtColor"
                AssertEqual("12AB34", app.monitoredEvents[SubStr(helper.field.Name, 2)]["color"])
            else
                AssertEqual("12AB34", app.%helper.field.Name%)
        }
        AssertEqual(24, app.dialogs)
        AssertTrue(app.NeedRestart)
        Sleep(220)
        AssertTrue(app.saves > 0, "Picking must trigger the normal delayed save.")
        app.SaveJsonToFile(path)
        AssertDeepEqual(app._JSON, JSON.Load(FileRead(path)))
    } finally {
        app.Dispose()
        if FileExist(path)
            FileDelete(path)
    }
}

TestRunner.Register("Custom color pickers replace only the selected numbered row and preserve blank rows", ColorPickerRowsTest)
ColorPickerRowsTest() {
    app := ColorSettingsFixture()
    try {
        app.nextColor := "A1B2C3"
        for name, property in Map("CBorderColor", "CustomColors_AllBColors", "CTextColor", "CustomColors_AllTColors", "IABorderColor", "CustomColors_IABorder_Colors") {
            app.%property% := "112233`n`n445566"
            helper := app.Find(name)
            helper.field.Value := app.%property%
            pos := SendMessage(0xBB, 2, 0, helper.field) ; EM_LINEINDEX, third row
            SendMessage(0xB1, pos, pos, helper.field) ; EM_SETSEL
            app.ClickPicker(helper)
            AssertEqual("445566", app.initialColor)
            AssertEqual("1: 112233`n2: `n3: A1B2C3", helper.field.Value)
            AssertEqual("1: 112233`n2: `n3: a1b2c3", app.%property%)
        }
        AssertTrue(app.NeedRestart)
    } finally {
        app.Dispose()
    }
}

TestRunner.Register("Cancel keeps manual RGB text, custom rows and saved configuration unchanged", ColorPickerCancelTest)
ColorPickerCancelTest() {
    app := ColorSettingsFixture()
    try {
        helper := app.Find("ThumbnailTextColor")
        helper.field.Value := "rgb(12, 34, 56)"
        before := JSON.Dump(app._JSON)
        app.ClickPicker(helper)
        AssertEqual("0C2238", app.initialColor)
        AssertEqual("rgb(12, 34, 56)", helper.field.Value)
        helper := app.Find("CBorderColor")
        helper.field.Value := "1: 112233`n2: `n3: 445566"
        pos := SendMessage(0xBB, 1, 0, helper.field)
        SendMessage(0xB1, pos, pos, helper.field)
        app.ClickPicker(helper)
        AssertEqual("FFFFFF", app.initialColor, "An empty selected row uses a safe initial color.")
        AssertEqual("1: 112233`n2: `n3: 445566", helper.field.Value)
        AssertEqual(before, JSON.Dump(app._JSON))
        AssertFalse(app.NeedRestart)
        Sleep(220)
        AssertEqual(0, app.saves)
    } finally {
        app.Dispose()
    }
}

TestRunner.Register("Picker changes follow the selected profile and retain other profiles' colors", ColorPickerProfilesTest)
ColorPickerProfilesTest() {
    app := ColorSettingsFixture()
    try {
        app.Profiles["Other"] := JSON.Load(JSON.Dump(app.Profiles["Default"]))
        app.LastUsedProfile := "Other"
        for group in ["Thumbnails Visuals", "Monitored Events", "Custom Colors"]
            app.Profiles["Other"]["Other"]["Global_Groups"][group] := 1
        app.ProfileOverride()
        defaultColors := JSON.Dump(app.Profiles["Default"])
        app.nextColor := "A1B2C3"
        for name in ["ThumbnailTextColor", "CwarpDisrupted", "CBorderColor"]
            app.ClickPicker(app.Find(name))
        AssertEqual("a1b2c3", app.Profiles["Other"]["Thumbnails Visuals"]["ThumbnailTextColor"])
        AssertEqual("A1B2C3", app.Profiles["Other"]["Game Logs Monitoring"]["monitoredEvents"]["warpDisrupted"]["color"])
        AssertEqual("a1b2c3", app.Profiles["Other"]["Custom Colors"]["cColors"]["Bordercolor"][1])
        AssertEqual(defaultColors, JSON.Dump(app.Profiles["Default"]))
    } finally {
        app.Dispose()
    }
}
