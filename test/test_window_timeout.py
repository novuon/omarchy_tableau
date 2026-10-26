#!/usr/bin/env python3
"""Window timeouts must not crash the loader or disrupt later workspaces."""

import argparse
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def load_cli():
    path = Path(__file__).parents[1] / "bin/omarchy-tableau"
    loader = importlib.machinery.SourceFileLoader("tableau_timeout_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def client(address, workspace=1):
    return {"address": address, "workspace": {"id": workspace}}


class WindowTimeoutTests(unittest.TestCase):
    def setUp(self):
        tmp = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(patch.dict(os.environ, {
            "XDG_STATE_HOME": tmp,
            "OMARCHY_TABLEAU_CONFIG": str(Path(tmp) / "tableau.toml"),
        }))
        self.cli = load_cli()
        # Never launch/close windows, call Hyprland, or send notifications.
        self.spawn = self.enterContext(patch.object(self.cli, "spawn_window"))
        self.dispatch = self.enterContext(patch.object(self.cli, "dispatch"))
        self.enterContext(patch.object(self.cli, "hypr_eval"))
        self.enterContext(patch.object(self.cli, "clients", return_value=[]))
        self.enterContext(patch.object(self.cli, "notify"))
        self.enterContext(patch.object(self.cli.time, "sleep"))
        self.sizes = self.enterContext(patch.object(self.cli, "apply_sizes"))
        self.wait = self.enterContext(patch.object(self.cli, "wait_for_window"))

    def test_timeout_stops_workspace_before_using_missing_anchor(self):
        windows = [{"term": "first"}, {"term": "second"}, {"term": "third"}]
        workspace = {"columns": [
            {"windows": windows},
            {"windows": [{"term": "later-column"}]},
        ]}
        plan = {"number": 1, "columns": 2}
        for failed_index in (0, 1, 2):
            with self.subTest(failed_index=failed_index):
                self.spawn.reset_mock()
                self.wait.side_effect = [
                    client(f"0x{index + 1:x}") for index in range(failed_index)
                ] + [None]
                problems = self.cli.build_workspace(workspace, plan, {}, lambda _: None)

                self.assertEqual(problems, [f"{windows[failed_index]['term']} never opened"])
                self.assertEqual(
                    [call.args[0] for call in self.spawn.call_args_list],
                    windows[:failed_index + 1],
                )
                self.sizes.assert_not_called()

    def test_successful_stack_still_places_and_sizes_windows(self):
        columns = [{"windows": [{"term": "first"}, {"term": "second"}]}]
        opened = [client("0x1"), client("0x2")]
        self.wait.side_effect = opened

        problems = self.cli.build_workspace(
            {"columns": columns}, {"number": 1, "columns": 1}, {}, lambda _: None)

        self.assertEqual(problems, [])
        self.assertEqual(self.spawn.call_count, 2)
        self.dispatch.assert_any_call('hl.dsp.layout("preselect d")')
        self.sizes.assert_called_once_with(1, columns, [opened])

    def test_load_reports_timeout_and_continues_to_next_workspace(self):
        failed = {"term": "missing-window"}
        skipped = {"term": "same-workspace"}
        later = {"term": "next-workspace"}
        setup = {"name": "Test", "workspaces": [
            {"number": 1, "columns": [{"windows": [failed, skipped]}]},
            {"number": 2, "columns": [{"windows": [later]}]},
        ]}
        self.enterContext(patch.object(self.cli, "load_config", return_value={"setups": [setup]}))
        self.enterContext(patch.object(self.cli, "close_windows", return_value=[]))
        self.enterContext(patch.object(self.cli, "stop_services"))
        self.enterContext(patch.object(self.cli, "start_services", return_value=[]))
        self.enterContext(patch.object(self.cli, "monitors", return_value=[]))
        self.wait.side_effect = [None, client("0x2", workspace=2)]

        result = self.cli.cmd_load(argparse.Namespace(name="Test", force=False))

        self.assertEqual(result, 0)
        self.assertEqual([call.args[0] for call in self.spawn.call_args_list], [failed, later])
        state = self.cli.read_state()
        self.assertEqual(state["phase"], "idle")
        self.assertEqual(state["error"], "missing-window never opened")
        self.assertEqual(state["loader_pid"], 0)
        self.assertFalse(self.cli.LOCK_PATH.exists())
        self.sizes.assert_called_once()
        self.assertEqual(self.sizes.call_args.args[0], 2)


if __name__ == "__main__":
    unittest.main()
