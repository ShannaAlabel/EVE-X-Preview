class SystemColorFixture extends SystemTrackingFixture {
    __New(count := 2) {
        super.__New()
        this.overlays := []
        loop count {
            name := A_Index = 1 ? "Alice" : A_Index = 2 ? "Bob" : "Pilot" A_Index
            hwnd := StrLower(name)
            this.active["EVE - " name] := hwnd
            overlay := Gui("-Caption")
            this.overlays.Push(overlay)
            overlay.MarginX := 5, overlay.MarginY := 5
            overlay.SystemTextDefaultColor := A_Index = 2 ? "66CC99" : "FAC57A"
            overlay.SetFont("s12 c" overlay.SystemTextDefaultColor, "Gill Sans MT")
            this.AddThumbnailTextControls(overlay, "EVE - " name, 200, 150)
            this.ThumbWindows.%hwnd% := Map("Window", {Title: "EVE - " name}, "TextOverlay", overlay)
        }
    }

    Overlay(hwnd) => this.ThumbWindows.%hwnd%["TextOverlay"]

    Cleanup() {
        super.Cleanup()
        for overlay in this.overlays
            overlay.Destroy()
    }
}

; Ask the real GUI color handler which RGB color it will use to paint this control.
ReadThumbnailControlColor(overlay, name := "SystemText") {
    dc := DllCall("GetDC", "ptr", overlay.Hwnd, "ptr")
    try {
        DllCall("SendMessageW", "ptr", overlay.Hwnd, "uint", 0x138, "ptr", dc, "ptr", overlay[name].Hwnd, "ptr") ; WM_CTLCOLORSTATIC
        color := DllCall("GetTextColor", "ptr", dc, "uint")
        return Format("{:06X}", ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF))
    } finally {
        DllCall("ReleaseDC", "ptr", overlay.Hwnd, "ptr", dc)
    }
}

TestRunner.Register("System colors normalize names and stay stable across window order and travel", SystemColorAssignmentsTest)
SystemColorAssignmentsTest() {
    colors := SystemColorManager()
    colors.Update([" Jita ", "JITA", "Amarr", ""])
    jita := colors.Get("jita"), amarr := colors.Get("Amarr")
    AssertEqual(2, colors.active.Count)
    AssertNotEqual(jita, amarr)
    AssertEqual("", colors.Get(""), "Unknown systems must have no assigned color.")
    colors.Update(["Amarr", "Dodixie", "Jita"])
    AssertEqual(jita, colors.Get("Jita"))
    AssertEqual(amarr, colors.Get("Amarr"))
    colors.Update(["Amarr"])
    colors.Update(["New System", "Jita", "Amarr"])
    AssertEqual(jita, colors.Get("Jita"), "Returning systems restore their color before new systems allocate one.")
    AssertEqual(amarr, colors.Get("Amarr"))
    AssertNotEqual(jita, colors.Get("New System"))
}

TestRunner.Register("System colors recycle only vacant colors and extend an exhausted palette", SystemColorPaletteTest)
SystemColorPaletteTest() {
    colors := SystemColorManager(), systems := []
    loop SystemColorManager.Palette.Length
        systems.Push("System " A_Index)
    colors.Update(systems)
    previous := colors.active.Clone()
    released := colors.Get(systems.RemoveAt(1))
    systems.Push("New System")
    colors.Update(systems)
    AssertEqual(released, colors.Get("New System"), "A vacant color should be recycled before generating more colors.")
    systems.Push("System 1")
    loop 10
        systems.Push("Extra " A_Index)
    colors.Update(systems)
    used := Map()
    for system in systems {
        color := colors.Get(system)
        AssertTrue(RegExMatch(color, "^[0-9A-F]{6}$"))
        AssertFalse(used.Has(color), "Different occupied systems must never share a color.")
        used[color] := true
        if previous.Has(SystemColorManager.Key(system)) && system != "System 1"
            AssertEqual(previous[SystemColorManager.Key(system)], color, "Occupied systems must keep their colors when new systems arrive.")
    }
    colors := SystemColorManager()
    loop 40
        colors.Update(["Anchor", "Travel " A_Index])
    AssertEqual(0, colors.generatedIndex, "Travel history alone must not exhaust the preset palette.")
}

TestRunner.Register("System coloring toggles immediately and restores each thumbnail's original text color", SystemColorToggleTest)
SystemColorToggleTest() {
    app := SystemColorFixture()
    try {
        alice := app.Overlay("alice"), bob := app.Overlay("bob")
        app.updateThumbnailSystemText("Jita", "alice")
        app.updateThumbnailSystemText("Jita", "bob")
        app.updateThumbnailEventText("Warp Disrupted", "alice")
        app.RefreshThumbnailSystemColors()
        AssertEqual(0, app.systemColorsEnabled)
        AssertEqual("FAC57A", ReadThumbnailControlColor(alice), "Default Alice system color")
        AssertEqual("66CC99", ReadThumbnailControlColor(bob), "Default Bob system color")
        app.systemColorsEnabled := 1
        jita := ReadThumbnailControlColor(alice)
        AssertEqual(jita, ReadThumbnailControlColor(bob), "Same-system colors override different character text colors.")
        AssertEqual("FAC57A", ReadThumbnailControlColor(alice, "OverlayText"), "Character name color must stay unchanged")
        AssertEqual("FAC57A", ReadThumbnailControlColor(alice, "EventText"), "Event color must stay unchanged")
        AssertEqual("Warp Disrupted", alice["EventText"].Text)
        app.updateThumbnailSystemText("Amarr", "bob")
        app.RefreshThumbnailSystemColors()
        AssertEqual(jita, ReadThumbnailControlColor(alice))
        AssertNotEqual(jita, ReadThumbnailControlColor(bob))
        app.systemColorsEnabled := 0
        AssertEqual("FAC57A", ReadThumbnailControlColor(alice), "Disabling must restore Alice's default color")
        AssertEqual("66CC99", ReadThumbnailControlColor(bob), "Disabling must restore the overlay's own default color.")
        app.systemColorsEnabled := 1
        AssertEqual(jita, ReadThumbnailControlColor(alice))
        app.SetThumbnailText["bob"] := "EVE - Carol"
        AssertEqual("", bob["SystemText"].Text)
        AssertEqual("66CC99", ReadThumbnailControlColor(bob), "A changed character must not inherit a previous system color.")
        app.systemTrackingEnabled := 0
        app.RefreshThumbnailSystemColors()
        AssertEqual("FAC57A", ReadThumbnailControlColor(alice), "Coloring requires system tracking.")
    } finally {
        app.Cleanup()
    }
}

