//  PushToTalk.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AVFoundation
import Foundation
import PushToTalk
import UIKit

/// Apple Push to Talk: a channel that gives the lock screen a Talk button and lets the Mac wake the app
/// to play a reply. The Mac sends a `pushtotalk` push to the ephemeral token this reports.
@MainActor
final class PushToTalkChannel: NSObject {
    private var manager: PTChannelManager?
    private let channelID = UUID(uuidString: "6F1E7B8A-4C3D-4E55-9A10-FC0000000001")!
    /// The Fleet Comms icon, shown on the lock screen's Push to Talk card.
    private nonisolated static var brandImage: UIImage? { UIImage(named: "BrandIcon") }

    var onToken: ((Data) -> Void)?
    var onTalkBegan: (() -> Void)?
    var onTalkEnded: (() -> Void)?
    var onIncomingReply: (() -> Void)?

    func join() async {
        guard manager == nil else { return }
        guard let manager = try? await PTChannelManager.channelManager(delegate: self, restorationDelegate: self) else {
            return
        }
        self.manager = manager
        let descriptor = PTChannelDescriptor(name: "First mate", image: Self.brandImage)
        manager.requestJoinChannel(channelUUID: channelID, descriptor: descriptor)
    }

    func leave() {
        manager?.leaveChannel(channelUUID: channelID)
    }

    func setTalking(_ talking: Bool) {
        manager?.setTransmissionMode(talking ? .fullDuplex : .listenOnly, channelUUID: channelID) { _ in }
    }
}

extension PushToTalkChannel: PTChannelManagerDelegate, PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        PTChannelDescriptor(name: "First mate", image: Self.brandImage)
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {}
    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {}
    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in onTalkBegan?() }
    }
    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        Task { @MainActor in onTalkEnded?() }
    }
    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        Task { @MainActor in onToken?(pushToken) }
    }
    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        Task { @MainActor in onIncomingReply?() }
        return .activeRemoteParticipant(PTParticipant(name: "First mate", image: Self.brandImage))
    }
    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {}
    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {}
    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: any Error) {}
    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: any Error) {}
}
