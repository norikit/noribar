// swift-tools-version:5.9
//
// noribar — a Swift macOS menu-bar replacement built around native animated SF Symbols,
// configured in embedded Lua, hosted in a private-SkyLight window.
//
// This is the first real product package (milestone M1): it promotes the two proven
// de-risking spikes (A: SkyLight-hosted AppKit symbol effects; B: embedded Lua runtime)
// into one app and wires the seam between them.
//
// Note on the private SkyLight (SLS/CGS) API: SkyLight.framework ships only inside the
// dyld shared cache (no on-disk Mach-O), so we resolve its symbols at runtime via
// dlsym(RTLD_DEFAULT, …) (see Sources/noribar/Window/SLS.swift) — no linker flags needed.

import PackageDescription

let package = Package(
    name: "noribar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "noribar", targets: ["noribar"]),
    ],
    targets: [
        // Vendored Lua 5.4.7 (MIT), compiled as a SwiftPM C target. Lifted verbatim from
        // Spike B — see Sources/CLua/VENDORING.md.
        .target(
            name: "CLua",
            path: "Sources/CLua",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .define("LUA_USE_MACOSX"),
                .headerSearchPath("include"),
            ]
        ),
        .executableTarget(
            name: "noribar",
            dependencies: ["CLua"],
            path: "Sources/noribar"
        ),
        .testTarget(
            name: "noribarTests",
            dependencies: ["noribar"],
            path: "Tests/noribarTests"
        ),
    ]
)
