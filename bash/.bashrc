# Bash 不原生支持 XDG 启动文件，因此这里只保留一个薄入口。
if [ -r /etc/bashrc ]; then
  source /etc/bashrc
fi

bash_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bash"
for bash_config_file in \
  "$bash_config_dir/env.bash" \
  "$bash_config_dir/aliases.bash" \
  "$bash_config_dir/interactive.bash" \
  "$bash_config_dir/prompt.bash"
do
  [ -r "$bash_config_file" ] && source "$bash_config_file"
done
unset bash_config_dir bash_config_file