TestRunner.Register("Local logs color ten characters and follow jumps and logout", SystemColorLocalLogsTest)
SystemColorLocalLogsTest() {
    app := SystemColorFixture(10)
    try {
        paths := Map(), index := 0
        for character, hwnd in app.active {
            index++
            system := hwnd = "pilot10" ? "Amarr" : "Jita"
            paths[hwnd] := app.WriteLog("Local_20261015_000001_" index ".txt", app.CleanTitle(character), "2026.10.15 12:00:00", app.Message(system))
        }
        app.systemColorsEnabled := 1
        app.monitorCharacterSystems()
        deadline := A_TickCount + 10000
        while app.systemLogMonitor.readers.Count < app.active.Count && A_TickCount < deadline {
            Sleep(10)
            app.monitorCharacterSystems()
        }
        AssertEqual("Jita", app.System("alice"), "Alice log seed")
        AssertEqual("Amarr", app.System("pilot10"), "Outlier log seed")
        jita := ReadThumbnailControlColor(app.Overlay("alice"))
        amarr := ReadThumbnailControlColor(app.Overlay("pilot10"))
        AssertNotEqual(jita, amarr)
        for character, hwnd in app.active {
            AssertEqual(hwnd = "pilot10" ? "Amarr" : "Jita", app.System(hwnd))
            AssertEqual(hwnd = "pilot10" ? amarr : jita, ReadThumbnailControlColor(app.Overlay(hwnd)))
        }
        app.Append(paths["bob"], app.Message("Amarr"))
        app.monitorCharacterSystems()
        AssertEqual(amarr, ReadThumbnailControlColor(app.Overlay("bob")))
        AssertEqual(jita, ReadThumbnailControlColor(app.Overlay("alice")))
        app.active.Delete("EVE - Pilot10")
        app.active.Delete("EVE - Bob")
        app.monitorCharacterSystems()
        AssertEqual("", app.System("bob"))
        AssertEqual("66CC99", ReadThumbnailControlColor(app.Overlay("bob")))
        AssertEqual(1, app.systemColors.active.Count, "Logged-out characters must release their system's color.")
    } finally {
        app.Cleanup()
    }
}

TestRunner.Register("System color setting defaults off, persists per profile and responds to checkbox clicks", SystemColorSettingsTest)
SystemColorSettingsTest() {
    app := CombatEventsFixture()
    AssertEqual(0, app.systemColorsEnabled)
    settings := app._JSON["_Profiles"]["Default"]["Game Logs Monitoring"]
    settings.Delete("systemColorsEnabled")
    AssertEqual(0, app.systemColorsEnabled, "Older settings must default to disabled.")
    app.systemColorsEnabled := 1
    app._JSON := JsonMergeNoOverwrite(JSON.Load(default_JSON), JSON.Load(JSON.Dump(app._JSON)))
    AssertEqual(1, app.systemColorsEnabled)
    app._JSON["_Profiles"]["Other"] := JSON.Load(default_JSON)["_Profiles"]["Default"]
    app.ProfileGameLogsMonitoring := "Other"
    AssertEqual(0, app.systemColorsEnabled)
    app.ProfileGameLogsMonitoring := "Default"
    AssertEqual(1, app.systemColorsEnabled)
    app.SetState()
    app.MainFrame := Gui()
    app.MainFrame.Group := Map()
    app.NeedRestart := 0
    app.Save_Settings_Delay_Timer := (*) => 0
    try {
        app.GameLogsMonitoring_Ctrl()
        checkbox := app.MainFrame["systemColorsEnabled"]
        AssertEqual(1, checkbox.Value)
        loop 2 {
            DllCall("SendMessageW", "ptr", checkbox.Hwnd, "uint", 0xF5, "ptr", 0, "ptr", 0, "ptr") ; BM_CLICK
            Sleep(-1) ; Dispatch the queued GUI Click callback.
            AssertEqual(A_Index - 1, app.systemColorsEnabled, "Checkbox click must change the saved setting")
            AssertEqual(app.systemColorsEnabled, checkbox.Value)
            AssertEqual(0, app.NeedRestart, "Changing only system colors must not require a restart.")
        }
    } finally {
        SetTimer(app.Save_Settings_Delay_Timer, 0)
        app.MainFrame.Destroy()
    }
}
