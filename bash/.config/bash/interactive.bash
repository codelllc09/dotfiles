# Bash 历史属于持久状态，不是配置；移到 XDG state 目录。
bash_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/bash"
mkdir -p "$bash_state_dir"
HISTFILE="$bash_state_dir/history"
unset bash_state_dir

# 兼容 Fedora 的 ~/.bashrc.d 扩展目录。
if [ -d "$HOME/.bashrc.d" ]; then
  for bash_rc_fragment in "$HOME/.bashrc.d"/*; do
    [ -r "$bash_rc_fragment" ] && source "$bash_rc_fragment"
  done
  unset bash_rc_fragment
fi

# fzf 快捷键：Ctrl+R 历史、Ctrl+T 文件、Alt+C 跳目录。
fzf_key_bindings=/usr/share/fzf/shell/key-bindings.bash
[ -r "$fzf_key_bindings" ] && source "$fzf_key_bindings"
unset fzf_key_bindings
