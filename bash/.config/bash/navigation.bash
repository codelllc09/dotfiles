# zoxide 根据使用频率提供 z / zi 目录跳转。
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
