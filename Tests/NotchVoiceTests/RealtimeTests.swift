//  RealtimeTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct RealtimeWireTests {
    @Test func serverEventsParse() {
        #expect(RealtimeWire.parse(#"{"type":"session.created","session":{}}"#) == .sessionCreated)
        #expect(RealtimeWire.parse(#"{"type":"input_audio_buffer.speech_started"}"#) == .speechStarted)
        let stopped = #"{"type":"input_audio_buffer.speech_stopped","audio_end_ms":900}"#
        #expect(RealtimeWire.parse(stopped) == .speechStopped)
        #expect(RealtimeWire.parse(#"{"type":"response.done","response":{"status":"cancelled"}}"#)
            == .responseDone(status: "cancelled"))
        #expect(RealtimeWire.parse(#"{"type":"error","error":{"type":"invalid_request_error"}}"#)
            == .error(code: "invalid_request_error"))
        #expect(RealtimeWire.parse(#"{"type":"ping"}"#) == .other)
        #expect(RealtimeWire.parse("not json") == .other)
    }

    @Test func audioDeltaDecodesBase64() {
        let line = #"{"type":"response.output_audio.delta","item_id":"item_1","delta":"AAD/fw=="}"#
        #expect(RealtimeWire.parse(line) == .audioDelta(itemID: "item_1", audio: Data([0, 0, 0xFF, 0x7F])))
    }

    @Test func functionCallCarriesItsArguments() {
        let line = """
        {"type":"response.function_call_arguments.done","call_id":"call_9","name":"pass_to_first_mate",\
        "arguments":"{\\"request\\":\\"merge the PR\\"}"}
        """
        guard case let .functionCall(callID, name, arguments) = RealtimeWire.parse(line) else {
            Issue.record("not a function call")
            return
        }
        #expect(callID == "call_9")
        #expect(name == RealtimePrompt.handoffToolName)
        #expect(RealtimePrompt.request(fromArguments: arguments) == "merge the PR")
        #expect(RealtimePrompt.request(fromArguments: #"{"request":"  "}"#) == nil)
    }

    @Test func sessionUpdateCarriesVoiceTurnDetectionAndTool() throws {
        let session = RealtimeWire.Session(provider: .grok, voice: "rex", instructions: "Be brief.", silenceMs: 800)
        let text = RealtimeWire.sessionUpdate(session)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let body = try #require(object["session"] as? [String: Any])
        let audio = try #require(body["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        let output = try #require(audio["output"] as? [String: Any])
        let turn = try #require(input["turn_detection"] as? [String: Any])
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(object["type"] as? String == "session.update")
        #expect(output["voice"] as? String == "rex")
        #expect(turn["silence_duration_ms"] as? Int == 800)
        #expect(turn["interrupt_response"] as? Bool == true)
        #expect(input["noise_reduction"] == nil)
        #expect(tools.first?["name"] as? String == RealtimePrompt.handoffToolName)
    }
}

struct SubscriptionLoginTests {
    private static func jwt(expiresIn seconds: TimeInterval) -> String {
        let claims = #"{"exp":\#(Int(Date().timeIntervalSince1970 + seconds))}"#
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJub25lIn0.\(payload).signature"
    }

    @Test func codexChatGPTLoginIsRead() throws {
        let token = Self.jwt(expiresIn: 3600)
        let file = #"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(token)"}}"#
        let login = try #require(SubscriptionLogin.parseCodex(Data(file.utf8)))
        #expect(login.isUsable())
        #expect(String(describing: login) == "Token(redacted)")
    }

    @Test func codexAPIKeyModeIsNotASubscription() {
        let file = #"{"auth_mode":"apikey","tokens":{"access_token":"\#(Self.jwt(expiresIn: 3600))"}}"#
        #expect(SubscriptionLogin.parseCodex(Data(file.utf8)) == nil)
    }

    @Test func grokLoginExpiryComesFromTheToken() throws {
        let entry = #"{"key":"\#(Self.jwt(expiresIn: -10))","expires_at":"2099-01-01T00:00:00Z"}"#
        let file = #"{"https://auth.x.ai::client":\#(entry)}"#
        let login = try #require(SubscriptionLogin.parseGrok(Data(file.utf8)))
        #expect(login.isUsable() == false)
        #expect(SubscriptionLogin.parseGrok(Data(#"{"other":{"key":"x"}}"#.utf8)) == nil)
    }
}

struct RealtimePCMTests {
    @Test func pcmRoundTripsWithinOneStep() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1]
        let decoded = RealtimePCM.decode(RealtimePCM.encode(samples))
        #expect(decoded.count == samples.count)
        for (original, back) in zip(samples, decoded) {
            #expect(abs(original - back) < 0.001)
        }
    }

    @Test func upsamplingKeepsDurationAndEnds() {
        let samples = (0 ..< 1600).map { Float($0) / 1600 }
        let upsampled = RealtimePCM.upsample16kTo24k(samples)
        #expect(upsampled.count == 2400)
        #expect(upsampled.first == 0)
        #expect(abs((upsampled.last ?? 0) - (samples.last ?? 0)) < 0.002)
    }
}

@MainActor
struct RealtimeIdleTests {
    private func call(timeout: Double = 10) -> RealtimeCall {
        RealtimeCall(
            provider: .grok,
            voice: "rex",
            source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8,
            idleHangUp: timeout
        ) { "" }
    }

