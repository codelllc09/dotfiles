-- rime.lua — Rime 輸入法聯動：徽章 / 游標色 / IME 自動癒合
-- 从主配置拆出（v4 模块化）；坏了只丢徽章和游标色，不影响其它。
-- setup(config) 必须在主配置里先调用（游标色 override 需要 tab_bar 配色引用）
--
-- 接口：
--   M.setup(config) → 注入主 config 引用（游标色 override 时保留 tab_bar 配色）
--   M.badge()       → 焦点 tab 徽章字形（'·'/西文，'◇'/简中，'◆'/繁中）
-- 内部行为（拆进来时就有的三件事）：
--   ① update-right-status：读 /tmp/rime-mode → 游标变色（Rime 推 title 触发重绘）
--   ② ime_heal：window-focus/update-right-status 时检测 ibus 引擎被覆盖成 xkb → 自动恢复
--   ③ 徽章字形替换：简◇繁◆（1 格宽，防药丸随输入法切换抖动）
local wezterm = require 'wezterm'
local M = {}
local config_ref = nil

function M.setup(config)
  config_ref = config
end

-- 光标颜色随输入模式（Rime 推送 set-tab-title 会连带触发本事件）
-- 绿=西文可输命令，红=中文；浅/深 = 小写/简体 vs 大写(Caps)/繁体
local CURSOR_COLORS = {
  ['a'] = '#ccf5d7', -- 亮薄荷绿: 西文
  ['A'] = '#0b6645', -- 墨绿: 西文(CapsLock)
  ['汉'] = '#f472b6', -- 粉色: 简中
  ['漢'] = '#e64553', -- 深红: 繁中
}
wezterm.GLOBAL.rime_cursor_color = nil
wezterm.on('update-right-status', function(window, pane)
  local f = io.open('/tmp/rime-mode', 'r')
  if not f then return end
  local s = f:read('*l'); f:close()
  local color = CURSOR_COLORS[s]
  if not color or color == wezterm.GLOBAL.rime_cursor_color then return end -- 防抖
  wezterm.GLOBAL.rime_cursor_color = color
  window:set_config_overrides {
    colors = {
      cursor_bg = color,
      cursor_border = color,
      tab_bar = config_ref and config_ref.colors and config_ref.colors.tab_bar or nil,
    },
  }
end)

-- 徽标：焦点 tab 现读状态文件（重绘由 Rime 推送 set-tab-title 触发，零轮询）
local function rime_mode_read()
  local f = io.open('/tmp/rime-mode', 'r')
  if not f then return '·' end
  local s = f:read('*l'); f:close()
  if s == nil or s == '' then return '·' end
  return s
end

-- 徽章字形：简=◇ 繁=◆（同源异繁简，皆 1 格宽；CJK 徽章 2 格会令药丸
-- 随输入法切换抖动，故在显示层替换。rime 协议与游标色键名不变）
local BADGE_GLYPH = {
  ['汉'] = '◇',
  ['漢'] = '◆',
}
local function rime_badge()
  local mode = rime_mode_read()
  return BADGE_GLYPH[mode] or mode
end

M.badge = rime_badge

-- ── 输入法自动愈合 ──
-- 实测环境：Fedora 44 / gnome-shell+mutter 50.0→50.4 / ibus 1.5.34-rc1→1.5.34 / wezterm 20260901 nightly
-- 解锁竞态会把 rime 覆盖成 xkb；检出 mru-sources 首位为 rime 而引擎不是时自动恢复
local function ime_heal()
  local now = os.time()
  if now - (wezterm.GLOBAL.ime_heal_at or 0) < 3 then return end -- 节流：3 秒内至多检一次
  wezterm.GLOBAL.ime_heal_at = now
  local f = io.popen('ibus engine 2>/dev/null')
  if not f then return end
  local engine = f:read('*a') or ''
  f:close()
  if engine:match('rime') then return end -- 引擎已是 rime，无需继续
  local g = io.popen('gsettings get org.gnome.desktop.input-sources mru-sources 2>/dev/null')
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
wezterm.on('window-focus-changed', function(window, pane) ime_heal() end)
wezterm.on('update-right-status', function(window, pane) ime_heal() end)

return M
