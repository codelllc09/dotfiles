#!/bin/bash
# 幂等安装：把每个包目录里的文件 symlink 到 $HOME 对应位置。
# 新增包 = 建同名目录、按真实路径摆放文件、重跑本脚本。
# 保护规则：目标处若已存在"真实文件"（非 symlink）则跳过并提示，
# 先手动 mv 进包目录再重跑。
# 需要手動安裝 curl tar xz fzf zoxide vicinae（Terra 倉庫），例如在federa則執行`sudo install ...`

set -euo pipefail
cd "$(dirname "$0")"

blesh_tmp_dir=
cleanup_blesh_tmp() {
  if [ -n "$blesh_tmp_dir" ] && [ -d "$blesh_tmp_dir" ]; then
    rm -rf -- "$blesh_tmp_dir"
  fi
}
trap cleanup_blesh_tmp EXIT

install_blesh() {
  local blesh_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local blesh_file="$blesh_data_home/blesh/ble.sh"
  local required_command

  if [ -r "$blesh_file" ]; then
    echo "保留已安装的 ble.sh: $blesh_file"
    return 0
  fi

  for required_command in curl tar xz; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
      echo "无法安装 ble.sh：缺少命令 $required_command" >&2
      return 1
    fi
  done

  echo "下载并安装 ble.sh 到 $blesh_data_home/blesh"
  blesh_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-blesh.XXXXXX")"
  curl --fail --location --retry 3 \
    --output "$blesh_tmp_dir/ble-nightly.tar.xz" \
    https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz
  tar -xJf "$blesh_tmp_dir/ble-nightly.tar.xz" -C "$blesh_tmp_dir"
  bash "$blesh_tmp_dir/ble-nightly/ble.sh" --install "$blesh_data_home"

  if [ ! -r "$blesh_file" ]; then
    echo "ble.sh 安装完成，但未找到预期文件: $blesh_file" >&2
    return 1
  fi
  echo "安装 ble.sh: $blesh_file"

  cleanup_blesh_tmp
  blesh_tmp_dir=
}

report_optional_shell_tools() {
  local tool
  for tool in fzf zoxide starship; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "提示：未安装 $tool；相关 Bash 功能会静默跳过。" >&2
    fi
  done
}

# 2026-09：WezTerm 主配置已迁到 XDG 路径。仅清理由本仓库旧布局
# 创建的 ~/.wezterm.lua 链接；真实文件或其他来源的链接一律不碰。
repo_root="$(pwd)"
legacy_wezterm="$HOME/.wezterm.lua"
legacy_wezterm_target="$repo_root/wezterm/.wezterm.lua"
if [ -L "$legacy_wezterm" ] && [ "$(readlink "$legacy_wezterm")" = "$legacy_wezterm_target" ]; then
  unlink "$legacy_wezterm"
  echo "移除旧链接: $legacy_wezterm"
fi

# Bash 历史是 state，不进入 dotfiles。首次部署时把传统路径迁到
# XDG_STATE_HOME；若两边都存在则不自动合并，避免覆盖历史。
bash_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
bash_state_dir="$bash_state_home/bash"
legacy_bash_history="$HOME/.bash_history"
xdg_bash_history="$bash_state_dir/history"
mkdir -p "$bash_state_dir"
if [ -f "$legacy_bash_history" ] && [ ! -e "$xdg_bash_history" ]; then
  mv "$legacy_bash_history" "$xdg_bash_history"
  echo "迁移 Bash 历史: $legacy_bash_history -> $xdg_bash_history"
elif [ -f "$legacy_bash_history" ] && [ -e "$xdg_bash_history" ]; then
  echo "保留旧 Bash 历史（XDG 目标已存在，请手动合并）: $legacy_bash_history"
fi

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

install_blesh
report_optional_shell_tools
