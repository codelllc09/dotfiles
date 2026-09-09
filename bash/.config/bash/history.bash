# Bash 历史属于持久状态，不是配置；移到 XDG state 目录。
bash_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/bash"
mkdir -p "$bash_state_dir"
HISTFILE="$bash_state_dir/history"
unset bash_state_dir
