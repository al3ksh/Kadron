import QtQuick
import QtCore

// Keeps a page's output options between runs when "Remember tool options" is
// on: `names` are properties of `target`, restored at startup and saved as
// they change. With the setting off nothing is read or written.
QtObject {
    id: options
    property QtObject target
    property var names: []
    property string category

    readonly property Settings store: Settings { category: options.category }

    function save(name) {
        if (Prefs.rememberToolOptions) store.setValue(name, target[name])
    }
    function saveAll() {
        for (var i = 0; i < names.length; ++i) save(names[i])
    }
    Component.onCompleted: {
        if (!target) return
        for (var i = 0; i < names.length; ++i) {
            var name = names[i]
            var stored = Prefs.rememberToolOptions ? store.value(name) : undefined
            if (stored !== undefined && stored !== null) {
                // The registry hands some values back as text.
                var current = target[name]
                if (typeof current === "boolean") target[name] = stored === true || stored === "true"
                else if (typeof current === "number") { if (isFinite(Number(stored))) target[name] = Number(stored) }
                else target[name] = String(stored)
            }
            target[name + "Changed"].connect((function(key) { return function() { options.save(key) } })(name))
        }
    }
    // Turning the setting on keeps what is set right now.
    readonly property Connections prefsWatch: Connections {
        target: Prefs
        function onRememberToolOptionsChanged() { options.saveAll() }
    }
}
