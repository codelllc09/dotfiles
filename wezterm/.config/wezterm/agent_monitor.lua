-- ═══════════════════════════════════════════════════════════════
-- agent_monitor.lua — coding agent 状态监视（纯 WezTerm Lua，零外部进程）
-- （前身为 herd.lua，2026-09 v4 模块化改名；思路代号「牧群」= 看管一群 agent。
--   运行时对外路径保留 herd- 前缀：~/.local/state/wezterm-herd/、
--   /tmp/herd-debug.log——改名会与历史状态/诊断习惯断裂，故不动）
-- ───────────────────────────────────────────────────────────────
-- 思路移植自 herdr.dev 的 screen-manifest 路线（Apache-2.0）：
--   识别前景进程 → 刮取 pane 底部 → 规则表判 working/idle/blocked
--   → tab 状态点+未读徽章 + JSONL 状态流水落盘
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
-- v4 拆分：佈局碼（layout_code/layout_glyph/LAYOUT_GLYPH）已拆至 layout.lua；
--          标题程序名（APPS 每秒缓存 + M.app_name）供 appicon.lua 取名
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

-- 运行期状态：[pane_id(number)] = {agent,state,since,rule,ctx,cost,cwd,tty,unread}
-- unread：QQ 式未读计数——不在视线内发生的 →blocked / working→idle 各记 1，
-- 聚焦该 pane 即清零（clear_unread / tab_badge）；徽章=你错过的事件，dot=持续状态
local STATE = {}

-- 标题程序名缓存：[pane_id(number)] = agent名 或 前景进程 basename
-- （scan 每秒对全量 pane 刷新；供 .wezterm.lua 的「TABn APPNAME」取名——
--   套壳启动（npm run claude）时也能出 claude 而非 node）
local APPS = {}

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
      '"%s":{"agent":%s,"state":%s,"since":%s,"rule":%s,"ctx":%s,"cost":%s,"cwd":%s,"tty":%s,"unread":%s}',
      tostring(pid), esc(r.agent), esc(r.state), num(r.since), esc(r.rule or ''),
      num(r.ctx), num(r.cost), esc(r.cwd or ''), esc(r.tty or ''), num(r.unread))
  end
  -- 注意：顶层 key 必须带引号（{"1":{…}}）才是合法 JSON——
  -- 历史上这里没引号，json_parse 一直静默失败，回温形同虚设；
  -- 未读数要跨 reload 存活后才暴露出来
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
        unread = tonumber(v.unread) or 0,
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
        '{"pane":%s,"agent":%s,"state":%s,"since":%s,"rule":%s,"ctx":%s,"cost":%s,"cwd":%s,"tty":%s,"unread":%s}',
        tostring(pid), esc(r.agent), esc(r.state), num(r.since), esc(r.rule or ''),
        num(r.ctx), num(r.cost), esc(r.cwd or ''), esc(r.tty or ''), num(r.unread))
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
      '{"ts":%s,"pane":%s,"agent":%s,"from":%s,"to":%s,"ctx":%s,"cost":%s,"cwd":%s,"unread":%s}\n',
      esc(os.date('%F %T')), tostring(rec.pane), esc(rec.agent), esc(rec.from),
      esc(rec.to), num(rec.ctx), num(rec.cost), esc(rec.cwd or ''), num(rec.unread)))
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

-- ── 未读清零（"已读"判定）──
-- 只有 OS 焦点窗口的活动 pane 才算"你在看"：切换 tab / 切分屏焦点都会
-- 经由 active_pane 反映出来。is_focused 若本 build 缺失（一次性 probe 落日志），
-- 保守退化为全窗口活动 pane 都清零（与通知抑制口径一致）。
local dirty = false -- 声明必须先于 clear_unread/update（后者赋值的是 upvalue）
local flip = false -- 強制重繪交替值（跨 scan 持久，同值會被 wezterm 當 no-op）
local focus_probe_done = false
local function clear_unread()
  pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      pcall(function()
        local gw = w:gui_window()
        local ok, isf = pcall(function() return gw:is_focused() end)
        if not focus_probe_done then
          focus_probe_done = true
          dbg('is_focused probe: ' .. (ok and tostring(isf) or ('ERR ' .. tostring(isf))))
        end
        if ok and isf == false then return end -- 明确失焦才跳过
        local pid = gw:active_pane():pane_id()
        local r = STATE[pid]
        if r and (r.unread or 0) > 0 then
          r.unread = 0
          dirty = true
        end
      end)
    end
  end)
end

