-- compose.lua — 中文組字緩衝窗:流式輸出期間的 Rime 候選框防閃方案
-- 機制:候選框閃爍源於 pi 流式輸出讓終端光標(=IME 錨點)逐幀移動,
--   gnome-shell 對每次 zwp_text_input_v3 錨點變化都重排彈窗。
--   把組字挪到本靜止小窗:焦點表面的錨點不動 → 不閃。
-- 流程:Ctrl+Shift+I 彈出緩衝窗 → 終端編輯器寫臨時文件(nano 自帶
--   ^A/^E/^K,vim 系自動注入同款映射;多行隨意;臨時文件在 /dev/shm,
--   純內存零磁盤 I/O)→ 保存退出 = 整段粘貼進 pi 輸入框(默認不回車,
--   回 pi 複查後按 Enter 發送;auto_submit=true 則自動回車直接發送);
--   :q! 或空文件 = 放棄。單發即關窗,焦點自動回 pi。
-- 接線(主配置 ~/.config/wezterm/wezterm.lua,仿 v4 模塊式):
--   local ce_ok, compose = pcall(require, 'compose')
--   if ce_ok then for _, k in ipairs(compose.keys) do table.insert(config.keys, k) end end
-- 變體:想邊看 pi 邊打字,可把 SpawnCommandInNewWindow 換成 SplitPane
--   (右側分屏);焦點分屏的錨點同樣靜止,防閃效果一致。
-- 驗證:WEZTERM_UNIX_SOCKET=/tmp/chk.sock wezterm start -e true
local wezterm = require 'wezterm'
local M = {}

-- false: 粘貼進輸入框,回 pi 按 Enter 發送(可複查,可再改)
-- true : 保存退出後自動補回車,直接發送
M.auto_submit = false

local COMPOSER = wezterm.config_dir .. '/composer.sh'

M.keys = {
  {
    key = 'I', mods = 'CTRL|SHIFT', -- 可按喜好改鍵
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(wezterm.action.SpawnCommandInNewWindow {
        args = { 'bash', COMPOSER, tostring(pane:pane_id()) },
        set_environment_variables = {
          COMPOSE_AUTO_SUBMIT = M.auto_submit and '1' or '0',
        },
      }, pane)
    end),
  },
}

return M
