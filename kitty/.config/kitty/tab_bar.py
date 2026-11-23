import re
import sys

from kitty.constants import config_dir
from kitty.fast_data_types import get_boss, truncate_point_for_length, wcswidth
from kitty.tab_bar import as_rgb

if config_dir not in sys.path:
    sys.path.insert(0, config_dir)

import agent_monitor as monitor
import terminal_state as state

BACKGROUND = 0x1e1e2e
ACTIVE = 0x313244
ACCENT = 0xb4befe
TEXT = 0xcdd6f4
DIM = 0x585b70
INACTIVE = 0x6c7086
URGENT = 0xf38ba8

APP_ICONS = {
    'pi': '\u03c0',
    'claude': '\U000f06a9',
    'codex': '\uec20',
    'nvim': '\ue6ae',
    'vim': '\ue7c5',
    'emacs': '\ue632',
    'emacsclient': '\ue632',
    'less': '\U000f0349',
    'man': '\U000f0349',
    'yazi': '\U000f01e5',
    'lf': '\U000f024b',
    'ranger': '\U000f024b',
    'nnn': '\U000f024b',
    'vifm': '\U000f024b',
    'mc': '\U000f024b',
    'bash': '\U000f1183',
    'zsh': '\U000f018d',
    'sh': '\U000f018d',
    'tmux': '\U000f018d',
    'node': '\U000f0399',
    'npm': '\U000f0399',
    'npx': '\U000f0399',
    'pnpm': '\U000f0399',
    'yarn': '\U000f0399',
    'bun': '\ue76f',
    'deno': '\ue7c0',
    'python': '\U000f0320',
    'python3': '\U000f0320',
    'cargo': '\U000f1617',
    'rustc': '\U000f1617',
    'go': '\U000f07d3',
    'gcc': '\U000f0671',
    'cc': '\U000f0671',
    'g++': '\U000f0672',
    'c++': '\U000f0672',
    'java': '\U000f0b37',
    'ruby': '\U000f0d2d',
    'php': '\U000f031f',
    'lua': '\U000f08b1',
    'perl': '\ue67e',
    'elixir': '\ue62d',
    'erlang': '\uf23f',
    'zig': '\ue6a9',
    'cmake': '\ue794',
    'git': '\U000f02a2',
    'docker': '\U000f0868',
    'podman': '\U000f0868',
    'kubectl': '\U000f10fe',
    'helm': '\U000f0031',
    'terraform': '\U000f1062',
    'aws': '\U000f0e0f',
    'htop': '\U000f035b',
    'btm': '\U000f035b',
    'top': '\U000f035b',
    'ssh': '\U000f08c0',
}


def app_label(window):
    name = monitor.applications.get(window.id, '') if window else ''
    return (APP_ICONS.get(name) or APP_ICONS.get(re.sub(r'[0-9.]+$', '', name))
            or APP_ICONS.get(re.sub(r'[0-9.]+$', '', name.partition('-')[0])) or name or '·')


def paint(screen, text, color, background, stop):
    length = max(0, stop - screen.cursor.x)
    screen.cursor.fg = as_rgb(color)
    screen.cursor.bg = as_rgb(background)
    screen.draw(text[:truncate_point_for_length(text, length)])


def right_status(boss, manager):
    window = manager.active_window
    if window is not None and (destination := window.user_vars.get(state.COMPOSE_DESTINATION)):
        return [(f'→ {destination}', ACCENT)]
    current = state.workspace_name(manager.active_tab)
    names = list(state.workspace_counts(boss))
    if current not in names:
        names = sorted((*names, current), key=lambda name: (name != state.DEFAULT, name))
    return [('WS ', DIM), (f'{names.index(current) + 1}/{len(names)}', TEXT),
            (': ', DIM), (current, ACCENT)]


def draw_tab(draw_data, screen, info, before, max_tab_length, index, is_last, extra_data):
    boss = get_boss()
    manager = boss.os_window_map[info.os_window_id]
    status = right_status(boss, manager) if manager.active_tab and not extra_data.for_layout else ()
    status_width = sum(wcswidth(text) for text, _ in status)
    if info.tab_id == -1:
        paint(screen, ' + ', ACCENT if info.is_active else INACTIVE, BACKGROUND,
              min(before + max_tab_length, screen.columns - 1))
        return finish_tab(screen, status, status_width, is_last)
    tab = next(tab for tab in manager if tab.id == info.tab_id)
    windows = state.panes(tab)
    active = tab.active_window
    if active is not None:
        active = tab.windows.main_window_for(active) or (windows[0] if windows else active)
    bg = ACTIVE if info.is_active else BACKGROUND
    badge = state.rime_badge[1] if info.is_active and state.rime_badge[0] == info.os_window_id else '·'
    stop = min(before + max_tab_length, before + 24, screen.columns - 1)
    if status_width:
        stop = max(before + 1, min(stop, screen.columns - status_width - 2))
    paint(screen, f' [{badge}] ', ACCENT if info.is_active else INACTIVE, bg, stop)
    records = [monitor.agents[window.id] for window in windows if window.id in monitor.agents]
    for condition in ('blocked', 'working', 'idle'):
        if any(record.state == condition for record in records):
            paint(screen, '● ', monitor.COLORS[condition], bg, stop)
            break
    unread = sum(record.unread for record in records)
    if unread:
        paint(screen, f'{min(unread, 9)}{"+" if unread > 9 else ""} ', URGENT, bg, stop)
    paint(screen, f'TAB{index} ', DIM, bg, stop)
    paint(screen, f'{app_label(active)} ', TEXT if info.is_active else INACTIVE, bg, stop)
    if glyph := state.layout_glyph(windows):
        paint(screen, glyph + ' ', DIM, BACKGROUND, stop)
    return finish_tab(screen, status, status_width, is_last)


def finish_tab(screen, status, status_width, is_last):
    end = screen.cursor.x
    if is_last and status:
        start = max(end + 1, screen.columns - status_width - 1)
        if start < screen.columns - 1:
            screen.cursor.x = start
            for value, color in status:
                paint(screen, value, color, BACKGROUND, screen.columns - 1)
    return end
