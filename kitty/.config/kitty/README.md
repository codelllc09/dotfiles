# kitty 操作對照

Fedora 44／niri · kitty 0.50.0 · WezTerm 20260901 nightly · 2026-11-12 核對。

以下比較這台機器的終端鍵位，合併同一鍵的大小寫與符號別名。表中的「—」表示未綁定該終端動作。

## 共用鍵位

- `Ctrl+Shift+Enter` 向右分割，`Ctrl+Shift+E` 向下分割，`Ctrl+Shift+方向鍵` 切到對應的相鄰窗格。`Ctrl+Shift+W` 確認後關目前窗格，`F8` 搬到新視窗。
- `Ctrl+Shift+T` 新分頁，`Ctrl+Shift+N` 新視窗，`Ctrl+Tab`／`Ctrl+Shift+Tab` 切下一頁／上一頁。
- `Ctrl+Shift+C`／`Ctrl+Shift+V` 複製／貼上剪貼簿。`Ctrl+Shift+Home`／`Ctrl+Shift+End` 捲到最上／最下。
- `Ctrl+Shift+O` 開工作區選單。方向鍵選擇，`Tab` 補全，`Enter` 切換或建立，`Esc` 取消。
- `Ctrl+Shift+I` 開中文緩衝窗。儲存並離開編輯器後，草稿貼回原窗格，等手動送出。空稿直接關閉，回填失敗可重試或複製草稿。

## 視窗、分頁與窗格

| 操作 | WezTerm | kitty |
|---|---|---|
| 依序切窗格 | — | `Ctrl+Shift+[`／`Ctrl+Shift+]` |
| 按號碼跳轉 | `Ctrl+Shift+1`～`8` 跳分頁，`Ctrl+Shift+9` 跳最後一頁 | `Ctrl+Shift+1`～`9`、`Ctrl+Shift+0` 跳分頁內的第 1～10 個窗格 |
| 按提示選窗格／交換窗格 | — | `Ctrl+Shift+F7`／`Ctrl+Shift+F8` |
| 調整窗格大小 | `Ctrl+Alt+Shift+方向鍵` | `Ctrl+Shift+R` 進入調整模式 |
| 放大／還原目前窗格 | `Ctrl+Shift+Z` | —，同鍵跳到上一個 shell 提示符 |
| 重排窗格 | — | `Ctrl+Shift+F`／`Ctrl+Shift+B` 向前／向後移，`Ctrl+Shift+反引號` 移到第一個 |
| 切上一／下一分頁的備用鍵 | `Ctrl+PageUp`／`Ctrl+PageDown` | 用 `Ctrl+Shift+Tab`／`Ctrl+Tab` |
| 左／右移分頁 | `Ctrl+Shift+PageUp`／`Ctrl+Shift+PageDown` | `Ctrl+Shift+,`／`Ctrl+Shift+.` |
| 關閉整個分頁 | `Super+W` | `Ctrl+Shift+Q` |
| 重新命名分頁 | — | `Ctrl+Alt+Shift+T`，或雙擊分頁 |
| 全螢幕 | `Alt+Enter` | `Ctrl+Shift+F11` |
| 最大化／隱藏視窗 | `Ctrl+Shift+M` 隱藏 | `Ctrl+Shift+F10` 最大化，隱藏交給桌面 |
| 放大／縮小／重設字型 | `Ctrl+=`／`Ctrl+-`／`Ctrl+0`，也接受 Shift | `Ctrl+Shift+=`／`Ctrl+Shift+-`／`Ctrl+Shift+Backspace` |

WezTerm 另有 `Ctrl+Alt+Shift+5` 向右分割、`Ctrl+Alt+Shift+'` 向下分割。kitty 用上面的共用分割鍵。
關整個分頁時，WezTerm 會詢問確認。kitty 的預設依窗格內是否有命令執行決定是否詢問。

## 回捲、搜尋與剪貼簿

| 操作 | WezTerm | kitty |
|---|---|---|
| 向上／下捲一頁 | `Shift+PageUp`／`Shift+PageDown` | `Ctrl+Shift+PageUp`／`Ctrl+Shift+PageDown` |
| 向上／下捲一行 | — | `Ctrl+Shift+K`／`Ctrl+Shift+J` |
| 清除回捲歷史 | `Ctrl+Shift+K` | —。`Ctrl+Shift+Delete` 是重置終端 |
| 搜尋回捲 | `Ctrl+Shift+F` 在原窗格搜尋 | `Ctrl+Shift+/` 開啟分頁器搜尋，`Ctrl+Shift+F` 改為前移窗格 |
| 鍵盤瀏覽與複製 | `Ctrl+Shift+X` 進複製模式，`Esc` 與搜尋切換，`y` 複製，`Q` 退出 | `Ctrl+Shift+H` 在分頁器瀏覽回捲。`Ctrl+Shift+X` 跳下一個 shell 提示符 |
| 看上一條命令輸出 | — | `Ctrl+Shift+G`。跳提示符和取命令輸出依賴 shell 整合 |
| 貼上滑鼠選取區（Primary Selection） | 中鍵。配置已釋放 `Ctrl+Insert`／`Shift+Insert` | 中鍵、`Ctrl+Shift+S` 或 `Shift+Insert` |
| 選 Unicode 字元 | `Ctrl+Shift+U`，選後複製到剪貼簿及選取區 | `Ctrl+Shift+U`，選後插入目前窗格 |

