//  PairingScanner.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import SwiftUI
import VisionKit

/// The in-app QR reader. Only this screen reads pairing codes, never the Camera app.
struct PairingScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    /// False in the Simulator and on devices without a camera; the Pair screen then offers Paste Link.
    @MainActor static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !done else { return }
            for case let .barcode(code) in addedItems {
                if let text = code.payloadStringValue, PhonePairingLink(text) != nil {
                    done = true
                    return onCode(text)
                }
            }
        }
    }
}
