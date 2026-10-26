#!/usr/bin/env python3
"""Only workspaces with an explicit `monitor` are pinned to a screen."""

import importlib.machinery
import importlib.util
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_plan_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


with tempfile.TemporaryDirectory() as tmp:
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(Path(tmp) / "tableau.toml")
    os.environ["XDG_STATE_HOME"] = str(Path(tmp) / "state")
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")

    mons = [
        {"name": "DP-5", "description": "Lenovo P27h", "focused": True, "width": 2560, "height": 1440, "scale": 1},
        {"name": "DP-6", "description": "Lenovo L27q", "focused": False, "width": 2560, "height": 1440, "scale": 1},
    ]
    setup = {"name": "Work", "workspaces": [
        {"number": 1, "columns": [{}]},                       # implicit: left to Hyprland's rules
        {"number": 3, "monitor": "L27q", "columns": [{}]},    # explicit: pinned by description
        {"number": 4, "monitor": "HDMI-9", "columns": [{}]},  # explicit but absent: focused monitor
    ]}

    plan = cli.resolve_plan(setup, mons, None)
    assert [w["monitor"] for w in plan["workspaces"]] == ["", "DP-6", "DP-5"], plan

    # A plan remembered under the old rules, which pinned everything to the
    # focused monitor, is recomputed rather than reused.
    stale = {"version": 2, "workspaces": [{"index": 0, "number": 1, "monitor": "DP-5", "columns": 1}]}
    assert cli.resolve_plan(setup, mons, stale)["workspaces"][0]["monitor"] == ""
    assert cli.resolve_plan(setup, mons, plan) is plan
