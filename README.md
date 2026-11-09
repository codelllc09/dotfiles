# dotfiles

單一真相倉庫 + symlink 農場。佈局相容 GNU Stow（`sudo dnf install stow`
後可用 `stow wezterm` 取代 install.sh）。

## 已驗證環境快照（2026-09-04；2026-11-07 追加 Dolphin）

本倉庫配置與下列版本深度耦合（尤其 wezterm nightly 和 rime 自癒邏輯），
跨發行版/跨大版本**不保證可用**，系統大版本升級後請按下方清單驗收：

| 組件 | 版本 |
|---|---|
| 發行版 | Fedora 44 (Forty Four)，內核 6.19.6-300.fc44 |
| 桌面 | GNOME Shell 50.4 · Wayland（mutter） |
| 終端 | wezterm **20260901 nightly**（非 distro 稳定版，坑位记录见 agent_monitor.lua 档头） |
| Bash 行編輯器 | ble.sh 0.4 nightly（由 `install.sh` 安裝至 XDG data 目錄） |
| 編輯器 | GNU Emacs 30.2（原生 package.el + use-package 模組化配置） |
| 文檔器 | Neovim 0.12.5（render-markdown 閱讀 + mini 六模塊；插件由內置 vim.pack 首啓自動下載） |
| 輸入法 | ibus 1.5.34-4.fc44 + ibus-rime 1.6.0-2.fc44 |
| 字體 | Maple Mono NF CN（主字體）+ Noto Sans Mono CJK SC 兜底；斜體楷體用 LXGW WenKai Mono（GitHub lxgw/LxgwWenKai v1.530，手動下載至 ~/.local/share/fonts，不入庫） |
| 文件管理器 | yazi 26.9.1（插件由 ya pkg 管理）+ swayimg 5.6 / ffmpegthumbnailer 2.3（dnf；畫廊式看圖與視頻首幀） |
| 檔案管理器（GUI） | Dolphin 26.08.1（Qt 6.11 / KF6；GNOME 風格：Papirus-Dark 圖示 + Adwaita 視窗按鈕，見 kde 段） |
| 啟動器 | vicinae 0.29.2（Terra 倉庫；Wayland 熱鍵走 GNOME 自定義快捷鍵，見 vicinae 段） |
| 截圖標註 | Gradia 1.14.0（Flathub；`Ctrl+Print` 走 GNOME 自定義快捷鍵，截圖後自動進入標註） |
| 頂欄監控 | GNOME Shell 擴展 Astra Monitor v43（EGO 62；配置經 dconf 入庫，見 gnome 段） |

### 升級後檢查清單

1. `wezterm show-keys | grep Split` 有輸出 → 配置載入正常（含 require agent_monitor）
2. `tail /tmp/herd-debug.log` 有新 `setup` → agent_monitor 模塊真加載了
   （路徑保留 herd- 前綴；注意 `Configuration Error` 為零不代表模塊在跑——
   pcall 靜默降級會裝沒事，認 setup 留痕）
3. 中英切換時游標色跟隨 → rime 自癒（ime_heal）還適用；
   **注意**：ime_heal 的實測環境寫在 rime.lua 該段註解裏
   （gnome-shell/mutter/ibus 版本敏感），升級後若行爲異常先看那裏
4. Fedora 大版本升級後：ibus-rime 的 userdb 建議先 `rime_deployer --sync`
   再動配置，避免詞庫損傷
5. Fedora/GNOME 大版本升級後：重跑 `~/.local/bin/dolphin-gnome-restore`，
   開 Dolphin 確認視窗按鈕仍是 – □ ✕（Adwaita 圖示路徑可能搬家）

## Niri 與 Noctalia

`niri` 管理 `config.kdl`，`noctalia` 管理頂欄、`panel-status` 插件與屏保腳本。
部署可用 `stow niri noctalia`（在倉庫根目錄執行），或沿用 `install.sh`。
部署後執行 `systemctl --user enable noctalia.service fcitx5-niri.service`。
Fcitx 5 的自啟與 D-Bus 按需啟動皆限於 Niri。
Niri 預設以 Papers 開 PDF、以 Loupe 開 PNG 和 JPEG。`Super+Shift+Y` 匯入剪貼簿圖片進行標註。
Noctalia GUI 的調整存於 `~/.local/state/noctalia/settings.toml`，同名設定以該檔為準。

新機需安裝 Niri、Noctalia、Fcitx 5 Rime、mpv 與 wl-clipboard。屏保素材放在 `~/Videos/screensaver.mp4`。
中英文指示需用 C 編譯器、pkg-config 和 GLib 開發檔（Fedora 的 `gcc`、`pkgconf-pkg-config`、`glib2-devel`）重建：

