-- quickselect.lua — QuickSelect：目標導向模式表 + DIY 掃描選擇器
-- 从主配置拆出（v4 模块化）。主键 Ctrl+Shift+Space / 备用 F6。
-- 内置匹配器在本 nightly 全灭 → 自建：扫回滚缓冲 → InputSelector →
-- 回车=复制+跳转+搜索高亮，完全绕开内置实现。
--
-- 接口：
--   M.patterns → 模式表（主配置喂给 config.quick_select_patterns）
--   M.keys     → 键位绑定（主配置 insert 到 keys 首位——必须插队，
--                否则默认 phys:Space 绑定会抢命中，这是本 nightly 实测坑）
-- 内部：'diy-quick-select' 事件（本文件内注册）+ package.loaded.diy_scan 供外部测试
local wezterm = require 'wezterm'
local M = {}

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

-- (config.quick_select_patterns 由主配置从 M.patterns 接入，模块内不碰 config)
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

-- 键位（见 M.keys）：主键 Ctrl+Shift+Space + 备用键 F6（防输入法/桌面环境按键拦截）
-- 关键：默认 QuickSelect 绑在 phys:Space（物理键）上，且此版本 config.keys 与默认表
-- 是合并语义，默认物理键绑定会抢命中 → 必须把 phys:Space 也显式绑过来才能盖掉它

M.patterns = QS_PATTERNS
M.keys = {
  { key = 'F6', mods = 'NONE', action = wezterm.action.EmitEvent 'diy-quick-select' },
  { key = 'phys:Space', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent 'diy-quick-select' },
  { key = ' ', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent 'diy-quick-select' },
}

return M
