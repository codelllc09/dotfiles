-- ═══════════════════════════════════════════════════════════════
-- herd.lua — coding agent 状态监视（纯 WezTerm Lua，零外部进程）
-- ───────────────────────────────────────────────────────────────
-- 思路移植自 herdr.dev 的 screen-manifest 路线（Apache-2.0）：
--   识别前景进程 → 刮取 pane 底部 → 规则表判 working/idle/blocked
--   → tab 状态点 + 右状态栏 + JSONL 状态流水落盘
--
-- 本 nightly 实测出的三个坑（代码里皆有对应处理）：
--   1. wezterm.GLOBAL 不是纯 Lua table：跨 eval 存取 table 会拿到
--      opaque Value，pairs/next 直接抛错 → GLOBAL 只放纯量
--      （状态跨 eval 用 JSON 字串运输：herd_state_json）
--   2. set_config_overrides（rime 游标色）会整份重评估 config，
--      且每次 reload 有多个 runtime 上下文各跑一次 setup
--      （GUI/connui/…，侧上下文的事件 handler 永不被调用）
--      → 存活权杖制：arm 时才写 herd_alive；被采纳链自然存活
--   3. 无事件循环上下文里排的 call_after 永不触发
--      → 由 GUI 高频事件 + dot_for 渲染路径懒启动
--
-- 输出：~/.local/state/wezterm-herd/{current.json,transitions.jsonl}
-- 诊断：/tmp/herd-debug.log（低频：setup/armed/chain die/mkdir）
--
-- Windows 适配暂时搁置：本模块假设 Linux（notify-send、~/.local/state、
-- /dev/pts 等），在 Windows 上经 pcall 静默降级——tab 灯可能部分工作，
-- 通知/落盘无。真要在 Windows 部署时再做：通知改 powershell toast 或
-- wezterm 内建、状态目录改 wezterm.home_dir、检测层基本可直接复用。
-- ═══════════════════════════════════════════════════════════════
local wezterm = require 'wezterm'
local M = {}

-- 运行期状态：[pane_id(number)] = {agent,state,since,rule,ctx,cost,cwd,tty}
local STATE = {}

local function dbg(msg)
  local f = io.open('/tmp/herd-debug.log', 'a')
  if f then f:write(os.date('%H:%M:%S '), tostring(msg), '\n'); f:close() end
end

-- ── 可调参数 ──
local TICK            = 1.0   -- 轮询间隔（秒）
local SCAN_LINES      = 40    -- 刮屏窗口行数
local BOTTOM_NONEMPTY = 15    -- 规则只看底部 N 个非空行（herdr 同款语义）
local STATE_DIR       = (os.getenv('HOME') or '~') .. '/.local/state/wezterm-herd'

-- ── agent 识别表：token 在 进程name / executable / argv前3项 里按整词匹配 ──
-- 新增 agent：这里加一行 + 下方 MANIFESTS 加规则即可
local AGENTS = {
  pi     = { token = { 'pi' } },
  claude = { token = { 'claude', 'claude-code' } },
  codex  = { token = { 'codex' } },
}

-- ── manifest：按 priority 降序，首条命中即定状态；全不中 → 保守回退 idle ──
--   any_contains : 任一子串命中即真
--   not_contains : 任一子串命中则整条否决
-- 想加强可从 herdr 仓库 distribution/agent-detection/<agent>.toml 翻译
local MANIFESTS = {
  -- pi 的 blocked 特征提炼自 pi 源码（dist/modes/interactive/components/）：
  -- pi 本体无任何授权/确认 UI（工具直接执行）；唯一的阻塞 UI 来自
  -- plugin/extension 的 ctx.ui.confirm() 与 trust 对话框。
  -- 实测验证：/model 等内置选择器用各自 keyHint（不含 ↑↓ navigate），不会误命中。
  pi = {
    -- 依据 pi 源码（dist/modes/interactive/components/）：
    -- trust-selector.js: 标题整行 theme.bold("Project trust")
    -- extension-selector.js / trust-selector.js: 提示行以 rawKeyHint("↑↓","navigate") 开头
    -- （整行/行首锚定，防对话文本冒充——教训：本 session 引用过这些字符串就误判过）
    { id = 'blocked_trust', priority = 210, state = 'blocked',
      line_exact = { 'Project trust' } },
    { id = 'blocked_selector', priority = 200, state = 'blocked',
      line_prefix = { '↑↓ navigate' } },
    { id = 'working_literal', priority = 100, state = 'working',
      any_contains = { 'Working...' } },
  },
  claude = {
    { id = 'blocked_form', priority = 1200, state = 'blocked',
      any_contains = { 'Do you want to proceed?', 'Would you like to proceed?' },
      not_contains = { 'esc to interrupt' } },
    { id = 'working_interrupt', priority = 1100, state = 'working',
      any_contains = { 'esc to interrupt' } },
  },
  codex = {
    { id = 'working_interrupt', priority = 1100, state = 'working',
      any_contains = { 'esc to interrupt' } },
  },
}
for _, rules in pairs(MANIFESTS) do
  table.sort(rules, function(a, b) return a.priority > b.priority end)
