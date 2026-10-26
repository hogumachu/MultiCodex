import Carbon
import Foundation

@MainActor
public final class GlobalHotKeys {
  private struct Registration {
    var shortcut: AccountShortcut
    var ref: EventHotKeyRef
    var token: UInt32
  }
  private var registrations: [String: Registration] = [:]
  private var nextToken: UInt32 = 1
  private var handler: EventHandlerRef?
  public var onTrigger: ((String) -> Void)?
  public var registeredIDs: Set<String> { Set(registrations.keys) }
  private static let signature: OSType = 0x4D43_6478  // MCdx

  public init() throws {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr else { return status }
        // Carbon delivers the application event handler on the main event loop.
        return MainActor.assumeIsolated {
          let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
          guard id.signature == GlobalHotKeys.signature,
            let profile = owner.registrations.first(where: { $0.value.token == id.id })?.key
          else {
            return OSStatus(eventNotHandledErr)
          }
          owner.onTrigger?(profile)
          return noErr
        }
      }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard status == noErr else { throw ShortcutError.unavailable }
  }

  public func replace(_ shortcut: AccountShortcut?, for id: String) throws {
    if registrations[id]?.shortcut == shortcut { return }
    guard let shortcut else {
      if let old = registrations.removeValue(forKey: id) { UnregisterEventHotKey(old.ref) }
      return
    }
    try shortcut.validate()
    var modifiers: UInt32 = 0
    if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
    if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
    if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
    if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
    let token = nextToken
    nextToken &+= 1
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode, modifiers,
      EventHotKeyID(signature: Self.signature, id: token),
      GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
    guard status == noErr, let ref else { throw ShortcutError.registration(status) }
    // Do not discard a working shortcut until its replacement is registered.
    if let old = registrations[id] { UnregisterEventHotKey(old.ref) }
    registrations[id] = Registration(shortcut: shortcut, ref: ref, token: token)
  }

  public func removeAll() {
    for registration in registrations.values { UnregisterEventHotKey(registration.ref) }
    registrations.removeAll()
  }

  public func stop() {
    removeAll()
    if let handler {
      RemoveEventHandler(handler)
      self.handler = nil
    }
  }
}
