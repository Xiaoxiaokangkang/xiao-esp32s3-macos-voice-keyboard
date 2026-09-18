import Foundation
import CoreAudio
import AVFoundation

setbuf(stdout, nil)

func deviceName(_ device: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    _ = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
    }
    return value as String
}

var devicesAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var devicesSize: UInt32 = 0
guard AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil,
    &devicesSize) == noErr else { exit(1) }

var devices = [AudioDeviceID](
    repeating: 0,
    count: Int(devicesSize) / MemoryLayout<AudioDeviceID>.size)
guard AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil,
    &devicesSize, &devices) == noErr else { exit(1) }

guard let xiao = devices.first(where: {
    deviceName($0).contains("XIAO Voice Keyboard Microphone")
}) else {
    print("ERROR: XIAO microphone not found")
    exit(2)
}

var defaultAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var selected = xiao
let selectStatus = AudioObjectSetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil,
    UInt32(MemoryLayout<AudioDeviceID>.size), &selected)
print("Selected:", selectStatus, xiao, deviceName(xiao))

let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
let outputURL = URL(fileURLWithPath: "/tmp/xiao-mic-test.wav")
try? FileManager.default.removeItem(at: outputURL)
let file = try AVAudioFile(forWriting: outputURL,
                           settings: format.settings,
                           commonFormat: .pcmFormatFloat32,
                           interleaved: false)

let lock = NSLock()
var totalFrames: UInt64 = 0
var globalPeak: Float = 0
var globalSquares: Double = 0

input.installTap(onBus: 0, bufferSize: 1600, format: format) { buffer, _ in
    guard let samples = buffer.floatChannelData?[0] else { return }
    var framePeak: Float = 0
    var squares: Double = 0
    for i in 0..<Int(buffer.frameLength) {
        let sample = samples[i]
        framePeak = max(framePeak, abs(sample))
        squares += Double(sample * sample)
    }
    do { try file.write(from: buffer) } catch {
        print("WRITE ERROR:", error)
    }
    lock.lock()
    totalFrames += UInt64(buffer.frameLength)
    globalPeak = max(globalPeak, framePeak)
    globalSquares += squares
    lock.unlock()
    print("LEVEL peak=\(framePeak) rms=\(sqrt(squares / Double(max(1, buffer.frameLength))))")
}

do {
    try engine.start()
    print("RECORDING 10 SECONDS ->", outputURL.path)
    RunLoop.current.run(until: Date().addingTimeInterval(10))
    engine.stop()
    lock.lock()
    let frames = totalFrames
    let peak = globalPeak
    let rms = sqrt(globalSquares / Double(max(1, totalFrames)))
    lock.unlock()
    print("RESULT frames=\(frames) peak=\(peak) rms=\(rms)")
} catch {
    print("AUDIO ERROR:", error)
    exit(3)
}
