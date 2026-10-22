; Event-only playback policy. Preview buttons use their own single player so a
; manual Test is never swallowed by an alert cooldown or a full event mixer.
class EventSoundMixer {
    channels := []
    lastStarted := Map()
    lastError := ""

    __New(config) {
        this.Configure(config)
    }

    Configure(config) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            this.limit := EventSounds.MaxSimultaneous(config)
            this.repeatTimeout := EventSounds.RepeatTimeout(config)
            this.Prune()
            while this.channels.Length > this.limit
                this.channels.RemoveAt(1).player.Dispose()
        } finally Critical(previousCritical)
    }

    CreatePlayer() => EventSoundPlayer()

    ValidateFile(path) => EventSounds.Validate(path)

    Play(path, volume := 100, event := "", now := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        this.lastError := ""
        player := 0
        try {
            this.Prune()
            if volume <= 0
                return false
            if !now
                now := DllCall("GetTickCount64", "UInt64")
            key := StrLower(EventSounds.FullPath(path))
            if this.repeatTimeout && this.lastStarted.Has(key) && now - this.lastStarted[key] < this.repeatTimeout
                return false
            this.ValidateFile(path)
            ; Match the previous one-channel behavior: newest alerts replace
            ; the oldest when full. Never queue stale alerts for later playback.
            while this.channels.Length >= this.limit
                this.channels.RemoveAt(1).player.Dispose()
            player := this.CreatePlayer()
            if !player.Play(path, false, volume) {
                this.lastError := player.lastError
                player.Dispose()
                return false
            }
            this.channels.Push({player: player, event: event})
            this.lastStarted[key] := now ; Only successful starts consume a timeout.
            return true
        } catch as err {
            if IsObject(player)
                player.Dispose()
            this.lastError := err.Message
            return false
        } finally Critical(previousCritical)
    }

    Prune() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            count := this.channels.Length
            loop count {
                index := count - A_Index + 1
                if !this.channels[index].player.IsPlaying()
                    this.channels.RemoveAt(index).player.Dispose()
            }
        } finally Critical(previousCritical)
    }

    ActiveCount() {
        this.Prune()
        return this.channels.Length
    }

    Dispose() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            for channel in this.channels
                channel.player.Dispose()
            this.channels := []
            this.lastStarted.Clear()
        } finally Critical(previousCritical)
    }
}
