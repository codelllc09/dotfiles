import base64
import json
import os
import shlex
import signal
import shutil
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from time import monotonic

from kittens.tui.handler import Handler, result_handler
from kittens.tui.line_edit import LineEdit
from kittens.tui.loop import Loop
from kittens.tui.operations import set_cursor_position, styled
from kitty.constants import config_dir, kitten_exe, kitty_exe
from kitty.fast_data_types import Color, truncate_point_for_length, wcswidth
from kitty.key_encoding import EventType

CONFIG = Path(config_dir)
if str(CONFIG) not in sys.path:
    sys.path.insert(0, str(CONFIG))

import terminal_state as state
from terminal_state import COMPOSE_DESTINATION, WORKSPACE_PICKER, switch_workspace, valid_workspace, workspace_counts, workspace_name

ACCENT = Color(180, 190, 254)
DIM = Color(88, 91, 112)
SELECTED = Color(49, 50, 68)


def clip(text, width):
    return text[:truncate_point_for_length(text, max(0, width))]


class WorkspacePicker(Handler):
    def __init__(self, current, counts):
        super().__init__()
        self.current = current
        self.counts = counts
        self.names = list(counts)
        self.index_of = {name: index for index, name in enumerate(self.names, start=1)}
        self.edit = LineEdit()
        self.index = 0
        self.result = ''
        self.error = ''

    @property
    def matches(self):
        return [name for name in self.names if name.startswith(self.edit.current_input)]

    def initialize(self):
        self.draw()

    def on_resize(self, size):
        super().on_resize(size)
        self.draw()

    def draw(self):
        rows, cols = self.screen_size.rows, self.screen_size.cols
        if rows < 5 or cols < 8:
            self.write('\x1b[H\x1b[2J')
            self.edit.write(self.write, '> ')
            return
        width = cols - 5
        matches = self.matches
        limit = rows - 5
        first = max(0, self.index - limit + 1)

        def row(text, fg=None, bg=None, bold=False):
            text = clip(text, width)
            text += ' ' * (width - wcswidth(text))
            return styled('│ ', fg=DIM) + styled(text, fg=fg, bg=bg, bold=bold) + styled(' │', fg=DIM)

        lines = [styled('╭' + '─' * (width + 2) + '╮', fg=DIM),
                 row('Workspace · Enter 跳轉／建立 · Tab 補全 · Esc 取消', fg=ACCENT, bold=True),
                 row('> ' + self.edit.current_input),
                 row(self.error or '─' * width, fg=Color(243, 139, 168) if self.error else DIM)]
        for i in range(first, first + limit):
            if i >= len(matches):
                lines.append(row(''))
                continue
            name = matches[i]
            tabs, panes = self.counts[name]
            label = f'{self.index_of[name]:2d}. {"*" if name == self.current else " "} {name}'
            label += f' {tabs}t' if tabs > 1 else ''
            label += f' {panes}p' if panes > 1 else ''
            lines.append(row(label, fg=ACCENT if name == self.current else None,
                             bg=SELECTED if i == self.index else None, bold=i == self.index))
        lines.append(styled('╰' + '─' * (width + 2) + '╯', fg=DIM))
        cursor = min(4 + self.edit.cursor_pos, cols - 3)
        self.write('\x1b[H\x1b[2J' + '\r\n'.join(lines) + set_cursor_position(cursor, 2))

    def on_text(self, text, in_bracketed_paste=False):
        chars = ''.join(char for char in text if char.isprintable())
        self.edit.add_text(chars[:max(0, 32 - len(self.edit.current_input))])
        self.index = 0
        self.error = ''
        self.draw()

    def perform_default_key_action(self, event):
        return False

    def on_key(self, event):
        if event.type is EventType.RELEASE:
            return
        self.error = ''
        matches = self.matches
        if event.matches('escape') or event.matches('ctrl+c'):
            self.quit_loop(0)
            return
        if event.matches('enter'):
            typed = self.edit.current_input
            name = typed if typed in matches or not matches else matches[self.index]
            if valid_workspace(name):
                self.result = name
                self.quit_loop(0)
                return
            self.error = '名稱最多 32 字，且不能包含 /。'
        elif event.matches('tab') and matches:
            self.edit.current_input = os.path.commonprefix(matches)
            self.edit.end()
            self.index = 0
        elif event.matches('up') or event.matches('ctrl+p'):
            self.index = max(0, self.index - 1)
        elif event.matches('down') or event.matches('ctrl+n'):
            self.index = min(max(0, len(matches) - 1), self.index + 1)
        elif self.edit.on_key(event):
            self.index = min(self.index, max(0, len(self.matches) - 1))
        self.draw()


def set_user_var(key, value):
    encoded = base64.b64encode(value.encode()).decode()
    sys.stdout.write(f'\x1b]1337;SetUserVar={key}={encoded}\x1b\\')
    sys.stdout.flush()


def run_picker(data):
    current, counts = json.loads(data)
    picker = WorkspacePicker(current, counts)
    loop = Loop()
    loop.loop(picker)
    if loop.return_code == 0 and picker.result:
        set_user_var(WORKSPACE_PICKER, picker.result)
    return loop.return_code


def editor_command():
    try:
        preferred = shlex.split(os.environ.get('EDITOR', ''))
    except ValueError:
        preferred = []
    if preferred and shutil.which(preferred[0]):
        return preferred
    return next(([editor] for editor in ('nano', 'nvim', 'vi') if shutil.which(editor)), [])


