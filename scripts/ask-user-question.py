#!/usr/bin/env python3
"""Claude PreToolUse bridge. Every failure leaves the terminal picker available."""

import json
import math
import os
from pathlib import Path
import shutil
import signal
import sys
import time
import uuid


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    temporary.replace(path)


def app_available(root):
    try:
        heartbeat = json.loads((root / "heartbeat.json").read_text())
        return 0 <= time.time() - heartbeat["time"] < 3
    except (OSError, ValueError, KeyError, TypeError):
        return False


def valid_questions(questions):
    if not isinstance(questions, list) or not 1 <= len(questions) <= 4:
        return False
    texts = set()
    for question in questions:
        if not isinstance(question, dict):
            return False
        text = question.get("question")
        options = question.get("options")
        if not isinstance(text, str) or not text.strip() or text in texts:
            return False
        texts.add(text)
        if not isinstance(question.get("header"), str) or not isinstance(options, list):
            return False
        if not 2 <= len(options) <= 4:
            return False
        for option in options:
            if not isinstance(option, dict) or not isinstance(option.get("label"), str):
                return False
            if not isinstance(option.get("description", ""), str):
                return False
    return True


def bridge(event):
    home_value = os.environ.get("FM_HOME", "")
    if not home_value or event.get("tool_name") != "AskUserQuestion":
        return
    home = Path(home_value).expanduser().resolve()
    cwd = Path(event.get("cwd", "")).resolve()
    if cwd != home and home not in cwd.parents:
        return
    tool_input = event.get("tool_input", {})
    questions = tool_input.get("questions")
    if not valid_questions(questions) or tool_input.get("answers"):
        return
    root = home / "state" / "fleet-comms-questions"
    if not app_available(root):
        return
    timeout = float(os.environ.get("FLEET_COMMS_ASK_TIMEOUT", "120"))
    if not math.isfinite(timeout):
        return
    timeout = min(300, max(1, timeout))
    folder = root / str(uuid.uuid4())
    folder.mkdir(mode=0o700)
    deadline = time.time() + timeout
    try:
        write_json(folder / "request.json", {
            "id": folder.name,
            "agent": os.environ.get("FLEET_COMMS_AGENT_LABEL", "claude-" + event.get("session_id", "session")[:8]),
            "sessionID": event.get("session_id", ""),
            "toolUseID": event.get("tool_use_id", ""),
            "expiresAt": deadline,
            "questions": questions,
        })
        until = time.monotonic() + timeout
        while time.monotonic() < until and app_available(root):
            if (folder / "dismiss.json").exists():
                return
            response = folder / "answer.json"
            if response.exists():
                answers = json.loads(response.read_text())
                expected = {question["question"] for question in questions}
                if set(answers) != expected or not all(
                    isinstance(value, str) and value.strip() for value in answers.values()
                ):
                    return
                if time.time() >= deadline:
                    return
                updated = dict(tool_input, answers=answers)
                print(json.dumps({"hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "updatedInput": updated,
                }}), flush=True)
                # The UI confirms delivery only after the hook has consumed the answer.
                write_json(folder / "consumed.json", {"agent": "answered"})
                for _ in range(20):
                    if (folder / "ack.json").exists():
                        break
                    time.sleep(0.05)
                return
            time.sleep(0.1)
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def main():
    os.umask(0o077)
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, lambda *_: sys.exit(0))
    try:
        bridge(json.loads(sys.stdin.read(256 * 1024)))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        # Never emit a partial hook decision or block the original AskUserQuestion.
        pass


if __name__ == "__main__":
    main()
