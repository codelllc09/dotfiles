-- WezTerm 配置（Lua）· v4 模块化
-- 拆分自单文件（v3 教训：476 行单文件改一处可能碰坏全局）：
--   agent_monitor.lua coding agent 状态监视（状态点/未读/通知/APPS 缓存/app_name）
--   pane_layout.lua   窗格分屏佈局碼（几何 → 唯一码 → 象形字：吅日田品卦象）
--   app_icon.lua      TABn 程序图标（APP_ICON 表 + 归一化查表）
--   rime.lua          Rime 联动（徽章/游标色/IME 愈合）
--   quick_select.lua  【已退役 2026-09-09】DIY picker——被 copy_keys.lua 搜索/複製模式取代,檔案已刪(git 歷史即 legacy)
--   workspace.lua    工作区：右栏 n/m 计数 + Ctrl+Shift+O 弹出式选择器（规格 workspace.md）
-- 各模块 pcall 引入，坏了只丢对应功能。验证配置（独立 socket 真启动）：
--   WEZTERM_UNIX_SOCKET=/tmp/chk.sock WEZTERM_LOG=warn wezterm start -e true
-- 文档: https://wezterm.org/config/files.html
--
-- ═══ 覆盖层/键表开发守则（2026-09-09 懸案代價換來的，動 overlay/keys 前必讀）═══
-- ① 搜索/複製覆蓋層的鍵表不歸 ClearKeyTableStack 管（古老設計，2024-02 穩定版
--    即如此），關它只有一條正道：CopyMode 'Close'
-- ② Close 的拆除是異步的：同一 Multiple 裏緊跟 ActivateCopyMode 會被連帶彈掉，
--    必須延遲 ≥50ms 再進（見 enter_copy_mode_clean）
-- ③ 覆蓋層開著時避免同窗口 spawn/kill pane（布局變化會清覆蓋層）；反向同理：
--    抽屉剛關別立刻開層（quick_select 的「延遲開層」0.45s 即為此）
-- ④ set_config_overrides（rime 每次切 IME）觸發全量重求值，殺光 pending
--    call_after——一切延遲開層/消費邏輯必須幂等且可重掛（qs/ws 模塊範式）
-- ⑤ key_tables 是整表替換：本 build 無 default_key_tables()，只能凍結快照為基
--    （copy_keys.lua）；改動後必須與 show-keys --key-table 全量 comm 對賬，
--    抽查會漏（Enter/Escape 慘案）
-- ⑥ wezterm.action 是嚴格 userdata：訪問不存在的動作名直接抛錯→整份配置靜默
--    回退默認（GUI 不彈窗！）。新用 action 前先探針；重載後必 show-keys 驗收
-- ⑦ 顯式綁 phys:X 等物理鍵防隱藏默認搶命中（本 build 實測行為）
-- ⑧ 渲染層殭屍（覆蓋層 UI 與狀態脫鈎，任何配置側動作摘不掉）→ F8 把 pane
--    搬進新窗口重建渲染狀態
-- ⑨ 禁 os.execute 後台批量 kill-pane：瞬時多 pane 銷毀 = 窗口 churn 風暴，
--    正中 wayland window.rs "should exist" panic 的食譜（9/4 六連崩同期行為）。
--    workspace 刪除流已因此拆除（2026-09-09）——真要刪工作區，進去手動關 tab

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

