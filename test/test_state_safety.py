#!/usr/bin/env python3
"""Regression tests for untrusted persisted teardown state."""

import importlib.machinery
import importlib.util
import json
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_state_test", str(path))
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
        'name = "Safe"\n'
        'services = ["safe.service"]\n'
    )
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")
    cfg = cli.load_config()

    # A replaced state file cannot authorize an unrelated unit or PID.
    forged = {
        "setup": "Safe",
        "services": [
            {"unit": "unrelated.service", "owned": True},
            {"run": "echo unrelated", "pid": os.getpid(), "owned": True},
        ],
    }
    assert cli.previous_services(cfg, forged) == []

    state_path = state_home / "omarchy/tableau/state.json"
    state_path.parent.mkdir(parents=True)
    state_path.write_text(json.dumps({
        "setup": "Safe", "phase": "loading", "loader_pid": 999999,
        "updated": "not-a-timestamp",
    }))
    assert cli.read_state()["phase"] == "error"

    state_path.write_text("{" + "x" * (cli.MAX_STATE_BYTES + 1) + "}")
    safe = cli.read_state()
    assert safe["setup"] is None
    assert safe["services"] == []

    # A planted FIFO must be rejected immediately rather than blocking open().
    state_path.unlink()
    os.mkfifo(state_path)
    assert cli.read_state()["setup"] is None

    # A planted predictable .tmp symlink must not receive an atomic write.
    state_path.unlink()
    victim = root / "victim"
    victim.write_text("untouched")
    predictable_tmp = state_path.with_suffix(state_path.suffix + ".tmp")
    predictable_tmp.symlink_to(victim)
    cli.write_json(state_path, {"setup": "Safe"})
    assert victim.read_text() == "untouched"
    assert json.loads(state_path.read_text())["setup"] == "Safe"

    # The same protections apply to the layouts and plugin configuration files.
    layouts_path = state_path.with_name("layouts.json")
    os.mkfifo(layouts_path)
    assert cli.read_json(layouts_path, {"fallback": True}) == {"fallback": True}
    layouts_path.unlink()
    layouts_path.write_text(json.dumps({
        "screen": {"Broken": {"version": cli.LAYOUT_PLAN_VERSION,
                                 "workspaces": [{"index": "bad"}]}}
    }))
    assert cli.read_layouts() == {}

    config_path = config
    config_path.unlink()
    os.mkfifo(config_path)
    try:
        cli.load_config()
    except cli.ConfigError:
        pass
    else:
        raise AssertionError("FIFO configuration should be rejected")

    # Initialization replaces a planted FIFO rather than opening it for writing.
    cli.cmd_init(type("Args", (), {"force": True})())
    assert config_path.is_file()
    assert "[[setups]]" in config_path.read_text()

    # Invalid numeric configuration is rejected before it can reach timers.
    config_path.write_text(
        "[options]\nwindow_wait = inf\n\n[[setups]]\nname = \"Bad\"\n")
    try:
        cli.load_config()
    except cli.ConfigError:
        pass
    else:
        raise AssertionError("non-finite configuration should be rejected")

    # Backup retention is bounded rather than growing on every edit.
    config_path.write_text("safe")
    for _ in range(cli.MAX_BACKUPS + 3):
        cli.write_backup(config_path, "backup")
    cli.prune_backups(config_path)
    backups = list(config_path.parent.glob(f".{config_path.name}.bak.*.toml"))
    assert len(backups) <= cli.MAX_BACKUPS

print("state-safety regression passed")
