-- Neovim 起步配置 · 保存即生效
-- Leader 明确化：Space 做全局 Leader（好按），LocalLeader 保持反斜杠
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

vim.opt.number = true          -- 行号
vim.opt.mouse = 'a'            -- 鼠标可用（点击定位、滚轮）
vim.opt.clipboard = 'unnamedplus' -- 与系统剪贴板互通（yy 复制直接可粘贴到别处）
vim.opt.undofile = true        -- 关闭文件后撤销历史仍在
vim.opt.expandtab = true       -- Tab 转空格
vim.opt.shiftwidth = 2         -- 缩进 2 格
vim.opt.termguicolors = true   -- 真彩色
vim.opt.cursorline = true       -- 高亮光标行，读长文档时定位方便
vim.opt.ignorecase = true       -- 搜索忽略大小写……
vim.opt.smartcase = true        -- ……但搜索词含大写时恢复区分
vim.opt.autoread = true         -- 文件在外部被改（如 AI 编辑）后自动重读
vim.opt.confirm = true          -- 退出有未保存修改时弹确认而非直接报错
vim.opt.scrolloff = 4           -- 光标上下各保留 4 行可见，阅读不贴边
vim.opt.signcolumn = 'yes'      -- Git / 诊断符号栏固定显示，避免正文左右跳动
vim.opt.laststatus = 3          -- 所有窗口共用一条底部状态栏
vim.opt.showmode = false        -- 模式交给状态栏显示，避免重复的 -- INSERT --

-- AI/外部程序改文件后，回到 nvim 自动刷新（本地有未保存修改时不覆盖）
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
  callback = function(args)
    if vim.bo[args.buf].buftype == '' and not vim.bo[args.buf].modified then
      vim.cmd('checktime')
    end
  end,
})

-- ── 插件：Markdown 阅读增强 ─────────────────────────────
-- 用 nvim 0.12 内置的 vim.pack 管理（无需 lazy/packer），首次启动自动下载
vim.pack.add({ 'https://github.com/MeanderingProgrammer/render-markdown.nvim' })
require('render-markdown').setup({
  -- HTML 块 / LaTeX 公式 / YAML front matter 的额外美化用不到，
  -- 显式关闭（正文渲染不受影响；以后想要再删掉这几行即可）
  html = { enabled = false },
  latex = { enabled = false },
  yaml = { enabled = false },
  -- 代码块：浑然一体的面板（Obsidian 风）——顶部语言标签嵌在面板内，
  -- 上下边条复用面板底色，不再出现独立的两根 bar
  code = {
    border = 'thick',
    highlight_border = 'RenderMarkdownCode',
    language_icon = true,                      -- 语言图标：上面 mini.icons 里的经典字形
    highlight_language = 'RenderMarkdownCodeLanguage',
    sign = false,                              -- sign 列不再显示语言符号
    language_pad = 1,
    left_pad = 2,
  },
  -- 标题：𝓱₁~𝓱₆ 花体字母 + 下标级别数字（如变量带指标，重心低不飘）
  -- 字母𝓱由 WezTerm 回退到 STIX Two Math 渲染，下标数字由 Maple Mono 渲染；
  -- markdown 规范最多 6 级，####### 不算标题
  heading = {
    icons = {
      '\u{1d4f1}\u{2081} ', '\u{1d4f1}\u{2082} ', '\u{1d4f1}\u{2083} ',
      '\u{1d4f1}\u{2084} ', '\u{1d4f1}\u{2085} ', '\u{1d4f1}\u{2086} ',
    },
    position = 'inline',
    width = 'full',
    foregrounds = {
      'RenderMarkdownH1Icon', 'RenderMarkdownH2Icon', 'RenderMarkdownH3Icon',
      'RenderMarkdownH4Icon', 'RenderMarkdownH5Icon', 'RenderMarkdownH6Icon',
    },
    backgrounds = {
      'RenderMarkdownH1', 'RenderMarkdownH2', 'RenderMarkdownH3',
      'RenderMarkdownH4', 'RenderMarkdownH5', 'RenderMarkdownH6',
    },
  },
  -- 链接图标：内置已带 GitHub/GitLab/Google/Stack Overflow/YouTube/Reddit/Wikipedia/X/
  -- Neovim/Apple/Discord/HN/LinkedIn/Microsoft/Slack/Steam 官方图标；
  -- 这里统一地球兑底，补国内常用站，本地路径用文件夹
  link = {
    hyperlink = '\u{f0ac} ',  -- fa-globe 地球（非 http 链接的兑底）
    custom = {
      web = { icon = '\u{f0ac} ', pattern = '^http' },     -- 普通网站 → 地球
      file = { icon = '\u{f07b} ', pattern = '^[^:]+/' },   -- 本地路径 → 文件夹
      wechat = { icon = '\u{f0611} ', pattern = 'weixin%.qq%.com', kind = 'url' },
      qq = { icon = '\u{f1d6} ', pattern = 'qq%.com', kind = 'url' },
      weibo = { icon = '\u{f18a} ', pattern = 'weibo%.com', kind = 'url' },
      alipay = { icon = '\u{eebc} ', pattern = 'alipay%.com', kind = 'url' },
      telegram = { icon = '\u{f2c6} ', pattern = 't%.me', kind = 'url' },
      docker = { icon = '\u{f21f} ', pattern = 'docker%.com', kind = 'url' },
      npm = { icon = '\u{e71e} ', pattern = 'npmjs%.com', kind = 'url' },
      medium = { icon = '\u{f23a} ', pattern = 'medium%.com', kind = 'url' },
      rust = { icon = '\u{e7a8} ', pattern = 'rust%-lang%.org', kind = 'url' },
      crates = { icon = '\u{e7a8} ', pattern = 'crates%.io', kind = 'url' },
    },
  },
})