-- ── 窗口標題欄嘗試退役（2026-09-09，實測否決）──
-- 背景懸案：GNOME/Mutter 不給 Wayland 原生窗口 SSD；wezterm 默認值
-- 'TITLE | RESIZE' 會「請求 SSD → 藏自帶 CSD → 不檢查是否兌現」→ 無標題欄
-- （上游 PR #7360 修此邏輯，至今未合）。實渗 window_decorations='TITLE'
-- 可觸發自繪 CSD，但本 nightly 的 CSD 是半成品：自帶 ConceptFrame 被
-- 注釋成死代碼（wayland/mod.rs '// mod frame;'，window_frame 配色無效），
-- 實際畫框的是 SCTK 0.19 FallbackFrame，症狀：①底部 tab 欄被裁出可視區
-- （幾何 bug，#6578/#5332 家族）②關閉鍵無反應（默認 AlwaysPrompt 走 confirm
-- 覆蓋層，而覆蓋層組件家族本 nightly 半滅）③最小化失效（set_minimized
-- Mutter 不理）④唯 Maximize 活（無依賴路徑）。窗口管理改走 GNOME 組合鍵：
-- Alt+F4 關 / Super+H 最小化 / Super+↑↓ 最大化平鋪。等 #7360+ConceptFrame
-- 復活後可重試。
config.warn_about_missing_glyphs = false  -- 字形告警不弹窗（渲染正常时的误报）
config.status_update_interval = 250       -- Rime 状态兜底刷新；单位毫秒

-- ── 模块引入（主配置与模块统一位于 XDG 配置目录）──
package.path = wezterm.config_dir .. '/?.lua;' .. package.path
local am_ok, agent_monitor = pcall(require, 'agent_monitor')
if not am_ok then agent_monitor = nil end
if agent_monitor then agent_monitor.setup() end
local pl_ok, pane_layout = pcall(require, 'pane_layout')
if not pl_ok then pane_layout = nil end
local ai_ok, app_icon = pcall(require, 'app_icon')
if not ai_ok then app_icon = nil end
local rime_ok, rime = pcall(require, 'rime')
if rime_ok then pcall(rime.setup, config) end
local ws_ok, workspace = pcall(require, 'workspace')
local ce_ok, compose = pcall(require, 'compose')

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
-- （InputSelector 配色已删：该组件在本 nightly Enter 全灭已弃用；
--   且其 label_fg/bg 需要 { Color = '...' } 包装格式，裸字符串会令
--   整份 config 转换失败回退——2026-09 实测坑）
config.colors.tab_bar = {
  background = '#1e1e2e',
  active_tab = { bg_color = '#1e1e2e', fg_color = '#cdd6f4' },
  inactive_tab = { bg_color = '#1e1e2e', fg_color = '#6c7086' },
  inactive_tab_hover = { bg_color = '#1e1e2e', fg_color = '#b4befe' },
  new_tab = { bg_color = '#1e1e2e', fg_color = '#6c7086' },
  new_tab_hover = { bg_color = '#1e1e2e', fg_color = '#b4befe' },
}

-- 官方 QuickSelect（Ctrl+Shift+Q）：保持主題默認外觀。label 疊繪在匹配串
-- 首格是硬編碼（無留白/位移選項）；2026-09 曾試「亮芯片 vs 暗高亮」配色分離
-- （quick_select_label_bg/fg、quick_select_match_bg/fg），實測仍分不清，已棄

-- ── 行为 ──────────────────────────────────────
config.scrollback_lines = 20000 -- QuickSelect 掃描捕獲面翻倍（diy_scan 全量掃回滾區）
config.tab_max_width = 24 -- 默認 16：藥丸(15格)+佈局碼會被硬切只露一個字符

