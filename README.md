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
| 終端 | wezterm **20260901 nightly**（非 distro 稳定版，坑位记录见 herd.lua 档头） |
| 輸入法 | ibus 1.5.34-4.fc44 + ibus-rime 1.6.0-2.fc44 |
| 字體 | Maple Mono NF CN（主字體）+ Noto Sans Mono CJK SC 兜底 |

### 升級後檢查清單

1. `wezterm show-keys | grep Split` 有輸出 → 配置載入正常（含 require herd）
2. `tail /tmp/herd-debug.log` 有新 `armed` → 監視鏈存活
3. 中英切換時游標色跟隨 → rime 自癒（ime_heal）還適用；
   **注意**：ime_heal 的實測環境寫在 wezterm.lua 該段註解裏
   （gnome-shell/mutter/ibus 版本敏感），升級後若行爲異常先看那裏
4. Fedora 大版本升級後：ibus-rime 的 userdb 建議先 `rime_deployer --sync`
   再動配置，避免詞庫損傷

## 佈局

每個工具一個「包」目錄，內部結構 = 家目錄相對路徑：

```
wezterm/
  .wezterm.lua                 → ~/.wezterm.lua（本 build 不認 XDG 路徑）
  .config/wezterm/herd.lua     → ~/.config/wezterm/herd.lua
```

## 日常

- **編輯**：直接改 live 路徑或倉庫路徑都一樣（同一個檔案），改完即生效
- **提交**：`cd ~/dotfiles && git add -A && git commit`
- **新機器（Linux）**：`git clone … ~/dotfiles && ~/dotfiles/install.sh`
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
