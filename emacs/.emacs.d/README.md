# 原生 Emacs IDE 使用說明

此配置針對 Fedora 44 / Emacs 30.2，保留原生 Emacs 操作。
重新啟動 Emacs 後生效。init.el 是入口；實際功能按主責拆在 lisp/init-*.el。

## 配置結構

- `init.el`：套件來源、可重建工具路徑與模組載入順序。
- `lisp/init-minibuffer.el`：Vertico、Orderless、Marginalia、Consult、Embark、Avy。
- `lisp/init-ime.el`：按命令前綴時，讓 Fcitx 5 切回英文直輸。
- `lisp/init-editing.el`：一般編輯、Corfu、Cape、snippet、多游標、Markdown、PDF。
- `lisp/init-ui.el`：Header Line、工作區 Tab Bar、字體、主題與圖標。
- `lisp/init-project.el`：project.el、Dired、Magit、工作區保存與 IDE 側邊面板。
- `lisp/init-programming.el`：Tree-sitter、Eglot、Flymake、格式化、測試與除錯。

每個套件只有一個主要配置模組；跨模組合作透過 hook 或函式引用完成。

## 已配置的能力

- Vertico / Orderless / Marginalia：命令與檔案候選、多關鍵字匹配、說明。
- Consult / ripgrep：專案搜尋、目前檔案搜尋、buffer 切換與預覽。
- Embark：對候選、檔案、符號或網址直接執行合適操作。
- Avy：用少量按鍵跳到畫面內任意文字位置。
- YASnippet：Python、C/C++、TypeScript/TSX、Lua、Elisp 程式碼片段。
- Cape：在 Eglot/語言模式補全之外提供檔名與 buffer 單字候選。
- multiple-cursors：依相同文字或所選行建立多個游標。
- Paredit：可手動啟用的 Lisp 括號結構與 S-expression 編輯工具。
- tab-bar / desktop.el：內建工作區分頁，以及退出時保存、啟動時恢復會話。
- so-long / VLF：自動降級超長行，並以 1 MB 分塊讀取大型檔案。
- project.el / Dired / Magit：專案、檔案管理、Git。
- Eglot / Corfu / Flymake：補全、跳轉、引用、重新命名、即時診斷。
- Python：Pyright、Ruff 格式化及檢查、pytest、REPL、專案 .venv、Dape/debugpy。
- JS / TS / JSX / TSX：Tree-sitter、TypeScript 語言伺服器、Prettier。
- JS / TS 除錯：Dape + Microsoft js-debug，TS 執行器為 tsx。
- Lua：lua-mode + LuaLS，支援語言分析、補全、跳轉與伺服器格式化。
- TRAMP：SSH 及現有 Podman/Docker 容器內的檔案與程序操作。
- Markdown：官方 markdown-mode 2.8，支援標準 Markdown、GFM、Wiki links、數學語法與 fenced code block 原生高亮。
- EditorConfig、括號配對、行號、快捷鍵提示、最近檔案、位置記憶。

本機程式碼檔案會自動連接已安裝的語言伺服器。
圖形介面的 Eglot buffer 開啟自動補全；其他 buffer 使用 TAB / C-M-i 手動補全。
Emacs 30 終端介面保留內建補全，沒有 Corfu 浮動選單。

## 操作速查

M-x = Alt+x；C-x = Ctrl+x。C-x p f 表示先按 Ctrl+x，再依序按 p、f。
C-g 取消目前操作；輸入前綴後稍等，Which-key 會顯示後續按鍵。
C-h t 開啟內建教學；C-h k 查詢按鍵；C-h f 查詢函式。

