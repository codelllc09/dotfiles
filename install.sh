#!/bin/bash
# 幂等安装：把每个包目录里的文件 symlink 到 $HOME 对应位置。
# 新增包 = 建同名目录、按真实路径摆放文件、重跑本脚本。
# 保护规则：目标处若已存在"真实文件"（非 symlink）则跳过并提示，
# 先手动 mv 进包目录再重跑。
set -euo pipefail
cd "$(dirname "$0")"
for pkg in */; do
  pkg="${pkg%/}"
  [ -d "$pkg" ] || continue
  find "$pkg" -type f | while IFS= read -r f; do
    src="$(pwd)/$f"
    dst="$HOME/${f#$pkg/}"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "跳过（目标已是真实文件，请先 mv 进包）: $dst"
    else
      ln -sfn "$src" "$dst"
      echo "链接: $dst -> $src"
    fi
  done
done
