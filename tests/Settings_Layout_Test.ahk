class SettingsLayoutFixture extends CombatEventsFixture {
    __New() {
        super.__New()
        this.ProfileOverride()
        this.SetState()
        this.S_Gui := Gui()
        this.CreateSidebar()
        this.CreateMainFrame()
        this.HotkeyGroups_Ctrl()
    }
    Dispose() {
        this.Sidebar.Destroy()
        this.MainFrame.Destroy()
        this.S_Gui.Destroy()
    }
}

SettingsNativeRect(hwnd, parentHwnd) {
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        throw OSError()
    DllCall("MapWindowPoints", "Ptr", 0, "Ptr", parentHwnd, "Ptr", rect, "UInt", 2)
    return {left: NumGet(rect, 0, "Int"), top: NumGet(rect, 4, "Int"), right: NumGet(rect, 8, "Int"), bottom: NumGet(rect, 12, "Int")}
}

TestRunner.Register("Settings panels stay adjacent at simulated 100, 125, 150 and 200 percent scaling", SettingsScaledPanelsTest)
SettingsScaledPanelsTest() {
    app := SettingsLayoutFixture()
    try {
        ; Change only these hidden test windows, never Windows display settings.
        ; Win32 pixel sizes reproduce the scaled sidebar/unscaled X mismatch.
        app.S_Gui.Show("Hide x-500 y-200 w700 h822")
        app.Sidebar.Show("Hide x0 y0 w240 h822")
        for scale in [1, 1.25, 1.5, 2] {
            sidebarWidth := Round(app.sidebarW * scale)
            AssertTrue(DllCall("SetWindowPos", "Ptr", app.Sidebar.Hwnd, "Ptr", 0,
                "Int", 0, "Int", 0, "Int", sidebarWidth, "Int", Round(app.guiHeight * scale), "UInt", 0x14))
            sidebar := SettingsNativeRect(app.Sidebar.Hwnd, app.S_Gui.Hwnd)
            app.MainFrame.Show(Format("x{} y0 w450 h812", app.sidebarW))
            oldContent := SettingsNativeRect(app.MainFrame.Hwnd, app.S_Gui.Hwnd)
            if scale > 1
                AssertTrue(oldContent.left < sidebar.right, "Reproduce the reported leftward overlap at " (scale * 100) "%.")
            app.ShowSettingsContent()
            content := SettingsNativeRect(app.MainFrame.Hwnd, app.S_Gui.Hwnd)
            AssertEqual(sidebar.right, content.left, "No overlap or gap at " (scale * 100) "%.")
            AssertEqual(sidebar.top, content.top)
            heading := SettingsNativeRect(app.MainFrame.Group["Hotkey Groups"][1].Hwnd, app.S_Gui.Hwnd)
            AssertTrue(heading.left > sidebar.right, "The heading must stay clear of the sidebar.")
        }
    } finally {
        app.Dispose()
    }
}

TestRunner.Register("Settings content placement uses parent coordinates including sidebar offsets", SettingsPanelParentCoordinatesTest)
SettingsPanelParentCoordinatesTest() {
    app := SettingsLayoutFixture()
    try {
        app.S_Gui.Show("Hide x-800 y-300 w700 h822")
        app.Sidebar.Show("Hide x13 y7 w240 h822")
        app.ShowSettingsContent()
        sidebar := SettingsNativeRect(app.Sidebar.Hwnd, app.S_Gui.Hwnd)
        content := SettingsNativeRect(app.MainFrame.Hwnd, app.S_Gui.Hwnd)
        AssertEqual(sidebar.right, content.left)
        AssertEqual(sidebar.top, content.top)
    } finally {
        app.Dispose()
    }
}
