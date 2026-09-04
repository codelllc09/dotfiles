-- app_icon.lua — TABn 程序圖標：APP_ICON 表 + 進程名歸一化查表
-- 从主配置拆出（v4 模块化）；取名依赖 herd 的每秒进程缓存（可选）。
-- 圖標策略：① md- 系（Plane 1）直书 ② 无平替者 Lua '\u{XXXX}' 转义 ③ 码位注释=恢复凭据
--
-- 接口：
--   M.label(tab) → 图标字形；无图标程序回退文字名；名字全无 → '·'
-- 取名三层：agent_monitor.app_name（含套壳识别）→ TabInformation.foreground_process_name → nil
-- 查表三层：精确 → 去尾版本号(python3.12→python) → 截首段(emacs-30.2-nw→emacs)
-- 沿革：AI 输出通道丢 BMP 私有区字符（U+E000-F8FF）→ 表内该区一律转义书写
local wezterm = require 'wezterm'
local M = {}
local am_ok, agent_monitor = pcall(require, 'agent_monitor')
if not am_ok then agent_monitor = nil end

-- ── 標題正文：TABn + 程序圖標（starship 式）──
-- 圖標策略（v3 教訓固化——AI 輸出通道丟 BMP 私有區字符）：
--   ① 優先選 Plane 1 的 md- 系圖標（U+F0000+，字面直書可存活於對話）
--   ② 無 md- 平替者保留經典字形，以 Lua 5.4 '\u{XXXX}' 轉義書寫（純 ASCII 源碼）
--   ③ 行尾 U+ 註釋＝恢復憑據，任何時候可用 python 按碼位重建
local APP_ICON = {
  -- herd agents
  pi        = 'π',  -- U+003C0  希腊字母
  claude    = '󰚩',  -- U+F06A9  md-robot
  codex     = '\u{ec20}',  -- U+0EC20  cod-robot（无平替·转义）
  -- 编辑器 / pager
  nvim      = '\u{e6ae}',  -- U+0E6AE  custom-neovim（无平替·转义）
  vim       = '\u{e7c5}',  -- U+0E7C5  dev-vim（无平替·转义）
  emacs     = '\u{e632}',  -- U+0E632  custom-emacs（无平替·转义）
  emacsclient = '\u{e632}',
  less      = '󰍉',  -- U+F0349  md-magnify
  man       = '󰍉',
  -- 文件管理器
  yazi      = '󰇥',  -- U+F01E5  md-duck（yazi＝鸭子）
  lf        = '󰉋',  -- U+F024B  md-folder（cod-folder 平替）
  ranger    = '󰉋',
  nnn       = '󰉋',
  vifm      = '󰉋',
  mc        = '󰉋',
  -- shell / 复用器
  bash      = '󱆃',  -- U+F1183  md-bash
  zsh       = '󰆍',  -- U+F018D  md-console（seti-shell 平替）
  sh        = '󰆍',
  tmux      = '󰆍',  -- U+F018D  md-console（cod-tmux 平替）
  -- node 家族
  node      = '󰎙',  -- U+F0399  md-nodejs
  npm       = '󰎙',
  npx       = '󰎙',
  pnpm      = '󰎙',
  yarn      = '󰎙',
  bun       = '\u{e76f}',  -- U+0E76F  starship bun（无平替·转义）
  deno      = '\u{e7c0}',  -- U+0E7C0  starship deno（无平替·转义）
  -- 语言
  python    = '󰌠',  -- U+F0320  md-language_python（starship 平替）
  python3   = '󰌠',
  cargo     = '󱘗',  -- U+F1617  md-language_rust
  rustc     = '󱘗',
  go        = '󰟓',  -- U+F07D3  md-language_go
  gcc       = '󰙱',  -- U+F0671  md-language_c
  cc        = '󰙱',
  ['g++'] = '󰙲',  -- U+F0672  md-language_cpp
  ['c++']   = '󰙲',
  java      = '󰬷',  -- U+F0B37  md-language_java
  ruby      = '󰴭',  -- U+F0D2D  md-language_ruby
  php       = '󰌟',  -- U+F031F  md-language_php
  lua       = '󰢱',  -- U+F08B1  md-language_lua
  perl      = '\u{e67e}',  -- U+0E67E  starship perl（无平替·转义）
  elixir    = '\u{e62d}',  -- U+0E62D  starship elixir（无平替·转义）
  erlang    = '\u{f23f}',  -- U+0F23F  starship erlang（无平替·转义）
  zig       = '\u{e6a9}',  -- U+0E6A9  starship zig（无平替·转义）
  cmake     = '\u{e794}',  -- U+0E794  starship cmake（无平替·转义）
  -- 工具
  git       = '󰊢',  -- U+F02A2  md-git
  docker    = '󰡨',  -- U+F0868  md-docker
  podman    = '󰡨',
  kubectl   = '󱃾',  -- U+F10FE  md-kubernetes
  helm      = '󰀱',  -- U+F0031  md-anchor（helm 本义舵柄）
  terraform = '󱁢',  -- U+F1062  md-terraform
  aws       = '󰸏',  -- U+F0E0F  md-aws
  htop      = '󰍛',  -- U+F035B  starship memory_usage
  btm       = '󰍛',
  top       = '󰍛',
  ssh       = '󰣀',  -- U+F08C0  md-ssh
}


-- 進程名 → 顯示標籤：查圖標表（尾版本號歸一後重查：python3.12 → python），
-- 無圖標回退顯示文字名（純圖標優先策略）
local function app_label(tab)
  local name
  if agent_monitor then pcall(function() name = agent_monitor.app_name(tab) end) end
  if not name then
    pcall(function()
      local f = tab.active_pane.foreground_process_name
      if type(f) == 'string' and f ~= '' then name = f:match('([^/]+)$') end
    end)
  end
  if not name then return '·' end
  -- 三层查表：精确 → 去尾版本号(python3.12→python) → 截首段再归一(emacs-30.2-nw→emacs)
  return APP_ICON[name]
      or APP_ICON[name:gsub('[%d.]+$', '')]
      or APP_ICON[(name:match('^([^-]+)') or name):gsub('[%d.]+$', '')]
      or name
end

M.label = app_label

return M
