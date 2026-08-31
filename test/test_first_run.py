"""Regression tests for first-run starter Tableaus and recovery state."""

import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import time
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_first_run_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    config = root / "tableau.toml"
    state_home = root / "state"
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")
    cli.monitors = lambda: []
    cli.fingerprint = lambda mons=None: "none"
    cli.fingerprint_label = lambda mons=None: "no screens"
    cli.remembered_plan = lambda *args: None

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert cli.cmd_status(argparse.Namespace(json=True)) == 0
    payload = json.loads(output.getvalue())
    assert [s["name"] for s in payload["setups"]] == ["Work", "Browse"]
    assert all(s["starter"] for s in payload["setups"])
    assert payload["configExists"] is False

    config.write_text("[options]\n")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert cli.cmd_status(argparse.Namespace(json=True)) == 0
    payload = json.loads(output.getvalue())
    assert payload["setups"] == []
    assert payload["configExists"] is True

    state_path = state_home / "omarchy/tableau/state.json"
    state_path.parent.mkdir(parents=True)
    state_path.write_text(json.dumps({
        "setup": "Work", "phase": "loading", "loader_pid": 999999,
        "updated": time.time() - 10,
    }))
    recovered = cli.read_state()
    assert recovered["recoverable"] is True
    assert recovered["phase"] == "error"

print("first-run regression passed")
