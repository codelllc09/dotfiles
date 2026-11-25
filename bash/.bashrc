# Bash 不原生支持 XDG 启动文件，因此这里只保留一个薄入口。
bash_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bash"

# 提前加载 ble.sh 核心，让系统级 shell integration 使用 blehook；
[ -r "$bash_config_dir/line-editor.bash" ] && source "$bash_config_dir/line-editor.bash"

# 加载系统配置
if [ -r /etc/bashrc ]; then
  source /etc/bashrc
fi

# secret.bash, env.local.bash 需手动创建并管理，权限为 600。
for bash_config_file in \
  "$bash_config_dir/env.bash" \
  "$bash_config_dir/env.local.bash" \
  "$bash_config_dir/secret.bash" \
  "$bash_config_dir/history.bash" \
  "$bash_config_dir/aliases.bash" \
  "$bash_config_dir/navigation.bash" \
  "$bash_config_dir/fuzzy.bash" \
  "$bash_config_dir/prompt.bash" \
  "$bash_config_dir/dsh-theme.bash" \
  "$bash_config_dir/options.bash"
do
  [ -r "$bash_config_file" ] && source "$bash_config_file"
done

# 若已加载 ble.sh，则启用其行编辑器。
[[ ! ${BLE_VERSION-} ]] || ble-attach
# 清理配置加载时使用的临时变量。
unset bash_config_dir bash_config_file

