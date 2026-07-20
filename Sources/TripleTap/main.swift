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

let expectedSymbols = [
    "MTDeviceCreateList",
    "MTDeviceStart",
    "MTDeviceStop",
    "MTRegisterContactFrameCallback",
    "MTUnregisterContactFrameCallback"
]

for symbol in expectedSymbols {
    let status = MultitouchSupport.resolve(symbol, in: framework) == nil ? "missing" : "available"
    print("\(symbol): \(status)")
}

if arguments.contains("--symbols") {
    print("\nExported global symbols:")
    exit(printExportedSymbols(at: MultitouchSupport.frameworkPath))
}
