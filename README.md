# dotfiles

單一真相倉庫 + symlink 農場。佈局相容 GNU Stow（`sudo dnf install stow`
後可用 `stow wezterm` 取代 install.sh）。

## 已驗證環境快照（2026-09-04）

本倉庫配置與下列版本深度耦合（尤其 wezterm nightly 和 rime 自癒邏輯），
跨發行版/跨大版本**不保證可用**，系統大版本升級後請按下方清單驗收：

| 組件 | 版本 |
|---|---|
| 發行版 | Fedora 44 (Forty Four)，內核 6.19.6-300.fc44 |
| 桌面 | GNOME Shell 50.4 · Wayland（mutter） |
| 終端 | wezterm **20260901 nightly**（非 distro 稳定版，坑位记录见 agent_monitor.lua 档头） |
| Bash 行編輯器 | ble.sh 0.4 nightly（由 `install.sh` 安裝至 XDG data 目錄） |
| 編輯器 | GNU Emacs 30.2（原生 package.el + use-package 模組化配置） |
| 輸入法 | ibus 1.5.34-4.fc44 + ibus-rime 1.6.0-2.fc44 |
| 字體 | Maple Mono NF CN（主字體）+ Noto Sans Mono CJK SC 兜底 |

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
  .emacs.d/lisp/init-editing.el       → 一般編輯、buffer 補全、Markdown、PDF
  .emacs.d/lisp/init-ui.el            → Tab Line、工作區、主題、字體與圖標
  .emacs.d/lisp/init-project.el       → project、Dired、Magit、會話與 IDE 面板
  .emacs.d/lisp/init-programming.el   → Tree-sitter、Eglot、格式化、測試與除錯
  .emacs.d/snippets/                  → 個人 YASnippet 模板
  .emacs.d/tools/                     → Node/Python 工具的可重建版本清單
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

Bash 只在家目录保留其固定入口 `~/.bash_profile` 与 `~/.bashrc`；实际配置
位于 `~/.config/bash/`。命令历史属于 state，部署脚本会在目标尚不存在时
将 `~/.bash_history` 一次性迁到 `${XDG_STATE_HOME:-~/.local/state}/bash/history`，
不会把历史提交进仓库。

ble.sh 的程式檔屬於外部依賴，不進 dotfiles；`install.sh` 會在尚未安裝時從
官方 nightly release 下載至 `${XDG_DATA_HOME:-~/.local/share}/blesh`，重跑時保留
既有安裝。下載需要 `curl`、`tar` 與 `xz`。fzf、zoxide、Starship 仍由系統或
各自安裝器管理；缺少時部署腳本會提示，對應 Bash 模組則靜默跳過。

## 日常

- **編輯**：直接改 live 路徑或倉庫路徑都一樣（同一個檔案），改完即生效
- **提交**：`cd ~/dotfiles && git add -A && git commit`
- **新機器（Linux）**：安裝 `curl`、`tar`、`xz` 後，執行
  `git clone … ~/dotfiles && ~/dotfiles/install.sh`；腳本會部署連結並安裝 ble.sh
- **新機器（Windows）**：
  ```powershell
  git clone <repo-url> $env:USERPROFILE\dotfiles
  powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\dotfiles\install.ps1
  ```
  注意兩端語義不同：Linux 是 symlink（倉庫即真身），Windows 是複製（改完要
  commit push，兩端各自 pull 後重跑安裝腳本）
- **新增工具**：`mkdir rime && mv ~/.config/ibus/rime/* rime/` 之類，
  再跑 `./install.sh`（記得加 .gitignore 排除執行期產物）

## 原則

- 只有 **config** 進倉庫；**state**（~/.local/state/）和快取永不入庫
- 手工 `.bak.日期` 備份壽終正寢——git history 就是備份
