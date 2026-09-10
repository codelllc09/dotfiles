# GPaste 剪貼板歷史 → 命令行插入。
# Alt+V / Alt+G:彈出 fzf 選一條,選中後直接插入到當前光標處(Win+V 式)。
# Alt+G 備選:在 Emacs vterm 裏 Alt+V 會被 Emacs 的向下翻頁搶走,用 Alt+G。
if command -v gpaste-client >/dev/null 2>&1; then
  __gsel_insert() {
      local idx content
      idx=$(gpaste-client --oneline --use-index \
          | fzf --height=40% --reverse --header='GPaste: Enter=插入到命令行  Esc=取消' \
          | sed -n 's/^\([0-9]*\):.*/\1/p')
      [ -n "$idx" ] || return 0
      # 同步把該條設爲當前剪貼板,便於之後在別處粘貼
      gpaste-client --use-index select "$idx" >/dev/null 2>&1
      content=$(gpaste-client --use-index get "$idx")
      READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${content}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$((READLINE_POINT + ${#content}))
  }
  bind -x '"\ev": __gsel_insert'
  bind -x '"\eg": __gsel_insert'
fi
