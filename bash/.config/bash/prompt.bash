# Starship 提示符；未安装时静默使用 Bash 默认提示符。
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
