//
//  SLS.swift — runtime bridge to the private SkyLight (SLS/CGS) API.
//
//  Signatures confirmed against real sources (never trust memory for private APIs):
//    • koekeishiya/yabai     src/misc/extern.h   (uint64_t space ids, tag signatures)
//    • FelixKratz/SketchyBar src/window.{c,h}    (tag bit constants, space route)
//
//  We bind every symbol with dlsym(RTLD_DEFAULT, …) rather than linking
//  -framework SkyLight, because the framework binary exists only in the dyld
//  shared cache (the on-disk SkyLight.framework/Versions/A/ has no Mach-O). AppKit
//  loads SkyLight into the process for us, so RTLD_DEFAULT can see every symbol.
//

import Foundation

// RTLD_DEFAULT on Darwin is the sentinel (void *)-2.
private let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

/// Resolve a symbol from the already-loaded images, cast to a @convention(c) type.
/// Returns nil (and records the name) if the symbol is missing on this OS.
private func bind<T>(_ name: String, as type: T.Type) -> T? {
    guard let p = dlsym(RTLD_DEFAULT, name) else {
        SLS.missing.insert(name)
        return nil
    }
    return unsafeBitCast(p, to: T.self)
}

// MARK: - C function signatures (typed)

private typealias Fn_MainConnectionID = @convention(c) () -> Int32
private typealias Fn_SetWindowLevel   = @convention(c) (Int32, UInt32, Int32) -> Int32
private typealias Fn_SetWindowSubLevel = @convention(c) (Int32, UInt32, Int32) -> Int32
private typealias Fn_SetWindowTags    = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt64>?, Int32) -> Int32
private typealias Fn_ClearWindowTags  = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt64>?, Int32) -> Int32
private typealias Fn_SetWindowOpacity = @convention(c) (Int32, UInt32, Bool) -> Int32
private typealias Fn_CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray?) -> Unmanaged<CFArray>?
private typealias Fn_ManagedDisplayGetCurrentSpace = @convention(c) (Int32, CFString?) -> UInt64
// Dedicated-space ("maximal stickiness") route — used only with --space.
private typealias Fn_SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
private typealias Fn_SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Void
private typealias Fn_SpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, UInt64, CFArray?, Int32) -> Void
private typealias Fn_ShowSpaces = @convention(c) (Int32, CFArray?) -> Void

/// Thin, lazily-bound facade over the private SkyLight surface noribar needs.
/// All private-API access is contained here, behind the `WindowBackend` boundary (D3).
enum SLS {
    /// Symbols that failed to bind on this OS (a valid finding to report).
    static var missing = Set<String>()

    // Tag bits — verbatim from SketchyBar src/window.h.
    static let kCGSExposeFadeTagBit: UInt64         = (1 << 1)
    static let kCGSPreventsActivationTagBit: UInt64 = (1 << 16)
    // "Sticky"/all-spaces tag bit observed in reverse-engineered CGSInternal headers.
    // AppKit's .canJoinAllSpaces already covers all-spaces, so this is belt-and-braces.
    static let kCGSStickyTagBit: UInt64             = (1 << 0)

    private static let _mainConnectionID = bind("SLSMainConnectionID", as: Fn_MainConnectionID.self)
    private static let _setWindowLevel   = bind("SLSSetWindowLevel", as: Fn_SetWindowLevel.self)
    private static let _setWindowSubLevel = bind("SLSSetWindowSubLevel", as: Fn_SetWindowSubLevel.self)
    private static let _setWindowTags    = bind("SLSSetWindowTags", as: Fn_SetWindowTags.self)
    private static let _clearWindowTags  = bind("SLSClearWindowTags", as: Fn_ClearWindowTags.self)
    private static let _setWindowOpacity = bind("SLSSetWindowOpacity", as: Fn_SetWindowOpacity.self)
    private static let _copySpacesForWindows = bind("SLSCopySpacesForWindows", as: Fn_CopySpacesForWindows.self)
    private static let _currentSpace =
        bind("SLSManagedDisplayGetCurrentSpace", as: Fn_ManagedDisplayGetCurrentSpace.self)
    private static let _spaceCreate = bind("SLSSpaceCreate", as: Fn_SpaceCreate.self)
    private static let _spaceSetAbsoluteLevel = bind("SLSSpaceSetAbsoluteLevel", as: Fn_SpaceSetAbsoluteLevel.self)
    private static let _spaceAddWindows =
        bind("SLSSpaceAddWindowsAndRemoveFromSpaces", as: Fn_SpaceAddWindowsAndRemoveFromSpaces.self)
    private static let _showSpaces = bind("SLSShowSpaces", as: Fn_ShowSpaces.self)

    static var mainConnectionID: Int32 { _mainConnectionID?() ?? -1 }

    @discardableResult
    static func setWindowLevel(_ cid: Int32, _ wid: UInt32, _ level: Int32) -> Int32 {
        _setWindowLevel?(cid, wid, level) ?? -1
    }

    @discardableResult
    static func setWindowSubLevel(_ cid: Int32, _ wid: UInt32, _ sub: Int32) -> Int32 {
        _setWindowSubLevel?(cid, wid, sub) ?? -1
    }

    @discardableResult
    static func setWindowTags(_ cid: Int32, _ wid: UInt32, _ tag: UInt64) -> Int32 {
        var t = tag
        return _setWindowTags?(cid, wid, &t, 64) ?? -1
    }

    @discardableResult
    static func clearWindowTags(_ cid: Int32, _ wid: UInt32, _ tag: UInt64) -> Int32 {
        var t = tag
        return _clearWindowTags?(cid, wid, &t, 64) ?? -1
    }

    /// How many spaces does this window currently belong to? (selector 0x7 = all spaces).
    /// A count > 1 (or == number of user spaces) is direct evidence of all-Spaces behavior.
    static func spaceCount(forWindow wid: UInt32) -> Int {
        guard let f = _copySpacesForWindows else { return -1 }
        let windows = [wid] as CFArray
        guard let arr = f(mainConnectionID, 0x7, windows)?.takeRetainedValue() else { return -1 }
        return CFArrayGetCount(arr)
    }

    // --- Dedicated-space route (only with --space) ----------------------------
    static func createSpace() -> UInt64 { _spaceCreate?(mainConnectionID, 0, 0) ?? 0 }
    static func setSpaceAbsoluteLevel(_ sid: UInt64, _ level: Int32) {
        _spaceSetAbsoluteLevel?(mainConnectionID, sid, level)
    }
    static func showSpace(_ sid: UInt64) { _showSpaces?(mainConnectionID, [sid] as CFArray) }
    static func addWindow(_ wid: UInt32, toSpace sid: UInt64) {
        _spaceAddWindows?(mainConnectionID, sid, [wid] as CFArray, 0x7)
    }
}
