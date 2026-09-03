# dotfiles

單一真相倉庫 + symlink 農場。佈局相容 GNU Stow（`sudo dnf install stow`
後可用 `stow wezterm` 取代 install.sh）。

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
