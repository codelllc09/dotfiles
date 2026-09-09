#!/usr/bin/env bash
# composer.sh v3 — 編輯器版中文組字緩衝窗(由 compose.lua 喚起,Ctrl+Shift+I)
# 流程:臨時文件(/dev/shm=tmpfs,純內存零磁盤 I/O)+ 終端編輯器 →
#   保存退出 = 整段「括號粘貼」進 pi 輸入框(默認不自動回車,回 pi 複查後
#              自己按 Enter 發送;COMPOSE_AUTO_SUBMIT=1 則補回車直接發送)
#   :q! / 空文件 = 放棄,什麼都不發
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

printf '\033]2;compose - pane %s\007' "$pane"
tmp=$(mktemp /dev/shm/compose-XXXXXX.txt) # tmpfs:全程內存,零磁盤 I/O
"${ed_cmd[@]}" ${extra:+"${extra[@]}"} "$tmp"
if [ ! -s "$tmp" ]; then # 空文件(含 :q! 放棄):靜默關窗
  rm -f "$tmp"
  exit 0
fi
ok=1
# 括號粘貼:整段(含內部換行)進 pi 輸入框,不觸發提交
wezterm cli send-text --pane-id "$pane" -- "$(cat "$tmp")" || ok=0
# 自動提交模式才補回車
if [ "$ok" = 1 ] && [ "$AUTO_SUBMIT" = 1 ]; then
  wezterm cli send-text --pane-id "$pane" --no-paste -- $'\r' || ok=0
fi
rm -f "$tmp"
[ "$ok" = 0 ] && { echo "inject failed: pane $pane may be closed" >&2; sleep 2; exit 1; }
# 成功路徑靜默退出：窗口即關，提示看不見，故不輸出
