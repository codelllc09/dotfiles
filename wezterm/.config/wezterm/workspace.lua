-- workspace.lua — 工作区：右栏 Workspace n/m: name + Ctrl+Shift+O yazi风TUI抽屉
-- ─────────────────────────────────────────────────────────────
-- 规格：workspace.md（2026-09 推倒重来版）。本模块独立自包含，与其他模块零牵连。
--
-- 接口：
--   M.keys → Ctrl+Shift+O 拉起 ws-picker.lua 抽屉（top-level 底部分割，约 42% 高）
--   M.key_tables → {}（占位，主配置统一合并）
-- 显示（update-right-status，本文件注册）：
--   常态：`Workspace n/m: x`；flash 提示（删除反馈等）
-- 抽屉（ws-picker.lua，LuaJIT 自绘TUI，清单经 argv 传入零子进程）：
--   字符过滤（完整行编辑：←→/Home/End/Ctrl+A·E·B·F，Backspace/Del 删字符）
--   · Tab 补全 · ↑↓/Ctrl+P·N 移动 · Enter 跳转（无匹配=新建并跳转）
--   · Esc 退出(2026-09-09 拆除刪除流:要刪工作區進去手動關 tab)
--
-- 结果消费（零状态设计——2026-09 悬案调查的最终形态）：
--   TUI 把结果写进 /tmp/ws-pick-<window_id>.result（路径按窗口 id 确定性生成，
--   配置侧【永不写入】该路径→无 io 写影子），然后 OSC 推标题（rime 同款机制，
--   必然唤醒配置侧）+ 退出（pane 关闭→布局变化同样唤醒）。
--   配置侧每次 update-right-status 直查该文件：有结果→消费。不定时器、
--   不依赖 GLOBAL——重载（rime 切 IME 每次全量重求值）杀不死任何东西。
--
-- ═══ 2026-09 悬案调查结论（全部实验证实）═══
-- ① perform_action(overlay{action=action_callback}) 嵌套=死路：运行时注册的回调
--    死于下一次配置重求值——本模块一律求值期注册/仅 perform 内建 action
-- ② 求值期注册的回调重载免疫（is-test2 F5 于 8Hz 风暴中幸存）
-- ③ set_config_overrides → 一次全量重求值；rime 每切一次 IME 即重载一次；
--    重载杀光 pending 定时器并重置 Lua 状态 → 消费逻辑必须事件驱动+零状态
-- ④ wezterm.GLOBAL 写入在重载后丢失（vanish 日志实证）→ 本模块不用 GLOBAL 存状态
-- ⑤ /tmp 下的配置文件会被过度监视（勿用）；SplitPane/pane:split 未知字段静默忽略
-- ⑥ 删除工作区无 mux 原语：枚举 pane → os.execute 后台异步 cli kill-pane
--    （同步 cli 死锁 GUI）——已於 2026-09-09 整體拆除(守則⑨:禁異步 kill-pane)
-- ⑦ 配置 Lua 对自己写过的 /tmp 路径存在读影子（write-shadow）——配置永不写
--    结果文件，TUI（真实进程）写真实文件，配置直读真实内容
-- 诊断：/tmp/ws-debug.log
local wezterm = require 'wezterm'
local M = {}

local DBG_PATH = '/tmp/ws-debug.log'
local PICKER_SCRIPT = wezterm.config_dir .. '/ws-picker.lua'
local PICKER_LUA = 'luajit' -- 系统已有 luajit，启动 ~3ms

local function dbg(msg)
  local f = io.open(DBG_PATH, 'a')
  if f then f:write(os.date('%H:%M:%S '), tostring(msg), '\n'); f:close() end
end