| 按鍵 | 操作 |
|---|---|
| C-x C-f / C-x C-s | 開檔 / 儲存 |
| M-x | 執行命令 |
| C-x b | Consult 增強版 buffer 切換（替代同類原生命令） |
| C-x p p / C-x p f | 切換專案 / 專案找檔 |
| C-c f / C-c s | 專案搜尋 / 目前 buffer 搜尋 |
| C-c r | 最近檔案 |
| M-g i / M-g I | Consult 的目前 buffer / 所有 buffer 符號導航 |
| M-g o | 目前文件大綱 |
| C-. / C-; | 對目前候選選擇操作 / 執行預設操作 |
| C-c j | 輸入字元後跳到畫面內標記的位置 |
| C-> / C-< | 加入下一個 / 上一個相同文字的游標 |
| C-c C-< | 標記全部相同文字 |
| C-S-c C-S-c | 在所選的每一行建立游標 |
| C-" / C-: | 多游標選取時跳過下一個 / 上一個匹配 |
| C-, | 複製目前行；有選區時複製選區 |
| M-x paredit-mode | 在目前 Lisp buffer 開關 Paredit 結構編輯 |
| C-x t 2 / C-x t 0 / C-x t o | 新增 / 關閉 / 切換工作區 tab |
| C-x t B / C-x t F | 工作區版面返回 / 前進 |
| TAB（輸入 snippet key 後） | 展開程式碼片段 |
| TAB / C-M-i | 縮排後補全 / 直接補全 |
| M-. / M-, / M-? | 定義 / 返回 / 引用 |
| C-c l l | 手動啟動 Eglot |
| C-c l r / C-c l a | 重新命名 / 程式碼動作 |
| C-c l f | 格式化目前 buffer |
| C-c l c | Ruff 檢查 Python 專案 |
| C-c ! l / C-c ! p | 檔案 / 專案診斷 |
| C-c ! n / C-c ! b | 下一個 / 上一個診斷 |
| C-c g | Magit Git 操作 |
| C-c c | 編譯、執行或測試命令 |
| C-c p t | pytest 測試目前 Python 檔案 |
| C-u C-c p t | pytest 測試整個 Python 專案 |
| C-c t / C-c d | 專案 shell / 檔案管理 |
| C-c v | 指定檔案並以 VLF 分塊開啟 |
| F5 | 選擇並啟動除錯配置 |
| F9 | 切換斷點 |
| F10 / F11 / Shift+F11 | 單步跳過 / 進入 / 跳出（也可用 C-c D n/i/o） |
| C-c D c / C-c D q | 繼續 / 結束除錯 |
| C-x 2 / C-x 3 / C-x 1 | 上下分割 / 左右分割 / 保留目前視窗 |

先開啟 Git 專案內的檔案，再使用專案操作。
C-c p 與 C-x p 都是專案前綴。
JS/TS 專案可用 C-c c 執行 npm test、npm run build 等專案命令。
編譯視窗可點選錯誤；C-x 加反引號鍵跳到下一個錯誤。

## Python 工作流

1. 開啟 Git 專案內的 .py 檔，Eglot 自動啟動。
2. 有專案根目錄的 .venv/bin/python 時，Pyright、REPL、測試、除錯目標會使用它。
3. 沒有 .venv 時，本機使用 Emacs 專用 Python 工具環境。
4. 其他環境（例如 Conda）可用 M-x lcw-select-python 選取 Python 執行檔，
   然後 M-x eglot-reconnect；選擇目前限於該 buffer。
5. 在測試檔按 C-c p t，或加 C-u 執行整個專案；在專案環境安裝 pytest 及專案相依套件。
6. M-x run-python 開 REPL；Python 模式的 C-c C-c 可傳送整個 buffer。
7. F9 設斷點，F5 選 debugpy 執行目前檔案。傳入參數可輸入：
   debugpy :args ["--name" "value"]
8. 模組除錯可選 debugpy-module :module "package.module"。
   pytest 除錯可選 debugpy-module :module "pytest" :args ["-q" "tests/test_example.py"]。

建立新環境的例子（在你的專案目錄執行）：

    python3 -m venv .venv
    .venv/bin/python -m pip install pytest

再依專案的 pyproject.toml 或 requirements.txt 安裝相依套件。
本機 debugpy 裝在工具環境，除錯目標可使用未安裝 debugpy 的 .venv。
格式化為手動觸發，Ruff 讀取專案設定；不會在存檔時批次整理檔案。

## JS / TS / Lua