```bash
mkdir -p ~/.local/libexec
cc -O2 ~/.local/share/noctalia/plugins/panel-status/fcitx-mode.c \
  $(pkg-config --cflags --libs gio-2.0) -o ~/.local/libexec/waybar-fcitx-mode
```

## 佈局

每個工具一個「包」目錄，內部結構 = 家目錄相對路徑：

```
wezterm/
  .config/wezterm/wezterm.lua         → ~/.config/wezterm/wezterm.lua（XDG 主配置：組裝+鍵位）
  .config/wezterm/agent_monitor.lua   → coding agent 狀態監視（前 herd.lua；運行時路徑仍 herd- 前綴）
  .config/wezterm/pane_layout.lua     → 窗格分屏佈局碼（幾何→唯一碼→象形字）
  .config/wezterm/app_icon.lua        → TABn 程序圖標（APP_ICON 表 + 三層歸一化查表）
  .config/wezterm/rime.lua            → Rime 聯動（徽章/游標色/IME 自癒）
  .config/wezterm/quick_select.lua    → QuickSelect 模式表 + DIY 掃描選擇器
  .config/wezterm/compose.lua         → 中文組字緩衝窗鍵位與啟動邏輯
  .config/wezterm/composer.sh         → 中文組字緩衝窗編輯與回填腳本

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
  .config/nvim/init.lua               → ~/.config/nvim/init.lua（文檔查看器定位，全部配置）
  .config/nvim/nvim-pack-lock.json    → vim.pack 插件版本鎖（4 個插件釘 rev，新機首啓自動下載同版本）

yazi/
  .config/yazi/keymap.toml            → 增量鍵位：<C-t> 開 swayimg 縮略圖畫廊、T 預覽最大化、+/- 預覽縮放
  .config/yazi/yazi.toml              → 預覽尺寸上限 2000×2000（zoom 插件放大不被截斷）
  .config/yazi/package.toml           → ya pkg 插件清單（toggle-pane/zoom/thumbnail），新機 ya pkg install 復原

vicinae/
  .config/vicinae/dotfiles.json       → 我們的基礎配置（遙測關/緊湊模式/無時鐘），經 settings.json 的 imports 引入
  .local/share/vicinae/scripts/       → 腳本命令：\gh/\bili/\tr 網搜（反斜杠前綴避免搶排名）（@vicinae.* 註解式，percentEncoded）

gnome/
  .config/gnome-extensions/astra-monitor.dconf → Astra Monitor 的 dconf 非默認鍵快照（dconf dump 產物，改設置後需重新 dump）
  .local/bin/gnome-shortcuts-restore           → 安裝 Gradia 並恢復 Vicinae/Gradia 的 GNOME 全局快捷鍵
  .local/bin/astra-monitor-restore             → 一鍵恢復：裝擴展 → dconf load → 啓用（冪等）

kde/
  .config/kdeglobals                  → KDE 全域設定：`[Icons] Theme=Papirus-Dark`（KConfig 寫入會跟隨軟鏈，見下文）
  .config/dolphinrc                   → Dolphin 設定（MenuBar=Disabled 等；`Version`/`ViewPropsTimestamp` 是 KDE 會更新的 state 值）
  .local/bin/dolphin-gnome-restore    → 產生 GNOME 視窗按鈕用的 breeze 影子主題（冪等；`--uninstall` 還原）
```

v4 模塊化（2026-09-04）：原 476 行單文件按功能拆成上述模塊（教訓：單文件
改一處可能碰壞全局）。各模塊 pcall 引入，壞了只丟對應功能。**改完配置的
可信驗證**（`wezterm cli list` 是假陽性——GUI 活著時只查 server 不 eval）：

```bash
WEZTERM_UNIX_SOCKET=/tmp/chk.sock WEZTERM_LOG=warn wezterm start -e true
```

Emacs 配置按主責拆分，每個套件只由一個模組擁有；套件下載、原生編譯、
Tree-sitter grammar、工具虛擬環境及會話資料仍留在 `~/.emacs.d/`，不進倉庫。
修改後可用以下命令驗證完整啟動：

```bash
emacs --batch -Q --load ~/.emacs.d/init.el --eval '(message "Emacs config OK")'
```

