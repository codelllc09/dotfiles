# Bash 不原生支持 XDG 启动文件，因此这里只保留一个薄入口。
bash_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bash"

# 提前加载 ble.sh 核心，让系统级 shell integration 使用 blehook；
# 行编辑器会在其余配置完成后才正式接管终端。
[ -r "$bash_config_dir/line-editor.bash" ] && source "$bash_config_dir/line-editor.bash"

if [ -r /etc/bashrc ]; then
  source /etc/bashrc
fi

for bash_config_file in \
  "$bash_config_dir/env.bash" \
  "$bash_config_dir/history.bash" \
  "$bash_config_dir/aliases.bash" \
  "$bash_config_dir/navigation.bash" \
  "$bash_config_dir/fuzzy.bash" \
  "$bash_config_dir/prompt.bash"
do
  [ -r "$bash_config_file" ] && source "$bash_config_file"
done

[[ ! ${BLE_VERSION-} ]] || ble-attach

unset bash_config_dir bash_config_file
