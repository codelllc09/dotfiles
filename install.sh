#!/bin/bash
# 按桌面将选定包中的配置逐文件链接到家目录。
set -euo pipefail

usage() {
  cat <<'EOF'
用法：./install.sh [niri|gnome|all]
各模式均部署 kitty、Bash、Emacs、Dolphin（kde）、Neovim、Yazi 的配置。
  niri   加上 niri、noctalia
  gnome  加上 gnome、vicinae
  all    加上两套桌面的配置
省略参数时识别当前桌面，无法识别时请明确指定。
请从 Git 工作副本部署。遇到目标冲突时保留原文件，汇总后以状态 1 退出。
EOF
}

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

if (( $# == 0 )); then
  session=${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}
  case ":${session,,}:" in
    *:niri:*) profile=niri ;;
    *:gnome:*) profile=gnome ;;
    *)
      echo "无法识别当前桌面，请指定 niri 或 gnome。" >&2
      usage >&2
      exit 2
      ;;
  esac
else
  profile=$1
fi

niri_packages=(niri noctalia)
gnome_packages=(gnome vicinae)
packages=(kitty bash emacs kde nvim yazi)
case "$profile" in
  niri)  packages+=("${niri_packages[@]}") ;;
  gnome) packages+=("${gnome_packages[@]}") ;;
  all)   packages+=("${niri_packages[@]}" "${gnome_packages[@]}") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

cd -- "$(dirname -- "$0")"
repo_root=$PWD
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
conflicts=()
install_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX")
finish_install() {
  local status=$?
  rm -rf -- "$install_tmp_dir"
  if (( ${#conflicts[@]} )); then
    printf '已保留 %d 个冲突目标，请比较后再部署：\n' "${#conflicts[@]}" >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    (( status != 0 )) || status=1
  fi
  exit "$status"
}
trap finish_install EXIT

install_blesh() {
  local blesh_file="$data_home/blesh/ble.sh"
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

  echo "下载并安装 ble.sh 到 $data_home/blesh"
  curl --fail --location --retry 3 \
    --output "$install_tmp_dir/ble-nightly.tar.xz" \
    https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz
  tar -xJf "$install_tmp_dir/ble-nightly.tar.xz" -C "$install_tmp_dir"
  bash "$install_tmp_dir/ble-nightly/ble.sh" --install "$data_home"

  if [ ! -r "$blesh_file" ]; then
    echo "ble.sh 安装完成，但未找到预期文件: $blesh_file" >&2
    return 1
  fi
  echo "安装 ble.sh: $blesh_file"
}

report_optional_shell_tools() {
  local tool
  for tool in fzf zoxide starship; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "提示：未安装 $tool；相关 Bash 功能会静默跳过。" >&2
    fi
  done
}

link_config() {
  local src="$repo_root/$1" relative=${1#*/} dst
  [[ -f $src ]] || return 0
  case "$relative" in
    .config/*) dst="$config_home/${relative#.config/}" ;;
    .local/share/*) dst="$data_home/${relative#.local/share/}" ;;
    *) dst="$HOME/$relative" ;;
  esac

  [[ $dst -ef $src ]] && return 0
  if [[ -L $dst ]]; then
    conflicts+=("$dst -> $(readlink -- "$dst")（仓库来源：$src）")
  elif [[ -e $dst ]]; then
    conflicts+=("$dst（仓库来源：$src）")
  else
    if ! mkdir -p -- "${dst%/*}"; then
      conflicts+=("无法创建目标目录 ${dst%/*}（仓库来源：$src）")
      return 0
    fi
    ln -sT -- "$src" "$dst"
    echo "链接: $dst -> $src"
  fi
}

echo "部署 $profile 配置：${packages[*]}"
exclude_paths=(':(exclude)nvim/tests/**')
if [[ $profile == niri ]]; then
  exclude_paths+=(':(exclude)kde/.local/bin/dolphin-gnome-restore')
fi
git ls-files -z -- "${packages[@]}" "${exclude_paths[@]}" > "$install_tmp_dir/files"
while IFS= read -r -d '' file; do
  link_config "$file"
done < "$install_tmp_dir/files"

# 两个本机配置由 Git 忽略，存在时随 Bash 模块一起部署。
for file in env.local.bash secret.bash; do
  link_config "bash/.config/bash/$file"
done

if [[ $profile == all ]]; then
  # 2026-09：WezTerm 主配置已迁到 XDG 路径。仅清理由本仓库旧布局
  # 创建的 ~/.wezterm.lua 链接；真实文件或其他来源的链接一律不碰。
  legacy_wezterm="$HOME/.wezterm.lua"
  legacy_wezterm_target="$repo_root/wezterm/.wezterm.lua"
  if [ -L "$legacy_wezterm" ] && [ "$(readlink "$legacy_wezterm")" = "$legacy_wezterm_target" ]; then
    unlink "$legacy_wezterm"
    echo "移除旧链接: $legacy_wezterm"
  fi
fi

# Bash 历史是 state，不进入 dotfiles。首次部署时把传统路径迁到
# XDG_STATE_HOME；若两边都存在则不自动合并，避免覆盖历史。
bash_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
bash_state_dir="$bash_state_home/bash"
legacy_bash_history="$HOME/.bash_history"
xdg_bash_history="$bash_state_dir/history"
mkdir -p "$bash_state_dir"
if [[ -L $legacy_bash_history ]]; then
  echo "保留 Bash 历史软链接：$legacy_bash_history -> $(readlink -- "$legacy_bash_history")"
elif [[ -f $legacy_bash_history ]]; then
  if [[ ! -e $xdg_bash_history && ! -L $xdg_bash_history ]]; then
    mv -nT -- "$legacy_bash_history" "$xdg_bash_history"
  fi
  if [[ -f $legacy_bash_history ]]; then
    echo "保留旧 Bash 历史（XDG 目标已存在，请手动合并）: $legacy_bash_history"
  else
    echo "迁移 Bash 历史: $legacy_bash_history -> $xdg_bash_history"
  fi
fi

install_blesh
report_optional_shell_tools