-- 区分代码块与行内代码的底色（默认两者同用 ColorColumn，看不出区别；
-- 色值取自终端的 Catppuccin Mocha：块=深色面板，行内=浅色小块）
vim.api.nvim_set_hl(0, 'RenderMarkdownCode', { bg = '#24273a' })       -- 代码块面板（macchiato base，黑底终端上可见）
vim.api.nvim_set_hl(0, 'RenderMarkdownCodeLanguage', { fg = '#6c7086', italic = true }) -- 语言标签：overlay0 弱灰斜体，对比度约 2.9:1，安安静静退后
vim.api.nvim_set_hl(0, 'RenderMarkdownCodeInline', { bg = '#313244' }) -- 行内代码背景（surface0）
-- ==高亮== 用荧光笔黄（Obsidian 惯例；黄取 Catppuccin Mocha yellow，深色字保证可读）
-- 想要多彩高亮可按前缀扩展，如 ==!红== ：
--   setup({ inline_highlight = { custom = { important = { prefix = '!', highlight = 'MdHlRed' } } } })
vim.api.nvim_set_hl(0, 'RenderMarkdownInlineHighlight', { bg = '#f9e2af', fg = '#1e1e2e' })
-- 标题彩虹底色带：赤橙黄绿青蓝（markdown 只有 h1~h6，紫色排不上号）
-- 色值按与正文 #cdd6f4 对比度 ≥ 4:1 挑选，标题加粗白字依然清晰
vim.api.nvim_set_hl(0, 'RenderMarkdownH1', { bg = '#7e3a45' }) -- 红
vim.api.nvim_set_hl(0, 'RenderMarkdownH2', { bg = '#8a5226' }) -- 橙
vim.api.nvim_set_hl(0, 'RenderMarkdownH3', { bg = '#6e6420' }) -- 黄
vim.api.nvim_set_hl(0, 'RenderMarkdownH4', { bg = '#3f6f45' }) -- 绿
vim.api.nvim_set_hl(0, 'RenderMarkdownH5', { bg = '#2f6b6b' }) -- 青
vim.api.nvim_set_hl(0, 'RenderMarkdownH6', { bg = '#3d5f94' }) -- 蓝
-- 前缀单独配色：Catppuccin Mocha 粉彩按色带同系提亮，与正文白字区分；
-- 对比度均 ≥ 4:1（黄/青本色就达标，其余向白提亮 5%~35%）
local prefix_colors = {
  '#f5a2b9', '#fbc29f', '#f9e2af', '#aae4a6', '#94e2d5', '#b2cefc',
}
for i, fg in ipairs(prefix_colors) do
  vim.api.nvim_set_hl(0, ('RenderMarkdownH%dIcon'):format(i), { fg = fg })
