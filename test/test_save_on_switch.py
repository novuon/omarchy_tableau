#!/usr/bin/env python3
"""Saving the desk you leave is optional, quiet, and off by default."""

import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_switch_save_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CONFIG = """\
[options]
grace = 8
restore_last = false
save_on_switch = {flag}

[[setups]]
name = "Work"
icon = "W"
services = ["docker-desktop"]

  [[setups.workspaces]]
  number = 1
  columns = [{{ width = 1, windows = [{{ term = "original" }}] }}]

[[setups]]
name = "Browse"
services = []

  [[setups.workspaces]]
  number = 1
  columns = [{{ width = 1, windows = [{{ term = "browse" }}] }}]
"""


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    config = root / "tableau.toml"
    state_home = root / "state"
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")

    captured = [{"number": 1, "columns": [{"width": 1, "windows": [{"term": "btop"}]}]}]
    cli.snapshot = lambda: captured
    cli.fingerprint = lambda *args, **kwargs: "screen"
    cli.fingerprint_label = lambda *args, **kwargs: "screen"
    cli.monitors = lambda: []
    cli.notify = lambda *args, **kwargs: None
    cli.dispatch = lambda *args, **kwargs: ""
    cli.build_workspace = lambda *args, **kwargs: []
    cli.start_services = lambda specs, report: []
    cli.stop_services = lambda *args, **kwargs: None
    closed = {"n": 0}

    def close_windows(*args, **kwargs):
        closed["n"] += 1
        return []

    cli.close_windows = close_windows

    def write_config(flag):
        config.write_text(CONFIG.format(flag=flag))

    def load(name):
        before = closed["n"]
        result = cli.cmd_load(argparse.Namespace(name=name, force=False))
        assert result == 0, result
        assert closed["n"] == before + 1
        return config.read_text()

    # Off by default, including a config that never mentions the option.
    write_config("false")
    assert cli.load_config()["options"]["save_on_switch"] is False
    config.write_text(CONFIG.format(flag="false").replace("save_on_switch = false\n", ""))
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert cli.cmd_status(argparse.Namespace(json=True)) == 0
    assert json.loads(output.getvalue())["saveOnSwitch"] is False

    # The switch is one boolean. A string is a config error, not a silent on.
    config.write_text('[options]\nsave_on_switch = "yes"\n\n[[setups]]\nname = "Work"\n')
    try:
        cli.load_config()
    except cli.ConfigError:
        pass
    else:
        raise AssertionError("save_on_switch must be true or false")

    write_config("false")
    assert cli.cmd_set_option(argparse.Namespace(option="save_on_switch", value="on")) == 0
    assert "save_on_switch = true" in config.read_text()
    assert "restore_last = false" in config.read_text()

    assert cli.leaving_setup_name({"currentKnown": True, "setup": "Work"}, "Browse") == "Work"
    assert cli.leaving_setup_name({"currentKnown": False, "setup": "Work"}, "Browse") is None
    assert cli.leaving_setup_name({"currentKnown": True, "setup": "Empty"}, "Browse") is None
    assert cli.leaving_setup_name({"currentKnown": True, "setup": "Work"}, "Work") is None

    # Off: switching does not rewrite the desk you leave.
    write_config("false")
    cli.save_state(setup="Work", currentKnown=True, phase="idle", error="")
    text = load("Browse")
    assert 'term = "original"' in text
    assert 'term = "btop"' not in text
    assert 'term = "browse"' in text

    # On: Work is updated from the open windows, Browse is what gets loaded,
    # and services that capture cannot see are kept. No error is raised.
    write_config("true")
    cli.save_state(setup="Work", currentKnown=True, phase="idle", error="")
    text = load("Browse")
    assert 'term = "btop"' in text
    assert 'term = "original"' not in text
    assert "docker-desktop" in text
    assert 'icon = "W"' in text
    assert 'term = "browse"' in text
    assert cli.read_state().get("setup") == "Browse"
    assert cli.read_state().get("error") == ""

    # Nothing open: skip the save and still switch.
    write_config("true")
    cli.snapshot = lambda: []
    cli.save_state(setup="Work", currentKnown=True, phase="idle", error="")
    text = load("Browse")
    assert 'term = "original"' in text
    assert cli.read_state().get("error") == ""
    cli.snapshot = lambda: captured

    # A desk Tableau did not load is not written into a tableau by surprise.
    write_config("true")
    cli.save_state(setup="Work", currentKnown=False, phase="idle", error="")
    text = load("Browse")
    assert 'term = "original"' in text

    # Retrying the same tableau must not overwrite it with a half-built desk.
    write_config("true")
    cli.save_state(setup="Work", currentKnown=True, phase="idle", error="")
    text = load("Work")
    assert 'term = "original"' in text

    # Leaving for an empty desktop still remembers the tableau you left.
    write_config("true")
    cli.save_state(setup="Work", currentKnown=True, phase="idle", error="")
    text = load("Empty")
    assert 'term = "btop"' in text
    assert cli.read_state().get("setup") == "Empty"

print("save-on-switch regression passed")
