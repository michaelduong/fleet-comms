#!/usr/bin/env python3
"""Exercise the actual hook process against a temporary local channel."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HOOK = Path(__file__).with_name("ask-user-question.py")
QUESTIONS = [{
    "question": "Which checks?", "header": "Checks", "multiSelect": True,
    "options": [{"label": "Unit (Recommended)", "description": "Fast"},
                {"label": "UI", "description": "Rendered"}],
}]


class HookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.root = self.home / "state" / "fleet-comms-questions"
        self.root.mkdir(parents=True)
        self.heartbeat()

    def heartbeat(self):
        (self.root / "heartbeat.json").write_text(json.dumps({"time": time.time()}))

    def start(self, timeout="2", **overrides):
        event = dict(tool_name="AskUserQuestion", tool_input={"questions": QUESTIONS, "extra": "preserve"},
                     session_id="scratch", tool_use_id="tool-test", cwd=str(self.home))
        event.update(overrides)
        env = dict(os.environ, FM_HOME=str(self.home), FLEET_COMMS_ASK_TIMEOUT=timeout)
        process = subprocess.Popen([sys.executable, str(HOOK)], env=env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        process.stdin.write(json.dumps(event))
        process.stdin.close()
        process.stdin = None
        return process

    def request(self):
        until = time.monotonic() + 2
        while time.monotonic() < until:
            requests = list(self.root.glob("*/request.json"))
            if requests:
                return requests[0].parent
            time.sleep(0.01)
        self.fail("No request was published")

    def assert_fallback(self, process):
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual((process.returncode, stdout, stderr), (0, "", ""))
        self.assertEqual(list(self.root.glob("*/request.json")), [])

    def test_selected_and_typed_answers_preserve_original_input(self):
        process = self.start()
        folder = self.request()
        self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        (folder / "answer.json").write_text(json.dumps({"Which checks?": "Unit (Recommended), UI, Other"}))
        stdout, stderr = process.communicate(timeout=4)
        decision = json.loads(stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "allow")
        self.assertEqual(decision["updatedInput"]["questions"], QUESTIONS)
        self.assertEqual(decision["updatedInput"]["extra"], "preserve")
        self.assertEqual(decision["updatedInput"]["answers"], {"Which checks?": "Unit (Recommended), UI, Other"})
        self.assertEqual(stderr, "")
        self.assertFalse(folder.exists())

    def test_timeout_and_late_response(self):
        started = time.monotonic()
        process = self.start(timeout="1")
        folder = self.request()
        self.assert_fallback(process)
        self.assertLess(time.monotonic() - started, 2)
        self.assertFalse(folder.exists())

    def test_absent_app(self):
        (self.root / "heartbeat.json").unlink()
        self.assert_fallback(self.start())

    def test_crashed_app(self):
        process = self.start()
        self.request()
        (self.root / "heartbeat.json").unlink()
        self.assert_fallback(process)

    def test_dismiss_to_terminal(self):
        process = self.start()
        folder = self.request()
        (folder / "dismiss.json").write_text("{}")
        self.assert_fallback(process)

    def test_cancelled_hook_removes_card(self):
        process = self.start()
        self.request()
        process.send_signal(signal.SIGTERM)
        self.assert_fallback(process)

    def test_incomplete_answer_never_auto_approves(self):
        process = self.start()
        folder = self.request()
        (folder / "answer.json").write_text("{}")
        self.assert_fallback(process)

    def test_unrelated_tool_or_home_never_publishes(self):
        self.assert_fallback(self.start(tool_name="Bash"))
        self.assert_fallback(self.start(cwd=str(self.home.parent)))


if __name__ == "__main__":
    unittest.main()
