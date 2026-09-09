# 先以 detached 模式加载；由 ~/.bashrc 在所有模块之后执行 ble-attach。
blesh_file="${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh"
if [[ $- == *i* && -r "$blesh_file" ]]; then
  source -- "$blesh_file" --attach=none
fi
unset blesh_file