JS 按 F5 選 js-debug-node；TS 選 js-debug-tsx。
瀏覽器程式有 js-debug-chrome 配置，需要本機 Chromium/Chrome 與實際開發伺服器；
本次只驗證 Node/TS 執行，尚未驗證瀏覽器除錯。React 專案仍需安裝自己的相依套件。

語言伺服器優先找專案的相容 TypeScript，後備使用專用工具目錄的 TypeScript 6。
TypeScript 7 已改變工具布局，不能直接當作目前 tsserver 客戶端的後備；
因此工具目錄固定在相容的 6.x，未修改任何專案的 TypeScript 版本。
專案使用 TS7 時，這個後備分析器不等同 TS7 編譯器，需依專案另行評估。

Lua 的語言服務已配置；Lua 執行器與斷點除錯尚未配置。
Lua 除錯需依實際執行環境選擇，例如獨立 Lua、LuaJIT、Neovim 或遊戲引擎。

## SSH 與容器

C-x C-f 後輸入下列範例路徑，將主機、容器與路徑換成實際值：

    /ssh:user@host:/home/user/project/
    /podman:container-name:/workspace/project/
    /docker:container-name:/workspace/project/

容器需已執行。本機已有 Podman；沒有安裝 Docker。
開啟遠端程式檔後，用 C-c l l 啟動該環境的語言伺服器。
語言伺服器、ruff/prettier、git、Python 與專案依賴必須安裝在遠端或容器內；
本機工具不會自動複製過去。搜尋需要遠端有 rg。

遠端 Python 除錯使用該環境的 Python，需在其中安裝 debugpy。
目前 debugpy 透過標準輸入輸出連接，避免依賴額外的開放 TCP 連接埠。
JS 遠端除錯還需要遠端 adapter 路徑與專案配置，尚未按特定主機配置。
這是 TRAMP 工作流；VS Code 的 devcontainer.json、launch.json 不會自動匯入。

尚未提供 SSH 目標，本機也沒有執行中的 Podman 容器，因此這兩部分尚未實際連線驗證。

## 維護

- 套件來源：GNU ELPA 與 NonGNU ELPA。平時啟動不下載或更新套件。
- 缺少套件時：M-x lcw-install-ide-packages，然後重新啟動。
- 套件更新：M-x list-packages，自行選擇更新。
- Node 工具版本記錄：tools/node/package.json 與 package-lock.json。
- Python 工具版本記錄：tools/python-requirements.txt。
- LuaLS：3.19.1；js-debug：1.117.0。下載時已校驗官方 SHA-256。
- Tree-sitter 語法版本列在 lisp/init-programming.el。缺少語法時執行 M-x treesit-install-language-grammar。
- Node 優先使用本機 pi-node 維護的穩定入口 ~/.local/share/pi-node/current/bin；
  pi-node 更新版本時只需更新 current 符號連結，無需修改 init.el。若未安裝
  pi-node，請確保圖形介面啟動的 Emacs 能從 PATH 找到 Node。語言工具存放在
  ~/.emacs.d/tools/。
- Customize 設定放在 custom.el；備份與自動儲存位於 backups/、auto-saves/。
- 啟動出錯用 emacs --debug-init；emacs -Q 可跳過配置。移開 init.el 即可停用配置。