-- ── 觸控板滾輪單獨降速（終端內有效 0.35）──
-- 全局靈敏度由 wayland-scroll-factor 管（LD_PRELOAD 注入 gnome-shell，
-- ~/.config/wayland-scroll-factor/config: factor=0.5），其他應用已合適；
-- 終端是行粒度滾動仍偏快，這裡在 wezterm 內再乘 0.7：0.5 × 0.7 = 0.35。
-- 原理：蓋掉默認滾輪綁定 ScrollByCurrentEventWheelDelta（每事件滾 delta 行），
-- 改為自行累積 delta×0.7、攢夠整行才 ScrollByLine（亞行累積器）。
-- 綁定帶 alt_screen=false + mouse_reporting=false：vim/tmux 開鼠標上報、
-- less/man 的方向鍵滾動（alt 屏）都不經過這裡，行為不變。
-- 調速改 WHEEL_V_FACTOR；恢復默認整段刪除即可。
local WHEEL_V_FACTOR = 0.5 -- × WSF 的 0.5 = 0.25 有效靈敏度
local wheel_v_acc, wheel_v_sign = 0.0, 0 -- 亞行累積器 + 換向標記
local function wheel_scroll_scaled(window, pane)
  local ok, ev = pcall(function() return window:current_event() end)
  if not ok or type(ev) ~= 'table' or type(ev.Down) ~= 'table' then return end
  local btn = ev.Down.button or {}
  local delta = btn.WheelUp or btn.WheelDown or 0 -- current_event 帶真實行數
  if delta <= 0 then return end
  local sign = btn.WheelUp and -1 or 1 -- ScrollByLine：負=向上回看
  if sign ~= wheel_v_sign then wheel_v_acc, wheel_v_sign = 0.0, sign end -- 換向清零防遲滯
  wheel_v_acc = wheel_v_acc + delta * WHEEL_V_FACTOR
  local lines = math.floor(wheel_v_acc)
  if lines >= 1 then
    wheel_v_acc = wheel_v_acc - lines
    window:perform_action(wezterm.action.ScrollByLine(sign * lines), pane)
  end
end
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'NONE',
    alt_screen = false,
    mouse_reporting = false,
    action = wezterm.action_callback(wheel_scroll_scaled),
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'NONE',
    alt_screen = false,
    mouse_reporting = false,
    action = wezterm.action_callback(wheel_scroll_scaled),
  },
}
-- alt 屏（less/man 等無鼠標上報全屏程序）滾輪→方向鍵的步進：默認 3 → 2（≈0.33，對齊 0.35 手感）
config.alternate_buffer_wheel_scroll_speed = 2

-- ── 超链接规则：默认裸 URL + markdown 四种包裹形式 ──
-- （自定义会整体替换默认表，故默认那条必须带上；Ctrl+点击打开，Fedora 走 xdg-open）
-- 来源参考：KevinSilvester/wezterm-config（1209★）
config.hyperlink_rules = wezterm.default_hyperlink_rules()
for _, re_ in ipairs {
  '\\((\\w+://\\S+)\\)',   -- (url)
  '\\[(\\w+://\\S+)\\]',   -- [url]
  '\\{(\\w+://\\S+)\\}',   -- {url}
  '<(\\w+://\\S+)>',   -- <url>
} do
  table.insert(config.hyperlink_rules, { regex = re_, format = '$1', highlight = 1 })
end
-- 默認已支持: Ctrl+Shift+C/V 複製粘貼、Ctrl+Shift+T 新標籤、Ctrl+Tab 切標籤
-- 分屏快捷鍵（對齊常見習慣）:

