# 先以 detached 模式加载；由 ~/.bashrc 在所有模块之后执行 ble-attach。
if [[ $- == *i* && -r "$HOME/.local/share/blesh/ble.sh" ]]; then
  source -- "$HOME/.local/share/blesh/ble.sh" --attach=none
fi
