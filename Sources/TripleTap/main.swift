import Darwin
import Foundation
import AppKit

enum MultitouchSupport {
    static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/A/MultitouchSupport"

    /// Keep the handle alive for the entire process lifetime: pointers returned
    /// by `dlsym` become invalid after `dlclose`.
    static func load() -> UnsafeMutableRawPointer? {
        let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL)
        guard handle == nil else { return handle }

        let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
        FileHandle.standardError.write(Data("Could not load MultitouchSupport: \(reason)\n".utf8))
        return nil
    }

    static func resolve(_ symbol: String, in handle: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        dlerror() // Clear a stale loader error before dlsym.
        let pointer = dlsym(handle, symbol)
        guard pointer == nil else { return pointer }
        return nil
    }
}

/// The private framework has no public Swift module. These ABI declarations
/// match the symbols currently exported by Tahoe and are intentionally kept
/// behind runtime lookup.
struct MultitouchAPI {
    typealias Device = UnsafeMutableRawPointer
    typealias DeviceCreateList = @convention(c) () -> CFArray?
    typealias DeviceStart = @convention(c) (Device, Int32) -> Void
    typealias DeviceStop = @convention(c) (Device) -> Void
    typealias ContactFrameCallback = @convention(c) (Device, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    typealias RegisterContactFrameCallback = @convention(c) (Device, ContactFrameCallback) -> Void
    typealias UnregisterContactFrameCallback = @convention(c) (Device, ContactFrameCallback) -> Void
    typealias DeviceGetDeviceID = @convention(c) (Device, UnsafeMutablePointer<Int32>) -> Void

    let createDeviceList: DeviceCreateList
    let start: DeviceStart
    let stop: DeviceStop
    let registerContactFrameCallback: RegisterContactFrameCallback
    let unregisterContactFrameCallback: UnregisterContactFrameCallback
    let deviceID: DeviceGetDeviceID?

    init?(handle: UnsafeMutableRawPointer) {
        func bind<T>(_ name: String, as _: T.Type) -> T? {
            guard let symbol = MultitouchSupport.resolve(name, in: handle) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }

        guard
            let createDeviceList = bind("MTDeviceCreateList", as: DeviceCreateList.self),
            let start = bind("MTDeviceStart", as: DeviceStart.self),
            let stop = bind("MTDeviceStop", as: DeviceStop.self),
            let register = bind("MTRegisterContactFrameCallback", as: RegisterContactFrameCallback.self),
            let unregister = bind("MTUnregisterContactFrameCallback", as: UnregisterContactFrameCallback.self)
        else { return nil }

        self.createDeviceList = createDeviceList
        self.start = start
        self.stop = stop
        self.registerContactFrameCallback = register
        self.unregisterContactFrameCallback = unregister
        self.deviceID = bind("MTDeviceGetDeviceID", as: DeviceGetDeviceID.self)
    }
}

struct MTPoint {
    let x: Float
    let y: Float
}

struct MTReadout {
    let position: MTPoint
    let velocity: MTPoint
}

/// The known 96-byte contact record layout. The four Int32 values between the
/// timestamp and normalized readout are essential: omitting two of the unknown
/// fields makes the second record be decoded at the wrong byte offset.
struct MTTouch {
    let frame: Int32
    let timestamp: Double
    let identifier: Int32
    let state: Int32
    let unknown1: Int32
    let unknown2: Int32
    let normalized: MTReadout
    let size: Float
    let unknown3: Int32
    let angle: Float
    let majorAxis: Float
    let minorAxis: Float
    let millimeters: MTReadout
    let unknown4: Int32
    let unknown5: Int32
    let unknown6: Float
}

let frameDiagnosticsEnabled = CommandLine.arguments.contains("--frames")
let rawDiagnosticsEnabled = CommandLine.arguments.contains("--raw")

enum MTTouchState: Int32 {
    case makeTouch = 3
    case touching = 4
}

final class GestureRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = ThreeFingerClickDetector()

    func process(activeTouchCount: Int, rawTouchCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return detector.process(
            activeTouchCount: activeTouchCount,
            rawTouchCount: rawTouchCount,
            now: ContinuousClock().now
        )
    }
}

let gestureRuntime = GestureRuntime()