end

-- markdown 文件按单词软换行，长段落阅读不折行断词
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true -- 折行后的后续行保持缩进
    -- conceallevel 不手动设：render-markdown 自己会按渲染开关切换
  end,
})

-- ── 插件：图片显示（snacks.nvim，走 Kitty 图形协议）──
-- WezTerm 不支持行内占位符 → 只能悬浮窗预览：
-- 光标停在 ![..](..) 或图片路径上按空格延迟或 \i 弹出；也可直接 nvim 打开图片文件
vim.pack.add({ 'https://github.com/folke/snacks.nvim' })
require('snacks').setup({
  -- 超大文件 / 超长行自动关闭 Treesitter、LSP 等重型功能，避免查看日志或压缩 JSON 时卡顿
  bigfile = { enabled = true },
  -- 左侧项目树：以 nvim 当前工作目录为根，打开文件后继续保持并自动跟随
  explorer = { replace_netrw = true },
  picker = {
    sources = {
      explorer = {
        follow_file = true,
        auto_close = false,
        layout = { preset = 'sidebar', preview = false },
      },
    },
  },
  image = {
    doc = { inline = false, float = true },
  },
})
-- \i：预览光标处图片（悬浮窗，按 q 或 Esc 关闭）
vim.keymap.set('n', '<LocalLeader>i', function() require('snacks.image').hover() end, { desc = '预览光标处图片' })
vim.keymap.set('n', '<LocalLeader>m', '<Cmd>RenderMarkdown toggle<CR>', { desc = '切换 Markdown 渲染' })

