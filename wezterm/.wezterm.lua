-- WezTerm 配置（Lua）· 起步版
-- 文档: https://wezterm.org/config/files.html
-- 改动后即时生效，无需重启

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
      tab_bar = config.colors.tab_bar,
    },
  }
end)

-- ── herd：coding agent 状态监视（纯 Lua、零外部进程）──
-- 识别前景进程(pi/claude/codex..) → 刮屏底部判 working/idle/blocked
-- → tab 状态点 + ~/.local/state/wezterm-herd/ 落盘 + GNOME 通知
-- 实测本 build 不解析 XDG 主档路径：主档必须在 ~/.wezterm.lua；
-- herd.lua 仍在 ~/.config/wezterm/（经 package.path 引入，家目录不堆模块）
package.path = wezterm.home_dir .. '/.config/wezterm/?.lua;' .. package.path
local herd_ok, herd = pcall(require, 'herd')
if not herd_ok then herd = nil end -- 模块坏了只丢状态点，不影响其它
if herd then herd.setup() end

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

wezterm.on('format-tab-title', function(tab, tabs, panes, conf, hover, max_width)
  local title = tab.active_pane.title or ''
  -- herd 状态点：agent pane 才有；任何失败静默回退为无点，不影响原渲染
  local herd_dot = {}
  if herd then pcall(function() herd_dot = herd.dot_for(tab.active_pane.pane_id) end) end
  -- 佈局碼（v2.2）：N≥2 才顯示，暗灰；單格不顯示
  local herd_code = ''
  if herd then
    pcall(function()
      local c = herd.layout_code(tab)
      if c and c ~= '' and c ~= '1' then herd_code = c end
    end)
  end
  if tab.is_active then
    local els = {
      { Background = { Color = '#313244' } },  -- 焦点 tab 药丸底色
      { Foreground = { Color = '#b4befe' } },   -- 徽标 accent 蓝
      { Text = ' [' .. rime_badge() .. '] ' },
    }
    for _, e in ipairs(herd_dot) do els[#els + 1] = e end
    if herd_code ~= '' then
      els[#els + 1] = { Foreground = { Color = '#585b70' } } -- 佈局碼暗灰
      els[#els + 1] = { Text = herd_code .. ' ' }
    end
    els[#els + 1] = { Foreground = { Color = '#cdd6f4' } } -- 标题亮色（状态点后重设，防染色）
    els[#els + 1] = { Text = title .. ' ' }
    return wezterm.format(els)
  else
    local els = {
      { Foreground = { Color = '#6c7086' } },   -- 非焦点：灰阶默认符
      { Text = ' [·] ' },
    }
    for _, e in ipairs(herd_dot) do els[#els + 1] = e end
    if herd_code ~= '' then
      els[#els + 1] = { Foreground = { Color = '#585b70' } } -- 佈局碼暗灰
      els[#els + 1] = { Text = herd_code .. ' ' }
    end
    els[#els + 1] = { Foreground = { Color = '#6c7086' } } -- 恢复灰阶（防状态点染色标题）
    els[#els + 1] = { Text = title .. ' ' }
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

-- ── QuickSelect（默认键 Ctrl+Shift+Space）：目标导向模式 ──
-- 思路：只匹配「值得复制的东西」——命令整行、仓库地址、URL、路径、id 等
-- 本轮诊断：不用 disable 开关（怀疑 nightly bug），默认 pattern + 自定义叠加
-- QSOK 是诊断用的纯字面量 pattern（零元字符）：若它都没 label = 配置未进 matcher

local QS_PATTERNS = {
  [[QSOK]],

  -- 命令整行（从命令词开始匹配，$ 提示符不带入，复制即用；要求命令后跟 ASCII，不误伤中文散文）
  [[\b(?:git|gh|docker|podman|kubectl|helm|npm|npx|pnpm|yarn|bun|node|deno|python3?|pip3?|uv|pipx|cargo|go|make|cmake|sudo|dnf|apt|apt-get|brew|pacman|systemctl|journalctl|firewall-cmd|crontab|curl|wget|ssh|scp|rsync|sftp|tar|zip|unzip|gpg|openssl|cd|cp|mv|rm|mkdir|touch|ln|chmod|chown|chgrp|grep|sed|awk|find|xargs|sort|cat|head|tail|echo|printf|export|source|alias|which|nvim|vim|tmux|flatpak|snap|ip|ss|ping|dig|nslookup|nc|tr|cut|tee|diff|patch|du|df|ps|kill)\s+[a-zA-Z0-9"'$./~(-].*]],

  -- git 仓库地址（https 形式由 URL 覆盖；补 ssh 形式和裸域名形式）
  [[git@[\w.-]+:[\w./~-]+?\.git\b]],
  [[\b(?:github|gitlab|gitee|bitbucket)\.com/[\w./-]+]],

  -- URL（本轮用纯 ASCII 字符类，排除中文字符嫌疑）
  [[https?://\S*[^\s,.:;!?()\[\]{}<>"']],

  -- 小物件
  [[\b[A-Z][A-Z0-9_]{1,30}=\S+]],                                        -- 环境变量赋值 FOO=bar
  [[\b[\w@/.-]+@[\w.*^~-]*\d[\w.*^~-]*\b]],                            -- 包名@版本 lodash@4.17.21
  [[\b(?:feature|fix|bugfix|hotfix|release|chore|refactor|docs)/[\w.-]+]], -- 分支名
  [[\b\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?\b]],                         -- IPv4(:端口)
  [[\b[0-9a-f]{7,40}\b]],                                                -- git hash / hex id
  [[(?:~|\.{1,2})?/?[\w.-]+(?:/[\w.-]+)+]],                              -- 路径（含 ~/ ./）
}

config.quick_select_patterns = QS_PATTERNS
-- ═════════════════════════════════════════════════════════
-- DIY Quick Select（Ctrl+Shift+Space / F6）
-- 实测本 nightly 内置 QuickSelect 匹配器全灭（连纯字面量都不匹配，
-- QuickSelectArgs 显式传参也无效）→ 自建：扫回滚缓冲 → Lua pattern
-- 匹配 → InputSelector 列表 → 回车=复制+跳转+搜索高亮，完全绕开内置实现
-- ═════════════════════════════════════════════════════════
local function pat_escape(s)
  return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1'))
end

-- 细粒度模式：单独的「小物件」（优先级高，先扫）
local DIY_FINE = {
  'QSOK',                                              -- 诊断字面量（测完删）
  '%f[%w]git@[%w%.%-]+:[%w%./%~%-]+%.git%f[%A]',       -- ssh 仓库地址
}
table.insert(DIY_FINE, 'https://[^%s]+')
table.insert(DIY_FINE, 'http://[^%s]+')
for _, w in ipairs { 'github', 'gitlab', 'gitee', 'bitbucket' } do
  table.insert(DIY_FINE, '%f[%w]' .. w .. '%.com/[%w%./%-]+') -- 裸域名地址（排在完整 URL 之后）
end
table.insert(DIY_FINE, '%u[%u%d_]+=%S+')                    -- 环境变量 FOO=bar（分支名不再单列：路径模式已全覆盖 feature/x 等形式）
table.insert(DIY_FINE, '[%w@/.%-]+@[%w%.%*%^%~%-]*%d[%w%.%*%^%~%-]*') -- pkg@version / user@host
table.insert(DIY_FINE, '%d+%.%d+%.%d+%.%d+:%d+')            -- IPv4:端口
table.insert(DIY_FINE, '%d+%.%d+%.%d+%.%d+')                -- IPv4
local HEX_PAT = '%f[%x]%x+%f[%X]'
table.insert(DIY_FINE, HEX_PAT)                              -- hash（长度在代码里过滤）
table.insert(DIY_FINE, '%~?%.?%.?%/?[%w%.%-]+/[%w%.%-]+[%w%./%-]*') -- 路径 ~/ ./ ../

-- 粗粒度模式：命令整行（与 URL 等重叠时共存，不互相排斥）
local DIY_COARSE = {}
for _, w in ipairs {
  'git', 'gh', 'docker', 'podman', 'kubectl', 'helm', 'npm', 'npx', 'pnpm', 'yarn', 'bun',
  'node', 'deno', 'python3', 'python', 'pip3', 'pip', 'uv', 'pipx', 'cargo', 'go', 'make',
  'cmake', 'sudo', 'dnf', 'apt', 'apt-get', 'brew', 'pacman', 'systemctl', 'journalctl',
  'firewall-cmd', 'crontab', 'curl', 'wget', 'ssh', 'scp', 'rsync', 'sftp', 'tar', 'zip',
  'unzip', 'gpg', 'openssl', 'cd', 'cp', 'mv', 'rm', 'mkdir', 'touch', 'ln', 'chmod',
  'chown', 'chgrp', 'grep', 'sed', 'awk', 'find', 'xargs', 'sort', 'cat', 'head', 'tail',
  'echo', 'printf', 'export', 'source', 'alias', 'which', 'nvim', 'vim', 'tmux', 'flatpak',
  'snap', 'ip', 'ss', 'ping', 'dig', 'nslookup', 'nc', 'tr', 'cut', 'tee', 'diff', 'patch',
  'du', 'df', 'ps', 'kill',
} do
  table.insert(DIY_COARSE, '%f[%w]' .. pat_escape(w) .. '%f[%W]%s%f[%w].*') -- 命令词+空格+参数，整行
end

local function diy_trim(m)
  m = m:gsub('^%s+', ''):gsub('%s+$', '')
  m = m:gsub('[%,%;%.%:%!%?%)%]]+$', '')
  return m
end

local function diy_scan(text, max_items)
  max_items = max_items or 120
  local items, seen = {}, {}
  local lineno = -1 -- 行号（相对抓取区域顶部，0 起）
  -- 先过滤（trim/长度/去重）再占位：被拒的匹配不阻挡后续更好的匹配
  local function accept(s, e, line, pat, spans)
    local m = diy_trim(line:sub(s, e))
    if m == '' or seen[m] then return false end
    if pat == HEX_PAT and (#m < 7 or #m > 40) then return false end
    for _, sp in ipairs(spans) do
      if s <= sp[2] and sp[1] <= e then return false end
    end
    table.insert(spans, { s, e })
    seen[m] = true
    table.insert(items, { text = m, line = lineno })
    return true
  end
  local function scan_group(line, pats, ignore_overlap)
    local spans = {}
    for _, pat in ipairs(pats) do
      local init = 1
      while init <= #line do
        local s, e = line:find(pat, init)
        if not s then break end
        init = e + 1
        if ignore_overlap then
          -- 命令整行：不占位、不排斥，仅去重后收下
          local m = diy_trim(line:sub(s, e))
          if m ~= '' and not seen[m] then
            seen[m] = true
            table.insert(items, { text = m, line = lineno })
          end
        else
          accept(s, e, line, pat, spans)
        end
        if #items >= max_items then return end
      end
    end
  end
  for line in text:gmatch('[^\r\n]+') do
    lineno = lineno + 1
    scan_group(line, DIY_FINE, false)   -- 细粒度：重叠互斥，先到先得
    scan_group(line, DIY_COARSE, true)  -- 命令整行：无视重叠，直接整行收
    if #items >= max_items then break end
  end
  return items
end
package.loaded.diy_scan = diy_scan    -- 供外部测试（wezterm.GLOBAL 不能存函数）

wezterm.on('diy-quick-select', function(window, pane)
  -- 抓取整个回滚缓冲：行号与 ScrollToPrompt 的坐标对齐
  local ok_dims, dims = pcall(pane.get_dimensions, pane)
  local rows = (ok_dims and dims and dims.scrollback_rows) or 10000
  local items = diy_scan(pane:get_lines_as_text(rows), 120)
  local line_of = {}
  local choices = {}
  for _, it in ipairs(items) do
    line_of[it.text] = it.line
    local preview = (#it.text > 96) and (it.text:sub(1, 93) .. '…') or it.text
    table.insert(choices, { id = it.text, label = string.format('L%-5d %s', it.line, preview) })
  end
  if #choices == 0 then
    choices = { { id = '', label = '(no match: DIY matcher alive, nothing found)' } }
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'DIY Quick Select',
    description = 'Enter = copy + jump + highlight · Esc = cancel',
    fuzzy = true,
    fuzzy_description = 'Filter: ',
    choices = choices,
    action = wezterm.action_callback(function(win, p, id)
      if not id or id == '' then return end
      pcall(function() win:perform_action(wezterm.action.CopyTo { item = id }, p) end)
      local line = line_of[id]
      if line then
        pcall(function() win:perform_action(wezterm.action.ScrollToPrompt(line), p) end)
      end
      -- 高亮：以选中原文激活搜索（大小写不敏感字面量），Esc 可退出搜索
      pcall(function() win:perform_action(wezterm.action.Search { CaseInSensitiveString = id }, p) end)
    end),
  }, pane)
end)

-- 绑定：主键 Ctrl+Shift+Space + 备用键 F6（防输入法/桌面环境按键拦截）
-- 关键：默认 QuickSelect 绑在 phys:Space（物理键）上，且此版本 config.keys 与默认表
-- 是合并语义，默认物理键绑定会抢命中 → 必须把 phys:Space 也显式绑过来才能盖掉它
table.insert(config.keys, 1, { key = 'F6', mods = 'NONE', action = wezterm.action.EmitEvent 'diy-quick-select' })
table.insert(config.keys, 1, { key = 'phys:Space', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent 'diy-quick-select' })
table.insert(config.keys, 1, { key = ' ', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent 'diy-quick-select' })

return config
