-- copy_keys.lua — 複製模式鍵表：默認鍵全量凍結 + 三組小增補（2026-09-08 v3）
-- ─────────────────────────────────────────────────────────────
-- 增補（v3，討論定案；v1 的 GUI 式 Shift+方向鍵方案已回滚廢棄）：
--   Ctrl+A / Ctrl+E = 行首 / 行尾（readline 習慣，對齊默認 `0` 與 `$`/End）
--   n = 下半屏、m = 上半屏（同 Ctrl+d / Ctrl+u）
--     · n/m 純鍵均空閒（僅 m+ALT 有行首綁定，不同 mods 不衝突）
--     · 完全不覆蓋任何默認鍵位（v2 曾覆蓋 o，已應用戶要求還原；
--       i 純鍵本就空閒，v2 用過又釋回，令 n/m 對應 i/o 的空間習慣：左=下、右=上）
--     · u/p 左右半屏不可行：複製模式無水平視口，長行折行顯示，
--       CopyMode 動作集只有垂直翻頁 MoveByPage
--
-- 實現說明:key_tables 賦值是「整表替換」,官方推薦以
-- wezterm.default_key_tables() 為基底疊加,但該函數在本 nightly
-- (20260901 copr)實測為 nil(default_keys 也沒有),故凍結本 build 的
-- 默認 copy_mode 全量快照(取自 `wezterm show-keys --lua --key-table
-- copy_mode`)。注意兩個本 build 的坑:①config_builder 的 __newindex 只
-- 追蹤頂層賦值,必須一次性整表賦 config.key_tables;②act.ScrollToBottom
-- 是字符串不是構造器,不可調用。升級 wezterm 後想回出廠鍵位:刪掉主配置
-- 的本模塊接線段即可。
--
-- 接口:
--   M.copy_mode  → 完整 copy_mode 鍵表（主配置餵給 config.key_tables.copy_mode）
--   M.search_mode → search_mode 鍵表（2026-09-09 接管：默認 Esc 會把整個複製
--                   模式彈掉〔探針實錘：EditPattern→Enter→Close→nil〕，用户被踢
--                   出後方向鍵直穿 pane。改：Esc/Tab = AcceptPattern 帶着匹配回
--                   複製模式〔探針：AcceptPattern→copy_mode〕，連按兩次 Esc 才
--                   全部退出。注意不能綁字母鍵——未綁的可打印鍵全用於搜索詞輸入，
--                   綁了就偷字）
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

-- ── 清选区兜底（2026-09-09 ④）：search 态 Esc 落位后 0.08s 的
-- ClearSelectionMode 是 pending 定时器；80ms 窗口内撞上 IME 切换（rime
-- override 全量重求值）或手动存配置 → 定时器被杀 → 匹配词自动选中（隐藏
-- 锚点）复活。守则④要求延迟逻辑幂等且可重挂：快路径照旧 80s 直清；慢路径
-- 以 GLOBAL 纯量记「待清时间戳」，由本模块 eval 期注册的 urs handler 兜底
-- 补刀（层已非 copy_mode 则 TTL 过期弃单）。
local function esc_land(window, pane)
  wezterm.GLOBAL.pending_clear_sel_at = os.time()
  wezterm.time.call_after(0.08, function()
    local at = wezterm.GLOBAL.pending_clear_sel_at
    pcall(function()
      if window:active_key_table() == 'copy_mode' then
        window:perform_action(wezterm.action.CopyMode 'ClearSelectionMode', pane)
      end
    end)
    if at == wezterm.GLOBAL.pending_clear_sel_at then
      wezterm.GLOBAL.pending_clear_sel_at = nil -- 快路径已落地，撤单
    end
  end)
end

wezterm.on('update-right-status', function(window, pane)
  local at = wezterm.GLOBAL.pending_clear_sel_at
  if type(at) ~= 'number' then return end
  local kt = select(2, pcall(function() return window:active_key_table() end))
  if kt == 'copy_mode' then
    wezterm.GLOBAL.pending_clear_sel_at = nil
    pcall(function()
      window:perform_action(wezterm.action.CopyMode 'ClearSelectionMode', pane)
    end)
  elseif os.time() - at > 3 then
    wezterm.GLOBAL.pending_clear_sel_at = nil -- TTL 过期：早已出层，弃单
  end
end)