參考文件：[Eglot](https://www.gnu.org/software/emacs/manual/html_node/eglot/)、
[Dape](https://github.com/svaante/dape)、
[TRAMP](https://www.gnu.org/software/tramp/)。


## 本次驗證（2026-09-04）

已透過 Emacs 批次實測：
- 配置載入、括號語法、Python/JS/TS/TSX Tree-sitter 模式。
- Python/TS/JS/Lua 的 Eglot 連線與文件符號。
- Python、TS 的故意型別錯誤能出現在 Flymake。
- Python Ruff、JS/TS Prettier 格式化。
- Dape 的 Python、JS、TS 啟動並停在程式入口。
- Python 除錯目標正確選用專案 .venv，adapter 使用獨立工具環境。
- pytest 範例測試執行成功；Magit 載入成功。

已實測 Wayland 圖形介面的 GitHub Dark、Maple Mono NF CN 與深色 GTK 菜單。
未實測真實專案相依套件、SSH/容器連線及瀏覽器除錯。

## 本次驗證（2026-09-05 主題與圖標）

已透過 Emacs 批次與 Wayland 圖形 frame 實測：
- catppuccin、doom-one、doom-dracula、modus-vivendi(-tinted)、nord、
  gruvbox(-dark-hard)、solarized-dark、doom-tokyo-night、doom-nord、
  doom-gruvbox、doom-solarized-dark、github-dark 逐一載入，
  真實 frame 下 default face 的背景/前景色均與各主題官方色板一致。
- nerd-icons 系列：corfu-margin-formatters 含 nerd-icons-corfu-formatter、
  nerd-icons-completion-mode 啟用、dired 圖標 hook 掛載，
  nerd-icons 字族解析為 Maple Mono NF CN。
- 週邊排查：GUI 下 char-displayable-p 帶 frame 參數查詢私有區碼位會掛起，
  屬 Emacs/GTK 層面 quirk，與本配置無關（配置未使用此呼叫）。

## 套件選擇原則

優先使用 Emacs 內建功能；外部套件以廣泛採用、持續維護、文件完整為準。
目前直接安裝並使用的套件為 Vertico、Orderless、Marginalia、Consult、
Embark、Embark Consult、Avy、Corfu、Cape、YASnippet、multiple-cursors、
Paredit、VLF、Magit、Dape、lua-mode、pdf-tools、autothemer。必要依賴由套件管理器處理。
主題與圖標（doom-themes、catppuccin-theme、nord-theme、gruvbox-theme、
solarized-theme、nerd-icons 系列）由 MELPA 安裝；package-archives 已
加入 MELPA，但仍只在 M-x lcw-install-ide-packages 時顯式刷新與下載。
先前試裝但未使用的 reformatter 已移除。
C/C++ 使用 GNU/LLVM 工具鏈；Elisp 使用內建分析工具與 Paredit 結構編輯。

## C / C++（2026-09-04 補充）

已加入 c-ts-mode / c++-ts-mode、clangd 自動連線設定及 Dape/GDB 入口。
2026-09-05 已安裝並驗證 GCC/G++ 16.2.1、GDB 17.1、clangd/clang-format
22.1.8、CMake 4.3.0 和 Ninja 1.13.2。套件均來自 Fedora 官方來源。
clang-tools-extra 提供 clangd；C/C++ 格式化由 clangd 完成。
重新啟動 Emacs，開啟 .c / .cpp 檔，便會自動啟動語言服務。
C-c l f 格式化，M-. 跳轉定義，M-? 查引用，C-c l r 重新命名。

CMake 專案建議產生編譯資料庫，讓 clangd 取得正確的標頭檔路徑、
巨集與編譯選項。在專案根目錄執行：

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    cmake --build build

若根目錄沒有 compile_commands.json，可連結到 build 裡的版本：

    ln -s build/compile_commands.json compile_commands.json

C-c c 也能執行 cmake --build build，或 ctest --test-dir build --output-on-failure。
既有 Makefile / Meson 專案繼續使用自身的建置方式，clangd 同樣讀取 compile_commands.json。
單一檔案可用 gcc 或 g++，除錯時加 -g3 -O0：

    gcc -g3 -O0 -Wall -Wextra main.c -o app
    g++ -std=c++20 -g3 -O0 -Wall -Wextra main.cpp -o app

F9 設斷點，F5 輸入 gdb :program "app"；CMake 專案把 app 改成真正的執行檔，
例如 gdb :program "build/my-app"。C-c D n/i/o 單步操作，C-c D c 繼續。
修改程式後先重新編譯再除錯。專案使用 C++23 或其他版本時，依建置設定調整。

本次已驗證 C/C++ Tree-sitter 模式；臨時 CMake C++20 專案可由 Ninja/G++
編譯並執行。clangd 能讀取 compile_commands.json、列出文件符號、
格式化程式碼並把故意的 std::string → int 錯誤交給 Flymake。
Dape 經 GDB DAP 啟動並停在 main.cpp 的 main 函式。
原配置備份位於 backups/before-c-cpp-*。

## Markdown 編輯

Emacs 使用官方 markdown-mode 2.8；所有 .md 和 .markdown 使用其 gfm-mode
擴充模式，並啟用 fenced code block 原生語言高亮、Obsidian 式 [[Wiki Links]]、
`==文字高亮==` 與數學語法辨識。`==...==` 是 Obsidian、Typora 等軟體支援的
擴充語法，不屬於 CommonMark 或 GFM。GFM pipe table 會在同一個編輯 buffer 中顯示成 Unicode
框線表格；游標進入表格時自動還原 Markdown 原文，離開後立即重新渲染，顯示
過程不會修改檔案內容。C-c C-x t 可暫時開關表格預覽。Wiki links 只做語法
顯示，不遞迴掃描大型專案或接管 vault。C-c C-h 顯示該模式完整鍵位。

此配置只負責 Markdown 編輯，不接管 Obsidian vault、反向連結、每日筆記、
Excalidraw、Canvas 或同步。沒有安裝 obsidian.el。HTML 預覽與導出需要
Pandoc、cmark 等外部渲染器，本機目前未安裝，因此沒有配置完整 HTML 預覽；
上述表格預覽完全由 Emacs 顯示層完成，不依賴外部程式。

套件來源固定為官方倉庫 https://github.com/jrblevin/markdown-mode 的
v2.8（commit f5d520b3ee7722dd2231ab586ba51d8eb166e49b），保存在
vendor/markdown-mode，不使用 MELPA 每日快照。

Emacs 自帶 Org mode；日後在 Emacs 內建立筆記時優先從原生 Org 開始。
目前尚未設定 Org 筆記目錄、capture template、Agenda 或 Org-roam，
避免在確認工作流前建立第二套資料結構。

## Emacs Lisp（Elisp）

Emacs 自帶的是 Emacs Lisp，與 Common Lisp、Scheme 不同。
.el 檔會進入 emacs-lisp-mode；已有內建補全、文件、Flymake 和 Edebug。
Corfu 顯示手動補全候選，不需要額外語言伺服器。

| 操作 | 功能 |
|---|---|
| C-x C-e | 求值游標前的表達式 |
| C-M-x | 求值目前函式定義 |
| C-u C-M-x | 對目前函式加入 Edebug 偵錯資訊 |
| M-x ielm | 開啟 Elisp REPL |
| C-h f / C-h v | 查函式 / 變數文件 |
| M-. / M-, | 定義跳轉 / 返回 |
| C-c l f | 縮排整個 buffer |
| M-x ert | 執行已定義的 ERT 測試 |

先用 C-u C-M-x 對函式加入 Edebug 偵錯資訊，再呼叫該函式就會進入除錯；
在 Edebug 中用 SPC 單步、b 設定斷點、g 繼續。
Elisp 使用這套內建除錯流程，F5 的 Dape 入口用於外部程式。

本次已驗證 Elisp 求值、縮排與 Edebug 偵錯資訊建立。

## 字體、主題與 PDF

圖形介面的 default 與 fixed-pitch 字體明確使用系統已安裝的
Maple Mono NF CN，保留原本字級。重啟 Emacs 生效。
終端版 emacs -nw 的字體由終端程式控制；中文也優先使用 Maple Mono NF CN；未涵蓋字元由系統 fallback 顯示。
可用 M-x describe-face RET default 查看文字字體，
或 M-x describe-char 查看游標所在字元實際使用的字體。
已啟用 GitHub Dark（github-dark），重啟 Emacs 生效；M-x customize-themes 可以預覽已安裝的主題。
挑選入口：https://emacsthemes.com/ 、https://github.com/doomemacs/themes 、
https://protesilaos.com/emacs/ef-themes-pictures 。

### 主題陣容（2026-09-05 更新）

已從 MELPA 安裝五套熱門暗色主題，加上內建 modus-vivendi 與原本的
github-dark，供並排試用：

| 主題 | 載入名 | 風格 | 預設背景 |
| --- | --- | --- | --- |
| Catppuccin（預設，mocha flavor） | catppuccin | 柔和粉彩 | #1e1e2e |
| Doom One / Dracula | doom-one / doom-dracula | 飽滿現代，Doom 生態 | #282c34 / #282a36 |
| Modus Vivendi（Emacs 28+ 內建） | modus-vivendi | WCAG AAA 護眼 | #000000 |
| Nord | nord | 北歐冷色低對比 | #2E3440 |
| Gruvbox Dark | gruvbox（-dark-hard/-medium/-soft） | 復古暖色 | #282828 |
| Solarized Dark | solarized-dark | 老牌色彩科學 | #002b36 |
| GitHub Dark（原配置） | github-dark | 原本預設 | #0d1117 |

doom-themes 附帶全部 100+ 變體（doom-tokyo-night、doom-nord、
doom-gruvbox、doom-solarized-dark 等一併可用）。catppuccin flavor 可改
latte / frappe / macchiato / mocha（lisp/init-ui.el 的 catppuccin-flavor）。
試用方式：C-c T（consult-theme）即時預覽循環切換；M-x lcw-load-theme
直接載入；開機預設主題改 lisp/init-ui.el 的 lcw-default-theme 變數。

### 圖標（2026-09-05 更新）

選用 nerd-icons 而非 all-the-icons：nerd-icons 直接讀 Nerd Fonts v3 碼位，
已安裝的 Maple Mono NF CN 即可渲染，無需另裝字體；all-the-icons 綁定
舊碼位並自帶字體下載，在 Nerd Fonts v3 下會錯位，且維護已停滯。
已啟用：nerd-icons-dired（Dired 檔案圖標）、nerd-icons-corfu（補全選單
圖標）、nerd-icons-completion（Marginalia 註解圖標）。
M-x nerd-icons-test-icons 可預覽全部字形。

已從 NonGNU ELPA 安裝 pdf-tools 1.3.0（及必要依賴 tablist）。
2026-09-05 已用套件自帶的 autobuild 編譯 epdfinfo，並明確跳過系統
套件安裝。Fedora 44 以 zlib-ng-compat-devel 提供 zlib 開發介面，
所以 rpm -q zlib-devel 顯示未安裝並不表示缺少功能。

PDF 開啟時才載入，預設適合視窗寬度。本次以套件內附的六頁 PDF
驗證後端檢查、開檔、頁數、文字抽取和 640×828 PNG 頁面渲染；
後端同時回報支援區分大小寫搜尋、文字批註與標記批註。
配置使用 pdf-loader-install 的 skip-dependencies 參數，Emacs 不會自行
呼叫系統套件管理器。日後更新 pdf-tools 若移除 epdfinfo，首次開啟
PDF 時同意重新建置即可。

PDF 常用操作：n / p 翻頁，+ / - 縮放，C-s 搜尋，
o 目錄，M-g g 跳頁，C-h m 查看完整操作。
PDF 原有的文字字體與版面不受 Emacs 等寬字體設定影響。

GitHub Dark 來源：https://github.com/ladroid/github-emacs-theme ，固定版本 80ee910537777781cc52511bd1a35c2413d3abd7。
主題原檔及授權保存在 themes/github-dark/；必要依賴 autothemer 與 dash 由 ELPA 管理。

外層 GTK 介面：只在 ~/.local/share/applications/emacs.desktop 覆寫一行：
Exec=/usr/bin/env GTK_THEME=Adwaita:dark /usr/bin/emacs %F
從桌面 Emacs 圖示開啟時，GTK 菜單及標題列使用深色 Adwaita。
編輯區主題由 lisp/init-ui.el 的 lcw-default-theme 決定（目前 catppuccin）；GNOME 全域主題未修改。
終端若也要同樣 GTK 配色，使用：
GTK_THEME=Adwaita:dark emacs
已在 Wayland 測試視窗擷取並確認菜單、標題列為深色。

已撤除先前的 ~/.local/bin/emacs 同名包裝腳本：
它會干擾 Fedora Emacs 尋找原生編譯檔。無效的 early-init GTK 設定
與多餘的郵件捷徑覆寫也已撤除，備份保存在 backups/simplify-gtk-*。
診斷用 GTK 擷取模組只存在 /tmp，未加入任何日常啟動設定。

## 快速操作與程式碼片段（2026-09-05）

- C-. 在目前檔案、搜尋結果或 minibuffer 候選上打開 Embark 操作選單；
  例如複製、開啟、重新命名或刪除，實際動作依候選類型顯示。
- C-; 直接執行該候選的預設 Embark 操作；C-h B 查看可用綁定。
- C-c j 輸入一段文字，畫面上每個匹配位置會出現短標籤；輸入標籤即跳轉。
- 程式 buffer 已啟用 YASnippet。輸入下列 key 再按 TAB 展開：
  Python / C / C++ 的 main、TypeScript / Lua 的 fn、TSX 的 fc、
  Emacs Lisp 的 defun。
- M-x yas-new-snippet 建立個人片段；片段存放在 ~/.emacs.d/snippets/。
  沒有安裝第三方 snippet 大合集，以免帶入大量用不到或過時的模板。

Embark、Avy、YASnippet 均來自 GNU ELPA；Embark Consult 也是 GNU ELPA，
只負責讓 Embark 結果使用 Consult 預覽。本次沒有啟用自動格式化或存檔副作用。

## 工具鏈完成驗證（2026-09-05）

驗證使用 /tmp/lcw-emacs-cpp-check，沒有修改任何使用者專案。
測試涵蓋 CMake 配置、Ninja 建置、G++ 執行、compile_commands.json、
c++-ts-mode、clangd 文件符號與格式化、Flymake 型別診斷，以及
Dape/GDB 停在 main。PDF 測試使用 pdf-tools 套件自帶的 test.pdf。
以上測試均成功；CMake 範例沒有定義 CTest 測試案例，因此 ctest
正確回報 No tests were found，這不屬於工具失敗。

尚未具備具體目標的項目仍是 SSH 主機、執行中的容器、瀏覽器前端專案
和實際 Lua runtime；收到目標或專案後才能做端到端連線驗證。

## 工作區、會話與後備補全（2026-09-05）

- Emacs 內建 tab-bar 已啟用。每個 tab 保存自己的視窗布局，可把不同專案
  放在不同 tab；它們共享同一組 buffer。
- C-x t 2 新建、C-x t 0 關閉、C-x t o 切換；C-x t r 重新命名。
  C-x t B / C-x t F 返回或前進該 tab 的視窗布局歷史。
- 內建 desktop-save-mode 會在正常退出時把互動會話保存到
  ~/.emacs.d/state/desktop/session，下次啟動先恢復五個 buffer，
  其餘延遲恢復。不恢復舊 frame 幾何尺寸。
- Cape 只作為後備 CAPF：語言伺服器仍優先，沒有合適語言候選時才提供
  檔名或其他 buffer 裡出現過的單字。它不啟動索引程序。
- multiple-cursors 使用上表快捷鍵。完成後按 RET 或 C-g 退出；
  多游標中要插入換行使用 C-j。它可能首次詢問未知命令應只執行一次
  還是對所有游標執行，答案記在 state/multiple-cursors-lists.el。
- multiple-cursors 1.5.0 來自 NonGNU ELPA，約 2.5k stars。它在 Emacs 30
  編譯時仍使用部分已棄用的 defadvice，會出現警告但本次功能測試通過；
  上游維護者說仍維護自身日用場景，但不再全面處理外部 issue。
- Cape 2.9 來自 GNU ELPA，由 Vertico/Consult 作者維護。


## Tsoding 配置中採用的編輯改進（2026-09-05）

- Paredit 26 來自 NonGNU ELPA。為保留原生 Lisp 鍵位，現在不再自動啟用；
  需要時執行 M-x paredit-mode。啟用後用 C-h m 查看完整按鍵，C-g 取消操作。
- Paredit 啟用時，C-) 把右側下一個 S-expression 收入目前列表（slurp），
  C-} 把最後一項移出列表（barf），M-( 包住下一個 expression，M-s 移除外層括號。
- multiple-cursors 增加 C-" 和 C-:，可略過不想建立游標的匹配。
- C-, 使用 Emacs 30 內建 duplicate-dwim，依有無選區複製區域或目前行。
- 兩個 Dired 視窗並排時，複製或改名預設以另一個 Dired 目錄為目標；
  檔案清單使用 -alh，兼顧 Fedora 與 TRAMP 遠端主機的可攜性。
- compilation-mode 已加入 Emacs 內建 ANSI filter，編譯器、測試與 npm
  腳本的終端色碼會轉成 Emacs 色彩。
- Paredit 26 在 Emacs 30 編譯時會提示部分 API 已棄用，但安裝與結構操作
  測試均成功。其他四項也已完成隔離功能測試。


## 大型檔案防護（2026-09-05）

此配置保留並明確設定 Emacs 的 10 MB 大檔門檻，並啟用兩層防護：

1. 內建 global-so-long-mode 偵測極端長行。它適合 minified JS/JSON、
   生成檔和單行日誌；觸發後暫時使用 so-long-mode，停用容易卡頓的
   major/minor mode 功能。C-c C-c 可嘗試恢復原 major mode。
2. VLF 1.7.2 來自 GNU ELPA。超過 10 MB 時提示普通開啟（o）、
   VLF 分塊開啟（v）或取消（a）；也可隨時按 C-c v 選檔。
   VLF 初始只載入 1 MB，C-c C-v n / p 切換下一塊 / 上一塊，
   C-c C-v s 搜尋整個檔案，C-c C-v o 建立 occur 索引。

普通程式碼仍使用 Tree-sitter、Eglot 和完整 IDE 功能。只有命中超長行，
或使用者選擇 VLF 時才降級。10 MB 以上若仍選 o，Emacs 會照常載入整個檔案，
因此對未知的大型 log、JSON、CSV 或生成檔應優先選 v。

VLF 是長期使用的 GNU ELPA 套件，但 1.7.2 在 Emacs 30 編譯時仍會提示
部分 defadvice 舊 API；分塊載入和大檔提示整合已在 Emacs 30.2 實測。
測試結果：20,015 字元的單行 JSON 成功觸發 so-long；5,460,000 bytes
測試檔只載入 1,000,000 bytes 的 VLF chunk。

## 側欄面板與檔案瀏覽

檔案瀏覽走 Dirvish：C-x d 以全屏多面板（父目錄、檔案列表、即時預覽）
開啟當前目錄，C-u C-x d 先提示目錄；h/j/k/l 導航、. 切換隱藏檔案、
TAB 展開子樹、M-f/M-b 翻歷史、? 打開功能面板。C-x C-f 保持 minibuffer
補全不變。左側 Dired 面板與 dired-subtree 已於 2026-10 退役（程式碼以
註釋保留）；需要樹狀側欄時用 dirvish-side（C-x w f，自動跟隨當前檔案）。

| 按鍵 | 操作 |
|---|---|
| C-x d | 全屏 Dirvish（C-u 先提示目錄） |
| C-x w f | 左側 Dirvish 檔案樹（dirvish-side，自動跟隨當前檔案） |
| C-x w t | 單獨顯示／收起下方專案 vterm 終端 |
| C-x w a | 顯示／收起目前選定的 agent |
| C-x w A | 從已安裝的 Codex、Pi、Copilot CLI 中選擇 agent |
| C-x w s | Emacs 原生命令：暫藏／恢復全部側窗 |
| C-x o | 在可見視窗之間循環 |

各專案的終端 buffer 相互獨立；切換或收起側窗不會終止程序。下方
vterm 可直接執行測試、建置或 yazi；Yazi 是終端檔案管理器，不是
終端後端。

目前偵測到 Codex 與 Pi；預設 agent 是 Codex。C-x w A 切換到 Pi 時，
Codex 程序會留在自己的隱藏 buffer，下次切回可繼續原會話，反之亦然。
配置也識別官方 GitHub Copilot CLI 的 copilot 命令；安裝完成後會自動
出現在選單。這些終端 agent 與 Codex 桌面應用中的目前對話不是同一會話。

目前沒有額外安裝終端或 AI 套件。若日後加入 vterm，只需更換側窗的
終端後端；佈局與 C-x w 快捷鍵可以保持不變。