-- PDF 保留两种阅读方式：直接打开时由 snacks.image 渲染页面；
-- \t 则用 pdftotext 提取为只读文本，便于 / 搜索、y 复制。q 关闭文本并回到 PDF。
local function open_pdf_text(path)
  path = path or vim.api.nvim_buf_get_name(0)
  path = path:gsub('#page=%d+$', '')
  path = vim.fn.fnamemodify(vim.fn.expand(path), ':p')

  if path == '' or path:lower():sub(-4) ~= '.pdf' then
    vim.notify('当前缓冲区不是 PDF', vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify('找不到 PDF：' .. path, vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable('pdftotext') ~= 1 then
    vim.notify('缺少 pdftotext（由 poppler-utils 提供）', vim.log.levels.ERROR)
    return
  end

  vim.notify('正在提取 PDF 文本…')
  vim.system({ 'pdftotext', '-layout', '-nopgbrk', path, '-' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = (result.stderr or ''):gsub('%s+$', '')
        vim.notify('PDF 文本提取失败' .. (message ~= '' and '：' .. message or ''), vim.log.levels.ERROR)
        return
      end

      local name = 'pdf-text://' .. path
      local bufnr = vim.fn.bufnr(name)
      if bufnr == -1 then
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, name)
      end

      vim.bo[bufnr].modifiable = true
      local text = (result.stdout or ''):gsub('\r\n', '\n')
      local lines = vim.split(text, '\n', { plain = true })
      if #lines > 1 and lines[#lines] == '' then table.remove(lines) end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].buftype = 'nofile'
      vim.bo[bufnr].bufhidden = 'wipe'
      vim.bo[bufnr].swapfile = false
      vim.bo[bufnr].filetype = 'text'
      vim.bo[bufnr].modifiable = false
      vim.bo[bufnr].readonly = true
      vim.bo[bufnr].modified = false
      vim.b[bufnr].pdf_source = path

      vim.api.nvim_set_current_buf(bufnr)
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.breakindent = true
      vim.keymap.set('n', 'q', function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end, { buffer = bufnr, nowait = true, desc = '关闭 PDF 文本阅读' })
    end)
  end)
end

vim.api.nvim_create_user_command('PdfText', function(opts)
  open_pdf_text(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', complete = 'file', desc = '以可搜索的只读文本打开 PDF' })
vim.keymap.set('n', '<LocalLeader>t', open_pdf_text, { desc = 'PDF 文本阅读模式' })

-- ── 插件：mini.nvim 模块化小工具（只启用用得上的模块）──
vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' }) -- 已迁组织：旧 echasnovski 地址靠重定向，改新址免依赖
require('mini.icons').setup({
  -- 文件类型图标：固定用经典 nerd font 字形（mini.icons 对 sh 的兜底字形在会话间不一致）。
  -- 颜色用 mini.icons 内置色板，文件树等处生效
  filetype = {
    sh =       { glyph = '\u{e691}', hl = 'MiniIconsGreen' },  -- seti-shell 终端提示符
    bash =     { glyph = '\u{e760}', hl = 'MiniIconsGreen' },  -- dev-bash
    lua =      { glyph = '\u{e620}', hl = 'MiniIconsBlue' },   -- seti-lua 月亮
    python =   { glyph = '\u{e73c}', hl = 'MiniIconsYellow' }, -- dev-python 双蛇
    json =     { glyph = '\u{e80b}', hl = 'MiniIconsYellow' }, -- dev-json 花括号
    yaml =     { glyph = '\u{e8eb}', hl = 'MiniIconsRed' },    -- dev-yaml
    toml =     { glyph = '\u{e6b2}', hl = 'MiniIconsGrey' },   -- custom-toml 齿轮
    markdown = { glyph = '\u{e609}', hl = 'MiniIconsBlue' },   -- seti-markdown m↓
    vim =      { glyph = '\u{e7c5}', hl = 'MiniIconsGreen' },  -- dev-vim 菱形
  },
})
require('mini.files').setup({       -- 保留为备用文件操作器，目录默认交给 Snacks Explorer
  options = { use_as_default_explorer = false },
})
require('mini.pick').setup()       -- 模糊查找
require('mini.pairs').setup()      -- 括号/引号自动配对
require('mini.surround').setup()   -- 环绕编辑：sa 加、sd 删、sr 换
require('mini.trailspace').setup() -- 行尾空格高亮，:MiniTrailspace.trim 一键清理
require('mini.bracketed').setup({
  -- [c / ]c 留给社区惯用的 Git change 跳转；注释块仍可用普通搜索移动
  comment = { suffix = '' },
})
require('mini.jump2d').setup({
  -- 默认 <CR> 会覆盖普通回车移动；改用 <Leader>j 启动屏幕内标签跳转
  mappings = { start_jumping = '<Leader>j' },
})

-- 快捷键提示：按下 Space 等前缀键后，显示当前实际生效的后续键与中文说明
vim.pack.add({ 'https://github.com/folke/which-key.nvim' })
require('which-key').setup({
  preset = 'classic',
  delay = 300,
  spec = {
    { '<Leader>h', group = 'Git 改动' },
  },
})

vim.keymap.set('n', '<Leader>e', function() Snacks.explorer() end, { desc = '左侧项目树' })
vim.keymap.set('n', '<Leader>E', function()
  local path = vim.api.nvim_buf_get_name(0) -- 定位到当前文件所在目录
  MiniFiles.open(path ~= '' and path or nil)
end, { desc = 'MiniFiles（定位当前文件）' })
vim.keymap.set('n', '<Leader>f', function() MiniPick.builtin.files() end, { desc = '查找文件' })
vim.keymap.set('n', '<Leader>b', function() MiniPick.builtin.buffers() end, { desc = '切换缓冲区' })
vim.keymap.set('n', '<Leader>g', function() MiniPick.builtin.grep_live() end, { desc = '实时全文搜索' })

-- ── Git：gitsigns.nvim（社区主流的行级改动显示 / 预览）──
vim.pack.add({ 'https://github.com/lewis6991/gitsigns.nvim' })
local gitsigns = require('gitsigns')
gitsigns.setup({
  signs = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '-' },
    topdelete = { text = '-' },
    changedelete = { text = '~' },
    untracked = { text = '?' },
  },
  signs_staged = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '-' },
    topdelete = { text = '-' },
    changedelete = { text = '~' },
  },
  -- 不只显示一个细小符号：整行以低饱和背景标出，仍保留语法高亮前景色
  linehl = true,
  on_attach = function(bufnr)
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    map('n', ']c', function()
      if vim.wo.diff then
        vim.cmd.normal({ ']c', bang = true })
      else
        gitsigns.nav_hunk('next')
      end
    end, '下一处 Git 改动')
    map('n', '[c', function()
      if vim.wo.diff then
        vim.cmd.normal({ '[c', bang = true })
      else
        gitsigns.nav_hunk('prev')
      end
    end, '上一处 Git 改动')
    map('n', '<Leader>hp', gitsigns.preview_hunk, '弹窗预览 Git 改动')
    map('n', '<Leader>hi', gitsigns.preview_hunk_inline, '行内预览 Git 改动')
    map('n', '<Leader>hb', function() gitsigns.blame_line({ full = true }) end, '查看当前行 Git 归属')
    map('n', '<Leader>hd', gitsigns.diffthis, '与 Git 暂存区比较')
    map('n', '<Leader>hD', function() gitsigns.diffthis('~') end, '与上一次提交比较')
  end,
})

