class ProfileSwitchFixture extends Main_Class {
    __New() {
        This._JSON := Map("LastUsedProfile", "First", "_Profiles", Map("First", Map(), "Second", Map()))
        This.layoutSwitches := 0
    }

    TrySwitchKeyboardToEnglish() {
        This.layoutSwitches++
        return true
    }
}

TestRunner.Register("Profile save replaces settings with complete selected profile", ProfileSaveTest)
ProfileSaveTest() {
    dir := A_Temp "\EVE-X-Preview-profile-test-" A_TickCount
    path := dir "\settings.json"
    DirCreate(dir)
    try {
        fixture := ProfileSwitchFixture()
        fixture.SaveJsonToFile(path)
        AssertEqual("First", JSON.Load(FileRead(path))["LastUsedProfile"])
        fixture.LastUsedProfile := "Second"
        fixture.SaveJsonToFile(path)
        AssertEqual("Second", JSON.Load(FileRead(path))["LastUsedProfile"])
        AssertFalse(FileExist(path ".save.tmp"), "Completed save must leave no temporary settings file.")
    } finally {
        if FileExist(path)
            FileDelete(path)
        if FileExist(path ".save.tmp")
            FileDelete(path ".save.tmp")
        if FileExist(dir)
            DirDelete(dir)
    }
}

TestRunner.Register("Invalid layout-sensitive hotkey does not abort profile startup", ProfileHotkeyRetryTest)
ProfileHotkeyRetryTest() {
    fixture := ProfileSwitchFixture()
    result := fixture.RegisterHotkeyWithLanguageRetry("!NotARealKeyName", (*) => 0, "P1", "Test hotkey")
    AssertFalse(result, "An invalid hotkey must be skipped after one retry.")
    AssertEqual(1, fixture.layoutSwitches)
}

class ProfileActivationFixture extends ProfileSwitchFixture {
    SwitchLangOnErr {
        get => false
    }

    __New() {
        super.__New()
        This.runningProfile := "First"
        This.saveCalls := 0
        This.reloadCalls := 0
        This.savedBeforeReload := ""
        This.saveWasCritical := false
        This.callbacks := Map()
        This.savePath := A_Temp "\EVE-X-Preview-hotkey-test-" A_TickCount ".json"
        This.Save_Settings_Delay_Timer := ObjBindMethod(This, "SaveJsonToFile")
    }

    SaveJsonToFile(*) {
        This.saveCalls++
        This.saveWasCritical := A_IsCritical != 0
        super.SaveJsonToFile(This.savePath)
    }

    ReloadForProfile() {
        This.reloadCalls++
        This.savedBeforeReload := JSON.Load(FileRead(This.savePath))["LastUsedProfile"]
    }

    TryRegisterProfileHotkey(keyName, callback, profileName) {
        if !super.TryRegisterProfileHotkey(keyName, callback, profileName)
            return false
        This.callbacks[keyName] := callback
        return true
    }

    Dispose() {
        SetTimer(This.Save_Settings_Delay_Timer, 0)
        if This.HasOwnProp("profileHotkeys") {
            HotIf(This.profileHotkeyCondition)
            for keyName in This.profileHotkeys
                Hotkey(keyName, "Off")
            HotIf()
        }
        if FileExist(This.savePath)
            FileDelete(This.savePath)
    }
}

TestRunner.Register("Profile activation shortcuts are independent and optional for old settings", ProfileActivationSettingsTest)
ProfileActivationSettingsTest() {
    fixture := ProfileActivationFixture()
    try {
        AssertEqual("", fixture.ProfileActivationHotkey)
        fixture.ProfileActivationHotkey := " ^!F23 `n"
        AssertEqual("^!F23", fixture.ProfileActivationHotkey)
        fixture.LastUsedProfile := "Second"
        AssertEqual("", fixture.ProfileActivationHotkey)
        fixture.ProfileActivationHotkey := "^!F24"
        fixture.LastUsedProfile := "First"
        AssertEqual("^!F23", fixture.ProfileActivationHotkey)
        fixture.ProfileActivationHotkey := ""
        AssertEqual("", fixture.ProfileActivationHotkey)
    } finally {
        fixture.Dispose()
    }
}

