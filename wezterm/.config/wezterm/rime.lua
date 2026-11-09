-- Rime 聯動：Fcitx5 的啟用狀態 + Rime 的中英、簡繁與大小寫。
local wezterm = require 'wezterm'
local M = {}
local config_ref
local focus
local is_gnome = (os.getenv('XDG_CURRENT_DESKTOP') or ''):find('GNOME', 1, true)
local runtime_dir = os.getenv('XDG_RUNTIME_DIR') or '/tmp'
local mode_file = runtime_dir .. '/rime-mode'

local CURSOR_COLORS = {
  a = '#ccf5d7',
  A = '#0b6645',
  ['汉'] = '#f472b6',
  ['漢'] = '#e64553',
}
local BADGE_GLYPH = { ['汉'] = '◇', ['漢'] = '◆' }
-- 左欄只用零寬的樣式控制碼觸發重繪，工作區仍用右欄。
local BADGE_REDRAW = {
  a = '\x1b[32m',
  A = '\x1b[92m',
  ['汉'] = '\x1b[35m',
  ['漢'] = '\x1b[31m',
  ['·'] = '',
}

function M.setup(config)
  config_ref = config
end

function M.badge(window_id)
  local indicator = wezterm.GLOBAL.rime_indicator
  local mode = indicator and indicator.window_id == window_id and indicator.mode or '·'
  return BADGE_GLYPH[mode] or mode
end

local function read_mode()
  local f = io.open(mode_file, 'r')
  if not f then return '·' end
  local mode = f:read('*l')
  f:close()
  return CURSOR_COLORS[mode] and mode or '·'
end

local function input_mode(window, engine)
  if is_gnome or engine == 'rime' then return read_mode() end
  if engine and engine:match('^keyboard%-') then
    local _, leds = window:keyboard_modifiers()
    return leds and leds:find('CAPS_LOCK', 1, true) and 'A' or 'a'
  end
  return '·'
end

local function show_badge(window, window_id, mode)
  local indicator = wezterm.GLOBAL.rime_indicator
  if indicator and indicator.window_id == window_id and indicator.mode == mode then return end
  wezterm.GLOBAL.rime_indicator = { window_id = window_id, mode = mode }
  window:set_left_status(BADGE_REDRAW[mode])
end

local function show_cursor(window, state, mode)
  if state.cursor_mode == mode then return end
  -- 複製／搜索時延後變色，避免設定重載打斷鍵表與定時器。
  local key_table = window:active_key_table()
  if key_table == 'copy_mode' or key_table == 'search_mode' then return end

  local overrides = window:get_config_overrides() or {}
  if not window:is_focused() or focus ~= state then return end
  state.cursor_mode = mode
  local colors = overrides.colors or {}
  local color = CURSOR_COLORS[mode]
  if not color then
    -- 只清理本模組使用的配色，包括更新配置前已套用的舊顏色。
    if colors.cursor_bg ~= colors.cursor_border then return end
    for _, previous in pairs(CURSOR_COLORS) do
      if colors.cursor_bg == previous then
        local base = config_ref and config_ref.colors or {}
        colors.cursor_bg, colors.cursor_border = base.cursor_bg, base.cursor_border
        window:set_config_overrides(overrides)
        return
      end
    end
    return
  end
  if colors.cursor_bg == color and colors.cursor_border == color then return end
  for name, value in pairs(config_ref and config_ref.colors or {}) do
    if colors[name] == nil then colors[name] = value end
  end
  colors.cursor_bg, colors.cursor_border = color, color
  overrides.colors = colors
  window:set_config_overrides(overrides)
end

wezterm.on('update-right-status', function(window)
  if not window:is_focused() then return end
  local id = window:window_id()
  if not focus or focus.id ~= id then focus = { id = id } end
  local state = focus

  local now = os.time()
  if not is_gnome and state.probed_at ~= now then
    state.probed_at = now
    -- 單一非同步查詢，同時識別 Rime、直接輸入及其他引擎。
    local called, ok, output = pcall(wezterm.run_child_process, {
      'busctl', '--user', '--auto-start=no', '--timeout=300ms', 'call',
      'org.fcitx.Fcitx5', '/controller', 'org.fcitx.Fcitx.Controller1', 'CurrentInputMethod',
    })
    if not window:is_focused() or focus ~= state then return end
    state.engine = called and ok and output:match('^s "([^"]+)"%s*$') or nil
  end
  local mode = input_mode(window, state.engine)
  show_badge(window, id, mode)
  show_cursor(window, state, mode)
end)

wezterm.on('window-focus-changed', function(window)
  local id = window:window_id()
  if focus and focus.id == id then focus = nil end
  if window:is_focused() then return end
  local indicator = wezterm.GLOBAL.rime_indicator
  if indicator and indicator.window_id == id then
    wezterm.GLOBAL.rime_indicator = nil
    window:set_left_status('')
  end
end)

-- ── 输入法自动愈合 ──
-- 实测环境：Fedora 44 / gnome-shell+mutter 50.0→50.4 / ibus 1.5.34-rc1→1.5.34 / wezterm 20260901 nightly
-- 解锁竞态会把 rime 覆盖成 xkb；检出 mru-sources 首位为 rime 而引擎不是时自动恢复
local function ime_heal()
  local now = os.time()
  if now - (wezterm.GLOBAL.ime_heal_at or 0) < 3 then return end -- 节流：3 秒内至多检一次
  wezterm.GLOBAL.ime_heal_at = now
  -- timeout 1 封顶（P1-2 2026-09-09）：本函数跑在 GUI 主线程，io.popen +
  -- read('*a') 是无上界同步等待——ibus daemon 卡死时（恰是解锁竞态最易发生
  -- 的时刻）D-Bus 默认超时 ≈25s，全窗口假死。timeout 到点杀子进程 → 管道
  -- EOF → read 立即返回，最坏阻塞 1s；正常路径 timeout 原地陪跑，零差异。
  local f = io.popen('timeout 1 ibus engine 2>/dev/null')
  if not f then return end
  local engine = f:read('*a') or ''
  f:close()
  if engine == '' then return end -- 查询被 timeout 杀/失败：本轮跳过（“不知道”≠“不是 rime”）
  if engine:match('rime') then return end -- 引擎已是 rime，无需继续
  local g = io.popen('timeout 1 gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null')
  if not g then return end
  local mru = g:read('*a') or ''
  g:close()
  local first = mru:match('%[(%b())') -- 首个 ('ibus','rime') 或 ('xkb','us')
  if first and first:match('rime') then
    os.execute('ibus engine rime >/dev/null 2>&1 &') -- 后台发出，引擎侧瞬态卡顿也不阻塞 UI
  end
  local lg = io.open('/tmp/wezterm-ime-heal.log', 'a') -- 仅引擎非 rime 时记录，便于事后核查
  if lg then
    lg:write(os.date('%F %T '), 'engine=', (engine:gsub('%s', '')), ' mru_first=', tostring(first),
      (first and first:match('rime')) and ' => healed' or '', '\n')
    lg:close()
  end
end
-- 只挂 focus 事件（P1-2 B 档，2026-09-09）：解锁竞态/输入源切换必伴随窗口
-- 焦点变化，检测一次不漏；摘掉 update-right-status 挂载，消掉常态下每 3s
-- 一次的常驻 fork（GUI 线程上的同步子进程）。
if is_gnome then
  wezterm.on('window-focus-changed', ime_heal)
end

return M
