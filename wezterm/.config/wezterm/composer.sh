#!/usr/bin/env bash
# composer.sh v3 — 編輯器版中文組字緩衝窗(由 compose.lua 喚起,Ctrl+Shift+I)
# 流程:臨時文件(/dev/shm=tmpfs,純內存零磁盤 I/O)+ 終端編輯器 →
#   保存退出 = 整段「括號粘貼」進 pi 輸入框(默認不自動回車,回 pi 複查後
#              自己按 Enter 發送;COMPOSE_AUTO_SUBMIT=1 則補回車直接發送)
#   :q! / 空文件 = 放棄；回填失敗時可重試或複製草稿。
#   單發即關窗,焦點自動回 pi;要再發一條,再按 Ctrl+Shift+I 即可。
# 編輯鍵:nano 自帶 ^A 行首 / ^E 行尾 / ^K 剪整行;vim/nvim 自動注入同款
#   insert 映射(^A→Home ^E→End ^K→d$),並禁 swap/viminfo(零磁盤寫入)。
# 多行:pi 輸入框原生多行——粘貼的換行會保留;手動換行鍵是 Shift+Enter。
# 發送機制:pi 支持括號粘貼(200~/201~),整段進輸入框不觸發提前提交
#   (已核對 pi 源碼:handlePaste 保留 \n;Enter 爲提交鍵)。
set -u
pane="${1:-}"
[ -z "$pane" ] && { echo "usage: composer.sh <pane_id>"; exit 1; }
command -v wezterm >/dev/null 2>&1 || { echo "wezterm cli not found"; exit 1; }
AUTO_SUBMIT="${COMPOSE_AUTO_SUBMIT:-0}"

# 編輯器選擇:$EDITOR(可含參數,如 "code --wait")→ nano → nvim → vi
pick_editor() {
  local e
  if [ -n "${EDITOR:-}" ] && command -v "${EDITOR%% *}" >/dev/null 2>&1; then
    printf '%s\n' "$EDITOR"; return
  fi
  for e in nano nvim vi; do
    command -v "$e" >/dev/null 2>&1 && { printf '%s\n' "$e"; return; }
  done
}
ed=$(pick_editor)
[ -n "$ed" ] || { echo "no editor available (set \$EDITOR?)"; exit 1; }
read -ra ed_cmd <<<"$ed"
base=$(basename "${ed_cmd[0]}")
extra=()
case "$base" in
  vim|nvim) # vim 家族補 readline 風格 insert 映射,對齊 ^A/^E/^K;
            # -n 不建 swap;-i NONE 不寫 viminfo/shada(那倆在 $HOME,真磁盤)
    extra+=(-n -i NONE
            -c 'inoremap <C-a> <Home>'
            -c 'inoremap <C-e> <End>'
            -c 'inoremap <C-k> <C-o>d$')
    ;;
esac

target=$(printf '%s' "${COMPOSE_DESTINATION:-窗格 #$pane}" | LC_ALL=C tr '\000-\037\177' ' ')
printf '\033]2;compose → %s\007' "$target"
if encoded_target=$(printf '%s' "$target" | base64 -w0); then
  printf '\033]1337;SetUserVar=compose_destination=%s\007' "$encoded_target"
fi
tmp=$(mktemp /dev/shm/compose-XXXXXX.txt) || exit 1
# 2026-11-04:手動關窗(X / C-S-W)時 bash 被 SIGHUP 殺死,rm 永遠走不到 →
# /dev/shm 殘留(實測已累積)。統一走 EXIT trap;HUP/INT/TERM 轉 exit 觸發之。
trap 'rm -f -- "$tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
"${ed_cmd[@]}" ${extra:+"${extra[@]}"} "$tmp" || exit "$?"
# 2026-11-04:$( ) 剝離全部尾換行(nvim 存盤必帶 \n,防粘貼多出空行/空提交);
# 純空白視同放棄。目標已不限 pi(其有 C-g),send-text 按目標窗格 2004 狀態自適應。
content=$(cat -- "$tmp") || exit "$?"
if [ -z "${content//[[:space:]]/}" ]; then # 空文件/純空白(含 :q! 放棄):靜默關窗
  exit 0
fi
pasted=0
while :; do
  if [ "$pasted" = 0 ]; then
    # 走 stdin，避免長稿超過命令列的單一參數大小限制。
    printf '%s' "$content" | wezterm cli --no-auto-start send-text --pane-id "$pane" && pasted=1
  fi
  if [ "$pasted" = 1 ]; then
    if [ "$AUTO_SUBMIT" != 1 ] ||
      wezterm cli --no-auto-start send-text --pane-id "$pane" --no-paste -- $'\r'; then
      exit 0
    fi
    printf '\n稿件已回填，送出回車失敗。請先核對目標窗格：%s\n' "$target"
  else
    printf '\n回填失敗，草稿仍保留。重試前請先核對目標窗格：%s\n' "$target"
  fi

  while :; do
    printf '[r] 重試原窗格  [c] 複製草稿  [q] 捨棄並關窗：'
    IFS= read -r choice || exit 1
    case "$choice" in
      r|R) break ;;
      c|C)
        if clipboard=$(base64 -w0 -- "$tmp"); then
          printf '\033]52;c;%s\007已送出複製請求，草稿仍保留。\n' "$clipboard"
        else
          printf '無法讀取草稿。\n' >&2
        fi
        ;;
      q|Q) exit 0 ;;
    esac
  done
done
