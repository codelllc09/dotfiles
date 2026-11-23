from collections import defaultdict
from pathlib import Path
from tempfile import TemporaryDirectory

from kitty.constants import config_dir

DEFAULT = 'default'
WORKSPACE_PICKER = 'workspace_picker'
COMPOSE_DESTINATION = 'compose_destination'
rime_badge = (None, '·')
last_compose = 0.0
last_detach = 0.0
_workspace_files = None

LAYOUT_GLYPHS = {
    '1H1': '吅', '1V1': '日', '1H1V1': '旧', '3V': '目', '1V1H1V1': '田',
    '1V(1H1)': '品', '(1H1)V1V1': '☱', '1V(1H1)V1': '☲',
    '(1H1)V(1H1)V1': '☳', '1V1V(1H1)': '☴', '(1H1)V1V(1H1)': '☵',
    '1V(1H1)V(1H1)': '☶', '3VH3V': '☷',
}


def panes(tab):
    windows = {window.id: window for window in tab}
    return tuple(windows[group.main_window_id] for group in tab.windows.iter_all_layoutable_groups()
                 if group.main_window_id in windows)


def workspace_name(tab):
    return (tab.created_in_session_name or tab.active_session_name or DEFAULT) if tab else DEFAULT


def workspace_counts(boss):
    counts = defaultdict(lambda: [0, 0])
    for tab in boss.all_tabs:
        normal = [window for window in panes(tab) if COMPOSE_DESTINATION not in window.user_vars]
        if normal:
            counts[workspace_name(tab)][0] += 1
            counts[workspace_name(tab)][1] += len(normal)
    return {name: counts[name] for name in sorted(counts, key=lambda name: (name != DEFAULT, name))}


def valid_workspace(name):
    return bool(name) and len(name) <= 32 and '/' not in name and name.isprintable()


def switch_workspace(boss, origin, name):
    global _workspace_files
    if not valid_workspace(name):
        boss.show_error('工作區名稱無效', '名稱最多 32 字，且不能包含 /。')
        return
    if origin.destroyed:
        return
    if workspace_name(origin.tabref()) == name:
        return
    # Session names select existing live windows before kitty reads a session file.
    if name == DEFAULT:
        path = Path(config_dir, 'default.kitty-session')
    else:
        if _workspace_files is None:
            _workspace_files = TemporaryDirectory(prefix='kitty-workspaces-')
        path = Path(_workspace_files.name, f'{name}.kitty-session')
        if not path.exists():
            path.write_text('layout splits\ncd ~\nlaunch\n', encoding='utf-8')
    boss.set_active_window(origin, switch_os_window_if_needed=True)
    boss.goto_session(str(path))


def split_groups(rectangles, axis):
    groups = []
    edge = 0
    for rectangle in sorted(rectangles, key=lambda bounds: bounds[axis]):
        if not groups or rectangle[axis] >= edge:
            groups.append([])
            edge = rectangle[axis + 2]
        else:
            edge = max(edge, rectangle[axis + 2])
        groups[-1].append(rectangle)
    return groups


def layout_code(rectangles, axis=0):
    if len(rectangles) == 1:
        return '1', None
    groups = split_groups(rectangles, axis)
    if len(groups) == 1:
        axis = 1 - axis
        groups = split_groups(rectangles, axis)
        if len(groups) == 1:
            return f'{len(rectangles)}?', axis
    direction = 'HV'[axis]
    parts = []
    for group in groups:
        code, used_axis = layout_code(group, 1 - axis)
        parts.append(f'({code})' if axis == 1 and used_axis == 0 else code)
    if len(parts) >= 3 and all(part == '1' for part in parts):
        return f'{len(parts)}{direction}', axis
    return direction.join(parts), axis


def layout_glyph(windows):
    if len(windows) < 2:
        return ''
    rectangles = [(g.left, g.top, g.right, g.bottom) for g in (window.geometry for window in windows)]
    code, _ = layout_code(rectangles)
    return LAYOUT_GLYPHS.get(code, code)
