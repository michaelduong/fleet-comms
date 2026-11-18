//  PhonePairSheet.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The one-time QR code the handset scans, with Copy Link for when the camera cannot be used.
struct PhonePairSheet: View {
    let pairings: PhonePairings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            if let code = pairings.code, let link = PhoneAddress.link(for: code).url {
                Image(nsImage: Self.qr(link.absoluteString))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .accessibilityLabel("Pairing code")
                    .accessibilityIdentifier("settings.advanced.phoneQR")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Works once, for \(max(0, Int(code.expires.timeIntervalSince(context.date)))) more seconds.")
                        .foregroundStyle(.secondary)
                }
                Text("In Fleet Comms on your iPhone, tap Pairing, then Scan.").font(.callout)
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                }
                .accessibilityIdentifier("settings.advanced.phoneCopyLink")
            } else if let phone = pairings.lastPaired {
                Label("\(phone.name) is paired.", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("settings.advanced.phonePaired")
            } else {
                Text("The code ran out. Close this and tap Pair iPhone again.")
                    .accessibilityIdentifier("settings.advanced.phoneExpired")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("settings.advanced.phonePairDone")
        }
        .padding(24)
        .frame(width: 320)
        .onAppear { pairings.beginPairing() }
        .onDisappear { pairings.cancelPairing() }
    }

    private static func qr(_ text: String) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = context.createCGImage(output, from: output.extent) else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
