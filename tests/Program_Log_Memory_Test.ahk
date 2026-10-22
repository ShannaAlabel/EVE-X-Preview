; Inject allocation failures instead of exhausting the user's system memory.
class MemoryPressureLogFixture extends ProgramLog {
    static Reset(fault := "") {
        this.Text := ""
        this.Pending := ""
        this.Directory := ""
        this.Busy := false
        this.MemoryRetryAt := 0
        this.MemoryNoticePending := false
        this.Activity := Map()
        this.SlowOperationAt := Map()
        this.DisplayNotificationAt := Map()
        this.ActivityAt := A_TickCount
        this.LastErrorTick := -60000
        this.LastErrorExport := ""
        this.Fault := fault
        this.AppendCalls := 0
        this.Writes := 0
        this.Exports := 0
    }

    static AppendTail(buffer, addition) {
        this.AppendCalls++
        if this.Fault = this.AppendCalls
            throw MemoryError("Out of memory.")
        return super.AppendTail(buffer, addition)
    }

    static ReportActivity(now := A_TickCount) {
        if this.Fault = "activity"
            throw MemoryError("Out of memory.")
        super.ReportActivity(now)
    }

    static WriteBatch(batch, path) {
        this.Writes++
        if this.Fault = "write-memory"
            throw MemoryError("Out of memory.")
        if this.Fault = "write-io"
            throw OSError(32)
        super.WriteBatch(batch, path)
    }

    static Export(path) {
        this.Exports++
        if this.Fault = "export-memory"
            throw MemoryError("Out of memory.")
        return super.Export(path)
    }
}

class MemoryFailureDetails {
    Message {
        get => MemoryFailureDetails.Fail()
    }
    static Fail() {
        throw MemoryError("Out of memory.")
    }
}

TestRunner.Register("Diagnostic append memory failures discard buffers, back off and resume", ProgramLogMemoryAppendTest)
ProgramLogMemoryAppendTest() {
    log := MemoryPressureLogFixture
    try {
        ; The second failure occurs after Text succeeded but Pending could not grow.
        for failureAt in [1, 2] {
            log.Reset(failureAt)
            log.Text := Format("{:0262144}", 0)
            log.Pending := log.Text
            log.Activity["event"] := 7
            log.SlowOperationAt["operation"] := A_TickCount
            log.DisplayNotificationAt["display"] := A_TickCount
            log.Add("foreground error during a large fight", "ERROR")
            AssertEqual("", log.Text)
            AssertEqual("", log.Pending)
            AssertTrue(log.IsMemoryBackoff())
            AssertTrue(log.MemoryRetryAt - A_TickCount <= log.MemoryCooldownMs)
            AssertEqual(0, log.Activity.Count)
            AssertEqual(0, log.SlowOperationAt.Count)
            AssertEqual(0, log.DisplayNotificationAt.Count)
            log.Add("must be dropped")
            log.Error(Error("must not export"))
            log.Count("must not accumulate")
            log.SlowOperation("must not accumulate", A_TickCount - 1000)
            log.ReportActivity(A_TickCount + 10000)
            log.DisplayChanged(0, 0, 0x031E, 0)
            log.Flush()
            AssertEqual(failureAt, log.AppendCalls, "Backoff must skip log formatting and appends.")
            AssertEqual(0, log.Activity.Count)
            AssertEqual(0, log.Writes)
            AssertEqual(0, log.Exports)
            log.Fault := ""
            log.MemoryRetryAt := A_TickCount - 1
            log.Add("recovered event")
            log.Add("another event")
            AssertFalse(log.IsMemoryBackoff())
            AssertTrue(InStr(log.Text, "recovered event"))
            AssertTrue(InStr(log.Pending, "recovered event"))
            AssertEqual(2, StrSplit(log.Text, "Out of memory:").Length, "One recovery notice per episode.")
        }
    } finally {
        log.Reset()
    }
}

