# dotfiles

## 選擇桌面

| 功能 | Niri 26.04（Noctalia） | GNOME Shell 50.4（Mutter） |
|---|---|---|
| 啟動器 | `Super+D` 開 Noctalia | `Super+R` 開 Vicinae 0.29.2 |
| 剪貼簿歷史 | `Super+Y` 開 Noctalia | `Ctrl+Alt+V` 開 Vicinae |
| 截圖與標註 | `Print` 互動截圖、`Ctrl+Print` 全螢幕、`Alt+Print` 目前視窗。`Super+Shift+Y` 用 Noctalia 標註剪貼簿圖片 | `Ctrl+Print` 選區，截圖後進入 Gradia 1.14.0 |
| 頂欄監控 | Noctalia 顯示 CPU、記憶體與網速 | GNOME Shell 擴充套件 Astra Monitor v43 |
| 中文輸入 | Fcitx 5 + Rime | IBus 1.5.34-4.fc44 + ibus-rime 1.6.0-2.fc44 |

在倉庫根目錄執行 `./install.sh` 會依目前的 Niri 或 GNOME 工作階段選擇配置。新機、TTY 或 SSH 中可直接指定桌面。先安裝該桌面所需的軟體，腳本負責連結設定檔。

每個模式都會部署 kitty、Bash、Emacs、Dolphin（`kde`）、Neovim 和 Yazi 的設定。

| 命令 | 額外部署的桌面設定 |
|---|---|
| `./install.sh niri` | `niri`、`noctalia` |
| `./install.sh gnome` | `gnome`、`vicinae` |
| `./install.sh all` | 上述兩套桌面的設定 |

