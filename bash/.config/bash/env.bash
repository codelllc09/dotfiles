# 使用目录存在性检查与去重，保持 PATH 可重复加载。
bash_prepend_path() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

bash_prepend_path "$HOME/bin"
bash_prepend_path "$HOME/.local/bin"
bash_prepend_path "$HOME/.local/share/pi-node/current/bin"
export PATH

unset -f bash_prepend_path