    @Test func longReplyGetsFullQuietWindowAfterPlayback() {
        let call = call()
        call.lastActivity = Date().addingTimeInterval(-60)
        call.handle(.responseCreated)
        call.audioQueued = true
        call.checkForIdle()
        #expect(!call.ended)
        call.handle(.responseDone(status: "completed"))
        call.checkForIdle()
        #expect(!call.ended)
        call.drained()
        let endOfAudio = call.lastActivity
        call.checkForIdle(at: endOfAudio.addingTimeInterval(9.99))
        #expect(!call.ended)
        call.checkForIdle(at: endOfAudio.addingTimeInterval(10.01))
        #expect(call.ended)
    }

    @Test func followUpSpeechAndModelAudioResetWindow() {
        let call = call(timeout: 5)
        call.lastActivity = Date().addingTimeInterval(-20)
        call.handle(.speechStarted)
        call.checkForIdle(at: Date().addingTimeInterval(20))
        #expect(!call.ended)
        call.handle(.speechStopped)
        call.checkForIdle(at: call.lastActivity.addingTimeInterval(4.99))
        #expect(!call.ended)
        call.handle(.responseCreated)
        call.audioQueued = true
        call.handle(.responseDone(status: "completed"))
        call.drained()
        call.checkForIdle(at: call.lastActivity.addingTimeInterval(5.01))
        #expect(call.ended)
    }

    @Test func localSpeechProtectsAgainstDelayedServerDetection() {
        let call = call()
        call.lastActivity = Date().addingTimeInterval(-20)
        call.lastSpeech.value = Date()
        call.checkForIdle()
        #expect(!call.ended)
        call.end()
        #expect(call.ended)
    }
}

@MainActor
struct RealtimeReplyRoutingTests {
    private func model() throws -> (AppModel, () -> Void) {
        let name = "realtime-reply-routing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        settings.setRealtimeEnabled(true, for: .chatGPT)
        settings.voiceLane = .chatGPTRealtime
        settings.outreachVoice = .gptRealtime
        settings.setRealtimeVoice("echo", for: .chatGPT)
        let model = AppModel(settings: settings)
        model.outreachSourceOverride = .wav(URL(fileURLWithPath: "/unused"))
        return (model, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func delayedVoiceReplyUsesSelectedRealtimeLane() throws {
        let (model, cleanup) = try model()
        defer { model.endCallQuietly(); cleanup() }
        #expect(model.call == nil)
        model.receive(.init(noteID: "synthetic-note", body: "An update is ready.", seenAt: Date()))
        #expect(model.call?.provider == .chatGPT)
        #expect(model.call?.voice == "echo")
    }

    @Test func outreachDoesNotWaitForUnusedLocalVoiceModels() throws {
        let (model, cleanup) = try model()
        defer { model.endCallQuietly(); cleanup() }
        #expect(!model.speaker.isLoaded)
        model.receiveSessionReply(.init(id: "synthetic-turn", text: "An update is ready."))
        #expect(model.call?.provider == .chatGPT)
        #expect(model.call?.voice == "echo")
    }

    @Test func requestedReplyKeepsItsSummaryChoiceAndFullDisplayText() throws {
        let (model, cleanup) = try model()
        defer { model.endCallQuietly(); cleanup() }
        model.settings.readWholeReply = false
        let text = (1 ... 12).map { "Sentence \($0) has useful details." }.joined(separator: " ")
        model.receive(.init(noteID: "synthetic-note", body: text, seenAt: Date()))
        let reading = try #require(model.call?.outreach)
        #expect(reading.reply.text == text)
        let expected = "Firstmate replied. " + SpokenSummary.make(from: text, readWholeReply: false)
        #expect(reading.spokenText == expected)
        #expect(reading.readingText == OutreachWire.readingText(expected))
    }

    @Test(arguments: [false, true])
    func failedRealtimeReplyShowsWhyWithoutLocalModels(requested: Bool) throws {
        let (model, cleanup) = try model()
        defer { model.endCallQuietly(); cleanup() }
        if requested {
            model.receive(.init(noteID: "synthetic-note", body: "An update is ready.", seenAt: Date()))
        } else {
            model.receiveSessionReply(.init(id: "synthetic-turn", text: "An update is ready."))
        }
        let call = try #require(model.call)
        call.end(.offline)
        #expect(model.call == nil)
        #expect(!model.isAutoSpeaking)
        #expect(model.autoSpeakID == nil)
        guard case let .reply(text, speaking, _) = model.state else {
            Issue.record("The failed lane must leave a visible explanation and reply.")
            return
        }
        #expect(text.contains("ChatGPT Realtime can't be reached"))
        #expect(text.contains("An update is ready."))
        #expect(!speaking)
    }

    @Test(arguments: [
        RealtimeWire.Event.error(code: "invalid_voice"), .responseDone(status: "failed"),
        .responseDone(status: "incomplete")
    ])
    func rejectedInteractiveResponseEndsInsteadOfWaitingSilently(event: RealtimeWire.Event) {
        let call = RealtimeCall(
            provider: .chatGPT, voice: "echo", source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8
        ) { "" }
        let delegate = RealtimeLookupDelegate()
        call.delegate = delegate
        call.handle(event)
        #expect(call.ended)
        #expect(delegate.failure != nil)
    }
}
