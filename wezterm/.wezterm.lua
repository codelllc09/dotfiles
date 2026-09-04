-- WezTerm 配置（Lua）· v4 模块化
-- 拆分自单文件（v3 教训：476 行单文件改一处可能碰坏全局）：
--   agent_monitor.lua coding agent 状态监视（状态点/未读/通知/APPS 缓存/app_name）
--   pane_layout.lua   窗格分屏佈局碼（几何 → 唯一码 → 象形字：吅日田品卦象）
--   app_icon.lua      TABn 程序图标（APP_ICON 表 + 归一化查表）
--   rime.lua          Rime 联动（徽章/游标色/IME 愈合）
--   quick_select.lua  QuickSelect 模式表 + DIY 扫描选择器
-- 各模块 pcall 引入，坏了只丢对应功能。验证配置（独立 socket 真启动）：
--   WEZTERM_UNIX_SOCKET=/tmp/chk.sock WEZTERM_LOG=warn wezterm start -e true
-- 文档: https://wezterm.org/config/files.html

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ── 外观 ──────────────────────────────────────
-- B方案：Maple Mono NF CN 单字体（英文+图标+中文全自带，严格 2:1）
-- 中文覆盖：CJK 基本区全量 20976 字；生僻字（扩展A/B）由 Noto 兜底
config.font = wezterm.font_with_fallback {
  'Maple Mono NF CN',
  'Noto Sans Mono CJK SC',
}
config.font_size = 12.0
config.color_scheme = 'Catppuccin Mocha'   -- 内置主题，可换 'Tokyo Night' / 'GitHub Dark' 等
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }
config.hide_tab_bar_if_only_one_tab = false -- 状态栏常驻
config.use_fancy_tab_bar = false           -- 复古细条（一行高的状态行，非花式标签栏）
config.tab_bar_at_bottom = true           -- 放底部，紧邻打字区
config.warn_about_missing_glyphs = false  -- 字形告警不弹窗（渲染正常时的误报）

-- ── 模块引入（~/.config/wezterm/，经 package.path；主档必须在 ~/.wezterm.lua）──
package.path = wezterm.home_dir .. '/.config/wezterm/?.lua;' .. package.path
local am_ok, agent_monitor = pcall(require, 'agent_monitor')
if not am_ok then agent_monitor = nil end
if agent_monitor then agent_monitor.setup() end
local pl_ok, pane_layout = pcall(require, 'pane_layout')
if not pl_ok then pane_layout = nil end
local ai_ok, app_icon = pcall(require, 'app_icon')
if not ai_ok then app_icon = nil end
local rime_ok, rime = pcall(require, 'rime')
if rime_ok then pcall(rime.setup, config) end
local qs_ok, quick_select = pcall(require, 'quick_select')

