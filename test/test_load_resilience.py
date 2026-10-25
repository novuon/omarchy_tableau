#!/usr/bin/env python3
"""Regression tests for load resilience and capture fidelity.

A window that never maps must abort its workspace -- the module docstring
promises exactly that -- instead of crashing the whole load on the next
column's preselect anchor. Captured terminal commands must stay runnable
even when the process rewrote its title, and a terminal without `dir`
must launch in $HOME, never in the loader's own working directory.
"""

import importlib.machinery
import importlib.util
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_load_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    config = root / "tableau.toml"
    state_home = root / "state"
    config.write_text("[options]\n")
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")

    # ---- a window that never opens aborts its workspace --------------------
    cli.hypr_eval = lambda lua: None
    cli.dispatch = lambda lua: None
    cli.clients = lambda: []
    cli.time.sleep = lambda s: None
    applied = []
    cli.apply_sizes = lambda *a: applied.append(a)  # never on an aborted one
    spawned = []
    original_spawn_window = cli.spawn_window
    cli.spawn_window = lambda win: spawned.append(win)
    cli.wait_for_window = lambda before, wait, want_class="": None

    def build(cfg, plan):
        try:
            return cli.build_workspace(cfg, plan, {}, lambda step: None)
        except IndexError:
            raise AssertionError(
                "a window that never opened crashed the load on the "
                "next column's preselect anchor")

    # First window of a column never maps: the rest of the workspace must
    # not be spawned, no sizes may be applied, the problem must be reported.
    cfg = {"columns": [{"width": 1, "windows": [
        {"term": "node dist/index.js"},
        {"term": "bash"},
    ]}]}
    plan = {"index": 0, "number": 1, "monitor": "eDP-1", "columns": 1}
    problems = build(cfg, plan)
    assert problems == ["node never opened"], problems
    assert len(spawned) == 1, "the rest of the workspace must not be spawned"
    assert applied == [], "an aborted workspace must not get half-measured sizes"

    # Same contract when a later column is the one that fails.
    spawned.clear()
    fake = {"address": "0x1234", "workspace": {"id": 1}, "floating": False}
    results = [fake, None, None]
    cli.wait_for_window = lambda before, wait, want_class="": (
        results.pop(0) if results else None)
    cfg = {"columns": [
        {"width": 1, "windows": [{"term": "btop"}]},
        {"width": 1, "windows": [{"term": "node"}, {"term": "bash"}]},
    ]}
    plan = {"index": 0, "number": 1, "monitor": "eDP-1", "columns": 2}
    problems = build(cfg, plan)
    assert problems == ["node never opened"], problems
    assert len(spawned) == 2, spawned
    assert applied == [], applied

    # ---- capture: rewritten process titles stay runnable --------------------
    workdir = root / "app"
    workdir.mkdir()
    expected_dir = str(workdir).replace(str(cli.HOME), "~", 1)
    cli.proc_exe = lambda pid: "foot"
    cli.proc_cmdline = lambda pid: (
        ["puma 8.0.2 (tcp://0.0.0.0:3000) [backend]"] if pid == 10 else ["foot"])
    cli.child_pids = lambda pid: [10] if pid == 5 else []
    cli.proc_cwd = lambda pid: str(workdir) if pid == 10 else str(root)

    original_which = cli.shutil.which
    try:
        # The leading word is an executable: keep it as the command.
        cli.shutil.which = lambda cmd: "/usr/bin/puma" if cmd == "puma" else None
        spec = cli.window_to_spec({"pid": 5, "class": "foot"})
        assert spec["term"] == "puma", spec
        assert spec["dir"] == expected_dir, spec
        # The leading word is not an executable: fall back to a plain shell
        # in the same directory rather than an unrunnable quoted blob.
        cli.shutil.which = lambda cmd: None
        spec = cli.window_to_spec({"pid": 5, "class": "foot"})
        assert spec["term"] == "", spec
        assert spec["dir"] == expected_dir, spec
    finally:
        cli.shutil.which = original_which

    # Ordinary leaf commands are captured verbatim.
    cli.proc_cmdline = lambda pid: (
        ["node", "dist/index.js"] if pid == 10 else ["foot"])
    spec = cli.window_to_spec({"pid": 5, "class": "foot"})
    assert spec["term"] == "node dist/index.js", spec

    # ---- spawn: a dirless terminal opens in $HOME ---------------------------
    cli.spawn_window = original_spawn_window
    seen = {}

    class FakeProcess:
        pid = 12345

    original_popen = cli.subprocess.Popen

    def fake_popen(argv, **kwargs):
        seen["argv"] = argv
        seen["cwd"] = kwargs.get("cwd")
        return FakeProcess()

    cli.launch_prefix = lambda: []
    cli.subprocess.Popen = fake_popen
    try:
        cli.spawn_window({"term": "btop"})
        assert seen["argv"] == [
            "xdg-terminal-exec", "--app-id=org.omarchy.tableau.btop",
            "-e", "btop",
        ], seen["argv"]
        assert seen["cwd"] == str(cli.HOME), seen["cwd"]
        cli.spawn_window({"term": "btop", "dir": str(root)})
        assert seen["cwd"] == str(root), seen["cwd"]
        # App windows keep the old cwd behaviour (no forced HOME).
        cli.spawn_window({"app": "nautilus"})
        assert seen["cwd"] is None, seen["cwd"]
    finally:
        cli.subprocess.Popen = original_popen

print("load-resilience regression passed")
