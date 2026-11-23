import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from time import monotonic

from kitty.constants import config_dir
from kitty.fast_data_types import add_timer, current_focused_os_window_id, get_boss

if config_dir not in sys.path:
    sys.path.insert(0, config_dir)

import agent_monitor
import terminal_state as state

COLORS = {'a': '#ccf5d7', 'A': '#0b6645', '汉': '#f472b6', '漢': '#e64553'}
BADGES = {'汉': '◇', '漢': '◆'}
GNOME = 'gnome' in os.environ.get('XDG_CURRENT_DESKTOP', '').lower()
RIME_MODE = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'rime-mode')

_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix='kitty-ime')
_timer = None
_engine_query = None
_engine = ''
_next_probe = 0.0
_next_scan = 0.0
_last_heal = 0.0
_cursor_modes = {}


def input_command(*args):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=0.5, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ''


def fcitx_engine():
    reply = input_command('busctl', '--user', '--auto-start=no', '--timeout=300ms', 'call',
                          'org.fcitx.Fcitx5', '/controller', 'org.fcitx.Fcitx.Controller1',
                          'CurrentInputMethod')
    match = re.fullmatch(r's "([^"]+)"', reply)
    return match[1] if match else ''


def heal_gnome_rime():
    engine = input_command('ibus', 'engine')
    if engine and engine != 'rime':
        mru = input_command('gsettings', 'get', 'org.gnome.desktop.input-sources', 'mru-sources')
        if re.match(r"\[\('ibus',\s*'rime'\)", mru):
            input_command('ibus', 'engine', 'rime')


def input_mode():
    if GNOME or _engine == 'rime':
        try:
            mode = RIME_MODE.read_text(encoding='utf-8', errors='replace').strip()
        except OSError:
            return '·'
        return mode if mode in COLORS else '·'
    if _engine.startswith('keyboard-'):
        for led in Path('/sys/class/leds').glob('*::capslock/brightness'):
            try:
                if led.read_text().strip() == '1':
                    return 'A'
            except OSError:
                continue
        return 'a'
    return '·'


def update_ime(boss, now):
    global _engine_query, _engine, _next_probe
    focused_id = current_focused_os_window_id()
    manager = boss.os_window_map.get(focused_id)
    if _engine_query is not None and _engine_query.done():
        _engine = _engine_query.result()
        _engine_query = None
    if manager is None:
        badge = (None, '·')
    else:
        if not GNOME and _engine_query is None and now >= _next_probe:
            _engine_query = _pool.submit(fcitx_engine)
            _next_probe = now + 1
        mode = input_mode()
        badge = focused_id, BADGES.get(mode, mode)
        for tab in manager:
            for window in tab:
                if _cursor_modes.get(window.id, '·') != mode:
                    window.set_dynamic_color(12 if mode in COLORS else 112, COLORS.get(mode, ''))
                    _cursor_modes[window.id] = mode
    if badge != state.rime_badge:
        old_id, _ = state.rime_badge
        state.rime_badge = badge
        for window_id in {old_id, focused_id}:
            if tm := boss.os_window_map.get(window_id):
                tm.mark_tab_bar_dirty()


def tick(_timer_id):
    global _next_scan
    boss = get_boss()
    now = monotonic()
    update_ime(boss, now)
    if now >= _next_scan:
        _next_scan = now + 1
        agent_monitor.scan(boss)


def on_load(boss, data):
    global _timer
    if _timer is None:
        _timer = add_timer(tick, 0.25, True)


def on_focus_change(boss, window, data):
    global _last_heal
    if data['focused']:
        agent_monitor.mark_read(boss, window)
        now = monotonic()
        if GNOME and now - _last_heal >= 3:
            _last_heal = now
            _pool.submit(heal_gnome_rime)


def on_close(boss, window, data):
    _cursor_modes.pop(window.id, None)