-- 複製模式（Ctrl+Shift+X）進入器（2026-09-09 懸案終結版）：
-- 「進複製模式連帶搜索」探針實錐——
--  · ActivateCopyMode 本身乾淨；真兇是 pane 裏駐留的搜索層（早期 Escape 綁定
--    缺失期間被打開、關不掉；層疊在 copy_mode 之下，UI 一直可見，退出又翻上來）
--  · ClearKeyTableStack 清不掉它（實測表仍 search_mode）；唯一有效關法是
--    搜索模式自己的 CopyMode 'Close'（實測 → nil）
--  · 但 Multiple{Close, ..., Activate} 同鏈無效：Close 的拆除是異步的，會把
--    剛 push 的 copy_mode 又彈掉（實測 → nil）；延遲 50ms 再 Activate 繞開 ✓
--  · ClearSelection 清駐留選區（wezterm 退出複製模式不清選區，舊選區會在
--    下次進入時恢復，看起來像默認按了 v）
-- 另：X 必須邏輯鍵+物理鍵雙綁（本 nightly 默認物理鍵綁定會搶命中，phys:Space
-- 前車之鑑：曾經的 picker 模組在層切換組合動作上翻車,已退役)；local 必須在 config.keys 構造器之外（Lua 語法）
local enter_copy_mode_clean = wezterm.action_callback(function(window, pane)
  -- 2026-09-09 v3 無競態設計（實錄：v2 的「Close→50ms→Activate」鏈對鍵表夠快，
  -- 對渲染拆除不夠快——選擇器開的搜索層還沒拆完就進複製模式，搜索欄殘留）
  -- 分支策略（兩段式，徽章可辨）：
  --   table == nil         → 直接清選區+進入（無任何拆除在途中，零競態）
  --   table == search_mode → 只關搜索層，本次不進入（第二次 X 再進，那時零競態）
  --   table == copy_mode   → 已在複製模式，幂等重進
  -- 全程留痕 /tmp/copy-debug.log；殭屍生產線(已隨 DIY picker 退役斷根)另見
  -- 「驗證抽屉死透才開層」修復
  local function clog(m)
    local f = io.open('/tmp/copy-debug.log', 'a')
    if f then f:write(os.date('%T '), m, '\n'); f:close() end
  end
  local function t() return select(2, pcall(function() return window:active_key_table() end)) end
  local kt = t()
  clog('X pressed, table=' .. tostring(kt))
  if kt == 'search_mode' then
    -- 只關層 + 清詞（2026-09-09 原地進入補丁）：舊詞殘留是下次進層滾底的真兇，
    -- 關層前先清（與 Q 的 exit_only 同構：清詞→關層，Close 必須墊尾）
    window:perform_action(wezterm.action.CopyMode 'ClearPattern', pane)
    window:perform_action(wezterm.action.CopyMode 'Close', pane)
    clog('  search layer open → cleared pattern + closed it only, press X again to enter')
    return
  end
  window:perform_action(wezterm.action.ClearSelection, pane)
  window:perform_action(wezterm.action.ActivateCopyMode, pane)
  if kt == nil then
    -- 原地進入的關鍵（2026-09-09）：本 build 進複製模式視口本就繼承（with_pane 取
    -- get_viewport），滾底真兇是按 tab 記憶的舊搜索詞（SAVED_PATTERN）被 with_pane
    -- 自動復活 → 立刻從最底端異步搜索 → activate_match_number(0) 跳最底匹配並拽走
    -- 視口。進入後同步清詞即可破局：在途搜索結果回來時因 pattern 不匹配被
    -- processed_search_chunk 守衛丟棄。順序不可變：overlay 存在才能路由 CopyMode 動作。
    -- 副作用：常態 Ctrl+Shift+X 進入後 `/` 不再預填舊詞（與「Q 清詞」哲學一致；
    -- 複製模式會話內 `/` 仍保留）
    window:perform_action(wezterm.action.CopyMode 'ClearPattern', pane)
    -- 光標投位（2026-09-09 v2）：with_pane 把光標初始化成 pane 真實光標（在底部
    -- 提示符處）——視口雖留住了，但按任何移動鍵都會被
    -- adjust_viewport_for_cursor_position 拽回光標處 (= 滾底)。補一刀
    -- MoveToViewportMiddle：以 overlay 保存的視口為基準把光標投到視口中間
    -- （select_to_cursor_pos 在 start=nil 時只移光標不啟動選區；中間位置與
    -- 上下緣均留 ≥5 行餘量，不會反過來調整視口）。等效進層即按了一次 `M`
    window:perform_action(wezterm.action.CopyMode 'MoveToViewportMiddle', pane)
  end
  -- kt == 'copy_mode'：冪等重進不清詞（`/` 會話內舊詞保留；此路徑 apply_params
  -- 不觸發搜索，無滾底風險）
  clog('  entered, table=' .. tostring(t()) .. ', pattern_cleared=' .. tostring(kt == nil))
end)

