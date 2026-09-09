# ble.sh 启用时由其原生 integration 提供 fzf 补全和快捷键；
# 未启用时回退到 Fedora 打包的 Readline 快捷键。
if [[ ! ${BLE_VERSION-} ]]; then
  fzf_key_bindings=/usr/share/fzf/shell/key-bindings.bash
  [ -r "$fzf_key_bindings" ] && source "$fzf_key_bindings"
  unset fzf_key_bindings
fi
