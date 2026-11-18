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
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.subheadline).accessibilityIdentifier("handset.status")
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

    /// Words already spoken are bright, the rest dim, so the text follows the voice as on the desktop.
    private var spoken: Text {
        let text = model.replyText
        let index = String.Index(utf16Offset: min(model.spokenOffset, text.utf16.count), in: text)
        return Text(text[..<index]).foregroundStyle(.white) + Text(text[index...]).foregroundStyle(.secondary)
    }

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
        Circle()
            .fill(model.isTalking ? Color.red : Color.accentColor)
            .frame(width: 150, height: 150)
            .overlay(Image(systemName: "mic.fill").font(.system(size: 54)).foregroundStyle(.white))
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
    @Bindable var model: PhoneModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host or Tailscale name", text: $model.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pairing.host")
                    TextField("Pairing code", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pairing.code")
                } footer: {
                    Text(
                        "On the Mac: Fleet Comms › Settings › Advanced › Phone link. "
                            + "Turn it on, then copy the host and code."
                    )
                }
                Button("Connect") {
                    model.connect()
                    dismiss()
                }
                .disabled(!model.isPaired)
                .accessibilityIdentifier("pairing.connect")
            }
            .navigationTitle("Pair with your Mac")
        }
    }
}