-- Catppuccin Mocha：符号用清晰的绿 / 蓝 / 红，整行背景只轻微着色
vim.api.nvim_set_hl(0, 'GitSignsAdd', { fg = '#a6e3a1', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsChange', { fg = '#89b4fa', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsDelete', { fg = '#f38ba8', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsUntracked', { fg = '#94e2d5', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsAddLn', { bg = '#26332d' })
vim.api.nvim_set_hl(0, 'GitSignsChangeLn', { bg = '#252b3a' })
vim.api.nvim_set_hl(0, 'GitSignsDeleteLn', { bg = '#382832' })
vim.api.nvim_set_hl(0, 'GitSignsUntrackedLn', { bg = '#243438' })
-- 已暂存改动使用相同符号但颜色更暗，仍能和工作区改动区分
vim.api.nvim_set_hl(0, 'GitSignsStagedAdd', { fg = '#6f9870', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsStagedChange', { fg = '#607da9', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsStagedDelete', { fg = '#a05d72', bold = true })
vim.api.nvim_set_hl(0, 'GitSignsStagedAddLn', { bg = '#222b26' })
vim.api.nvim_set_hl(0, 'GitSignsStagedChangeLn', { bg = '#222632' })
vim.api.nvim_set_hl(0, 'GitSignsStagedDeleteLn', { bg = '#30242a' })

-- ── 状态栏：lualine.nvim（模式 / Git / 诊断 / 文件 / 位置）──
vim.pack.add({ 'https://github.com/nvim-lualine/lualine.nvim' })
local mocha = {
  base = '#1e1e2e', mantle = '#181825', surface0 = '#313244', surface1 = '#45475a',
  text = '#cdd6f4', subtext0 = '#a6adc8', blue = '#89b4fa', green = '#a6e3a1',
  mauve = '#cba6f7', red = '#f38ba8', peach = '#fab387',
}
local lualine_theme = {
  normal = {
    a = { fg = mocha.base, bg = mocha.blue, gui = 'bold' },
    b = { fg = mocha.text, bg = mocha.surface1 },
    c = { fg = mocha.text, bg = mocha.mantle },
  },
  insert = { a = { fg = mocha.base, bg = mocha.green, gui = 'bold' } },
  visual = { a = { fg = mocha.base, bg = mocha.mauve, gui = 'bold' } },
  replace = { a = { fg = mocha.base, bg = mocha.red, gui = 'bold' } },
  command = { a = { fg = mocha.base, bg = mocha.peach, gui = 'bold' } },
  inactive = {
    a = { fg = mocha.subtext0, bg = mocha.mantle },
    b = { fg = mocha.subtext0, bg = mocha.mantle },
    c = { fg = mocha.subtext0, bg = mocha.mantle },
  },
}

local function current_directory()
  local path = vim.fn.fnamemodify(vim.fn.getcwd(), ':~')
  if #path > 32 then path = vim.fn.pathshorten(path) end
  return '  ' .. path
end

require('lualine').setup({
  options = {
    theme = lualine_theme,
    globalstatus = true,
    component_separators = { left = '│', right = '│' },
    section_separators = { left = '', right = '' },
  },
  sections = {
    lualine_a = { 'mode' },
    lualine_b = {
      'branch',
      { 'diff', symbols = { added = '+', modified = '~', removed = '-' } },
    },
    lualine_c = {
      { current_directory, color = { fg = mocha.mauve } },
      { 'filename', path = 1, symbols = { modified = ' ●', readonly = ' ', unnamed = '[无名]', newfile = '[新文件]' } },
    },
    lualine_x = {
      { 'diagnostics', symbols = { error = 'E:', warn = 'W:', info = 'I:', hint = 'H:' } },
      'filetype',
    },
    lualine_y = { 'progress' },
    lualine_z = { 'location' },
  },
  inactive_sections = {
    lualine_a = {}, lualine_b = {},
    lualine_c = { { 'filename', path = 1 } },
    lualine_x = { 'location' }, lualine_y = {}, lualine_z = {},
  },
})

-- ── 插件：nvim-treesitter（常见文本 / 配置 / 代码格式）──
-- 0.11+ 高亮/折叠由 nvim 内置引擎接管，旧式 setup({highlight=...}) 已废弃
vim.pack.add({ 'https://github.com/nvim-treesitter/nvim-treesitter' })
-- Neovim 自带 c/lua/markdown/query/vim/vimdoc；其余 parser 声明式安装：
-- 新机器部署后自动补齐（已装则跳过、无网络动作）。
-- 注意：vim.pack.update() 升级本插件后需跑 :TSUpdate 同步 parser 版本
require('nvim-treesitter').install({
  -- 常用脚本与配置
  'bash', 'python', 'json', 'yaml', 'toml', 'ini', 'regex',
  -- Git / 构建 / 容器
  'diff', 'git_config', 'git_rebase', 'gitattributes', 'gitcommit', 'gitignore',
  'make', 'cmake', 'dockerfile', 'requirements', 'ssh_config',
  -- Web / 数据
  'html', 'css', 'javascript', 'typescript', 'tsx', 'sql', 'xml', 'csv', 'tsv',
})

-- 任意普通文件只要已有对应 parser，就自动启用 Treesitter 高亮和折叠；
-- 没有 parser 的格式静默回退到 Neovim 自带的传统语法高亮。
vim.api.nvim_create_autocmd('FileType', {
  pattern = '*',
  callback = function(args)
    if vim.bo[args.buf].buftype ~= '' then return end
    local has_parser = pcall(vim.treesitter.start, args.buf)
    if not has_parser then return end
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.opt_local.foldlevel = 99 -- 打开时全部展开
  end,
})

-- ── Python：使用 0.12 内置 LSP 客户端连接 Pyright ─────────────
-- 优先使用 PATH 中的命令；桌面启动时 PATH 较短，则复用 Emacs 已安装的
-- Pyright。这样两款编辑器的 Python 对比使用同一个语言服务器。
local pyright = vim.fn.exepath('pyright-langserver')
if pyright == '' then
  local bundled = vim.fn.expand('~/.emacs.d/tools/node/node_modules/.bin/pyright-langserver')
  if vim.fn.executable(bundled) == 1 then pyright = bundled end
end

if pyright ~= '' then
  vim.lsp.config('pyright', {
    cmd = { pyright, '--stdio' },
    filetypes = { 'python' },
    root_markers = {
      'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git',
    },
    settings = {
      python = {
        analysis = {
          typeCheckingMode = 'basic',
          diagnosticMode = 'openFilesOnly',
        },
      },
    },
  })
  vim.lsp.enable('pyright')
end