-- 搜索模式進入器（2026-09-09 原地進入）：Ctrl+Shift+F 出廠默認是 Search
-- 'CurrentSelectionOrEmptyString'——無選區時詞空，同樣復活 SAVED_PATTERN 舊詞
-- → 跳最底匹配（= 進搜索態滾底）。接管為三分支：
--   常態     → ClearSelection + Search 空詞 + 立刻 ClearPattern + 光標投位
--              MoveToViewportMiddle（詞空欄、視口原地、光標在視口中間；打字後
--              350ms 跳到匹配是增量搜索本義，不受影響）
--   複製模式 → EditPattern（等價 `/`：原地、保留會話內舊詞）
--   搜索態   → 冪等 Nop
local enter_search_clean = wezterm.action_callback(function(window, pane)
  local okt, kt = pcall(function() return window:active_key_table() end)
  if not okt then return end
  if kt == 'search_mode' then return end
  if kt == 'copy_mode' then
    window:perform_action(wezterm.action.CopyMode 'EditPattern', pane)
    return
  end
  window:perform_action(wezterm.action.ClearSelection, pane)
  window:perform_action(wezterm.action.Search { CaseInSensitiveString = '' }, pane)
  window:perform_action(wezterm.action.CopyMode 'ClearPattern', pane)
  -- 光標投位（同 Ctrl+Shift+X 進入器）：搜索態直接 Esc 擺渡回複製模式時，光標
  -- 已在視口中間，不會一按移動鍵就滾底
  window:perform_action(wezterm.action.CopyMode 'MoveToViewportMiddle', pane)
end)

