// swift-tools-version:5.9
//
// Spike A — throwaway de-risking executable.
// Goal: prove an AppKit/CALayer view tree running native SF Symbol effects can live
// inside a window that also has SkyLight ricing powers (all-Spaces, over-fullscreen,
// non-activating). Not the product.
//
// Note on the private SkyLight (SLS/CGS) API:
// SkyLight.framework ships ONLY inside the dyld shared cache — there is no on-disk
// Mach-O to link against — so `-framework SkyLight` is fragile. AppKit already pulls
// SkyLight into every GUI process, so we resolve the private symbols at runtime via
// dlsym(RTLD_DEFAULT, …) instead (see Sources/SpikeA/SLS.swift). That means this
// package needs NO special linker flags and NO bridging header.

import PackageDescription

let package = Package(
    name: "SpikeA",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpikeA",
            path: "Sources/SpikeA"
        )
    ],
    swiftLanguageVersions: [.v5]
)
