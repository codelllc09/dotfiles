# 個人 alias 放在這裏

# 用時間戳建立 Markdown 草稿，並啟用 Neovim 的草稿自動存檔。
_nvim_draft() (
  local draft_dir="$HOME/Document/drafts"
  mkdir -p -- "$draft_dir" && cd -- "$draft_dir" || return

  local draft_file
  if [[ ${1-} == --today ]]; then
    local draft_day lock_dir
    draft_day=$(date +%F) || return
    draft_file="$draft_dir/daily-$draft_day.md"
    lock_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nvim-drafts"
    mkdir -p -- "$lock_dir" || return

    (
      if ! flock -n 9; then
        printf '這份每日草稿已開啟：%s\n' "$draft_file" >&2
        return 1
      fi
      (umask 077; : >> "$draft_file") || return
      nvim '+doautocmd User DraftAutosave' -- "$draft_file" 9>&-
    ) 9>"$lock_dir/$draft_day.lock"
    return
  fi

  if (( $# > 0 )); then
    nvim +startinsert "$@"
    return
  fi

  draft_file=$(mktemp -- "$draft_dir/$(date +%Y-%m-%d_%H-%M-%S)-XXXXXX.md") || return
  nvim '+doautocmd User DraftAutosave' +startinsert -- "$draft_file"
)

alias draft='_nvim_draft'
alias draft-today='_nvim_draft --today'
