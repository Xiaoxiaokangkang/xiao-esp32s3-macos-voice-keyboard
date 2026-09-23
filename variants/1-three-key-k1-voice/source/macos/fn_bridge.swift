import ApplicationServices
import CoreGraphics
import CoreAudio
import Foundation
import AppKit

private let f13KeyCode: Int64 = 105
private let fnKeyCode: CGKeyCode = 63
private var fnIsDown = false
private var f13IsDown = false
private let diagnosticURL = FileManager.default.temporaryDirectory.appendingPathComponent("xiao-fn-bridge.log")
private func diagnostic(_ message: String) {
    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    let data = Data("\(Date()) app=\(app) \(message)\n".utf8)
    if !FileManager.default.fileExists(atPath: diagnosticURL.path) {
        FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil)
    }
    if let file = try? FileHandle(forWritingTo: diagnosticURL) {
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
    }
}

private final class AudioInputManager {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var xiaoWasConnected = false
    private var previousInputUID: String?
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        let status = AudioObjectAddPropertyListenerBlock(
            systemObject,
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh(reason: "device list changed")
        }
        diagnostic("Core Audio listener status=\(status)")

        // USB Audio can appear shortly after the USB keyboard interface.
        for delay in [0.0, 0.25, 0.75, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh(reason: "startup retry \(delay)s")
            }
        }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            systemObject,
            &devicesAddress,
            DispatchQueue.main,
            { _, _ in }
        )
    }

    func ensureXIAOSelected() {
        guard let xiao = findXIAO() else {
            diagnostic("XIAO microphone not available at key press")
            return
        }
        selectInput(xiao, reason: "key press")
    }

    private func refresh(reason: String) {
        if let xiao = findXIAO() {
            if !xiaoWasConnected {
                let current = defaultInput()
                if current != 0 && current != xiao {
                    previousInputUID = stringProperty(current, kAudioDevicePropertyDeviceUID)
                    diagnostic("saved previous input uid=\(previousInputUID ?? "unknown")")
                }
                xiaoWasConnected = true
                diagnostic("XIAO microphone connected id=\(xiao)")
            }
            selectInput(xiao, reason: reason)
        } else if xiaoWasConnected {
            xiaoWasConnected = false
            restorePreviousInput()
            diagnostic("XIAO microphone disconnected")
        }
    }

    private func allDevices() -> [AudioObjectID] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        let status = devices.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, bytes.baseAddress!)
        }
        return status == noErr ? devices : []
    }

    private func stringProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func findXIAO() -> AudioObjectID? {
        allDevices().first { device in
            let name = stringProperty(device, kAudioObjectPropertyName) ?? ""
            let maker = stringProperty(device, kAudioObjectPropertyManufacturer) ?? ""
            return name == "XIAO Voice Keyboard Microphone" && maker == "Seeed Studio"
        }
    }

    private func defaultInput() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr else {
            return AudioObjectID(kAudioObjectUnknown)
        }
        return device
    }

    private func selectInput(_ device: AudioObjectID, reason: String) {
        guard defaultInput() != device else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newDefault = device
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(systemObject, &address, 0, nil, size, &newDefault)
        diagnostic("select XIAO input reason=\(reason) status=\(status)")
    }

    private func restorePreviousInput() {
        guard let uid = previousInputUID,
              let device = allDevices().first(where: {
                  stringProperty($0, kAudioDevicePropertyDeviceUID) == uid
              }) else {
            previousInputUID = nil
            return
        }
        selectInput(device, reason: "restore after unplug")
        previousInputUID = nil
    }
}

private let audioInputManager = AudioInputManager()

private func postFn(_ down: Bool) {
    guard down != fnIsDown else { return }

    guard let source = CGEventSource(stateID: .hidSystemState),
          let event = CGEvent(keyboardEventSource: source,
                              virtualKey: fnKeyCode,
                              keyDown: down) else {
        return
    }

    // macOS represents the hardware Fn key as a flagsChanged event.
    event.type = .flagsChanged
    var flags = CGEventSource.flagsState(.hidSystemState)
    if down { flags.insert(.maskSecondaryFn) }
    else { flags.remove(.maskSecondaryFn) }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    fnIsDown = down
    diagnostic("Fn \(down ? "down" : "up") flags=\(flags.rawValue)")
}

private let callback: CGEventTapCallBack = { proxy, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        diagnostic("event tap disabled: \(type.rawValue)")
        postFn(false)
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp,
          event.getIntegerValueField(.keyboardEventKeycode) == f13KeyCode else {
        return Unmanaged.passUnretained(event)
    }

    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if !isRepeat {
        diagnostic("F13 \(type == .keyDown ? "down" : "up")")
        f13IsDown = type == .keyDown
        if f13IsDown {
            audioInputManager.ensureXIAOSelected()
            postFn(true)
        } else {
            postFn(false)
        }
    }

    // F13 is only an internal transport key; do not pass it to applications.
    return nil
}

private var eventTap: CFMachPort?

guard AXIsProcessTrusted() else {
    fputs("需要辅助功能权限：请在 系统设置 → 隐私与安全性 → 辅助功能 中允许 fn-bridge。\n", stderr)
    exit(2)
}

let mask = (1 << CGEventType.keyDown.rawValue) |
           (1 << CGEventType.keyUp.rawValue)

eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                             place: .headInsertEventTap,
                             options: .defaultTap,
                             eventsOfInterest: CGEventMask(mask),
                             callback: callback,
                             userInfo: nil)

guard let eventTap else {
    fputs("无法建立键盘事件监听；请确认 fn-bridge 已获辅助功能权限。\n", stderr)
    exit(3)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

signal(SIGINT) { _ in
    postFn(false)
    exit(0)
}
signal(SIGTERM) { _ in
    postFn(false)
    exit(0)
}

print("Fn Bridge 已运行：自动选择 XIAO 麦克风，按住设备按键会发送 Fn。")
diagnostic("bridge started")
CFRunLoopRun()