WezTerm 的搜尋和複製細節見 `~/.config/wezterm/copy-mode.md`。kitty 用內建分頁器，滑鼠選取後可按 `Ctrl+Shift+C` 複製。WezTerm 也綁定鍵盤上的專用 Copy／Paste 鍵。

## 命令、設定與提示選取

| 操作 | WezTerm | kitty |
|---|---|---|
| 命令面板 | `Ctrl+Shift+P` | `Ctrl+Shift+F3` |
| 重載配置 | `Ctrl+Shift+R` | `Ctrl+Shift+F5`，也已啟用自動重載 |
| 偵錯 | `Ctrl+Shift+L` 開偵錯覆蓋層 | `Ctrl+Shift+F6` 顯示配置，`Ctrl+Shift+Esc` 開 kitty 控制命令視窗 |
| 開啟說明／編輯配置 | — | `Ctrl+Shift+F1`／`Ctrl+Shift+F2` |
| 輪換佈局 | — | `Ctrl+Shift+L`。本配置只啟用 splits，沒有其他佈局可輪換 |

kitty 的 `Ctrl+Shift+P` 是提示選取前綴。接 `F` 插入路徑、`Shift+F` 開啟路徑、`C`／`D` 選檔案／目錄、`L` 插入行、`W` 插入詞、`H` 插入雜湊值、`N` 開啟檔案的指定行、`Y` 開啟超連結。WezTerm 配置已停用 QuickSelect。 [kitty 動作參考](https://sw.kovidgoyal.net/kitty/actions/)

kitty 另帶 `Ctrl+Shift+A` 後接 `M`／`L`／`1`／`D` 的透明度鍵，目前動態透明度未啟用。

## 滑鼠與工作區行為

| 操作 | WezTerm | kitty |
|---|---|---|
| 左鍵選取後 | 自動複製到剪貼簿和選取區 | 保留滑鼠選取區，用 `Ctrl+Shift+C` 寫入剪貼簿 |
| 矩形選取 | `Alt`＋左鍵拖曳 | `Ctrl+Alt`＋左鍵拖曳。應用程式接管滑鼠時再加 `Shift` |
| 擴大選取 | `Shift`＋左鍵。矩形擴選再加 `Alt` | 右鍵或 `Shift`＋左鍵。應用程式接管滑鼠時，用 `Shift`＋右鍵擴選 |
| 開啟連結 | 未形成選區時左鍵點擊 | `Ctrl`＋左鍵。預設的 `Shift`／`Ctrl+Shift`＋左鍵也可開啟 |
| 拖動視窗 | `Ctrl+Shift` 或 `Super`＋左鍵拖曳 | 視窗由 niri 移動。分頁可在分頁列上拖曳重排 |
| 觸控板／滾輪 | 普通回捲縮放 0.5 倍。全螢幕程式的替代畫面步進為 2 | 觸控板 0.5 倍，滑鼠滾輪倍率 2.5。由 kitty 的整行捲動處理，停用像素和慣性捲動 |

- kitty 另可用 Alt＋左鍵三擊從行首選取，Ctrl+Alt＋左鍵三擊從點選位置開始。應用程式接管滑鼠時，再加 Shift。
- kitty 的 `Ctrl+Shift`＋右鍵可顯示被點選的命令輸出。分頁列支援單擊切換、雙擊改名、中鍵關分頁。雙擊空白或點 `+` 新建。 [kitty 滑鼠與分頁操作](https://sw.kovidgoyal.net/kitty/overview/)
- **工作區**在 WezTerm 是 mux workspace，在 kitty 是目前程序內的原生 session。kitty 分頁列隨 session 篩選。另開獨立 kitty 程序時，各自管理工作區。kitty 的名稱最多 32 字且不可包含斜線。
- **Rime** 的徽章和四種游標色一致。kitty 直接更新游標色。niri 下使用 Fcitx 5 狀態、Rime 模式檔和系統 Caps Lock 指示燈。
- **Agent** 狀態點、未讀數及通知由定時掃描更新。kitty 以實際取得焦點的窗格判定已讀和抑制通知。狀態存於 `~/.local/state/kitty-herd/`（或 XDG_STATE_HOME 下），每個程序各有 `current.<pid>.json`，歷史為 `transitions.jsonl`。
- **字型**沿用 Maple Mono NF CN 和斜體文楷。kitty 透過 Fontconfig 補缺字，WezTerm 使用配置中的回退順序。

## 檔案與部署

[kitty.conf](kitty.conf) 是入口。此目錄由 dotfiles 的 `kitty/.config/kitty/` 管理，以符號連結部署到 `~/.config/kitty/`。核對實際鍵位可用 kitty 命令面板和 `wezterm show-keys`。