def send_text(target, content, paste):
    try:
        result = subprocess.run(
            [kitten_exe(), '@', 'send-text', '--match', f'id:{target}', '--stdin',
             '--bracketed-paste=' + ('auto' if paste else 'disable')],
            input=content.encode(), capture_output=True, timeout=8, check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def close_composer(signum, _frame):
    raise SystemExit(128 + signum)


def run_composer(target, destination, auto_submit):
    for signum in (signal.SIGHUP, signal.SIGTERM):
        signal.signal(signum, close_composer)
    editor = editor_command()
    if not editor:
        print('找不到編輯器。請設定 EDITOR，或安裝 nano、nvim、vi。')
        input('按 Enter 關閉。')
        return 1
    if Path(editor[0]).name in ('vim', 'nvim'):
        editor.extend(('-n', '-i', 'NONE', '-c', 'inoremap <C-a> <Home>',
                       '-c', 'inoremap <C-e> <End>', '-c', 'inoremap <C-k> <C-o>d$'))
    with TemporaryDirectory(prefix='kitty-compose-', dir='/dev/shm') as directory:
        draft = Path(directory) / 'draft.txt'
        draft.touch(mode=0o600)
        editor_env = os.environ.copy()
        editor_env.pop('KITTY_LISTEN_ON', None)
        if subprocess.run([*editor, str(draft)], env=editor_env).returncode != 0:
            return 1
        content = draft.read_text(encoding='utf-8').rstrip('\n')
        if not content.strip():
            return 0
        pasted = False
        while True:
            if not pasted:
                pasted = send_text(target, content, paste=True)
            if pasted and (not auto_submit or send_text(target, '\r', paste=False)):
                return 0
            problem = '稿件已回填，送出回車失敗' if pasted else '回填失敗，草稿仍保留'
            print(f'\n{problem}。請核對目標窗格：{destination}')
            while True:
                try:
                    choice = input('[r] 重試原窗格  [c] 複製草稿  [q] 捨棄並關窗：').strip().lower()
                except EOFError:
                    return 1
                if choice == 'r':
                    break
                if choice == 'c':
                    encoded = base64.b64encode(content.encode()).decode()
                    print(f'\x1b]52;c;{encoded}\x07已送出複製草稿的請求。')
                elif choice == 'q':
                    return 0


def launch_worker(boss, options, *args):
    from kitty.launch import launch, parse_launch_args

    command = (kitty_exe(), '+runpy', 'import runpy, sys; runpy.run_path(sys.argv.pop(1), run_name="__main__")',
               str(CONFIG / 'workflow_keys.py'), *args)
    opts, argv = parse_launch_args((*options, '--', *command))
    return launch(boss, opts, argv)


def open_picker(boss, origin):
    tab = origin.tabref()
    if tab is None or any(WORKSPACE_PICKER in window.user_vars for window in tab):
        return
    data = json.dumps((workspace_name(tab), workspace_counts(boss)), ensure_ascii=False)
    drawer = launch_worker(
        boss, ('--type=tab-dock', '--dock-edge=bottom', '--dock-size=42%',
               f'--source-window=id:{origin.id}', '--add-to-session=.', f'--var={WORKSPACE_PICKER}='),
        'workspace-ui', data,
    )
    if drawer is not None:
        def selected(window):
            if name := window.user_vars.get(WORKSPACE_PICKER):
                if target := boss.window_id_map.get(origin.id):
                    switch_workspace(boss, target, name)
        drawer.actions_on_removal.append(selected)


def open_composer(boss, origin, auto_submit):
    now = monotonic()
    if COMPOSE_DESTINATION in origin.user_vars or now - state.last_compose < 1:
        return
    manager = boss.os_window_map[origin.os_window_id]
    tab = origin.tabref()
    number = tuple(manager.tabs_to_be_shown_in_tab_bar).index(tab) + 1
    title = ''.join(char if char.isprintable() else ' ' for char in origin.title).strip()
    destination = f'{workspace_name(tab)} / TAB{number} / #{origin.id} {title}'.strip()
    state.last_compose = now
    launch_worker(
        boss, ('--type=os-window', f'--source-window=id:{origin.id}', '--cwd=current',
               f'--os-window-title=compose → {destination}', f'--var={COMPOSE_DESTINATION}={destination}',
               '--allow-remote-control', '--remote-control-password="" send-text'),
        'compose-ui', str(origin.id), destination, str(int(auto_submit)),
    )


def detach_pane(boss, origin):
    now = monotonic()
    if now - state.last_detach < 2:
        return
    state.last_detach = now
    name = origin.created_in_session_name
    boss.set_active_window(origin, switch_os_window_if_needed=True)
    boss.detach_window('new')
    if (tab := origin.tabref()) is not None:
        tab.created_in_session_name = name
        tab.mark_tab_bar_dirty()


@result_handler(no_ui=True)
def handle_result(args, _data, target_window_id, boss):
    if origin := boss.window_id_map.get(target_window_id):
        if args[1:] == ['workspace']:
            open_picker(boss, origin)
        elif args[1:] == ['detach']:
            detach_pane(boss, origin)
        elif args[1:2] == ['compose']:
            open_composer(boss, origin, args[2:] == ['auto-submit'])


def main(args):
    if args[1] == 'workspace-ui':
        return run_picker(args[2])
    if args[1] == 'compose-ui':
        return run_composer(int(args[2]), args[3], args[4] == '1')
    raise SystemExit('Use the workflow_keys.py key mappings in kitty.conf')


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
