# DSH 内嵌终端使用 Catppuccin Mocha 的 16 色调色板。
[[ -t 1 && -n ${DSH_SESSION_ID-} ]] || return 0
[[ -r "$HOME/Documents/deepseek-harness/default-workspace/plugins/dsh-tui-theme/docs/terminal-palette-osc4.sh" ]] || return 0

__dsh_tui_osc4() {
  source "$HOME/Documents/deepseek-harness/default-workspace/plugins/dsh-tui-theme/docs/terminal-palette-osc4.sh"
}

if [[ -z ${DSH_TUI_OSC4_HOOKED-} ]]; then
  DSH_TUI_OSC4_HOOKED=1
  if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
    PROMPT_COMMAND+=( '__dsh_tui_osc4' )
  else
    PROMPT_COMMAND="__dsh_tui_osc4${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
  # 回车后、命令执行前再发送一次，覆盖终端组件晚于 Bash 启动的情况。
  PS0='$(__dsh_tui_osc4)'"${PS0-}"
fi
__dsh_tui_osc4