Neovim 定位是「文檔查看器 + 輕量編輯器」：render-markdown（==螢光筆高亮、
代碼塊/行內代碼分色，配 Catppuccin Mocha 色板）+ snacks image 模塊
（WezTerm 不支持 unicode 佔位符，僅懸浮窗預覽：`\i`）+ mini.nvim
（files/pick/icons/pairs/surround/trailspace 六模塊）+ nvim-treesitter
（只爲安裝 json/yaml parser，markdown 系隨 nvim 自帶）。高亮/摺疊用
0.11+ 內置引擎（`vim.treesitter.start()`），無舊式 setup({highlight})。
驗證：`nvim --headless +'lua print(type(MiniPick))' +qa` 輸出 table 即配置健全。

Yazi 看圖走兩條路：終端內快速預覽（T 最大化後 j/k 上下張、+/- 縮放，官方
toggle-pane/zoom 插件）；GUI 式體驗按 <C-t> 開 swayimg 畫廊（PgDn/PgUp 翻頁、
縮放保留、方向鍵/拖動平移、Enter 畫廊↔單圖、Esc 回 yazi）。swayimg 與
ffmpegthumbnailer（視頻首幀）由 dnf 安裝，不入庫；插件本體在
~/.config/yazi/plugins 由 ya pkg 下載，清單記於 package.toml，新機先裝 yazi
再 `ya pkg install` 復原。

Vicinae 是 GNOME Wayland 下的原生 C++/Qt 啟動器（Super+R 呼出，替代
Super 概覽，視頻會議投屏不暴露已開窗口）。**Wayland 坑位**：普通應用不允許
全局抓鍵，熱鍵由 GNOME 自定義快捷鍵承擔（Super+R → `vicinae toggle`），
駐留走 systemd user service，配套 GNOME Shell 擴展（vicinae@dagimg-dot）
經 D-Bus 暴露剪貼板與窗口管理（wm:switch-windows 等）。服務與擴展不落文件；
Vicinae 與 Gradia 的 GNOME 自定義快捷鍵由下列命令聲明，新機恢復：

```bash
~/.local/bin/gnome-shortcuts-restore
systemctl --user enable --now vicinae.service
curl -sL -o /tmp/vicinae-ext.zip 'https://github.com/vicinaehq/gnome-extension/releases/latest/download/vicinae%40dagimg-dot.shell-extension.zip' \
  && gnome-extensions install --force /tmp/vicinae-ext.zip  # 裝完註銷重登，在 Extensions 應用啟用
```

`gnome-shortcuts-restore` 會在缺少時從 Flathub 安裝 Gradia，並以 custom0/custom1
恢復兩個快捷鍵。Gradia 是截圖後編輯器：`Ctrl+Print` 先打開 GNOME 交互式選區，
完成截圖後自動進入 Gradia 標註。應用本體由 Flathub 管理，不進倉庫。

另注意 GNOME 50 起 custom-keybinding 的 `binding` 鍵已改**純字符串**
（`'<Super>r'`），寫舊數組格式 `"['<Super>r']"` 時 g-s-d 會把字面量整個
傳給 Mutter 並**靜默**抓取失敗（僅 journal 可見 `not a valid accelerator`）。
腳本命令在 `~/.local/share/vicinae/scripts/`（由本倉庫 symlink 管理，索引器跟軟鏈）。
**配置文件分工**：GUI 保存設置時會用「臨時文件+原子替換」整個重寫
`settings.json`（軟鏈會被替換成真文件——實測踩過），故本倉庫只管
dotfiles.json 並在 settings.json 的 imports 數組引入（官方推薦模式）；
GUI 改的值落在 settings.json 且優先級高於 imports。主題在 GUI 裏選。
vicinae.db／剪貼板庫／文件索引／主題／snippets 屬 state，不入庫。
商店擴展同屬 state（~/.local/share/vicinae/extensions/），但已裝清單在此登記，
新機從 store 重裝：**Process Manager、Systemd、Kill Port**（2026-10-29 裝）。

頂欄監控用 GNOME Shell 擴展 **Astra Monitor**（`monitor@astraext.github.io`）。
配置不在文件而在 dconf 數據庫，倉庫只存非默認鍵快照
（`gnome/.config/gnome-extensions/astra-monitor.dconf`，`dconf dump` 產物）。
佈局取「緊湊」取向：CPU 圖標+20px 曲線、內存百分比（剩餘 <1.5GB 圖標變紅告警）、
磁盤 IO 速度+20px 曲線；GPU/傳感器/網絡模塊關閉，各實時條關閉。
新機恢復：`~/.local/bin/astra-monitor-restore`（裝擴展 → dconf load → 啓用；
首次安裝需註銷重登讓 Shell 掃描）。改了擴展設置後同步倉庫：
`dconf dump /org/gnome/shell/extensions/astra-monitor/ > ~/dotfiles/gnome/.config/gnome-extensions/astra-monitor.dconf`
。查 iowait：點頂欄 CPU 區開菜單，懸停 User/System 行彈出
「CPU Category Usage Raw Info」，I/O wait 持續 >5% 即 IO 瓶頸信號。