-- ═══ 纯逻辑 ═══
local function ordered_names()
  local all, names = {}, {}
  pcall(function()
    for _, n in ipairs(wezterm.mux.get_workspace_names()) do all[#all + 1] = n end
  end)
  local has_default = false
  for _, n in ipairs(all) do
    if n == 'default' then has_default = true else names[#names + 1] = n end
  end
  table.sort(names)
  if has_default then table.insert(names, 1, 'default') end
  return names
end

-- ═══ 渲染 ═══
local C = { dim = '#585b70', text = '#cdd6f4', accent = '#b4befe', red = '#f38ba8' }
-- flash 消息（零定時器版，2026-09-09）：過期判定交給 render() 的自然節拍
-- （urs/focus 必發），不再有可被重載殺死的 pending call_after——舊版 2.5s
-- 清除定時器一旦撞上 IME 切換（守則④重求值）就被殺，紅字永駐右欄。
local flash_msg, flash_until = nil, 0

local function flash(msg)
  flash_msg = msg
  flash_until = os.time() + 3
end

local function current_workspace(window)
  return select(2, pcall(function() return window:active_workspace() end))
end

local function render(window)
  if flash_msg and os.time() > flash_until then flash_msg = nil end -- 零定時器：過期自清
  local ok, err = pcall(function()
    local names = ordered_names()
    local cur = current_workspace(window) or 'default'
    local idx = '?'
    for i, n in ipairs(names) do
      if n == cur then idx = i break end
    end
    local els = {
      { Foreground = { Color = C.dim } }, { Text = 'WS ' },
      { Foreground = { Color = C.text } }, { Text = tostring(idx) .. '/' .. tostring(#names) },
      { Foreground = { Color = C.dim } }, { Text = ': ' },
      { Foreground = { Color = C.accent } }, { Text = cur },
    }
    -- 複製/搜索模式徽章（2026-09-08）：主配置 format-tab-title 完全接管了標題渲染，
    -- 默認 "Copy Mode" 前綴不顯示——右欄黃色徽章補回模式指示。僅徽章、
    -- 不加其他提示文案。active_key_table() 隨 status_update_interval(250ms)
    -- 週期重查，進/出模式最多遲 250ms 顯現/消失
    pcall(function()
      local kt = window:active_key_table()
      if kt == 'copy_mode' or kt == 'search_mode' then
        els[#els + 1] = { Foreground = { Color = '#f9e2af' } }   -- Catppuccin yellow
        els[#els + 1] = { Attribute = { Intensity = 'Bold' } }
        els[#els + 1] = { Text = '  ' .. kt:upper():gsub('_MODE', '') .. '-MODE' }
        els[#els + 1] = { Attribute = { Intensity = 'Normal' } } -- 防 Bold 殘留
      end
    end)
    if flash_msg then
      els[#els + 1] = { Foreground = { Color = C.red } }
      els[#els + 1] = { Text = ' ✗' .. flash_msg }
    end
    els[#els + 1] = { Text = ' ' }
    window:set_right_status(wezterm.format(els))
  end)
  if not ok then dbg('render err: ' .. tostring(err)) end
end

-- ═══ 结果消费（标题通道；文件通道在本 build 不可用——配置 Lua 看不见
-- pane 子进程新建的 /tmp 文件，实测 No such file or directory）═══
-- TUI finish() 把动作编码为 pane 标题 'ws-pick:<op>:<name>' 并保活 1.2s；
-- 本函数在 update-right-status 里扫描 mux pane 标题并派发。
local last_sig, last_sig_at = '', 0 -- 已消费签名＋时间戳（防重复；见 consume_pending 内注）

local function consume_pending(window, pane)
  local found_op, found_name, found_pane = nil, nil, nil
  pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      for _, tb in ipairs(w:tabs() or {}) do
        for _, pp in ipairs(tb:panes() or {}) do
          local title = select(2, pcall(function() return pp:get_title() end)) or ''
          local op, name = title:match('^ws%-pick:(%a+):(.*)$')
          if op and #op > 0 then
            found_op, found_name, found_pane = op, name, pp
            break
          end
        end
        if found_op then break end
      end
      if found_op then break end
    end
  end)
  if not found_op then return false end

  -- 時間窗去重（2026-09-09）：舊簽名只有 op:name 且永不過期——連續兩次切同
  -- 一個工作區（dev→scratch→dev 高頻流）第二次被靜默吞掉。改為「同名且 3s
  -- 内」才視為同一保活期的重複掃描（TUI 保活 1.2s，3s 留足餘量）；超窗即新
  -- 選擇，正常消費。邊緣：3-4s 内連選同名兩次會被誤吞（1s 抽屜防抖下幾乎
  -- 不可達），自癒——3s 後再選即通。
  local sig = found_op .. ':' .. found_name
  local now = os.time()
  if sig == last_sig and now - last_sig_at < 3 then return false end
  last_sig, last_sig_at = sig, now

  if found_op == 'goto' or found_op == 'new' then
    local ok, err = pcall(function()
      window:perform_action(wezterm.action.SwitchToWorkspace { name = found_name }, pane)
    end)
    dbg(ok and ('switch → ' .. found_name) or ('switch ERR: ' .. tostring(err)))
  end
  -- 'del' 分支已拆除(2026-09-09):批量後台 kill-pane = 窗口 churn 風暴,餵
  -- wayland panic(守則⑨)。舊標題若再出現 del 簽名會被無聲消費,不執行
  return true
end

-- 定时器兜底链：150ms 扫描标题消费（探针实测 idle 时 urs 不触发，链可靠跳动）；
-- 消费即停；90s 上限防幽灵；重载杀链后由 urs 处理器重挂（GLOBAL 标量存活）
-- 自滅修復（P1-3 2026-09-09）：cancel 無標題可消費 → ws_alive 無人清 →
-- urs 每 250ms 重掛且 arm_poll 無條件清零 poll_ticks → 90s 上限被永遠重置，
-- cancel 後鏈成永動機（每 150ms 全 mux 掃描直到下次成功切換）。修：fresh
-- 參數分離「開抽屜重掛」與「urs 續掛」——只有前者重置計數；到點自滅順手清
-- ws_alive。無害性：消費主通道是 urs 處理器自身的 consume_pending（每次必
-- 跑），本鏈只是 urs 安静時的保險帶；清標誌只影響續掛，抽屜超 90s 再選仍
-- 被 urs 兜住。
local poll_token, poll_ticks = 0, 0
local function arm_poll(window, pane, fresh)
  poll_token = poll_token + 1
  if fresh then poll_ticks = 0 end
  local tok = poll_token
  local function tick()
    if poll_token ~= tok then return end
    poll_ticks = poll_ticks + 1
    if consume_pending(window, pane) then
      wezterm.GLOBAL.ws_alive = nil
      return
    end
    if poll_ticks > 600 then
      wezterm.GLOBAL.ws_alive = nil -- 90s 兜底：自滅並清標誌，urs 不再續掛
      return
    end
    wezterm.time.call_after(0.15, tick)
  end
  wezterm.time.call_after(0.15, tick)
end

-- ═══ 主键：Ctrl+Shift+O 拉起抽屉 ═══
-- 工作区清单快照经 argv 传入（名字:pane数 对）→ TUI 零子进程、启动即绘、数据新鲜
local function open_drawer(window, pane)
  -- 覆蓋層門禁（2026-09-09）：copy/search 鍵表未綁 CTRL|SHIFT+O → fall
  -- through 到全局鍵，層内按 O 照樣觸發本函數；top_level split＝同窗口布局
  -- 變化＝清覆蓋層（守則③）。層内直接忽略——先出層再拉抽屜。放在防重入
  -- 之前，被攔截的按鍵不消耗防抖預算。
  local kt = select(2, pcall(function() return window:active_key_table() end))
  if kt then return end
  -- 防重入（2026-09-09 P0）：key repeat 連發會以 ~30cps 疊出幾十個 top_level
  -- 抽屜 pane（pane churn＋arm_poll 鏈混戰，守則⑨同族）。GLOBAL 純量跨
  -- reload 存活；正常流（Esc 掉再重開）間隔遠超 1s，不受影響。
  local now = os.time()
  if now - (wezterm.GLOBAL.ws_drawer_at or 0) < 1 then return end
  wezterm.GLOBAL.ws_drawer_at = now
  local res = '/tmp/ws-pick.result' -- 仅作 TUI 侧备份（配置不读；文件通道在本 build 不可见）
  local cur = current_workspace(window) or 'default'
  -- 统计各工作区 tab 数与 pane 数（[ws] = {tabs=n, panes=m}）
  local per_ws = {}
  pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      local ws = select(2, pcall(function() return w:get_workspace() end))
      if ws then
        local st = per_ws[ws]
        if not st then st = { tabs = 0, panes = 0 }; per_ws[ws] = st end
        for _, tb in ipairs(w:tabs() or {}) do
          st.tabs = st.tabs + 1
          st.panes = st.panes + #(tb:panes() or {})
        end
      end
    end
  end)
  local args = { PICKER_LUA, PICKER_SCRIPT, res, cur }
  for _, n in ipairs(ordered_names()) do
    local st = per_ws[n] or { tabs = 1, panes = 1 }
    args[#args + 1] = n .. ':' .. tostring(st.tabs) .. ':' .. tostring(st.panes)
  end
  local ok, p2 = pcall(function()
    return pane:split {
      args = args,
      direction = 'Bottom', top_level = true, size = 0.42,
    }
  end)
  if ok and p2 then
    dbg('drawer open pane=' .. tostring(select(2, pcall(function() return p2:pane_id() end))))
    wezterm.GLOBAL.ws_alive = 1
    arm_poll(window, pane, true) -- fresh=true：開抽屜才重置 90s 計數（見 arm_poll 注）
  else
    dbg('split err: ' .. tostring(p2))
    flash('drawer spawn failed (see ws-debug)')
  end
  render(window)
end

M.keys = {
  { key = 'O', mods = 'CTRL|SHIFT', action = wezterm.action_callback(open_drawer) },
}

-- update-right-status：渲染 + 结果消费（rime 同款：标题推送/任意活动必发本事件；
-- 零状态 → 重载杀不死任何东西）
wezterm.on('update-right-status', function(window, pane)
  render(window)
  if consume_pending(window, pane) then
    wezterm.GLOBAL.ws_alive = nil
  end
  if wezterm.GLOBAL.ws_alive == 1 then arm_poll(window, pane, false) end -- 續掛不重置計數（自滅修復）
end)

-- 焦点回迁（抽屉关闭后必发）：第三消费入口
wezterm.on('window-focus-changed', function(window, pane)
  render(window)
  if consume_pending(window, pane) then
    wezterm.GLOBAL.ws_alive = nil
  end
end)

M.key_tables = {}
M._internal = { ordered_names = ordered_names, open_drawer = open_drawer }

dbg('workspace.lua loaded (v3.3 drawer)')
return M
