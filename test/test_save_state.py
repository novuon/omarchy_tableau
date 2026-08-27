#!/usr/bin/env python3
"""Regression test for saving a live desktop as the active setup."""

import argparse
import importlib.machinery
import importlib.util
import json
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_cli_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    config = root / "tableau.toml"
    state_home = root / "state"
    config.write_text(
        '[[setups]]\n'
        'name = "Old"\n\n'
        '  [[setups.workspaces]]\n'
        '  number = 1\n'
        '  columns = [{ width = 1, windows = [{ term = "btop" }] }]\n'
    )
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")

    cli.snapshot = lambda: [{
        "number": 1,
        "columns": [{"width": 1, "windows": [{"term": "btop"}]}],
    }]
    cli.close_windows = lambda *args, **kwargs: (_ for _ in ()).throw(
        AssertionError("save must never close windows"))
    cli.fingerprint = lambda: "test-screen"
    cli.monitor_of_workspace = lambda number: "test-monitor"
    cli.notify = lambda *args, **kwargs: None

    result = cli.cmd_save(argparse.Namespace(name="Saved"))
    assert result == 0
    state = json.loads((state_home / "omarchy/tableau/state.json").read_text())
    assert state["setup"] == "Saved"
    assert state["phase"] == "idle"
    assert 'name = "Saved"' in config.read_text()

    # Chromium exposes its complete command line as one argv[0] in /proc.
    cli.proc_cmdline = lambda pid: [
        "/usr/lib/chromium/chromium --ozone-platform=wayland"
    ]
    cli.proc_exe = lambda pid: "chromium"
    spec = cli.window_to_spec({"pid": 123, "class": "chromium"})
    assert spec["app"] == "/usr/lib/chromium/chromium --ozone-platform=wayland"

print("save-state regression passed")