func emitPlayPause() {
    // IOKit's ev_keymap.h defines NX_KEYTYPE_PLAY as 16. The system-defined
    // event payload is the same down/up encoding produced by the media key.
    let keyType = 16
    for flags in [0xA, 0xB] { // NX_KEYDOWN, NX_KEYUP
        let data1 = (keyType << 16) | (flags << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { continue }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}

func hexBytes(from pointer: UnsafeRawPointer, count: Int) -> String {
    let bytes = UnsafeRawBufferPointer(start: pointer, count: count)
    return bytes.enumerated().map { index, byte in
        let separator = index > 0 && index % 16 == 0 ? "\n" : (index > 0 ? " " : "")
        return separator + String(format: "%02X", byte)
    }.joined()
}

func contactFrameCallback(
    _: MultitouchAPI.Device,
    _ contacts: UnsafeRawPointer?,
    _ fingerCount: Int32,
    _: Double,
    _: Int32
) -> Int32 {
    let rawCount = max(0, Int(fingerCount))
    guard rawCount > 0, let contacts else {
        if gestureRuntime.process(activeTouchCount: 0, rawTouchCount: 0) {
            print("Three-finger click detected")
            emitPlayPause()
        }
        return 0
    }

    let contactsPointer = contacts.assumingMemoryBound(to: MTTouch.self)
    var activeTouchCount = 0
    for index in 0..<rawCount {
        let contact = contactsPointer[index]
        if MTTouchState(rawValue: contact.state) == .makeTouch || MTTouchState(rawValue: contact.state) == .touching {
            activeTouchCount += 1
        }
    }

    if gestureRuntime.process(activeTouchCount: activeTouchCount, rawTouchCount: rawCount) {
        print("Three-finger click detected")
        emitPlayPause()
    }

    guard frameDiagnosticsEnabled else { return 0 }
    print("Frame")
    print("Finger count: \(fingerCount), active: \(activeTouchCount)")
    for index in 0..<rawCount {
        let contact = contactsPointer[index]
        print("\nFinger \(index)")
        print("identifier: \(contact.identifier)")
        print("x: \(contact.normalized.position.x)")
        print("y: \(contact.normalized.position.y)")
        print("state: \(contact.state)")
        print("size: \(contact.size)")
        if rawDiagnosticsEnabled {
            let record = UnsafeRawPointer(contactsPointer.advanced(by: index))
            print("Raw MTTouch (\(MemoryLayout<MTTouch>.stride) bytes)")
            print(hexBytes(from: record, count: MemoryLayout<MTTouch>.stride))
        }
    }
    print("")
    return 0
}

@discardableResult
func printExportedSymbols(at frameworkPath: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
    process.arguments = ["-gU", frameworkPath]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        FileHandle.standardError.write(Data("Unable to run nm: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

let arguments = Set(CommandLine.arguments.dropFirst())
guard let framework = MultitouchSupport.load() else { exit(EXIT_FAILURE) }
defer { dlclose(framework) }

print("Loaded MultitouchSupport.framework")
print("Path: \(MultitouchSupport.frameworkPath)")

guard let multitouch = MultitouchAPI(handle: framework) else {
    FileHandle.standardError.write(Data("Required MultitouchSupport symbols are unavailable.\n".utf8))
    exit(EXIT_FAILURE)
}
print("Required MultitouchSupport symbols: available")

if arguments.contains("--layout") {
    print("MTTouch size: \(MemoryLayout<MTTouch>.size) bytes")
    print("MTTouch stride: \(MemoryLayout<MTTouch>.stride) bytes")
    print("MTTouch alignment: \(MemoryLayout<MTTouch>.alignment) bytes")
    print("Pointer width: \(MemoryLayout<UnsafeRawPointer>.size) bytes")
    print("Offsets: frame=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.frame)!), timestamp=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.timestamp)!), identifier=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.identifier)!), state=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.state)!), normalized=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.normalized)!), size=\(MemoryLayout<MTTouch>.offset(of: \MTTouch.size)!)")
    exit(EXIT_SUCCESS)
}

if arguments.contains("--symbols") {
    print("\nExported global symbols:")
    exit(printExportedSymbols(at: MultitouchSupport.frameworkPath))
}

guard let devices = multitouch.createDeviceList() else {
    FileHandle.standardError.write(Data("MTDeviceCreateList returned no device list.\n".utf8))
    exit(EXIT_FAILURE)
}

let count = CFArrayGetCount(devices)
print("Found \(count) trackpad\(count == 1 ? "" : "s")")
for index in 0..<count {
    guard let rawDevice = CFArrayGetValueAtIndex(devices, index) else { continue }
    let device = UnsafeMutableRawPointer(mutating: rawDevice)
    if let deviceID = multitouch.deviceID {
        var id: Int32 = 0
        deviceID(device, &id)
        print("Trackpad \(index): device ID \(id)")
    } else {
        print("Trackpad \(index): device handle \(device)")
    }
}

if arguments.contains("--frames") || arguments.contains("--listen") {
    guard count > 0 else { exit(EXIT_SUCCESS) }

    for index in 0..<count {
        guard let rawDevice = CFArrayGetValueAtIndex(devices, index) else { continue }
        let device = UnsafeMutableRawPointer(mutating: rawDevice)
        multitouch.registerContactFrameCallback(device, contactFrameCallback)
        multitouch.start(device, 0)
    }
    print(frameDiagnosticsEnabled ? "Listening for touch frames. Press Control-C to stop." : "Listening for three-finger clicks. Press Control-C to stop.")
    RunLoop.main.run()
}