TestRunner.Register("Memory failures during error formatting, append, flush and export do not recurse", ProgramLogMemoryErrorTest)
ProgramLogMemoryErrorTest() {
    log := MemoryPressureLogFixture
    directory := A_Temp "\EVE-X-Preview-memory-errors-" A_TickCount
    DirCreate(directory)
    try {
        for fault in ["direct", "details", 1, 2, "activity", "write-memory", "export-memory"] {
            log.Reset(fault)
            log.Directory := directory
            log.Text := "old history"
            log.Pending := "unflushed events"
            err := fault = "direct" ? MemoryError("Out of memory.")
                : fault = "details" ? MemoryFailureDetails() : Error("original foreground error")
            log.Error(err, "Main timer foreground check")
            AssertEqual("", log.Text, "Discard history after " fault)
            AssertEqual("", log.Pending, "Discard pending writes after " fault)
            AssertTrue(log.IsMemoryBackoff(), "Back off after " fault)
            AssertFalse(log.Busy, "Flush lock must be released after " fault)
            AssertEqual(fault = "export-memory" ? 1 : 0, log.Exports, "No recursive error snapshot.")
        }
        ; An ordinary disk sharing error retains a bounded batch for retry.
        log.Reset("write-io")
        log.Directory := directory
        log.Add("retry this write")
        pending := log.Pending
        log.Flush()
        AssertEqual(pending, log.Pending)
        AssertFalse(log.IsMemoryBackoff())
        AssertFalse(log.Busy)
        log.Fault := ""
        log.Flush()
        AssertEqual("", log.Pending)
        AssertTrue(InStr(FileRead(directory "\current.log"), "retry this write"))
        ; Logging reaches disk again after a memory episode as well.
        log.RecoverMemory()
        log.MemoryRetryAt := A_TickCount - 1
        log.Add("memory recovery persisted")
        log.Flush()
        AssertTrue(InStr(FileRead(directory "\current.log"), "memory recovery persisted"))
    } finally {
        log.Reset()
        loop files directory "\*.log"
            FileDelete(A_LoopFileFullPath)
        DirDelete(directory)
    }
}

TestRunner.Register("Diagnostic joins retain only the newest capped text", ProgramLogBoundedJoinTest)
ProgramLogBoundedJoinTest() {
    log := MemoryPressureLogFixture
    try {
        log.Reset()
        log.MaxChars := 128
        AssertEqual("old-new", log.AppendTail("old", "-new"))
        AssertEqual("", log.AppendTail("", ""))
        log.Add(Format("{:0300000}", 0) "LATEST")
        AssertEqual(128, StrLen(log.Text))
        AssertEqual(128, StrLen(log.Pending))
        AssertTrue(InStr(log.Text, "LATEST`r`n"))
        log.Add("NEXT")
        AssertTrue(StrLen(log.Text) <= 128)
        AssertTrue(StrLen(log.Pending) <= 128)
        AssertTrue(InStr(log.Text, "LATEST"))
        AssertTrue(InStr(log.Text, "NEXT"))
        log.MaxChars := 4
        AssertEqual("tail", log.AppendTail("discard", "tail"))
        AssertEqual("tail", log.AppendTail("discard", "long-tail"))
    } finally {
        log.MaxChars := ProgramLog.MaxChars
        log.Reset()
    }
}

TestRunner.Register("Global memory handler suppresses only recoverable allocation dialogs", ProgramLogMemoryHandlerTest)
ProgramLogMemoryHandlerTest() {
    text := ProgramLog.Text, pending := ProgramLog.Pending
    retryAt := ProgramLog.MemoryRetryAt, notice := ProgramLog.MemoryNoticePending
    activity := ProgramLog.Activity.Clone()
    slow := ProgramLog.SlowOperationAt.Clone()
    display := ProgramLog.DisplayNotificationAt.Clone()
    try {
        for mode in ["Return", "Exit"] {
            AssertEqual(1, Error_Handler(MemoryError("Out of memory."), mode), "Abort the failed callback; do not continue it.")
            AssertEqual("", ProgramLog.Text)
            AssertEqual("", ProgramLog.Pending)
            AssertTrue(ProgramLog.IsMemoryBackoff())
        }
        AssertThrows(() => Error_Handler(Error("ordinary error"), "Return"), "ordinary error")
        AssertThrows(() => Error_Handler(MemoryError("critical failure"), "ExitApp"), "critical failure")
    } finally {
        ProgramLog.Text := text, ProgramLog.Pending := pending
        ProgramLog.MemoryRetryAt := retryAt, ProgramLog.MemoryNoticePending := notice
        ProgramLog.Activity := activity
        ProgramLog.SlowOperationAt := slow
        ProgramLog.DisplayNotificationAt := display
    }
}
