import Foundation
import os

/// Raw finger data from MultitouchSupport.framework.
/// Memory layout must exactly match the C struct.
struct Finger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32 // 1=not-touching, 2=starting, 3=hovering, 4=touching, 5=staying, 7=lifting
    var fingerData1: Int32
    var fingerData2: Int32
    var normalizedX: Float // 0.0 – 1.0
    var normalizedY: Float // 0.0 – 1.0
    var velocityX: Float
    var velocityY: Float
    var reserved1: Int32
    var reserved2: Float
    var size: Float
    var reserved3: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var normalizedX2: Float
    var normalizedY2: Float
    var reserved4: Int32
    var reserved5: Int32
    var reserved6: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer

/// Callback signature: (device, fingers, fingerCount, timestamp, frame) -> Int32
/// fingers is UnsafeMutableRawPointer? to make it compatible with C conventions.
typealias MTContactFrameCallback = @convention(c) (
    MTDeviceRef?, // device
    UnsafeMutableRawPointer?, // finger array
    Int32, // finger count
    Double, // timestamp
    Int32 // frame
) -> Int32

final class MultitouchBridge {
    static let shared = MultitouchBridge()

    private var frameworkHandle: UnsafeMutableRawPointer?

    // Dynamically resolved function pointers
    private(set) var deviceCreateList: (@convention(c) () -> Unmanaged<CFArray>?)?
    private(set) var deviceStart: (@convention(c) (MTDeviceRef, Int32) -> Void)?
    private(set) var deviceStop: (@convention(c) (MTDeviceRef) -> Void)?
    private(set) var registerContactFrameCallback: (@convention(c) (MTDeviceRef, MTContactFrameCallback) -> Void)?
    private(set) var unregisterContactFrameCallback: (@convention(c) (MTDeviceRef, MTContactFrameCallback) -> Void)?

    var isLoaded: Bool {
        frameworkHandle != nil
    }

    private init() {}

    func ensureLoaded() {
        guard frameworkHandle == nil else { return }
        loadFramework()
    }

    func unloadFramework() {
        guard let handle = frameworkHandle else { return }
        dlclose(handle)
        frameworkHandle = nil
        deviceCreateList = nil
        deviceStart = nil
        deviceStop = nil
        registerContactFrameCallback = nil
        unregisterContactFrameCallback = nil
        AppLogger.multitouch.info("Unloaded MultitouchSupport.framework")
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/A/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            let errorMsg = dlerror().map { String(cString: $0) } ?? "unknown"
            AppLogger.multitouch.error("Failed to load MultitouchSupport.framework: \(errorMsg, privacy: .public)")
            return
        }

        self.frameworkHandle = handle

        if let sym = dlsym(handle, "MTDeviceCreateList") {
            deviceCreateList = unsafeBitCast(sym, to: (@convention(c) () -> Unmanaged<CFArray>?).self)
        }
        if let sym = dlsym(handle, "MTDeviceStart") {
            deviceStart = unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStop") {
            deviceStop = unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef) -> Void).self)
        }
        if let sym = dlsym(handle, "MTRegisterContactFrameCallback") {
            registerContactFrameCallback = unsafeBitCast(
                sym,
                to: (@convention(c) (MTDeviceRef, MTContactFrameCallback) -> Void).self
            )
        }
        if let sym = dlsym(handle, "MTUnregisterContactFrameCallback") {
            unregisterContactFrameCallback = unsafeBitCast(
                sym,
                to: (@convention(c) (MTDeviceRef, MTContactFrameCallback) -> Void).self
            )
        }

        AppLogger.multitouch.info("Successfully loaded and resolved framework symbols")
    }

    deinit {
        unloadFramework()
    }
}
