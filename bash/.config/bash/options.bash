# 交互式 Bash 的重定向、通配符、历史及退出行为。
if [[ $- == *i* ]]; then
  set -o noclobber
  shopt -s failglob
  shopt -s checkjobs
  set -o ignoreeof
  shopt -s histappend
  shopt -s globskipdots
fi