-- ── format-tab-title：标签渲染组装 ──
-- 结构：[徽章] [状态点●] [未读n] TABn 图标 [佈局碼]
-- 数据源（各自 pcall，坏了静默降级）：
--   rime.badge()              输入法徽章（焦点 tab 专用；非焦点固定 '·'）
--   agent_monitor.tab_dot/unread agent 状态点与 QQ 式未读计数
--   app_icon.label(tab)       TABn 程序图标（agent_monitor.app_name → 进程名 → '·'）
--   pane_layout.glyph(tab)    佈局碼象形字（N≥2 pane 才显示，药丸外暗灰）
wezterm.on('format-tab-title', function(tab, tabs, panes, conf, hover, max_width)
  local badge = '·'
  if rime_ok then pcall(function() badge = rime.badge() end) end
  -- TABn：位置序号（0 起转 1 起；关 tab 后自动重排）
  local tabno = '?'
  pcall(function() tabno = tostring((tab.tab_index or 0) + 1) end)
  local label = '·'
  if app_icon then pcall(function() label = app_icon.label(tab) end) end
  -- herd 指示燈（方案A tab 級聚合）與未讀徽章（QQ 式）：各自獨立渲染；
  -- 任何失败静默回退为空，不影响原渲染
  local herd_dot, herd_unread = {}, {}
  if agent_monitor then
    pcall(function() herd_dot = agent_monitor.tab_dot(tab) end)
    pcall(function() herd_unread = agent_monitor.tab_unread(tab) end)
  end
  -- 佈局碼（v2.2）：N≥2 才顯示，暗灰；單格不顯示
  local herd_code = ''
  if pane_layout then
    pcall(function()
      local c = pane_layout.glyph(tab, panes)
      if c and c ~= '' and c ~= '1' then herd_code = c end
    end)
  end
  if tab.is_active then
    local els = {
      { Background = { Color = '#313244' } },  -- 焦点 tab 药丸底色
      { Foreground = { Color = '#b4befe' } },   -- 徽标 accent 蓝
      { Text = ' [' .. badge .. '] ' },
    }
    for _, e in ipairs(herd_dot) do els[#els + 1] = e end
    for _, e in ipairs(herd_unread) do els[#els + 1] = e end
    els[#els + 1] = { Foreground = { Color = '#585b70' } } -- TABn 暗灰（状态点后重设，防染色）
    els[#els + 1] = { Text = 'TAB' .. tabno .. ' ' }
    els[#els + 1] = { Foreground = { Color = '#cdd6f4' } } -- 程序图标亮色
    els[#els + 1] = { Text = label .. ' ' }
    -- 佈局碼：藥丸外的額外部分（退出藥丸底色後再渲染）
    if herd_code ~= '' then
      els[#els + 1] = { Background = { Color = '#1e1e2e' } } -- 退出藥丸底色
      els[#els + 1] = { Foreground = { Color = '#585b70' } }
      els[#els + 1] = { Text = herd_code .. ' ' }
    end
    return wezterm.format(els)
  else
    local els = {
      { Foreground = { Color = '#6c7086' } },   -- 非焦点：灰阶默认符
      { Text = ' [·] ' },
    }
    for _, e in ipairs(herd_dot) do els[#els + 1] = e end
    for _, e in ipairs(herd_unread) do els[#els + 1] = e end
    els[#els + 1] = { Foreground = { Color = '#585b70' } } -- TABn 暗一档
    els[#els + 1] = { Text = 'TAB' .. tabno .. ' ' }
    els[#els + 1] = { Foreground = { Color = '#6c7086' } } -- 图标灰阶
    els[#els + 1] = { Text = label .. ' ' }
    -- 佈局碼：藥丸外的額外部分
    if herd_code ~= '' then
      els[#els + 1] = { Foreground = { Color = '#585b70' } }
      els[#els + 1] = { Text = herd_code .. ' ' }
    end
    return wezterm.format(els)
  end
end)

-- 状态栏配色：与 Catppuccin Mocha 背景同色，融为一体
config.colors = config.colors or {}
config.colors.tab_bar = {
  background = '#1e1e2e',
  active_tab = { bg_color = '#1e1e2e', fg_color = '#cdd6f4' },
  inactive_tab = { bg_color = '#1e1e2e', fg_color = '#6c7086' },
  inactive_tab_hover = { bg_color = '#1e1e2e', fg_color = '#b4befe' },
  new_tab = { bg_color = '#1e1e2e', fg_color = '#6c7086' },
  new_tab_hover = { bg_color = '#1e1e2e', fg_color = '#b4befe' },
}

-- ── 行为 ──────────────────────────────────────
config.scrollback_lines = 10000
config.tab_max_width = 24 -- 默認 16：藥丸(15格)+佈局碼會被硬切只露一個字符
-- 默认已支持: Ctrl+Shift+C/V 复制粘贴、Ctrl+Shift+T 新标签、Ctrl+Tab 切标签
-- 分屏快捷键（对齐常见习惯）:
config.keys = {
  -- 搜索回滚缓冲区：唯一入口 Ctrl+Shift+F（WezTerm 出厂默认，无需自绑）
  -- 简繁切换已移至 Rime 的 Super+F；释放多余的默认搜索键：
  { key = 'f', mods = 'SUPER', action = wezterm.action.DisableDefaultAssignment }, -- Super+F 让给 Rime 简繁切换
  { key = 'f', mods = 'CTRL', action = wezterm.action.DisableDefaultAssignment },  -- Ctrl+F 放行给终端内程序
  -- Ctrl+Shift+Enter 右侧新分屏
  { key = 'Enter', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  -- Ctrl+Shift+E 下方新分屏
  { key = 'E', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- Ctrl+Shift+W 关闭当前分屏
  { key = 'W', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },
}

-- ── Super 镜像键全禁（Super+W 暂留待议）──
-- ①与 Ctrl+Shift+* 系完全重复；②把 Super 空间完整腾给将来（GNOME 层/nvim kitty 协议等）
for _, k in ipairs { 'c', 'v', 't', 'n', 'r', 'k', 'm', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '=' } do
  table.insert(config.keys, { key = k, mods = 'SUPER', action = wezterm.action.DisableDefaultAssignment })
end
-- 方括号系（切/移标签）的四种拼写变体
for _, k in ipairs { '[', ']', '{', '}' } do
  table.insert(config.keys, { key = k, mods = 'SHIFT|SUPER', action = wezterm.action.DisableDefaultAssignment })
end
for _, k in ipairs { '{', '}' } do
  table.insert(config.keys, { key = k, mods = 'SUPER', action = wezterm.action.DisableDefaultAssignment })
end

-- ── Insert 家族禁用（复制/粘贴已由 Ctrl+Shift+C/V 唯一承担）──
for _, m in ipairs { 'CTRL', 'SHIFT' } do
  table.insert(config.keys, { key = 'Insert', mods = m, action = wezterm.action.DisableDefaultAssignment })
end

-- ── QuickSelect 接入（模式表 + 键位：插队到 keys 首位盖掉 phys:Space 默认绑定）──
if qs_ok then
  config.quick_select_patterns = quick_select.patterns
  for _, k in ipairs(quick_select.keys) do table.insert(config.keys, 1, k) end
end

return config
