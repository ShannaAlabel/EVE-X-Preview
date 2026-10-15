; Session-only assignments shared by all thumbnails. Only occupied systems reserve colors.
class SystemColorManager {
    static Palette := [
        "00D4FF", "FFD166", "C792EA", "70E080", "FF8FA3", "FF9F43", "A3B8FF", "F6F58C",
        "38D9A9", "FF6B6B", "E599F7", "B8E986", "7AB8FF", "E5C3A6", "D0D7DE", "F783AC"
    ]

    active := Map()
    remembered := Map()
    generatedIndex := 0

    static Key(system) => StrLower(Trim(system))

    Update(systems) {
        occupied := Map(), used := Map()
        for system in systems {
            key := SystemColorManager.Key(system)
            if key != ""
                occupied[key] := true
        }
        for key, color in this.active.Clone() {
            if occupied.Has(key)
                used[color] := true
            else
                this.active.Delete(key)
        }
        ; Restore remembered colors before allocating new ones, regardless of window order.
        for key in occupied {
            if this.active.Has(key)
                continue
            color := this.remembered.Get(key, "")
            if color != "" && !used.Has(color)
                this.active[key] := color, used[color] := true
        }
        for key in occupied {
            if this.active.Has(key)
                continue
            color := ""
            for candidate in SystemColorManager.Palette {
                if !used.Has(candidate) {
                    color := candidate
                    break
                }
            }
            ; More simultaneous systems than preset colors: add bright, spaced hues.
            while color = "" || used.Has(color)
                color := SystemColorManager.GenerateColor(this.generatedIndex++)
            this.active[key] := color
            this.remembered[key] := color
            used[color] := true
        }
    }

    Get(system) => this.active.Get(SystemColorManager.Key(system), "")

    static GenerateColor(index) {
        hue := Mod(index * 137.507764, 360) / 60
        chroma := 0.65, minimum := 1 - chroma
        secondary := chroma * (1 - Abs(Mod(hue, 2) - 1))
        switch Floor(hue) {
            case 0: red := chroma, green := secondary, blue := 0
            case 1: red := secondary, green := chroma, blue := 0
            case 2: red := 0, green := chroma, blue := secondary
            case 3: red := 0, green := secondary, blue := chroma
            case 4: red := secondary, green := 0, blue := chroma
            default: red := chroma, green := 0, blue := secondary
        }
        return Format("{:02X}{:02X}{:02X}", Round((red + minimum) * 255),
            Round((green + minimum) * 255), Round((blue + minimum) * 255))
    }
}