切換參數只會補上所選配置，會保留先前部署的另一套桌面。若只想加裝個別工具，安裝 GNU Stow 後可執行 `stow --no-folding -t "$HOME" nvim`，將 `nvim` 換成所需的包名。[GNU Stow 手冊](https://www.gnu.org/software/stow/manual/html_node/Invoking-Stow.html)

## Niri 與 Noctalia

安裝 Niri、Noctalia、kitty、Fcitx 5 及其 Rime 引擎。剪貼簿圖片標註另用 wl-clipboard 的 `wl-paste`。連結設定後執行以下命令，兩個服務會在下次登入 Niri 時啟動。

```bash
systemctl --user daemon-reload
systemctl --user enable noctalia.service fcitx5-niri.service
```

- `Super+T` 開 kitty，`Super+S` 開控制中心，`Super+N` 看通知，`Super+Alt+L` 用 swaylock 鎖屏。[Niri 快捷鍵](niri/.config/niri/config.kdl)
- Niri 用 Papers 開 PDF、Loupe 開 PNG 和 JPEG。登入時啟動 KDE Connect 指示器。[預設應用](niri/.config/niri-mimeapps.list)
- Noctalia 的頂欄與閒置動作由 `noctalia` 包管理。GUI 修改寫入 `~/.local/state/noctalia/settings.toml`，同名設定以該檔為準。[Noctalia 設定](noctalia/.config/noctalia/config.toml)

閒置 10 分鐘後播放 `~/Videos/bubbles-loop.webm`，移動滑鼠、點擊或按鍵即可退出。泡泡屏保依賴 GJS、GTK 3 layer-shell 和 GStreamer（Matroska、VP8、gtkwaylandsink）。重建影片才需要 NumPy、Pillow 和支援 libvpx 的 FFmpeg。[影片生成器](noctalia/.local/share/bubble-screensaver/render.py)

頂欄的中英文指示器需用 C 編譯器、pkg-config 和 GLib 開發檔重建。Fedora 對應套件為 `gcc`、`pkgconf-pkg-config`、`glib2-devel`。

```bash
mkdir -p ~/.local/libexec
cc -O2 ~/.local/share/noctalia/plugins/panel-status/fcitx-mode.c \
  $(pkg-config --cflags --libs gio-2.0) -o ~/.local/libexec/waybar-fcitx-mode
```

## GNOME Shell

### 啟動器、剪貼簿與截圖

安裝 Vicinae（Terra）後，在 GNOME 工作階段執行以下命令。恢復腳本會從 Flathub 補裝 Gradia，並將 GNOME 自訂快捷鍵清單設為上表的三項（`custom0` 至 `custom2`）。[快捷鍵恢復腳本](gnome/.local/bin/gnome-shortcuts-restore)

```bash
~/.local/bin/gnome-shortcuts-restore
systemctl --user enable --now vicinae.service
```

同一帳號也用 Niri 時，Fedora 的 `vicinae.service` 預設跟隨 `graphical-session.target`。本機在 `~/.config/systemd/user/vicinae.service.d/override.conf` 加入以下條件以跳過 Niri。此檔需另行配置，更動後執行 `systemctl --user daemon-reload`。

```ini
[Unit]
ConditionEnvironment=!XDG_CURRENT_DESKTOP=niri
```

Vicinae 的剪貼簿與視窗切換透過 GNOME Shell 擴充套件 `vicinae@dagimg-dot` 存取。安裝後登出再登入，在 Extensions 啟用。

```bash
curl -sL -o /tmp/vicinae-ext.zip 'https://github.com/vicinaehq/gnome-extension/releases/latest/download/vicinae%40dagimg-dot.shell-extension.zip' \
  && gnome-extensions install --force /tmp/vicinae-ext.zip
```

GNOME 50 的自訂快捷鍵 `binding` 使用字串（如 `'<Super>r'`）。腳本命令位於 `~/.local/share/vicinae/scripts/`。Vicinae 的 `settings.json` 透過 `imports` 載入 `dotfiles.json`，GUI 存檔會原子替換 `settings.json`，其中的值優先。剪貼簿、索引與主題由應用管理。新機從商店重裝 Process Manager、Systemd、Kill Port。

### 頂欄監控

Astra Monitor（`monitor@astraext.github.io`，快照 v43 / EGO 62）顯示 CPU 與磁碟 I/O 的 20 px 曲線，以及記憶體百分比。執行 `~/.local/bin/astra-monitor-restore` 安裝擴充套件並匯入 dconf。首次安裝若未啟用，登出再登入後重跑。修改設定後可回存快照。

```bash
dconf dump /org/gnome/shell/extensions/astra-monitor/ > ~/dotfiles/gnome/.config/gnome-extensions/astra-monitor.dconf
```

記憶體剩餘低於 1.5 GB 時圖示變紅。在 CPU 選單懸停 User/System 可看 I/O wait，持續高於 5% 時可進一步排查磁碟 I/O。[Astra Monitor 設定](gnome/.config/gnome-extensions/astra-monitor.dconf)

### Dolphin 外觀與升級檢查

兩套桌面共用 `kde` 包的 Papirus-Dark 圖示設定及 `dolphinrc`。GNOME 模式另附外觀恢復腳本。執行 `~/.local/bin/dolphin-gnome-restore`，為 Qt 的 Breeze 圖示主題建立影子主題，將四個視窗按鈕換成 Adwaita 圖示。缺少 Papirus 時腳本會提示安裝方式。重開 Dolphin 生效，還原用 `~/.local/bin/dolphin-gnome-restore --uninstall`。[外觀恢復腳本](kde/.local/bin/dolphin-gnome-restore)

- Fedora 或 GNOME 大版本升級後，重跑外觀腳本並確認 Dolphin 的最小化、最大化與關閉按鈕。
- Fedora 大版本升級後，修改 ibus-rime 設定前先執行 `rime_deployer --sync` 同步詞庫。

## 共用與按需工具

以下是共用工具與選用依賴的本機版本。Fedora 44（核心 6.19.6-300.fc44）基線記於 2026-09-04，11-07 補記 Dolphin，11-24 核對桌面與 kitty。

| 組件 | 版本 |
|---|---|
| 終端 | kitty 0.50.0，使用 `splits` 佈局與自訂分頁列。[快捷鍵與工作區](kitty/.config/kitty/README.md) |
| Bash 行編輯器 | ble.sh 0.4 nightly（由 `install.sh` 安裝至 XDG data 目錄） |
| 編輯器 | GNU Emacs 30.2（原生 package.el + use-package 模組化配置） |
| 編輯器／文檔閱讀 | Neovim 0.12.5（Markdown、Typst、LaTeX 預覽及 Codex 側欄，插件由內建 vim.pack 管理） |
| 字體 | Maple Mono NF CN（主字體）+ Noto Sans Mono CJK SC 兜底；斜體楷體用 LXGW WenKai Mono（GitHub lxgw/LxgwWenKai v1.530，手動下載至 ~/.local/share/fonts，不入庫） |
| 文件管理器 | yazi 26.9.1（插件由 ya pkg 管理）+ swayimg 5.6 / ffmpegthumbnailer 2.3（dnf；畫廊式看圖與視頻首幀） |
| 圖形檔案管理器 | Dolphin 26.08.1（Qt 6.11 / KF6）。`kde` 包讓 Dolphin 處理 FileManager1 的 D-Bus 請求，並指定 kitty 為 KDE 終端。 |

### kitty 升級後檢查

1. 在 kitty 按 `Ctrl+Shift+F6` 查看載入的設定，用 `Ctrl+Shift+Enter` 向右分割、`Ctrl+Shift+E` 向下分割。
2. 在窗格內啟動受監視的 agent，確認分頁列顯示狀態。每個 kitty 程序的快照預設寫在 `~/.local/state/kitty-herd/current.<pid>.json`，狀態轉換記錄在同目錄下的 `transitions.jsonl`。設定了 `XDG_STATE_HOME` 時，以該目錄為準。
3. 在 kitty 切換 Rime 中英文模式，確認分頁列徽章與游標顏色跟著改變。

### Neovim 使用指南

在程式碼中選取文字，依次按 **空格、a、a** 即可帶著選區開啟 Codex 側欄，`Ctrl+s` 送出，`空格 at` 收起或展開。新機需備妥已登入的 Codex CLI 和 `codex-acp`。[Agentic 指南](nvim/.config/nvim/agentic.nvim.help.md)

Markdown 用 render-markdown，Typst 用 Markview。Kitty 中的 Snacks 可行內顯示公式與 Mermaid 圖，分別需要對應的排版工具（`typst`、`pdflatex` 或 `tectonic`）及 `mmdc`。[Typst 測試文件](nvim/tests/typst-hybrid.typ) · [LaTeX 測試文件](nvim/tests/latex-hybrid.tex)

| 要做什麼 | 使用指南 |
|---|---|
| 找檔案、搜尋內容、編輯程式碼 | [Snacks](nvim/.config/nvim/snacks.nvim.help.md) · [mini.nvim](nvim/.config/nvim/mini.nvim.help.md) |
| 查看改動、暫存與提交 | [Gitsigns](nvim/.config/nvim/gitsigns.nvim.help.md) · [Neogit](nvim/.config/nvim/neogit.help.md) |
| 閱讀 Markdown、預覽 Typst | [render-markdown](nvim/.config/nvim/render-markdown.nvim.help.md) · [Markview](nvim/.config/nvim/markview.nvim.help.md) |
| 查快捷鍵、摺疊程式碼、看狀態欄 | [which-key](nvim/.config/nvim/which-key.nvim.help.md) · [Treesitter](nvim/.config/nvim/nvim-treesitter.help.md) · [lualine](nvim/.config/nvim/lualine.nvim.help.md) |

### Emacs

Emacs 配置按主責拆分，每個套件只由一個模組擁有；套件下載、原生編譯、
Tree-sitter grammar、工具虛擬環境及會話資料仍留在 `~/.emacs.d/`，不進倉庫。
修改後可用以下命令驗證完整啟動：

```bash
emacs --batch -Q --load ~/.emacs.d/init.el --eval '(message "Emacs config OK")'
```

### Yazi

Yazi 看圖走兩條路：終端內快速預覽（T 最大化後 j/k 上下張、+/- 縮放，官方
toggle-pane/zoom 插件）；GUI 式體驗按 <C-t> 開 swayimg 畫廊（PgDn/PgUp 翻頁、
縮放保留、方向鍵/拖動平移、Enter 畫廊↔單圖、Esc 回 yazi）。swayimg 與
ffmpegthumbnailer（視頻首幀）由 dnf 安裝，不入庫；插件本體在
~/.config/yazi/plugins 由 ya pkg 下載，清單記於 package.toml，新機先裝 yazi
再 `ya pkg install` 復原。

### Bash

Bash 只在家目录保留其固定入口 `~/.bash_profile` 与 `~/.bashrc`；实际配置
位于 `~/.config/bash/`。命令历史属于 state，`install.sh` 会在目标尚不存在时
将 `~/.bash_history` 一次性迁到 `${XDG_STATE_HOME:-~/.local/state}/bash/history`，
不会把历史提交进仓库。

ble.sh 的程式檔屬於外部依賴，不進 dotfiles；`install.sh` 會在尚未安裝時從
官方 nightly release 下載至 `${XDG_DATA_HOME:-~/.local/share}/blesh`，重跑時保留
既有安裝。下載需要 `curl`、`tar` 與 `xz`。fzf、zoxide、Starship 仍由系統或
各自安裝器管理；缺少時部署腳本會提示，對應 Bash 模組則靜默跳過。

### Dolphin

KConfig 會沿軟連結寫回 `kdeglobals` 和 `dolphinrc`。`Version` 與 `ViewPropsTimestamp` 會由 Dolphin 自動更新，提交前用 `git diff` 確認變更。

## 佈局

每個設定包內的路徑都相對於家目錄。

```
kitty/
  .config/kitty/kitty.conf            → 字型、分屏、快捷鍵及啟動會話
  .config/kitty/tab_bar.py            → 自訂分頁列
  .config/kitty/terminal_watcher.py   → 輸入法狀態與游標顏色
  .config/kitty/agent_monitor.py      → agent 狀態、未讀數與通知
  .config/kitty/workflow_keys.py      → 工作區選單、中文草稿窗與窗格移動
  .config/kitty/README.md             → 操作指南與遷移鍵位對照
  .config/environment.d/60-default-terminal.conf → 設定 TERMINAL=kitty
  .config/xdg-terminals.list          → XDG 預設終端 kitty.desktop

bash/
  .bash_profile                       → ~/.bash_profile（Bash 固定的登录入口）
  .bashrc                             → ~/.bashrc（薄入口，加载 XDG 模块）
  .config/bash/env.bash               → PATH 与环境变量
  .config/bash/history.bash           → XDG 命令历史路径
  .config/bash/aliases.bash           → 个人 alias
  .config/bash/navigation.bash        → zoxide 目录导航
  .config/bash/fuzzy.bash             → fzf 快捷键后备配置
  .config/bash/line-editor.bash       → ble.sh detached 预加载
  .config/bash/prompt.bash            → Starship 提示符
  .config/blesh/init.sh               → ble.sh 的 fzf 与 bash-preexec 相容整合

emacs/
  .emacs.d/init.el                    → ~/.emacs.d/init.el（啟動、套件清單、模組載入）
  .emacs.d/lisp/init-minibuffer.el    → minibuffer 補全、搜尋與候選操作
  .emacs.d/lisp/init-editing.el       → 一般編輯行為與 in-buffer 工具（snippets、Corfu、paredit）
  .emacs.d/lisp/init-docs.el          → 長文檔格式：Markdown（含表格預覽、Dirvish 預覽 hook）與 PDF
  .emacs.d/lisp/init-ui.el            → frame 視覺：modeline、Tab Bar、主題、字體與圖標
  .emacs.d/lisp/init-project.el       → project、Dired、Magit、會話恢復
  .emacs.d/lisp/init-dashboard.el     → 啟動螢幕（Restore 按鈕依賴 init-project 的會話恢復）
  .emacs.d/lisp/init-terminal.el      → 專案終端面板（Vterm，C-x w t）與 ansi-color
  .emacs.d/lisp/init-programming.el   → Tree-sitter、Eglot、格式化、測試與除錯
  .emacs.d/snippets/                  → 個人 YASnippet 模板
  .emacs.d/tools/                     → Node/Python 工具的可重建版本清單

nvim/
  .config/nvim/init.lua               → 編輯、文檔預覽、Git 與 Codex 側欄配置
  .config/nvim/nvim-pack-lock.json    → vim.pack 鎖定的 10 個插件版本
  .config/nvim/*.help.md              → 各插件的本機快捷鍵與使用指南
  tests/                              → Typst 與 LaTeX 混合預覽測試文件

yazi/
  .config/yazi/keymap.toml            → 增量鍵位：<C-t> 開 swayimg 縮略圖畫廊、T 預覽最大化、+/- 預覽縮放
  .config/yazi/yazi.toml              → 預覽尺寸上限 2000×2000（zoom 插件放大不被截斷）
  .config/yazi/package.toml           → ya pkg 插件清單（toggle-pane/zoom/thumbnail），新機 ya pkg install 復原

niri/
  .config/niri/config.kdl             → Niri 快捷鍵、視窗規則與啟動項
  .config/niri-mimeapps.list          → Niri 的預設應用
  .config/systemd/user/fcitx5-niri.service → Niri 工作階段的輸入法

noctalia/
  .config/noctalia/config.toml        → Niri 的頂欄與閒置動作
  .local/share/noctalia/plugins/panel-status/ → 輸入狀態與網速
  .local/bin/screensaver              → 閒置時播放泡泡屏保

vicinae/
  .config/vicinae/dotfiles.json       → 我們的基礎配置（遙測關/緊湊模式/無時鐘），經 settings.json 的 imports 引入
  .local/share/vicinae/scripts/       → 腳本命令：\gh/\bili/\tr 網搜（反斜杠前綴避免搶排名）（@vicinae.* 註解式，percentEncoded）

gnome/
  .config/gnome-extensions/astra-monitor.dconf → Astra Monitor 的 dconf 非默認鍵快照（dconf dump 產物，改設置後需重新 dump）
  .local/bin/gnome-shortcuts-restore           → 安裝 Gradia 並恢復 Vicinae/Gradia 的 GNOME 全局快捷鍵
  .local/bin/astra-monitor-restore             → 一鍵恢復：裝擴展 → dconf load → 啓用（冪等）

kde/
  .config/kdeglobals                  → KDE 全域設定：`[Icons] Theme=Papirus-Dark`（KConfig 寫入會跟隨軟鏈）
  .config/dolphinrc                   → Dolphin 設定（MenuBar=Disabled 等；`Version`/`ViewPropsTimestamp` 是 KDE 會更新的 state 值）
  .local/bin/dolphin-gnome-restore    → 產生 GNOME 視窗按鈕用的 breeze 影子主題（冪等；`--uninstall` 還原）
```

## 日常

- 直接修改已連結的設定檔，再用 `git -C ~/dotfiles status` 查看改動。
- 新增工具時，依家目錄的相對路徑建立設定包，從倉庫根目錄用 Stow 連結該包。
- 提交用 `cd ~/dotfiles && git add -A && git commit`。

## 原則

- 只有 **config** 進倉庫；**state**（~/.local/state/）和快取永不入庫
- 手工 `.bak.日期` 備份壽終正寢——git history 就是備份