-- ── 核心：单 pane 状态更新 ──

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
  -- 未读计数：与通知同款抑制口径（focused_panes＝全窗口活动 pane 都算在看）。
  -- 只有你没看到的 →blocked / working→idle 才算一条"未读消息"；封顶 99，显示层 >9 记 9+
  local unread = prev and prev.unread or 0
  if not focused[pid] then
    if state == 'blocked' or (state == 'idle' and from == 'working') then
      unread = math.min(unread + 1, 99)
    end
  end
  local tty = ''
  pcall(function() tty = pane:get_tty_name() or '' end)
  STATE[pid] = {
    agent = agent, state = state, since = os.time(), rule = rule,
    ctx = ctx, cost = cost,
    cwd = info.cwd or (prev and prev.cwd) or '',
    tty = tty,
    unread = unread,
  }
  dirty = true
  append_transition({
    pane = pid, agent = agent, from = from, to = state,
    ctx = ctx, cost = cost, cwd = STATE[pid].cwd, unread = unread,
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
  clear_unread() -- "已读"：焦点窗口的活动 pane 清未读（在计数前先做，语义无冲突）
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
                -- 标题程序名：agent 名优先（含 children 套壳识别），否则进程 basename
                local exe = basename(info.executable or '')
                if exe == '' then exe = tostring(info.name or '') end
                APPS[pid] = agent or exe
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
  for pid in pairs(APPS) do
    if not seen[pid] then APPS[pid] = nil end
  end
  if dirty then
    save_global()
    write_current()
    -- 強制 tab bar 重繪：format-tab-title 是快取的，狀態變了它不會自己重跑；
    -- 且 set_right_status 同值會被當 no-op（教訓：'固定空格'版本實測無效，
    -- 徽章要等 ~30s 的自然重繪）。手段（並用，皆不可見）：
    --   ① MuxTab:set_title 交替空格——tab_title 是 formatter 的直接輸入，
    --      必然觸發重評（顯示層用 pane title，不受污染）
    --   ② set_right_status 交替空格——雙保險
    flip = not flip
    pcall(function()
      for _, w in ipairs(wezterm.mux.all_windows()) do
        pcall(function() w:gui_window():set_right_status(flip and ' ' or '  ') end)
        local ok_tabs, tabs = pcall(function() return w:tabs() end)
        if ok_tabs and type(tabs) == 'table' then
          for _, t in ipairs(tabs) do
            pcall(function() t:set_title(flip and ' ' or '  ') end)
          end
        end
      end
    end)
    dirty = false
  end
  return n_seen, n_agents
end

-- ── 轮询链（存活权杖制 + 心跳看门狗）──
-- 教训一（原有）：reload 时多上下文各跑 setup，共用计数器被侧上下文乱加 → 权杖制。
-- 教训二（实锤 03:57-03:58）：reload/override 会取消旧 universe 的 pending
--   call_after——旧链无声蒸发（连 chain die 都不留）；且旧版 arm() 先置
--   armed=true 再写 GLOBAL，一旦写抛错就被上層 pcall 吞掉，实例永久卡在
--   「假活」，渲染路径不再重试。症状：灯冻结在最后一次落盘的状态（绿尸灯）、
--   transition 断流、徽章不出。
-- 对策：① arm 事务化：pcall 写 GLOBAL 成功后才置 armed；失败留日志下輪重试
--       ② 心跳看门狗：tick 每輪打 last_beat；渲染/事件路徑調 arm() 時發現
--          armed 且心跳停 >5s → 換新令牌重啟鏈（僵屍鏈下一 tick 令牌不符自滅）
--   侧上下文 handler 永不被调用 → 永不 arm → 不会误杀（原权杖语义不变）。
local my_token, armed, last_beat = nil, false, 0

local function tick(token)
  local ok_alive, alive = pcall(function() return wezterm.GLOBAL.herd_alive end)
  if not ok_alive or alive ~= token then
    dbg('chain die ' .. tostring(token))
    return
  end
  last_beat = os.time()
  if next(STATE) == nil then load_global() end      -- 重评估后回温
  local ok = pcall(scan)
  if not ok then dbg('scan ERR') end
  wezterm.time.call_after(TICK, function() tick(token) end)
end

local function arm()
  if not my_token then return end
  if armed and (os.time() - last_beat) <= 5 then return end -- 健康链：免打扰
  local rearm = armed
  if rearm then -- 看门狗复活：换令牌，僵尸链下一 tick 自灭
    my_token = tostring(os.time()) .. ':' .. tostring(math.random())
  end
  local ok, err = pcall(function() wezterm.GLOBAL.herd_alive = my_token end)
  if not ok then
    dbg('arm GLOBAL ERR: ' .. tostring(err)) -- armed 未置位：下輪渲染路徑重試
    return
  end
  dbg((rearm and 'watchdog rearm ' or 'armed ') .. my_token)
  armed = true
  last_beat = os.time()
  tick(my_token) -- 立即扫一輪；后续自续链
end

-- ═══ 对外接口 ═══

-- tab 状态点：非 agent pane 返回空表（调用方 ipairs 直接吃掉）
-- 同时兼作启动器：config 重载必触发 tab 重绘 → dot_for → arm
function M.dot_for(pane_id)
  arm()
  local r = STATE[tonumber(pane_id)]
  if not r then return {} end
  return {
    { Foreground = { Color = STATE_COLOR[r.state] or '#6c7086' } },
    { Text = '● ' },
  }
end

-- ═══ 方案A（tab 級聚合）：指示燈與未讀徽章各自獨立 ═══
-- 指示燈 tab_dot  ：全 tab 最壞狀態（blocked > working > idle）——「有沒有事要我」
-- 未讀徽章 tab_unread：QQ 式計數（上角標）——你錯過的 →blocked / 跑完了 事件數；
--       聚焦該 pane 即清零。>9 顯示 ⁹⁺。燈=持續狀態、徽章=錯過的事件，互不耦合。
-- 教訓（probe 實錦）：本 nightly 的 tab/pane 物件是 userdata（type(tab)=userdata），
-- 不能用 type()==table 把關——以 pcall 包裹存取，失敗回空靜默降級。
local PRECEDENCE = { blocked = 3, working = 2, idle = 1 }

local function tab_records(tab)
  local recs = {}
  local ok = pcall(function()
    local panes = tab.panes
    if type(panes) ~= 'table' then error('panes not table: ' .. type(panes)) end
    for _, p in ipairs(panes) do
      local r = STATE[p.pane_id]
      if r then recs[#recs + 1] = r end
    end
  end)
  if not ok then return nil end
  return recs
end

-- ── 渲染遙測：量「偵測→上屏」延遲 ──
-- format-tab-title 重跑時，若本 tab 的(燈/未讀)有變則留痕；
-- 與 transitions.jsonl 的 ts 對照即可量出渲染延遲（優化後應 ≤1-2s）
local last_render = {}
local function log_render(tab, key, val)
  pcall(function()
    local k = tostring(tab.tab_id) .. ':' .. key
    if last_render[k] ~= val then
      last_render[k] = val
      dbg(('render %s = %s'):format(k, tostring(val)))
    end
  end)
end

-- 指示燈（獨立）：非 agent tab 返回空表（調用方 ipairs 直接吃掉）
function M.tab_dot(tab)
  arm()
  local recs = tab_records(tab)
  if not recs then return {} end
  local best = 0
  for _, r in ipairs(recs) do
    local pr = PRECEDENCE[r.state] or 0
    if pr > best then best = pr end
  end
  if best == 0 then return {} end
  local state = best == 3 and 'blocked' or (best == 2 and 'working' or 'idle')
  log_render(tab, 'dot', state)
  return {
    { Foreground = { Color = STATE_COLOR[state] or '#6c7086' } },
    { Text = '● ' },
  }
end

-- 未讀徽章（獨立）：QQ 式紅底反白藥丸；無未讀返回空表；>9 記 9+
-- 細節：① 底色復位按 tab.is_active 分流——作用中 tab 標題坐在 #313244
-- 焦點藥丸上，非作用中坐在 tab 欄底 #1e1e2e，復位錯色會截斷焦點藥丸/漏染標題
--       ② Intensity=Bold 會殘留到後續文字，用後必須復位 Normal
function M.tab_unread(tab)
  arm()
  local recs = tab_records(tab)
  if not recs then return {} end
  local n = 0
  for _, r in ipairs(recs) do n = n + (r.unread or 0) end
  log_render(tab, 'unread', n)
  if n == 0 then return {} end
  local base = '#1e1e2e'
  pcall(function() if tab.is_active then base = '#313244' end end)
  return {
    { Background = { Color = '#f38ba8' } },    -- 紅底（Catppuccin red）
    { Foreground = { Color = '#1e1e2e' } },    -- 深色數字（反白）
    { Attribute = { Intensity = 'Bold' } },
    { Text = ' ' .. (n > 9 and '9+' or tostring(n)) .. ' ' },
    { Background = { Color = base } },          -- 復位（防紅底漏染後續）
    { Attribute = { Intensity = 'Normal' } },   -- 復位（防 Bold 殘留）
    { Text = ' ' },                              -- 與標題隔開
  }
end

-- 標題程序名（.wezterm.lua 的「TABn APPNAME」取名，三層兜底）：
--   ① STATE agent（JSON 跨 reload 回温，套壳启动已识别）② APPS 每秒缓存
--   ③ TabInformation.active_pane.foreground_process_name 静态快照
-- 返回 nil = 三层都拿不到（调用方自回退 '·'）
function M.app_name(tab)
  arm()
  local pid
  pcall(function() pid = tonumber(tab.active_pane.pane_id) end)
  if pid then
    local r = STATE[pid]
    if r and r.agent then return r.agent end
    local app = APPS[pid]
    if app and app ~= '' then return app end
  end
  local name
  pcall(function()
    local f = tab.active_pane.foreground_process_name
    if type(f) == 'string' and f ~= '' then name = basename(f) end
  end)
  return name
end

function M.state()
  return STATE
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
