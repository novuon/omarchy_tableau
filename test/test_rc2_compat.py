#!/usr/bin/env python3
"""Omarchy 4.5 workspace blocks, floating layouts, and terminal rules."""

import importlib.machinery
import importlib.util
import os
import tempfile
from pathlib import Path


def load_cli(path: Path):
    loader = importlib.machinery.SourceFileLoader("tableau_rc2_test", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def monitor(name, focused=False, description=""):
    return {
        "name": name,
        "focused": focused,
        "width": 1920,
        "height": 1080,
        "scale": 1,
        "transform": 0,
        "description": description,
    }


def client(address, workspace, x, y, width=400, height=300, floating=False,
           tags=None, cls="org.omarchy.tableau.terminal"):
    return {
        "address": address,
        "mapped": True,
        "floating": floating,
        "tags": tags or [],
        "class": cls,
        "pid": 0,
        "workspace": {"id": workspace, "name": str(workspace)},
        "at": [x, y],
        "size": [width, height],
    }


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    config = root / "tableau.toml"
    state_home = root / "state"
    config.write_text("[options]\n")
    os.environ["OMARCHY_TABLEAU_CONFIG"] = str(config)
    os.environ["XDG_STATE_HOME"] = str(state_home)
    cli = load_cli(Path(__file__).parents[1] / "bin/omarchy-tableau")

    blocks_path = state_home / "omarchy" / "monitor-workspaces"
    layouts = state_home / "omarchy" / "workspace-layouts"
    mons = [monitor("eDP-1", focused=True, description="Laptop"),
            monitor("DP-2", description="Dell U2720Q")]

    # Before per-monitor workspaces, a config number is the Hyprland id.
    assert cli.load_monitor_blocks() == {}
    assert cli.resolve_workspace_number(3, "DP-2", True) == (3, "DP-2")
    plan = cli.resolve_plan(
        {"workspaces": [{"number": 3, "monitor": "DP-2", "columns": [{}]}]},
        mons, None)
    assert plan["workspaces"][0]["number"] == 3
    assert plan["workspaces"][0]["monitor"] == "DP-2"
    assert plan["version"] == cli.LAYOUT_PLAN_VERSION

    blocks_path.parent.mkdir(parents=True)
    blocks_path.write_text("0\teDP-1\tLaptop Panel\n1\tDP-2\tDell U2720Q\n")
    assert cli.load_monitor_blocks() == {"eDP-1": 0, "DP-2": 1}

    # number = 3 on DP-2 is the third slot of block 1, Hyprland workspace 13.
    assert cli.resolve_workspace_number(3, "DP-2", True) == (13, "DP-2")
    # A capture that already stored the Hyprland id stays on that workspace.
    assert cli.resolve_workspace_number(13, "DP-2", True) == (13, "DP-2")
    # The same slot on the laptop panel is still workspace 3.
    assert cli.resolve_workspace_number(1, "eDP-1", True) == (1, "eDP-1")
    # An old global id with no monitor follows the monitor that owns its block.
    assert cli.resolve_workspace_number(13, "eDP-1", False) == (13, "DP-2")
    # An explicit monitor wins, by slot, when the stored id is in another block.
    assert cli.resolve_workspace_number(13, "eDP-1", True) == (3, "eDP-1")

    plan = cli.resolve_plan({
        "workspaces": [
            {"number": 3, "monitor": "DP-2", "columns": [{}, {}]},
            {"number": 1, "columns": [{}]},
        ],
    }, mons, None)
    assert [(w["number"], w["monitor"], w["slot"]) for w in plan["workspaces"]] == [
        (13, "DP-2", 3),
        (1, "eDP-1", 1),
    ]

    # Focused external monitor: an unscoped 1-10 is that monitor's slot.
    external = [monitor("eDP-1"), monitor("DP-2", focused=True)]
    plan = cli.resolve_plan(
        {"workspaces": [{"number": 3, "columns": [{}]}]},
        external, None)
    assert plan["workspaces"][0]["number"] == 13
    assert plan["workspaces"][0]["monitor"] == "DP-2"

    # A remembered plan whose ids are outside the current block is rebuilt.
    stale = {"version": cli.LAYOUT_PLAN_VERSION, "workspaces": [
        {"index": 0, "number": 3, "monitor": "DP-2", "columns": 1},
    ]}
    rebuilt = cli.resolve_plan(
        {"workspaces": [{"number": 3, "monitor": "DP-2", "columns": [{}]}]},
        mons, stale)
    assert rebuilt["workspaces"][0]["number"] == 13

    fresh = {"version": cli.LAYOUT_PLAN_VERSION, "workspaces": [
        {"index": 0, "number": 13, "monitor": "DP-2", "columns": 1},
    ]}
    assert cli.resolve_plan(
        {"workspaces": [{"number": 3, "monitor": "DP-2", "columns": [{}]}]},
        mons, fresh) is fresh

    # The same slot on two monitors is two workspaces. Twice on one is not.
    config.write_text(
        '[[setups]]\n'
        'name = "Split"\n'
        '  [[setups.workspaces]]\n'
        '  number = 1\n'
        '  monitor = "eDP-1"\n'
        '  columns = []\n'
        '  [[setups.workspaces]]\n'
        '  number = 1\n'
        '  monitor = "DP-2"\n'
        '  columns = []\n'
    )
    loaded = cli.load_config()
    assert len(loaded["setups"][0]["workspaces"]) == 2
    config.write_text(
        '[[setups]]\n'
        'name = "Dup"\n'
        '  [[setups.workspaces]]\n'
        '  number = 1\n'
        '  columns = []\n'
        '  [[setups.workspaces]]\n'
        '  number = 1\n'
        '  columns = []\n'
    )
    try:
        cli.load_config()
    except cli.ConfigError:
        pass
    else:
        raise AssertionError("duplicate workspace numbers on one monitor should be rejected")

    # Layout rules follow the workspace mode instead of always naming dwindle.
    assert 'layout = "dwindle"' in cli.workspace_rule_lua(13, "DP-2", "dwindle")
    scrolling = cli.workspace_rule_lua(13, "DP-2", "scrolling")
    assert 'layout = "scrolling"' in scrolling
    assert "dwindle" not in scrolling
    floating_rule = cli.workspace_rule_lua(13, "DP-2", "floating")
    assert "layout" not in floating_rule
    assert 'monitor = "DP-2"' in floating_rule

    layouts.mkdir(parents=True)
    (layouts / "13.lua").write_text(
        'o.workspace_mode({ workspace = "13", mode = "floating" })\n')
    (layouts / "default.lua").write_text(
        'o.workspace_mode({ default = "scrolling" })\n')
    assert cli.read_workspace_mode(13) == "floating"
    assert cli.read_workspace_mode(2) == "scrolling"
    (layouts / "default.lua").unlink()
    assert cli.read_workspace_mode(2) == "dwindle"

    tiled = {"floating": False}
    floated = {"floating": True, "tags": ["omarchy-mode-floated"]}
    opening = {"floating": True, "tags": ["omarchy-mode-opened*"]}
    user_float = {"floating": True, "float": True}
    assert cli.should_unfloat({**tiled, "floating": True}, {}, "dwindle") is True
    assert cli.should_unfloat(floated, {}, "dwindle") is False
    assert cli.should_unfloat(opening, {}, "dwindle") is False
    assert cli.should_unfloat({"floating": True}, {}, "floating") is False
    assert cli.should_unfloat({"floating": True}, {"float": True}, "dwindle") is False
    assert cli.should_unfloat(tiled, {}, "dwindle") is False

    # Capture keeps mode-floated windows as layout, not as float = true,
    # and writes the monitor's slot rather than the Hyprland id.
    cli.clients = lambda: [
        client("0x1", 13, 10, 10, floating=True,
               tags=["omarchy-mode-floated", "omarchy-floating-workspace"]),
        client("0x2", 13, 500, 10, floating=True, tags=[], cls="org.gnome.Nautilus"),
        client("0x3", 1, 10, 10, floating=False, tags=[], cls="org.omarchy.screensaver"),
        client("0x4", 2, 20, 20, floating=False, tags=[], cls="chromium"),
    ]
    cli.monitor_of_workspace = lambda number: {13: "DP-2", 1: "eDP-1", 2: "eDP-1"}.get(number, "")
    captured = cli.snapshot()
    assert [ws["number"] for ws in captured] == [2, 3]
    by_number = {ws["number"]: ws for ws in captured}
    assert by_number[3]["monitor"] == "DP-2"
    spec = by_number[3]["columns"][0]["windows"][0]
    assert spec.get("float") is not True
    assert "float" not in spec
    assert "opacity" not in spec
    assert by_number[2]["monitor"] == "eDP-1"
    assert all(win.get("class") != "org.omarchy.screensaver"
               for ws in captured for col in ws["columns"] for win in col["windows"])
    rendered = cli.render_setup("Now", captured, [])
    assert 'number = 3' in rendered
    assert 'monitor = "DP-2"' in rendered
    assert "float" not in rendered

    # org.omarchy.* is not itself enough to call a window a terminal.
    cli.proc_exe = lambda pid: "ghostty" if pid == 7 else "chromium"
    assert cli.is_terminal_window(
        {"class": "org.omarchy.screensaver", "pid": 7}, ["ghostty"]) is False
    assert cli.is_terminal_window(
        {"class": "org.omarchy.captive-portal", "pid": 7}, ["ghostty"]) is False
    assert cli.is_terminal_window(
        {"class": "chrome-ping.omacom.io__-1", "pid": 8}, ["chromium"]) is False
    assert cli.is_terminal_window(
        {"class": "org.omarchy.tableau.btop", "pid": 0}, []) is True
    assert cli.is_terminal_window(
        {"class": "org.omarchy.about", "pid": 7}, ["ghostty"]) is True

    terminal_tag = cli.re.compile(r"org\.omarchy\..*")
    for command in ("", "btop", "bash", "imv", "mpv", "About", "Omarchy", "TUI.float", "echo"):
        app_id = cli.app_id_for(command)
        assert app_id.startswith(cli.APP_ID_PREFIX), app_id
        assert terminal_tag.search(app_id), app_id
        assert cli.matches_omarchy_float_rule(app_id) is False, app_id
    assert cli.matches_omarchy_float_rule("org.omarchy.btop") is True
    assert cli.matches_omarchy_float_rule("org.omarchy.terminal") is True
    assert cli.home_workspace_id(external) == 11
    assert cli.home_workspace_id([]) == 1

print("rc2 compatibility regression passed")
