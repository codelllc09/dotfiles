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

# 默认编辑器：nvim（2026-10 弃用 emacsclient 方案：无 daemon 依赖，且 yazi 的
# opener 不经 shell 解析，EDITOR 里的引号会被字面化导致 -a "" 兜底失效）。
export VISUAL='nvim'
export EDITOR="$VISUAL"

unset -f bash_prepend_path