end

local STATE_COLOR = {
  working = '#a6e3a1',  -- 绿
  idle    = '#585b70',  -- 暗（Catppuccin surface2）
  blocked = '#f9e2af',  -- 黄：等你决策
}

-- ── 小工具 ──
local function basename(p)
  return (tostring(p):gsub('\\', '/'):match('([^/]+)$') or '')
end

local function word_has(s, tok)
  return type(s) == 'string' and s:find('%f[%w]' .. tok .. '%f[%W]') ~= nil
end

-- 候选词：进程自身的 name / executable / argv 前 3 项
local function candidates_of(info)
  local cands = {}
  if type(info) ~= 'table' then return cands end
  if type(info.name) == 'string' and info.name ~= '' then cands[#cands + 1] = info.name end
  local exe = basename(info.executable or '')
  if exe ~= '' then cands[#cands + 1] = exe end
  if type(info.argv) == 'table' then
    for i = 1, math.min(#info.argv, 3) do cands[#cands + 1] = basename(info.argv[i]) end
  end
  return cands
end

local function match_tokens(cands)
  for agent, def in pairs(AGENTS) do
    for _, tok in ipairs(def.token) do
      for _, c in ipairs(cands) do
        if word_has(c, tok) then return agent end
      end
    end
  end
  return nil
end

-- 识别：自身 → 子进程族谱（一層）
-- 子进程扫描抄自 agent-deck detector.lua 的思路：套壳启动
-- （npm run claude / fence -- claude / 包装脚本）时前景进程认不出，
-- 翻 children 兜底。返回 agent, 来源（self/children，供诊断日志）
local function identify(info)
  local hit = match_tokens(candidates_of(info))
  if hit then return hit, 'self' end
  if type(info.children) == 'table' then
    for _, ch in pairs(info.children) do
      hit = match_tokens(candidates_of(ch))
      if hit then return hit, 'children' end
    end
  end
  return nil, 'none'
end

-- 取 pane 底部窗口：返回底部 N 个非空行组成的数组
local function bottom_lines(pane)
  local ok, text = pcall(function() return pane:get_lines_as_text(SCAN_LINES) end)
  if not ok or type(text) ~= 'string' then return nil end
  local all = {}
  for line in text:gmatch('[^\r\n]+') do all[#all + 1] = line end
  while #all > 0 and not all[#all]:find('%S') do all[#all] = nil end
  local n = #all
  local lo = math.max(1, n - BOTTOM_NONEMPTY + 1)
  local lines = {}
  for i = lo, n do lines[#lines + 1] = all[i] end
  return lines
end

-- 规则引擎：保守（无命中 → idle）
-- 匹配方式（可叠加，任一命中即真）：
--   line_exact  : 某行去首尾空白后完全相等（pi 标题行等，最抗对话文本冒充）
--   line_prefix : 某行以此前缀开头（selector 提示行）
--   any_contains: 规则区任意子串（最宽松，易被对话文本冒充，慎用）
--   not_contains: 任一命中则否决本条
local function line_trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function classify(agent, lines)
  local rules = MANIFESTS[agent]
  if not rules or type(lines) ~= 'table' or #lines == 0 then
    return 'idle', 'default_no_rule'
  end
  local region = table.concat(lines, '\n')
  for _, r in ipairs(rules) do
    local hit = false
    if not hit and r.line_exact then
      for _, p in ipairs(r.line_exact) do
        for _, ln in ipairs(lines) do
          if line_trim(ln) == p then hit = true break end
        end
        if hit then break end
      end
    end
    if not hit and r.line_prefix then
      for _, p in ipairs(r.line_prefix) do
        for _, ln in ipairs(lines) do
          if ln:sub(1, #p) == p then hit = true break end
        end
        if hit then break end
      end
    end
    if not hit and r.any_contains then
      for _, s in ipairs(r.any_contains) do
        if region:find(s, 1, true) then hit = true break end
      end
    end
    if hit and r.not_contains then
      for _, s in ipairs(r.not_contains) do
        if region:find(s, 1, true) then hit = false break end
      end
    end
    if hit then return r.state, r.id end
  end
  return 'idle', 'default_known_agent_idle_fallback'
end

-- pi 状态栏遥测：↑366k ↓182k R20M CH99.9% $6.402 27.1%/1.0M (auto)
local function parse_telemetry(foot)
  if not foot then return nil, nil end
  local ctx = foot:match('(%d+%.?%d*)%%/%S+')
  local cost = foot:match('%$(%d+%.%d+)')
  return tonumber(ctx), tonumber(cost)
end

-- ── 跨 eval 状态运输：GLOBAL 只放纯量（JSON 字串）──
local function esc(s)
  return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
    :gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end

local function num(v) return v == nil and 'null' or tostring(v) end

local function save_global()
  local parts = {}
  for pid, r in pairs(STATE) do
    parts[#parts + 1] = string.format(
      '%s:{"agent":%s,"state":%s,"since":%s,"rule":%s,"ctx":%s,"cost":%s,"cwd":%s,"tty":%s}',
      tostring(pid), esc(r.agent), esc(r.state), num(r.since), esc(r.rule or ''),
      num(r.ctx), num(r.cost), esc(r.cwd or ''), esc(r.tty or ''))
  end
  -- GLOBAL 赋值纯量字串，安全
  wezterm.GLOBAL.herd_state_json = '{' .. table.concat(parts, ',') .. '}'
end

local function load_global()
  local s = wezterm.GLOBAL.herd_state_json
  if type(s) ~= 'string' or s == '' or s == '{}' then return end
  local ok, t = pcall(wezterm.json_parse, s)
  if not ok or type(t) ~= 'table' then return end
  for k, v in pairs(t) do
    if type(v) == 'table' then
      STATE[tonumber(k) or k] = {
        agent = v.agent, state = v.state,
        since = tonumber(v.since) or 0, rule = v.rule,
        ctx = tonumber(v.ctx), cost = tonumber(v.cost),
        cwd = v.cwd, tty = v.tty,
      }
    end
  end
end

-- ── 落盘 ──
local dir_ensured = false
local function ensure_dir()
  if dir_ensured then return end
  -- 直接试写实际会用的 tmp 文件：能写 = 目录在；不能写 = mkdir 后再试一次
  local t = io.open(STATE_DIR .. '/.current.tmp', 'w')
  if t then
    t:close()
  else
    local ok, _, code = os.execute("mkdir -p '" .. STATE_DIR .. "'")
    dbg('mkdir ok=' .. tostring(ok) .. ' code=' .. tostring(code))
  end
  dir_ensured = true
end

local function write_current()
  pcall(function()
    ensure_dir()
    local recs = {}
    for pid, r in pairs(STATE) do
      recs[#recs + 1] = string.format(
        '{"pane":%s,"agent":%s,"state":%s,"since":%s,"rule":%s,"ctx":%s,"cost":%s,"cwd":%s,"tty":%s}',
        tostring(pid), esc(r.agent), esc(r.state), num(r.since), esc(r.rule or ''),
        num(r.ctx), num(r.cost), esc(r.cwd or ''), esc(r.tty or ''))
    end
    table.sort(recs)
    local tmp = STATE_DIR .. '/.current.tmp'
    local f = io.open(tmp, 'w')
    f:write('{"ts":', esc(os.date('%F %T')), ',"panes":[', table.concat(recs, ','), ']}')
    f:close()
    os.rename(tmp, STATE_DIR .. '/current.json')
  end)
end

local function append_transition(rec)
  pcall(function()
    ensure_dir()
    local f = io.open(STATE_DIR .. '/transitions.jsonl', 'a')
    f:write(string.format(
      '{"ts":%s,"pane":%s,"agent":%s,"from":%s,"to":%s,"ctx":%s,"cost":%s,"cwd":%s}\n',
      esc(os.date('%F %T')), tostring(rec.pane), esc(rec.agent), esc(rec.from),
      esc(rec.to), num(rec.ctx), num(rec.cost), esc(rec.cwd or '')))
    f:close()
  end)
end

-- ── 桌面通知（GNOME notify-send，后台发出不阻塞 UI）──
-- 仅两类事件弹：→ blocked（plugin 确认框等你）与 working→idle（跑完了）
-- 正在看的 pane 不弹（你已经在看了）
local function notify(title, msg, critical)
  pcall(os.execute, string.format(
    "notify-send -a wezterm-herd%s -i utilities-terminal '%s' '%s' >/dev/null 2>&1 &",
    critical and ' -u critical' or '',
    tostring(title):gsub("'", ''), tostring(msg):gsub("'", '')))
end

-- 收集各窗口当前聚焦的 pane（用于通知抑制）
local function focused_panes()
  local set = {}
  pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      pcall(function() set[w:gui_window():active_pane():pane_id()] = true end)
    end
  end)
  return set
end

-- ── 核心：单 pane 状态更新 ──
local dirty = false

local function update(pid, agent, info, pane, focused)
  local prev = STATE[pid]
  local lines = bottom_lines(pane)
  local foot
  if lines and #lines > 0 then
    foot = table.concat({ lines[math.max(1, #lines - 2)],
      lines[math.max(1, #lines - 1)], lines[#lines] }, '\n')
  end
  local state, rule = classify(agent, lines)
  local ctx, cost = parse_telemetry(foot)

  if prev and prev.state == state and prev.agent == agent then
    if ctx ~= prev.ctx or cost ~= prev.cost then prev.ctx, prev.cost = ctx, cost end
    return
  end

  local from = prev and prev.state or 'new'
  local tty = ''
  pcall(function() tty = pane:get_tty_name() or '' end)
  STATE[pid] = {
    agent = agent, state = state, since = os.time(), rule = rule,
    ctx = ctx, cost = cost,
    cwd = info.cwd or (prev and prev.cwd) or '',
    tty = tty,
  }
  dirty = true
  append_transition({
    pane = pid, agent = agent, from = from, to = state,
    ctx = ctx, cost = cost, cwd = STATE[pid].cwd,
  })

  -- 桌面通知：blocked 等你决策（critical）、跑完收工（normal）；聚焦中的 pane 不扰
  if not focused[pid] then
    if state == 'blocked' then
      notify(string.format('%s · pane %d', agent, pid), '在等你决定', true)
    elseif state == 'idle' and from == 'working' then
      notify(string.format('%s · pane %d', agent, pid), '运行完成')
    end
  end
end

local function clear(pid)
  local r = STATE[pid]
  if not r then return end
  STATE[pid] = nil
  dirty = true
  append_transition({ pane = pid, agent = r.agent, from = r.state, to = 'gone', cwd = r.cwd })
end

-- ── 每轮扫描 ── 返回 (扫到 pane 数, agent pane 数)
local function scan()
  local seen = {}
  local n_agents = 0
  local focused = focused_panes()
  for _, w in ipairs(wezterm.mux.all_windows()) do
    local ok_tabs, tabs = pcall(function() return w:tabs() end)
    if ok_tabs and type(tabs) == 'table' then
      for _, tab in ipairs(tabs) do
        local ok_panes, panes = pcall(function() return tab:panes() end)
        if ok_panes and type(panes) == 'table' then
          for _, pane in ipairs(panes) do
            pcall(function()
              local pid = pane:pane_id()
              seen[pid] = true
              local info = pane:get_foreground_process_info()
              if type(info) == 'table' then
                local agent, src = identify(info)
                if agent then
                  n_agents = n_agents + 1
                  if src == 'children' then
                    dbg(('identify via children: pane %d = %s'):format(pid, agent))
                  end
                  update(pid, agent, info, pane, focused)
                else
                  clear(pid) -- 前景进程不是已知 agent（退回 shell 等）
                end
              end
            end)
          end
        end
      end
    end
  end
  local n_seen = 0
  for _ in pairs(seen) do n_seen = n_seen + 1 end
  for pid in pairs(STATE) do
    if not seen[pid] then clear(pid) end
  end
  if dirty then
    save_global()
    write_current()
    dirty = false
  end
  return n_seen, n_agents
end

-- ── 轮询链（存活权杖制）──
-- 教训：每次 reload 有多个 runtime 上下文各跑一次 setup（GUI/connui/…），
-- 共用计数器会被侧上下文乱加 → 被采纳链被误杀。
-- 改为：arm 时才写入权杖；侧上下文的 handler 永不被调用 → 永不 arm → 永不误杀。
-- 新链 arm 时接管权杖，旧链在下一 tick 自灭。
local my_token, armed = nil, false

local function tick(token)
  if wezterm.GLOBAL.herd_alive ~= token then
    dbg('chain die ' .. tostring(token))
    return
  end
  if next(STATE) == nil then load_global() end      -- 重评估后回温
  local ok = pcall(scan)
  if not ok then dbg('scan ERR') end
  wezterm.time.call_after(TICK, function() tick(token) end)
end

local function arm()
  if armed or not my_token then return end
  armed = true
  wezterm.GLOBAL.herd_alive = my_token -- 接管：旧链下一 tick 自灭
  dbg('armed ' .. my_token)
  tick(my_token) -- 立即扫一轮；后续自续链
end

-- ═══ 对外接口 ═══

-- tab 状态点：非 agent pane 返回空表（调用方 ipairs 直接吃掉）
-- 同时兼作启动器：config 重载必触发 tab 重绘 → dot_for → arm
function M.dot_for(pane_id)
  if not armed then arm() end
  local r = STATE[tonumber(pane_id)]
  if not r then return {} end
  return {
    { Foreground = { Color = STATE_COLOR[r.state] or '#6c7086' } },
    { Text = '● ' },
  }
end

function M.state()
  return STATE
end

-- ═══ v2.2 佈局碼（TLC）：geometry → 唯一碼 ═══
-- 三法則：①優先級 V>H（僅影響文本：H 之子免括號，V 之內嵌 H 需括號）
--        ②同向鏈 n 元合併；全單葉且 n≥3 糖寫 nH/nV（n=2 保持 1H1，與原表 N=2 行一致）
--        ③典範化：每節點先取 H 方向全部乾淨切線，無則取 V——算法即典範化
-- 幾何 → 碼：x 區間的重疊連通分量 = 可被豎切線分離的組（觸邊不算重疊 = 乾淨切線）
-- 單位注記：left_col/top_row 與 width/height 若單位不一致（格 vs 像素），
-- 分組比較將失真——首輪 dbg dump 會暴露實際值，必要時再修。

local function strip_groups(panes, is_h)
  local keyed = {}
  for _, p in ipairs(panes) do
    local lo = is_h and p.left or p.top
    local hi = is_h and (p.left + p.width) or (p.top + p.height)
    keyed[#keyed + 1] = { lo = lo, hi = hi, p = p }
  end
  table.sort(keyed, function(a, b) return a.lo < b.lo end)
  local groups, cur, cur_hi = {}, nil, 0
  for _, e in ipairs(keyed) do
    if cur and e.lo < cur_hi then -- 區間重疊 → 同組
      cur[#cur + 1] = e.p
      if e.hi > cur_hi then cur_hi = e.hi end
    else
      cur = { e.p }
      cur_hi = e.hi
      groups[#groups + 1] = cur
    end
  end
  return groups
end

local function enc_layout(panes, axis) -- 返回 code, used_axis
  if #panes == 1 then return '1', nil end
  local groups = strip_groups(panes, axis == 'H')
  if #groups == 1 then
    axis = (axis == 'H') and 'V' or 'H'
    groups = strip_groups(panes, axis == 'H')
    if #groups == 1 then
      return tostring(#panes) .. '?', axis -- 非 guillotine 兜底（wezterm 理論上不會產生）
    end
  end
  local child_axis = (axis == 'H') and 'V' or 'H'
  local parts, all_single = {}, true
  for i, g in ipairs(groups) do
    local s, child_used = enc_layout(g, child_axis)
    if axis == 'V' and child_used == 'H' then
      s = '(' .. s .. ')'
    end
    if s ~= '1' then all_single = false end
    parts[i] = s
  end
  if all_single and #groups >= 3 then
    return tostring(#groups) .. axis, axis
  end
  return table.concat(parts, axis), axis
end

local layout_dumped = {}
local layout_probe = false
function M.layout_code(tab, panes3)
  -- 一次性探针：逐项体检 tab.panes 与第三参数 panes 的可访问性
  if not layout_probe then
    layout_probe = true
    local function try(label, f)
      local ok, v = pcall(f)
      dbg('probe ' .. label .. ': ' .. (ok and tostring(v) or ('ERR ' .. tostring(v))))
    end
    local tp = tab and tab.panes
    try('type(tab)', function() return type(tab) end)
    try('type(tab.panes)', function() return type(tp) end)
    try('#tab.panes', function() return #tp end)
    try('tp[1] type', function() return type(tp[1]) end)
    try('tp[1].pane_id', function() return tostring(tp[1].pane_id) end)
    try('tp[1].left_col', function() return tostring(tp[1].left_col) end)
    try('tp[1].width', function() return tostring(tp[1].width) end)
    try('ipairs(tp) count', function() local n = 0 for _ in ipairs(tp) do n = n + 1 end return n end)
    try('type(p3)', function() return type(panes3) end)
    if type(panes3) == 'table' or type(panes3) == 'userdata' then
      try('#p3', function() return #panes3 end)
      try('p3[1].pane_id', function() return tostring(panes3[1].pane_id) end)
      try('p3[1].left_col', function() return tostring(panes3[1].left_col) end)
      try('p3[1].width', function() return tostring(panes3[1].width) end)
      try('ipairs(p3) count', function() local n = 0 for _ in ipairs(panes3) do n = n + 1 end return n end)
    end
  end
  local panes = tab and tab.panes
  if type(panes) ~= 'table' or #panes == 0 then
    dbg('layout guard 拦截: type=' .. type(panes))
    return ''
  end
  local ok, code = pcall(enc_layout, panes, 'H')
  if not ok then
    dbg('layout ENC ERR: ' .. tostring(code))
    return ''
  end
  -- 驗證協議：每 (tab, 窗格数) 组合首次渲染时落一份幾何+碼的證據
  local key = tostring(tab.tab_id) .. '#' .. #panes
  if not layout_dumped[key] then
    layout_dumped[key] = true
    local bits = {}
    for _, p in ipairs(panes) do
      bits[#bits + 1] = string.format('%d:[%d,%d %dx%d]',
        p.pane_id or -1, p.left or -1, p.top or -1, p.width or -1, p.height or -1)
    end
    dbg('layout tab' .. key .. ' {' .. table.concat(bits, ' ') .. '} => ' .. code)
  end
  return code
end

function M.setup()
  load_global()
  my_token = tostring(os.time()) .. ':' .. tostring(math.random())
  dbg('setup ' .. my_token)
  -- 历史遗留清理：右状态栏曾被本模块写入，内容会跨 reload 驻留。
  -- 经验：空串疑似被当 no-op，用单空格强制覆盖；每 eval 一次即可。
  local rs_cleared = false
  wezterm.on('update-right-status', function(window, pane)
    if not rs_cleared then
      rs_cleared = true
      local ok, err = pcall(function() window:set_right_status(' ') end)
      dbg(ok and 'rs cleared' or ('rs clear ERR: ' .. tostring(err)))
    end
    arm()
  end)
  wezterm.on('window-focus-changed', function() arm() end)
  wezterm.time.call_after(0.3, arm)
end

return M
