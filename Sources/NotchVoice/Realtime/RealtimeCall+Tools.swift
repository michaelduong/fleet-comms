//  RealtimeCall+Tools.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension RealtimeCall {
    func handleToolCall(callID: String, name: String, arguments: String) {
        guard !ended else { return }
        #if DEBUG
            observeToolCall?(name, arguments)
        #endif
        let endpoint = turn?.endpoint ?? Endpoint(detected: Date(), lastSpeech: Date())
        let turnID = turn?.id ?? "none"
        pendingTools += 1
        lastActivity = Date()
        Task {
            guard !ended else { return }
            let output = await toolOutput(name: name, arguments: arguments, endpoint: endpoint, turnID: turnID)
            guard !ended else { return }
            socket?.send(RealtimeWire.toolResult(callID: callID, output: output))
            pendingTools -= 1
            lastActivity = Date()
            toolResponsePending = true
            continueAfterTools()
        }
    }

    func toolOutput(name: String, arguments: String, endpoint: Endpoint, turnID: String) async -> String {
        switch name {
        case RealtimePrompt.lookupToolName:
            let started = Date()
            let output: String
            if let question = RealtimePrompt.argument("question", from: arguments) {
                let lookup = lookup
                output = await Task.detached(priority: .userInitiated) {
                    lookup?.search(question) ?? "Past-work lookup unavailable: no firstmate data folder is configured."
                }.value
            } else {
                output = "Lookup requires a non-empty question."
            }
            EventLog.record("realtime_lookup", [
                "lane": provider.id, "turn_id": turnID, "ms": EventLog.milliseconds(from: started)
            ])
            return output
        case "", RealtimePrompt.handoffToolName:
            var noteID: String?
            if let request = RealtimePrompt.request(fromArguments: arguments) {
                noteID = await delegate?.call(self, handOff: request, endpoint: endpoint)
            }
            EventLog.record("realtime_handoff", [
                "lane": provider.id, "turn_id": turnID, "note_id": noteID ?? "none"
            ])
            return noteID == nil ? "not passed" : "passed"
        default:
            return "Unknown tool. Use a registered tool."
        }
    }

    func continueAfterTools() {
        // Providers reject response.create while the response that requested a tool is still active.
        guard !ended, !responseActive, pendingTools == 0, toolResponsePending, let socket else { return }
        toolResponsePending = false
        socket.send(RealtimeWire.createResponse())
        responseActive = true
    }
}
