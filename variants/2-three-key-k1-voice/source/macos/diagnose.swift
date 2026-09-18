import Foundation
import CoreAudio
import CoreGraphics
import ApplicationServices
import AVFoundation

setbuf(stdout, nil)
if CommandLine.arguments.contains("--select-xiao") {
    var listAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var listSize: UInt32 = 0
    _ = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &listSize)
    var devices = [AudioDeviceID](repeating: 0, count: Int(listSize) / MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &listSize, &devices)
    for candidate in devices {
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var candidateName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        _ = withUnsafeMutablePointer(to: &candidateName) { AudioObjectGetPropertyData(candidate, &nameAddress, 0, nil, &nameSize, $0) }
        if (candidateName as String).contains("XIAO Voice Keyboard Microphone") {
            var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var selected = candidate
            let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &selected)
            print("Select XIAO:", result, candidate)
            break
        }
    }
}
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var dev: AudioDeviceID = 0
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
addr.mSelector = kAudioObjectPropertyName
var name: CFString = "" as CFString
size = UInt32(MemoryLayout<CFString>.size)
_ = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, $0) }
print("Default input:", status, dev, name)
print("Accessibility:", AXIsProcessTrusted(), "microphone authorization:", AVCaptureDevice.authorizationStatus(for: .audio).rawValue)
if CommandLine.arguments.contains("--audio") {
    guard (name as String).contains("XIAO") else { print("STOP: default input is not XIAO"); exit(2) }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    print("Format:", format)
    var frames: UInt64 = 0
    input.installTap(onBus: 0, bufferSize: 1600, format: format) { buffer, _ in
        guard let samples = buffer.floatChannelData?[0] else { return }
        var peak: Float = 0
        var sum: Double = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])); sum += Double(samples[i] * samples[i]) }
        frames += UInt64(buffer.frameLength)
        print("AUDIO frames=\(frames) peak=\(peak) rms=\(sqrt(sum / Double(max(1, buffer.frameLength))))")
    }
    do { try engine.start(); RunLoop.current.run(until: Date().addingTimeInterval(15)); engine.stop() }
    catch { print("Audio error:", error); exit(3) }
} else {
    let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if key == 105 || key == 63 { print("KEY type=\(type.rawValue) key=\(key) flags=\(event.flags.rawValue) sourcePID=\(event.getIntegerValueField(.eventSourceUnixProcessID))") }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil) else { print("Event tap unavailable"); exit(4) }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    RunLoop.current.run(until: Date().addingTimeInterval(45))
}