-- ═══ 退出鍵設計史(2026-09-09,三連敗後定稿)═══
-- q 直接退 → 誤觸(w 相鄰);:q 時間戳 → 無可視反饋;: 輸入框(PromptInputLine)
-- → 本 build 陣亡(連框都不彈,覆蓋層組件全家族滅,見主配置頭註釋)。
-- 定稿:Q(Shift+Q)退出——單鍵、需 Shift 天然防誤觸、零機制依賴。
-- 出口唯一化(用戶定稿):q/:/Ctrl+G/Ctrl+C 全部吞掉,唯一出口 = Q。

-- 退出不複製、留在原位（2026-09-09 應用戶要求去掉回底部;清詞保留）。
-- 上游本就支持:Close 不自帶滾動,滾動是默認綁定顯式拼的(#4924)——拆掉即得。
-- 回底部交給常態鍵 Ctrl+Shift+End(見 wezterm.lua)。y 仍回底部(複製完通常要粘貼)
local exit_only = act.Multiple {
  act.CopyMode 'ClearPattern',
  act.CopyMode 'Close',
}

M.copy_mode = {
  -- ── 凍結的本 build 默認鍵位（show-keys 快照；2026-09-09 對賬補齊 Enter/Escape
  --    兩條——v2 重寫時遺漏，致 Esc 穿透到 pane、pi 快捷鍵被誤觸發的懸案）──
  { key = 'Tab', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
  { key = 'Tab', mods = 'SHIFT', action = act.CopyMode 'MoveBackwardWord' },
  { key = 'Enter', mods = 'NONE', action = act.CopyMode 'MoveToStartOfNextLine' },
  -- vim 模态语义(2026-09-09 定稿 v2):Esc 是复制⇄搜索的纯往返键——
  -- 复制模式按 Esc = 进搜索;搜索按 Esc = 回复制(见 search_mode 表);永不退出。
  -- 取消选区 = 再按一次 v(切换语义);退出 = 显式键 q / y。
  { key = 'Escape', mods = 'NONE', action = act.CopyMode 'EditPattern' },
  { key = 'Space', mods = 'NONE', action = act.CopyMode { SetSelectionMode = 'Cell' } },
  { key = '$', mods = 'NONE', action = act.CopyMode 'MoveToEndOfLineContent' },
  { key = '$', mods = 'SHIFT', action = act.CopyMode 'MoveToEndOfLineContent' },
  { key = ',', mods = 'NONE', action = act.CopyMode 'JumpReverse' },
  { key = '0', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
  { key = ';', mods = 'NONE', action = act.CopyMode 'JumpAgain' },
  { key = 'F', mods = 'NONE', action = act.CopyMode { JumpBackward = { prev_char = false } } },
  { key = 'F', mods = 'SHIFT', action = act.CopyMode { JumpBackward = { prev_char = false } } },
  { key = 'G', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackBottom' },
  { key = 'G', mods = 'SHIFT', action = act.CopyMode 'MoveToScrollbackBottom' },
  { key = 'H', mods = 'NONE', action = act.CopyMode 'MoveToViewportTop' },
  { key = 'H', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportTop' },
  { key = 'L', mods = 'NONE', action = act.CopyMode 'MoveToViewportBottom' },
  { key = 'L', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportBottom' },
  { key = 'M', mods = 'NONE', action = act.CopyMode 'MoveToViewportMiddle' },
  { key = 'M', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportMiddle' },
  { key = 'O', mods = 'NONE', action = act.CopyMode 'MoveToSelectionOtherEndHoriz' },
  { key = 'O', mods = 'SHIFT', action = act.CopyMode 'MoveToSelectionOtherEndHoriz' },
  { key = 'T', mods = 'NONE', action = act.CopyMode { JumpBackward = { prev_char = true } } },
  { key = 'T', mods = 'SHIFT', action = act.CopyMode { JumpBackward = { prev_char = true } } },
  { key = 'V', mods = 'NONE', action = act.CopyMode { SetSelectionMode = 'Line' } },
  { key = 'V', mods = 'SHIFT', action = act.CopyMode { SetSelectionMode = 'Line' } },
  { key = '^', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLineContent' },
  { key = '^', mods = 'SHIFT', action = act.CopyMode 'MoveToStartOfLineContent' },
  { key = 'b', mods = 'NONE', action = act.CopyMode 'MoveBackwardWord' },
  { key = 'b', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
  { key = 'b', mods = 'CTRL', action = act.CopyMode 'PageUp' },
  { key = 'c', mods = 'CTRL', action = act.Nop }, -- 吞掉(2026-09-09 定稿:出口唯一化,僅 Q)
  { key = 'd', mods = 'CTRL', action = act.CopyMode { MoveByPage = 0.5 } },
  { key = 'e', mods = 'NONE', action = act.CopyMode 'MoveForwardWordEnd' },
  { key = 'f', mods = 'NONE', action = act.CopyMode { JumpForward = { prev_char = false } } },
  { key = 'f', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
  { key = 'f', mods = 'CTRL', action = act.CopyMode 'PageDown' },
  { key = 'g', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackTop' },
  { key = 'g', mods = 'CTRL', action = act.Nop }, -- 吞掉(同上)
  { key = 'h', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
  { key = 'j', mods = 'NONE', action = act.CopyMode 'MoveDown' },
  { key = 'k', mods = 'NONE', action = act.CopyMode 'MoveUp' },
  { key = 'l', mods = 'NONE', action = act.CopyMode 'MoveRight' },
  { key = 'm', mods = 'ALT', action = act.CopyMode 'MoveToStartOfLineContent' },
  { key = 'o', mods = 'NONE', action = act.CopyMode 'MoveToSelectionOtherEnd' },
  { key = 'q', mods = 'NONE', action = act.Nop }, -- 吞掉(防 w 誤觸)
  { key = ':', mods = 'NONE', action = act.Nop }, -- 吞掉(PromptInputLine 陣亡,防漏穿)
  { key = 'Q', mods = 'NONE', action = exit_only }, -- Q = 退出(留原位+清詞)
  { key = 't', mods = 'NONE', action = act.CopyMode { JumpForward = { prev_char = true } } },
  { key = 'u', mods = 'CTRL', action = act.CopyMode { MoveByPage = -0.5 } },
  { key = 'v', mods = 'NONE', action = act.CopyMode { SetSelectionMode = 'Cell' } },
  { key = 'v', mods = 'CTRL', action = act.CopyMode { SetSelectionMode = 'Block' } },
  { key = 'w', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
  -- y = 复制+留任(2026-09-09 定稿,vim yank 语义):复制模式是"阅读室"——
  -- 留在里面浏览/连抄都不会被拉回底部(Down 在模式内只移动视口);
  -- 退出后按任意键/Down 即回底部(故上游无需滚底默认键)。退出只走 q。
  -- y = 复制+关选区+留任(2026-09-09 定稿讨论结论):高亮消失=复制回执,
  -- 并消除「旧锚点延伸」陷阱;同层收尾组合,与 q 链同安全类
  { key = 'y', mods = 'NONE', action = act.Multiple {
    act.CopyTo 'ClipboardAndPrimarySelection',
    act.CopyMode 'ClearSelectionMode',
  } },
  { key = 'PageUp', mods = 'NONE', action = act.CopyMode 'PageUp' },
  { key = 'PageDown', mods = 'NONE', action = act.CopyMode 'PageDown' },
  { key = 'End', mods = 'NONE', action = act.CopyMode 'MoveToEndOfLineContent' },
  { key = 'Home', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
  { key = 'LeftArrow', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
  { key = 'LeftArrow', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
  { key = 'RightArrow', mods = 'NONE', action = act.CopyMode 'MoveRight' },
  { key = 'RightArrow', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
  { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'MoveUp' },
  { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'MoveDown' },

  -- ── 增補 v3（2026-09-09）──
  -- readline 行首/行尾（Ctrl+A 對齊 `0`，Ctrl+E 對齊 `$`/End）
  { key = 'a', mods = 'CTRL', action = act.CopyMode 'MoveToStartOfLine' },
  { key = 'e', mods = 'CTRL', action = act.CopyMode 'MoveToEndOfLineContent' },
  -- 半屏簇 n/m（對應 i/o 的空間習慣：左=下、右=上；i/u/p 空閒未用）
  { key = 'n', mods = 'NONE', action = act.CopyMode { MoveByPage = 0.5 } },  -- 下半屏
  { key = 'm', mods = 'NONE', action = act.CopyMode { MoveByPage = -0.5 } }, -- 上半屏
  -- 跳轉：/ 進入搜索編輯態（less/vim 手感）——2026-09-09 補回跳轉功能。
  -- 背景選擇器的「Search 高亮層」因穩定產出渲染殭屍已停用（已退役的 DIY picker(2026-09)
  -- 的 highlight_after_pick=false），跳轉改走這條用戶按鍵驅動的路徑：
  --   X 進複製模式 → / 輸入詞 → Enter/↑↓ 在匹配間跳 → Esc 回複製模式 → Esc 退出。
  -- 此路徑不經程序化開層（殭屍配方的必要成分），且無預填無白動跳。
  { key = '/', mods = 'NONE', action = act.CopyMode 'EditPattern' },
  { key = 'y', mods = 'CTRL', action = act.Nop }, -- 吞掉(2026-09-09:與 y 重複,刪;搜索態的 Ctrl+Y 保留——那裏它仍是唯一複製鍵)
}

-- search_mode：凍結默認 + 雙出口落位設計（2026-09-09）。
-- 背景坑：AcceptPattern 落位時匹配詞已被自動選中（錨點在詞首、光標在詞尾），
-- 此時往左移動是在「收窄」現成選區而不是重新選——收到只剩首字母，y 就只複製
-- 一個字（用户實測踩坑）。雙出口：
--   Esc = AcceptPattern + ClearSelectionMode：乾淨落位，自己 v 選（yazi 流）
--   Tab = AcceptPattern：保留匹配選中，直接 y 複製整詞（快捷流）
-- 用戶流：X → / 輸詞 → Enter 跳最近 → ↑↓ 選匹配 → Esc 或 Tab 落回複製模式
--   →（Esc 路：v → 移動 → y；Tab 路：直接 y）→ 再 Esc 退出
M.search_mode = {
  { key = 'Enter', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
  -- 教訓（2026-09-09 深夜）：本 build 的「層切換組合動作」全部不可靠
  -- （Close+Activate、Accept+ClearSelection 均被異步拆除連帶吃掉）——
  -- 落位出口一律單一動作，絕不組合。
  -- Esc = 干净落位(2026-09-09 v3):落回复制模式后清掉自动选中的匹配词,
  -- 自己 v 选(用户要求——自动选区的隐藏锚点易踩坑)。两段式:先切层、等落地
  -- (0.08s)、再同层清选区——层切换绝不组合(本 build 组合会被异步拆除吃掉)。
  { key = 'Escape', mods = 'NONE', action = wezterm.action_callback(function(window, pane)
    window:perform_action(wezterm.action.CopyMode 'AcceptPattern', pane)
    esc_land(window, pane) -- 两段式：先落位（层切换组合动作必被异步拆除，不能拼链）；
    -- 清选区走 esc_land：快路径 80ms 直清 + GLOBAL 兜底补刀（可重挂，见模块头注）
  end) },
  { key = 'n', mods = 'CTRL', action = act.CopyMode 'NextMatch' },
  { key = 'p', mods = 'CTRL', action = act.CopyMode 'PriorMatch' },
  { key = 'r', mods = 'CTRL', action = act.CopyMode 'CycleMatchType' },
  { key = 'u', mods = 'CTRL', action = act.CopyMode 'ClearPattern' },
  { key = 'PageUp', mods = 'NONE', action = act.CopyMode 'PriorMatchPage' },
  { key = 'PageDown', mods = 'NONE', action = act.CopyMode 'NextMatchPage' },
  { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
  { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'NextMatch' },
  -- Tab = 帶選中落位:匹配詞保持選中,落位後直接 y 抄整詞(快捷流專用)
  { key = 'Tab', mods = 'NONE', action = act.CopyMode 'AcceptPattern' },
  { key = 'y', mods = 'CTRL', action = act.Nop }, -- 吞掉(2026-09-09 定稿:搜索態純導航,複製一律 Esc 落位後在複製模式做)
}

return M
