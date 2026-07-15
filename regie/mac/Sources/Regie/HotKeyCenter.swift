import AppKit
import Carbon

/// Raccourcis clavier globaux via l'API Carbon (RegisterEventHotKey).
/// Contrairement aux moniteurs NSEvent, aucun besoin d'autorisation
/// Accessibilité : le système livre l'événement directement à l'app.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    // Modificateurs Carbon (bits historiques, stables depuis toujours).
    static let cmd: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var installed = false
    private var nextId: UInt32 = 1

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        installIfNeeded()
        let id = nextId
        nextId += 1
        handlers[id] = handler
        let signature = OSType(0x434C_4348) // "CLCH"
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr {
            refs.append(ref)
            return true
        }
        NSLog("Regie: échec RegisterEventHotKey (code %d, status %d)", keyCode, status)
        return false
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                if let handler = center.handlers[hotKeyID.id] {
                    DispatchQueue.main.async { handler() }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
}
