// swift-tools-version:5.9
import PackageDescription

// Spike B — throwaway de-risking spike for noribar.
// Embeds vanilla Lua 5.4.7 (MIT) as a SwiftPM C target and drives a live,
// hot-reloadable bar rendered in a plain NSWindow (public AppKit only).
let package = Package(
    name: "SpikeB",
    platforms: [.macOS(.v13)],
    targets: [
        // Vendored Lua 5.4.7 C sources, compiled as a SwiftPM C target.
        // src/  -> the .c implementation files (lua.c / luac.c omitted: they carry main())
        // include/ -> all Lua headers + an umbrella exposing only the public API to Swift.
        .target(
            name: "CLua",
            path: "Sources/CLua",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                // Lua's own macOS configuration switch: enables LUA_USE_POSIX +
                // dlopen-based package loading. See luaconf.h.
                .define("LUA_USE_MACOSX"),
                // The vendored .c files #include "lua.h" etc. with quotes; point the
                // compiler at the header directory so those resolve.
                .headerSearchPath("include"),
            ]
        ),
        .executableTarget(
            name: "SpikeB",
            dependencies: ["CLua"],
            path: "Sources/SpikeB"
        ),
    ]
)
