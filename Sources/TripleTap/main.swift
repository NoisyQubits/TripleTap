import Darwin
import Foundation

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

/// Reverse-engineered `MTContact` layout used by MultitouchSupport on arm64.
/// Keep this private-framework type isolated so its layout can be updated
/// independently if a later macOS release changes it.
struct MTContact {
    let frame: Int32
    let timestamp: Double
    let identifier: Int32
    let state: Int32
    let fingerID: Int32
    let x: Float
    let y: Float
    let z: Float
    let majorAxis: Float
    let minorAxis: Float
    let angle: Float
    let size: Float
    let xVelocity: Float
    let yVelocity: Float
}

func contactFrameCallback(
    _: MultitouchAPI.Device,
    _ contacts: UnsafeRawPointer?,
    _ fingerCount: Int32,
    _: Double,
    _: Int32
) -> Int32 {
    print("Frame")
    print("Finger count: \(fingerCount)")

    guard fingerCount > 0, let contacts else {
        print("")
        return 0
    }

    let contactsPointer = contacts.assumingMemoryBound(to: MTContact.self)
    for index in 0..<Int(fingerCount) {
        let contact = contactsPointer[index]
        print("\nFinger \(index)")
        print("x: \(contact.x)")
        print("y: \(contact.y)")
        print("state: \(contact.state)")
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

if arguments.contains("--frames") {
    guard count > 0 else { exit(EXIT_SUCCESS) }

    for index in 0..<count {
        guard let rawDevice = CFArrayGetValueAtIndex(devices, index) else { continue }
        let device = UnsafeMutableRawPointer(mutating: rawDevice)
        multitouch.registerContactFrameCallback(device, contactFrameCallback)
        multitouch.start(device, 0)
    }
    print("Listening for touch frames. Press Control-C to stop.")
    RunLoop.main.run()
}