config.keys = {
  -- 搜索回滚缓冲区：唯一入口 Ctrl+Shift+F——2026-09-09 起接管为 enter_search_clean
  -- （原地进入：出廠默認會復活按 tab 記憶的舊搜索詞並跳最底匹配；機制見上方註釋）。
  -- 邏輯鍵+物理鍵雙綁（規則⑦，大小寫歸一坑同 Ctrl+Shift+X 進入器）
  { key = 'F', mods = 'CTRL|SHIFT', action = enter_search_clean },
  { key = 'phys:F', mods = 'CTRL|SHIFT', action = enter_search_clean },
  { key = 'phys:f', mods = 'CTRL|SHIFT', action = enter_search_clean },
  -- 简繁切换已移至 Rime 的 Super+F；释放多余的默认搜索键：
  { key = 'f', mods = 'SUPER', action = wezterm.action.DisableDefaultAssignment }, -- Super+F 让给 Rime 简繁切换
  { key = 'f', mods = 'CTRL', action = wezterm.action.DisableDefaultAssignment },  -- Ctrl+F 放行给终端内程序
  -- Ctrl+Shift+Enter 右侧新分屏
  { key = 'Enter', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  -- Ctrl+Shift+E 下方新分屏
  { key = 'E', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- Ctrl+Shift+W 关闭当前分屏
  { key = 'W', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },
  -- 複製模式：懸案終結版進入器（見上方 local 處的探針實錐）
  { key = 'X', mods = 'CTRL|SHIFT', action = enter_copy_mode_clean },
  { key = 'phys:X', mods = 'CTRL|SHIFT', action = enter_copy_mode_clean },
  { key = 'phys:x', mods = 'CTRL|SHIFT', action = enter_copy_mode_clean }, -- 大小寫雙拼（本 build phys: 鍵大小寫歸一不穩，防隱藏默認 phys:x 搶命中）
  -- 常態視口一鍵滾底/滾頂（2026-09-09）：q 退出複製模式已改爲留在原位,
  -- 回底部用這對鍵;瀏覽回滾後 Ctrl+Shift+End 一鍵回家(輸入也會自動帶回)
  { key = 'End', mods = 'CTRL|SHIFT', action = wezterm.action.ScrollToBottom },
  { key = 'Home', mods = 'CTRL|SHIFT', action = wezterm.action.ScrollToTop },
  -- 渲染層殭屍救援（2026-09-09）：搜索欄 UI 與鍵表/覆蓋層狀態脫鈎後，配置側無法
  -- 摘除；把當前 pane 搬進全新窗口可重建渲染狀態（舊窗口稍後手動關閉即可）。
  -- 注意：本 build 無 MovePaneToNewWindow 動作（wezterm.action 是嚴格 userdata，
  -- 訪問不存在變體直接抛錯→整份配置重載失敗回退默認——親測踩坑），
  -- 但 Pane 對象有 move_to_new_window() 方法，走 action_callback。
  { key = 'F8', mods = 'NONE', action = wezterm.action_callback(function(window, pane)
    -- 防重入（2026-09-09 P0）：key repeat 連發會以 ~30cps 反覆搬窗＝窗口 churn 風暴
    -- （守則⑨ panic 食譜，且 F8 常在渲染狀態異常時按，疊加風險）。GLOBAL 純量
    -- 跨 reload 存活（rime 切 IME 即重求值，local 狀態靠不住）；os.time 秒級粒度，
    -- 實際間隔 2-3s，救援場景可接受。
    local now = os.time()
    if now - (wezterm.GLOBAL.f8_at or 0) < 2 then return end
    wezterm.GLOBAL.f8_at = now
    pcall(function() pane:move_to_new_window() end)
  end) },
  -- （分流實驗 F7 已於定案後移除：證實症狀與鍵位無關，是渲染層殭屍；F8 換窗終結）
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

-- ── QuickSelect 全面退役（2026-09-09）──
-- DIY picker（quick_select.lua + qs-picker.lua，2026-09 全套）已刪：搜索/複製
-- 模式（copy_keys.lua）完整取代其職能，且 picker 的「開 Search 高亮層 + 異步殺
-- 抽屜」競態是渲染殭屍的生產線（教訓見頭部守則第 5 條）。
-- 官方 QuickSelect 同步封印：本 build 實測疑似零高亮（#7752 交互重做嫌疑），
-- 且 prefix 提示字母疊繪在選項上方難以辨認——按了只會看到死相,不如封死。
table.insert(config.keys, { key = 'phys:Space', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment })
table.insert(config.keys, { key = ' ', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment })

-- ── workspace 接入（Ctrl+Shift+O 选择器；右栏 Workspace n/m 显示由该模块注册）──
-- 接口校验（P2-4 2026-09-09）：pcall 只保加载、不保导出。若模块加载成功但
-- M.keys/M.key_tables 缺失（手滑改名/改 return），裸取 .keys 会在顶层抛错
-- → 整份配置静默回退默认（守则⑥）。按件校验、按件降级，兑现“坏了只丢对应功能”。
if ws_ok and type(workspace) == 'table' then
  if type(workspace.keys) == 'table' then
    for _, k in ipairs(workspace.keys) do table.insert(config.keys, k) end
  end
  if type(workspace.key_tables) == 'table' then
    config.key_tables = workspace.key_tables
  end
end

-- ── 複製模式鍵表增補（2026-09-08 v2，討論定案：保留 vim 默認手感）──
-- copy_keys.lua = 凍結的本 build 默認表 + Ctrl+A/E 行首尾 + i/o 上下半屏。
-- 詳情（含本 nightly 的 default_key_tables 為 nil、整表賦值、字符串 action
-- 三個坑）見 copy_keys.lua 模塊頭註釋。
local ck_ok, copy_keys = pcall(require, 'copy_keys')
if ck_ok and copy_keys and copy_keys.copy_mode then
  -- 必須一次性整表賦值：config_builder 的 __newindex 只追蹤頂層賦值，
  -- 先賦 key_tables 再嵌套寫 copy_mode 會被吞（實測 show-keys 不認）
  local merged = {}
  for k, v in pairs(config.key_tables or workspace.key_tables or {}) do merged[k] = v end
  merged.copy_mode = copy_keys.copy_mode
  if copy_keys.search_mode then merged.search_mode = copy_keys.search_mode end
  config.key_tables = merged
end

-- ── compose 接入（Ctrl+Shift+I 中文緩衝輸入窗；流式輸出時防 Rime 候選框閃爍）──
if ce_ok and type(compose) == 'table' and type(compose.keys) == 'table' then
  for _, k in ipairs(compose.keys) do table.insert(config.keys, k) end
end

return config
