//  HandsetView.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import SwiftUI

struct HandsetView: View {
    let model: PhoneModel
    @State private var showingPairing = false

    var body: some View {
        VStack(spacing: 20) {
            header
            transcript
            TalkButton(model: model)
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("handset.hint")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showingPairing) { PairingView(model: model) }
        .onAppear {
            if !model.isPaired {
                showingPairing = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("Fleet Comms")
                .accessibilityIdentifier("handset.icon")
            VStack(alignment: .leading, spacing: 2) {
                Text("Fleet Comms").font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("handset.status")
                }
            }
            Spacer()
            Button("Pairing", systemImage: "link") { showingPairing = true }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("handset.pairing")
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.transcript.isEmpty {
                        Text(model.transcript).foregroundStyle(.secondary)
                            .accessibilityIdentifier("handset.transcript")
                    }
                    if !model.replyText.isEmpty {
                        spoken.id("reply").accessibilityIdentifier("handset.reply")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title3)
            }
            .onChange(of: model.spokenOffset) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    /// While the voice speaks, only the words said so far show, each fading in over 200 ms. Once it stops
    /// or finishes, the words not said show dimmed.
    private var spoken: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isSpeaking)) { _ in
            revealed(now: CACurrentMediaTime())
        }
    }

    // swiftlint:disable shorthand_operator
    private func revealed(now: Double) -> Text {
        let text = model.replyText
        let utf16 = text.utf16
        func slice(_ from: Int, _ upTo: Int) -> String {
            let start = String.Index(utf16Offset: min(from, utf16.count), in: text)
            return String(text[start ..< String.Index(utf16Offset: min(upTo, utf16.count), in: text)])
        }
        var result = Text("")
        var done = 0
        for mark in model.revealMarks where mark.end > done {
            let alpha = model.isSpeaking ? min(1, max(0, (now - mark.time) / 0.2)) : 1
            result = result + Text(slice(done, mark.end)).foregroundStyle(Color.white.opacity(alpha))
            done = mark.end
        }
        if !model.isSpeaking, done < utf16.count {
            result = result + Text(slice(done, utf16.count)).foregroundStyle(.secondary)
        }
        return result
    }
    // swiftlint:enable shorthand_operator

    private var statusText: String {
        switch model.link {
        case .unpaired: "Not paired"
        case .connecting: "Connecting…"
        case let .failed(reason): reason
        case .connected:
            switch model.macState {
            case "listening": "Listening…"
            case "sending": "Sending to Firstmate…"
            case "thinking": "Thinking…"
            case "waiting": "Sent. Waiting for the reply…"
            case "preparing": "Mac is loading models…"
            case "message": model.macMessage
            default: "Connected"
            }
        }
    }

    private var statusColor: Color {
        switch model.link {
        case .connected: .green
        case .connecting: .orange
        default: .red
        }
    }

    private var hint: String {
        model.isTalking
            ? "Release to send, or pause. Tap again to send now."
            : "Hold to talk. Tap once and pause also works."
    }
}

struct TalkButton: View {
    let model: PhoneModel
    @State private var pressed = false

    var body: some View {
        let ring = model.isTalking ? Color.red : Color.accentColor
        Circle()
            .fill(model.isTalking ? Color.red : Color(red: 0.08, green: 0.09, blue: 0.12))
            .frame(width: 150, height: 150)
            .overlay(Circle().strokeBorder(ring, lineWidth: 4))
            .shadow(color: ring.opacity(0.5), radius: 18)
            .overlay(
                Image(systemName: "mic.fill").font(.system(size: 54))
                    .foregroundStyle(model.isTalking ? Color.white : Color.accentColor)
            )
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(model.isConnected ? 1 : 0.35)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    model.pressDown()
                }
                .onEnded { _ in
                    pressed = false
                    model.pressUp()
                })
            .accessibilityLabel("Talk")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("handset.talk")
    }
}

struct PairingView: View {
    let model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var pasted = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("BrandIcon")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Fleet Comms")
                        .accessibilityIdentifier("pairing.icon")
                }
                Section {
                    if PairingScanner.isSupported {
                        Button("Scan QR Code", systemImage: "qrcode.viewfinder") { scanning = true }
                            .accessibilityIdentifier("pairing.scan")
                    }
                    TextField("Or paste the link", text: $pasted)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pairing.link")
                    Button("Pair") { accept(pasted) }
                        .disabled(pasted.isEmpty)
                        .accessibilityIdentifier("pairing.pair")
                } footer: {
                    Text(problem ?? "On the Mac: Fleet Comms › Settings › Advanced › Phone link › Pair iPhone…")
                }
                if model.isPaired {
                    Section("Paired with \(model.mac.name)") {
                        Button("Connect") {
                            model.connect()
                            dismiss()
                        }
                        .accessibilityIdentifier("pairing.connect")
                    }
                }
            }
            .navigationTitle("Pair with your Mac")
            .fullScreenCover(isPresented: $scanning) {
                PairingScanner { text in
                    scanning = false
                    accept(text)
                }
            }
        }
    }

    private func accept(_ text: String) {
        if model.pair(with: text) {
            dismiss()
        } else {
            problem = "That is not a Fleet Comms pairing code."
        }
    }
}
