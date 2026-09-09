# fzf completion 需要先载入 bash-completion。登录 shell 已载入时，此脚本会自行跳过。
if [ -r /etc/profile.d/bash_completion.sh ]; then
  source /etc/profile.d/bash_completion.sh
fi

# 登录 shell 中，Fedora 会在 ~/.bashrc 之前初始化 WezTerm 的 bash-preexec；
# 检测到它时，用 ble.sh 的兼容层接管既有 hooks。
if [[ ${bash_preexec_imported-${__bp_imported-}} ]]; then
  ble-import integration/bash-preexec
fi

# 使用 ble.sh 原生适配，避免普通 Readline bindings 与 ble.sh 冲突。
ble-import -d integration/fzf-completion
ble-import -d integration/fzf-key-bindings

# 不存在或未識別的命令標紅
ble-face syntax_command=fg=red
