# Bash 的登录入口固定为 ~/.bash_profile；实际交互配置由 ~/.bashrc 加载。
if [ -r "$HOME/.bashrc" ]; then
  source "$HOME/.bashrc"
fi
