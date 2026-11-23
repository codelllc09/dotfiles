import json
import os
import re
from atexit import register
from contextlib import suppress
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from time import time

from kitty.child import cached_process_data
from kitty.fast_data_types import current_focused_os_window_id
from kitty.utils import log_error

from terminal_state import COMPOSE_DESTINATION, panes

TOKENS = re.compile(r'(?<![A-Za-z0-9])(claude(?:-code)?|codex|pi)(?![A-Za-z0-9])')
PI_SPINNER = re.compile(
    r'^─*\s*[\u2800-\u28ff] (?:Working|Retrying \(|Compacting context|'
    r'Auto-compacting|Context overflow detected|Summarizing branch)'
)
CONTEXT = re.compile(r'(\d+\.?\d*)%/\S+')
COST = re.compile(r'\$(\d+\.\d+)')
COLORS = {'working': 0xa6e3a1, 'idle': 0x585b70, 'blocked': 0xf9e2af}
STATE_DIR = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'kitty-herd'
SNAPSHOT = STATE_DIR / f'current.{os.getpid()}.json'


@dataclass
class Agent:
    agent: str
    state: str
    since: int
    rule: str
    ctx: float | None
    cost: float | None
    cwd: str
    tty: str
    unread: int


agents = {}
applications = {}


def classify(agent, lines):
    if not lines:
        return 'idle', 'default_no_rule'
    region = '\n'.join(lines)
    if agent == 'pi':
        if any(line.strip() == 'Project trust' for line in lines):
            return 'blocked', 'blocked_trust'
        if any(line.startswith('↑↓ navigate') for line in lines):
            return 'blocked', 'blocked_selector'
        if any(PI_SPINNER.match(line.strip()) for line in lines):
            return 'working', 'working_spinner'
    elif 'esc to interrupt' in region:
        return 'working', 'working_interrupt'
    elif agent == 'claude' and any(prompt in region for prompt in
                                   ('Do you want to proceed?', 'Would you like to proceed?')):
        return 'blocked', 'blocked_form'
    return 'idle', 'default_known_agent_idle_fallback'


def foreground(window):
    processes = window.child.foreground_processes
    first = window.child.foreground_cmdline or window.child.argv
    name = os.path.basename(first[0]) if first else ''
    # The foreground group includes the wrappers used to launch agents.
    for process in processes:
        cmdline = process['cmdline'] or ()
        for arg in cmdline[:3]:
            if match := TOKENS.search(os.path.basename(arg)):
                agent = match[1].split('-', 1)[0]
                return agent, process['cwd'] or ''
    return name, ''


def timestamp():
    return datetime.now().isoformat(sep=' ', timespec='seconds')


def snapshot():
    temp = SNAPSHOT.with_suffix('.tmp')
    try:
        STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        payload = {'ts': timestamp(), 'panes': [dict(pane=pid, **asdict(agents[pid]))
                                               for pid in sorted(agents)]}
        temp.write_text(json.dumps(payload, ensure_ascii=False) + '\n', encoding='utf-8')
        temp.replace(SNAPSHOT)
    except OSError as error:
        log_error(f'kitty agent state: {error}')


def transition(pid, agent, previous, new, record):
    entry = {
        'ts': timestamp(), 'pane': pid, 'instance': os.getpid(), 'agent': agent,
        'from': previous, 'to': new, 'ctx': record.ctx, 'cost': record.cost,
        'cwd': record.cwd, 'unread': record.unread,
    }
    try:
        STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (STATE_DIR / 'transitions.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(entry, ensure_ascii=False) + '\n')
    except OSError as error:
        log_error(f'kitty agent transition: {error}')


def inspect_agent(boss, window, name, cwd, focused):
    screen = window.screen
    lines = [str(screen.line(row)) for row in range(max(0, screen.lines - 40), screen.lines)]
    while lines and not lines[-1].strip():
        lines.pop()
    state, rule = classify(name, lines[-15:])
    footer = '\n'.join(lines[-3:])
    ctx = CONTEXT.search(footer)
    cost = COST.search(footer)
    old = agents.get(window.id)
    if old and old.agent == name and old.state == state:
        old.ctx = float(ctx[1]) if ctx else None
        old.cost = float(cost[1]) if cost else None
        return False
    previous = old.state if old else 'new'
    notify = not focused and (state == 'blocked' or (state == 'idle' and previous == 'working'))
    unread = min((old.unread if old else 0) + int(notify), 99)
    tty = ''
    try:
        tty = os.readlink(f'/proc/{window.child.pid}/fd/0')
    except OSError:
        pass
    record = Agent(name, state, int(time()), rule, float(ctx[1]) if ctx else None,
                   float(cost[1]) if cost else None, cwd, tty, unread)
    agents[window.id] = record
    transition(window.id, name, previous, state, record)
    if notify:
        args = ['notify-send', '-a', 'kitty-herd', '-i', 'utilities-terminal']
        if state == 'blocked':
            args.extend(('-u', 'critical'))
        args.extend((f'{name} · pane {window.id}', '在等你决定' if state == 'blocked' else '运行完成'))
        boss.run_background_process(args)
    return True


def mark_read(boss, window):
    if (record := agents.get(window.id)) is not None and record.unread:
        record.unread = 0
        snapshot()
        if manager := boss.os_window_map.get(window.os_window_id):
            manager.mark_tab_bar_dirty()


def scan(boss):
    focused_id = current_focused_os_window_id()
    dirty_os_windows = set()
    agent_changed = False
    seen = set()
    with cached_process_data():
        for tab in boss.all_tabs:
            for window in panes(tab):
                if window.destroyed or COMPOSE_DESTINATION in window.user_vars:
                    continue
                seen.add(window.id)
                name, cwd = foreground(window)
                if applications.get(window.id) != name:
                    applications[window.id] = name
                    dirty_os_windows.add(window.os_window_id)
                if name in ('pi', 'claude', 'codex'):
                    focused = window.is_focused and window.os_window_id == focused_id
                    if inspect_agent(boss, window, name, cwd, focused):
                        agent_changed = True
                        dirty_os_windows.add(window.os_window_id)
                elif (record := agents.pop(window.id, None)) is not None:
                    transition(window.id, record.agent, record.state, 'gone', record)
                    agent_changed = True
                    dirty_os_windows.add(window.os_window_id)
    for pid in applications.keys() - seen:
        del applications[pid]
    for pid in agents.keys() - seen:
        record = agents.pop(pid)
        transition(pid, record.agent, record.state, 'gone', record)
        agent_changed = True
    if agent_changed:
        snapshot()
    for os_window_id in dirty_os_windows:
        if manager := boss.os_window_map.get(os_window_id):
            manager.mark_tab_bar_dirty()


@register
def close():
    with suppress(OSError):
        SNAPSHOT.unlink(missing_ok=True)
