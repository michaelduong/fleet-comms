// swift-tools-version: 5.9

// Microsoft's ONNX Runtime 1.24.2 Swift package, rebuilt from Microsoft's own downloads after its
// GitHub repositories (microsoft/onnxruntime-swift-package-manager, microsoft/onnxruntime) started
// returning 404. `objectivec/` is the unmodified content of
// https://download.onnxruntime.ai/pod-archive-onnxruntime-objc-1.24.2.zip (tests omitted); every file
// is identical to the same path in Microsoft's 1.24.2 release commit of the Swift package. The binary
// target below uses the URL and SHA-256 checksum from that release's Package.swift.

import PackageDescription

let package = Package(
    name: "onnxruntime",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "onnxruntime", type: .static, targets: ["OnnxRuntimeBindings"]),
    ],
    targets: [
        .target(name: "OnnxRuntimeBindings",
                dependencies: ["onnxruntime"],
                path: "objectivec",
                cxxSettings: [.define("SPM_BUILD")]),
        .binaryTarget(name: "onnxruntime",
                      url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip",
                      checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"),
    ],
    cxxLanguageStandard: .cxx17
)
