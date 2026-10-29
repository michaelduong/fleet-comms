//  MessengerCommand.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

struct MessengerCommand {
    let arguments: [String]
    let environment: [String: String]
    let directory: URL

    init(model: MessengerModel, input: AssistantTurnInput, directory: URL) throws {
        self.directory = directory
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SHELL"] {
            environment[key] = inherited[key]
        }
        let message = AssistantPrompt.message(for: input, fresh: true, includeContext: true)
        let prompt = AssistantPrompt.system + "\nReturn only JSON matching: " + AssistantPrompt.schema + "\n" + message
        switch model {
        case .haiku:
            arguments = AssistantPrompt.arguments()
        case .grok:
            arguments = [
                "--single", prompt, "--model", model.modelID, "--reasoning-effort", "low",
                "--tools", "", "--no-subagents",
                "--disable-web-search", "--verbatim", "--system-prompt-override", AssistantPrompt.system,
                "--output-format", "json",
                "--json-schema", AssistantPrompt.schema
            ]
        case .codexLuna:
            arguments = try Self.codexArguments(model: model, prompt: prompt, directory: directory)
        case .deepSeekFlash:
            environment["OPENCODE_CONFIG_DIR"] = directory.path
            environment["OPENCODE_CONFIG_PROJECT_DISABLE"] = "1"
            environment["OPENCODE_DISABLE_CLAUDE_CODE"] = "1"
            environment["OPENCODE_CONFIG_CONTENT"] = Self.openCodeConfig
            arguments = [
                "run",
                "--standalone",
                "--model",
                model.modelID,
                "--agent",
                "messenger",
                "--format",
                "json",
                prompt
            ]
        }
        self.environment = environment
    }

    private static func codexArguments(model: MessengerModel, prompt: String, directory: URL) throws -> [String] {
        let schema = directory.appendingPathComponent("reply-schema.json")
        let catalog = directory.appendingPathComponent("messenger-catalog.json")
        let instructions = directory.appendingPathComponent("instructions.txt")
        try AssistantPrompt.schema.write(to: schema, atomically: true, encoding: .utf8)
        try AssistantPrompt.system.write(to: instructions, atomically: true, encoding: .utf8)
        try codexCatalog.write(to: catalog, atomically: true, encoding: .utf8)
        var arguments = [
            "exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--skip-git-repo-check",
            "--sandbox", "read-only", "-C", directory.path, "--model", model.modelID,
            "-c", "model_catalog_json=\"\(catalog.path)\"", "-c", "model_instructions_file=\"\(instructions.path)\"",
            "-c", "project_doc_max_bytes=0", "-c", "model_reasoning_effort=\"low\"", "-c", "web_search=\"disabled\"",
            "--output-schema", schema.path, "--json"
        ]
        for feature in ["shell_tool", "view_image", "multi_agent", "sleep_tool", "plugins", "skill_search", "apps"] {
            arguments += ["-c", "features.\(feature)=false"]
        }
        return arguments + [prompt]
    }

    /// The CLI's catalog override removes model tools as well as disabling tool features.
    private static let codexCatalog = """
    {"models":[{"slug":"gpt-6-luna",
    "display_name":"GPT-6-Luna",
    "description":"Fast and affordable model for easier tasks.",
    "default_reasoning_level":"medium",
    "supported_reasoning_levels":[{"effort":"low",
    "description":"Fast responses with lighter reasoning"},{"effort":"medium",
    "description":"Balances speed and reasoning depth for everyday tasks"},{"effort":"high",
    "description":"Greater reasoning depth for complex problems"},{"effort":"xhigh",
    "description":"Extra high reasoning depth for complex problems"},{"effort":"max",
    "description":"Maximum reasoning depth for the hardest problems"}],
    "shell_type":"disabled",
    "visibility":"list",
    "supported_in_api":true,
    "priority":5,
    "additional_speed_tiers":["fast"],
    "service_tiers":[{"id":"priority",
    "name":"Fast",
    "description":"1.5x speed"}],
    "available_access_programs":{"cyber":["standard",
    "daybreak_blue"]},
    "availability_nux":null,
    "upgrade":null,
    "model_messages":{},
    "include_skills_usage_instructions":false,
    "include_plugin_usage_instructions":false,
    "include_apps_usage_instructions":false,
    "default_reasoning_summary":"none",
    "support_verbosity":true,
    "default_verbosity":"low",
    "apply_patch_tool_type":null,
    "web_search_tool_type":"text_and_image",
    "truncation_policy":{"mode":"tokens",
    "limit":10000},
    "supports_image_detail_original":true,
    "context_window":272000,
    "max_context_window":872000,
    "comp_hash":"3000",
    "effective_context_window_percent":95,
    "experimental_supported_tools":[],
    "input_modalities":["text",
    "image"],
    "supports_search_tool":false,
    "supports_experimental_context":false,
    "use_responses_lite":true,
    "supports_reasoning_effort_updates":true,
    "node_repl_auto_review_required":false,
    "node_repl_disabled":false,
    "tool_mode":"direct_model_only",
    "multi_agent_version":"v2",
    "base_instructions":"You are a tool-free fleet messenger."}]}
    """

    private static let openCodeConfig = """
    {"update":"disable","share":"disabled","snapshots":false,"warming":false,
    "policies":[{"action":"tool.use","resource":"*","effect":"deny"},
    {"action":"integration.use","resource":"*","effect":"deny"}],
    "agents":{"messenger":{"mode":"primary","system":"You are a tool-free fleet messenger.",
    "permissions":[{"action":"*","resource":"*","effect":"deny"}]}},
    "permissions":[{"action":"*","resource":"*","effect":"deny"}]}
    """

    static func reply(from data: Data, model: MessengerModel) throws -> AssistantReply {
        if model == .grok {
            return try grokReply(data)
        }
        guard let output = String(data: data, encoding: .utf8) else { throw AssistantError.turnFailed("encoding") }
        let lines = output.split(separator: "\n")
        var text = ""
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            switch model {
            case .codexLuna:
                if let item = object["item"] as? [String: Any], item["type"] as? String == "agent_message" {
                    text = item["text"] as? String ?? ""
                }
            case .deepSeekFlash:
                if object["type"] as? String == "text", let part = object["part"] as? [String: Any] {
                    text += part["text"] as? String ?? ""
                }
            case .grok: break
            case .haiku: break
            }
        }
        return try validated(Data(text.utf8))
    }

    private static func grokReply(_ data: Data) throws -> AssistantReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistantError.turnFailed("malformed")
        }
        if let structured = object["structuredOutput"] {
            return try validated(JSONSerialization.data(withJSONObject: structured))
        }
        return try validated(Data((object["text"] as? String ?? "").utf8))
    }

    static func validated(_ data: Data) throws -> AssistantReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["handoff", "speak"] else { throw AssistantError.turnFailed("malformed") }
        let reply = try JSONDecoder().decode(AssistantReply.self, from: data)
        guard !reply.speak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reply.handoff else {
            throw AssistantError.turnFailed("empty")
        }
        return reply
    }
}