Bash 只在家目录保留其固定入口 `~/.bash_profile` 与 `~/.bashrc`；实际配置
位于 `~/.config/bash/`。命令历史属于 state，部署脚本会在目标尚不存在时
将 `~/.bash_history` 一次性迁到 `${XDG_STATE_HOME:-~/.local/state}/bash/history`，
不会把历史提交进仓库。

ble.sh 的程式檔屬於外部依賴，不進 dotfiles；`install.sh` 會在尚未安裝時從
官方 nightly release 下載至 `${XDG_DATA_HOME:-~/.local/share}/blesh`，重跑時保留
既有安裝。下載需要 `curl`、`tar` 與 `xz`。fzf、zoxide、Starship 仍由系統或
各自安裝器管理；缺少時部署腳本會提示，對應 Bash 模組則靜默跳過。
（剪貼板歷史已改由 Vicinae 承擔，終端外 Ctrl+Alt+V 打開；GPaste/gsel 已退役。）

Dolphin 是 GNOME 桌面上的 KDE 檔案管理器（Dolphin 26.08.1 / Qt 6.11 / KF6）。
Fedora 44 的 Qt 在 GNOME 下會自動採用 GTK3 平台主題（字型、深色配色、游標）與
Adwaita 視窗裝飾，所以真正不一致的只剩圖示與視窗按鈕符號。處理分兩層：

- **文字設定**入 `kdeglobals`（`[Icons] Theme=Papirus-Dark`）與 `dolphinrc`
  （`[MainWindow] MenuBar=Disabled` 等），由 `install.sh` symlink 部署。
  KConfig 保存設定時（`kwriteconfig6` 對兩個檔案實測）會**跟隨**軟鏈寫入目標，
  不會像 Electron 類 GUI 用「臨時檔+原子替換」把軟鏈換成真文件。若哪天發現
  設定檔變成真文件，把真文件 mv 回 `kde/.config/` 再跑 `install.sh` 即可。
  `dolphinrc` 的 `Version`/`ViewPropsTimestamp` 由 Dolphin 自動更新，屬 state；
  提交前 `git diff` 確認，只提交有意義的設定變更。
- **非文字資源**由 `~/.local/bin/dolphin-gnome-restore` 重建（冪等）：
  1. 檢查 Papirus 圖示主題：`sudo dnf install papirus-icon-theme papirus-icon-theme-dark`，
     或手動放到 `~/.local/share/icons/`；主題本體約 400MB，**不入庫**；
  2. 在 `~/.local/share/icons/breeze` 建一個 breeze **影子主題**（152KB）：所有目錄
     symlink 回系統 Breeze，只把 4 個 `window-{minimize,maximize,restore,close}-symbolic.svg`
     覆寫成 Adwaita（GNOME）的 – □ ✕。原因是 Qt 的 Adwaita 窗框外掛按鈕符號取自
     Qt 圖示主題 `breeze`，而 Breeze 的 window-*-symbolic 是 chevron（⌄ ⌃）；
     另 `adwaita-qt6` 已不建議（Fedora 44 無套件、上游年久失修）。

新機恢復：`~/.local/bin/dolphin-gnome-restore`（Papirus 缺會提示 dnf 指令），重開 Dolphin 生效。
同步方式：改圖示/按鈕後 `git -C ~/dotfiles status` 確認 `kde/.config/kdeglobals` 變更；
影子主題屬產生檔，不入庫。還原按鈕：`~/.local/bin/dolphin-gnome-restore --uninstall`。

## 日常

- **編輯**：直接改 live 路徑或倉庫路徑都一樣（同一個檔案），改完即生效
- **提交**：`cd ~/dotfiles && git add -A && git commit`
- **新機器（Linux）**：安裝 `curl`、`tar`、`xz` 後，執行
  `git clone … ~/dotfiles && ~/dotfiles/install.sh`；腳本會部署連結並安裝 ble.sh
- **新增工具**：`mkdir rime && mv ~/.config/ibus/rime/* rime/` 之類，
  再跑 `./install.sh`（記得加 .gitignore 排除執行期產物）

## 原則

- 只有 **config** 進倉庫；**state**（~/.local/state/）和快取永不入庫
- 手工 `.bak.日期` 備份壽終正寢——git history 就是備份