TestRunner.Register("Profile activation cancels pending save and persists before reload", ProfileActivationActionTest)
ProfileActivationActionTest() {
    fixture := ProfileActivationFixture()
    previousCritical := A_IsCritical
    try {
        SetTimer(fixture.Save_Settings_Delay_Timer, -20)
        AssertTrue(fixture.ActivateProfile("Second", "Tray"))
        Sleep(50)
        AssertEqual("Second", fixture.LastUsedProfile)
        AssertEqual("Second", fixture.savedBeforeReload)
        AssertEqual(1, fixture.saveCalls, "A pending timer must not save again after profile activation.")
        AssertEqual(1, fixture.reloadCalls)
        AssertTrue(fixture.saveWasCritical)
        AssertEqual(previousCritical, A_IsCritical)
    } finally {
        fixture.Dispose()
    }
}

TestRunner.Register("Profile shortcut ignores active and deleted profiles", ProfileActivationGuardTest)
ProfileActivationGuardTest() {
    fixture := ProfileActivationFixture()
    try {
        AssertFalse(fixture.ActivateProfileFromHotkey("First"))
        AssertFalse(fixture.ActivateProfileFromHotkey("Deleted"))
        AssertEqual(0, fixture.saveCalls)
        AssertEqual(0, fixture.reloadCalls)
        AssertEqual("First", fixture.LastUsedProfile)
    } finally {
        fixture.Dispose()
    }
}

TestRunner.Register("Profile hotkeys bind inactive profiles and skip invalid or equivalent duplicate keys", ProfileActivationRegistrationTest)
ProfileActivationRegistrationTest() {
    fixture := ProfileActivationFixture()
    try {
        fixture.Profiles["Second"]["ActivationHotkey"] := "^!F23"
        fixture.Profiles["Third"] := Map("ActivationHotkey", "^!F24")
        fixture.Profiles["Invalid"] := Map("ActivationHotkey", "!NotARealKeyName")
        fixture.Profiles["ZDuplicate"] := Map("ActivationHotkey", "!^f23")
        ; A leftover context must not restrict profile shortcuts to EVE windows.
        HotIf (*) => false
        fixture.RegisterProfileHotkeys()
        AssertEqual(2, fixture.profileHotkeys.Count, JSON.Dump(fixture.profileHotkeys))
        AssertEqual("Second", fixture.profileHotkeys["^!F23"])
        AssertEqual("Third", fixture.profileHotkeys["^!F24"])

        ; Invoke the actual registered callback without sending keys to the user's focused app.
        fixture.callbacks["^!F23"].Call("^!F23")
        AssertEqual(1, fixture.reloadCalls, "The registered shortcut must invoke profile activation.")
        AssertEqual("Second", fixture.savedBeforeReload, "An equivalent duplicate must not replace the original target.")
    } finally {
        HotIf()
        fixture.Dispose()
    }
}

TestRunner.Register("Profile hotkey field fits sidebar and saves edits for the selected profile", ProfileActivationSidebarTest)
ProfileActivationSidebarTest() {
    fixture := ProfileActivationFixture()
    fixture.SetState()
    fixture.S_Gui := Gui()
    try {
        fixture.CreateSidebar()
        field := fixture.Sidebar["ProfileActivationHotkey"]
        field.GetPos(&fieldX, &fieldY, &fieldW, &fieldH)
        fixture.firstBtn.GetPos(, &firstY)
        AssertTrue(fieldX + fieldW <= fixture.sidebarW, "The profile hotkey edit must fit in the sidebar.")
        AssertTrue(fieldY + fieldH < firstY, "The profile hotkey edit must not overlap settings navigation.")
        fixture.updateNotice.GetPos(, &noticeY)
        for control in fixture.Sidebar {
            if control.Text = "About" {
                control.GetPos(, &aboutY, , &aboutH)
                AssertTrue(aboutY + aboutH <= noticeY, "The added row must leave room for About and update notices.")
            }
        }
        field.Value := "^!F23"
        fixture.ProfileActivationHotkeyChanged(field)
        AssertEqual("^!F23", fixture.Profiles["First"]["ActivationHotkey"])
        AssertEqual("", fixture.Profiles["Second"].Get("ActivationHotkey", ""))
        AssertTrue(fixture.NeedRestart)
    } finally {
        fixture.Sidebar.Destroy()
        fixture.S_Gui.Destroy()
        fixture.Dispose()
    }
}
