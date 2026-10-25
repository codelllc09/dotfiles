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
  -- 代码块加一圈细边框（高亮组在下方 setup 之后统一设定）
  code = { border = 'thin' },
})

-- 区分代码块与行内代码的底色（默认两者同用 ColorColumn，看不出区别；
-- 色值取自终端的 Catppuccin Mocha：块=深色面板，行内=浅色小块）
vim.api.nvim_set_hl(0, 'RenderMarkdownCode', { bg = '#181825' })       -- 代码块背景（mantle）
vim.api.nvim_set_hl(0, 'RenderMarkdownCodeBorder', { bg = '#45475a' }) -- 代码块边框（surface1）
vim.api.nvim_set_hl(0, 'RenderMarkdownCodeInline', { bg = '#313244' }) -- 行内代码背景（surface0）
-- ==高亮== 用荧光笔黄（Obsidian 惯例；黄取 Catppuccin Mocha yellow，深色字保证可读）
-- 想要多彩高亮可按前缀扩展，如 ==!红== ：
--   setup({ inline_highlight = { custom = { important = { prefix = '!', highlight = 'MdHlRed' } } } })
vim.api.nvim_set_hl(0, 'RenderMarkdownInlineHighlight', { bg = '#f9e2af', fg = '#1e1e2e' })

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
  image = {
    doc = { inline = false, float = true },
  },
})
-- \i：预览光标处图片（悬浮窗，按 q 或 Esc 关闭）
vim.keymap.set('n', '<LocalLeader>i', function() require('snacks.image').hover() end, { desc = '预览光标处图片' })
vim.keymap.set('n', '<LocalLeader>m', '<Cmd>RenderMarkdown toggle<CR>', { desc = '切换 Markdown 渲染' })

-- ── 插件：mini.nvim 模块化小工具（只启用用得上的模块）──
vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' }) -- 已迁组织：旧 echasnovski 地址靠重定向，改新址免依赖
require('mini.icons').setup()      -- 文件类型图标（render-markdown 会自动改用它）
require('mini.files').setup()      -- 目录浏览器，支持在目录里直接新建/重命名/移动
require('mini.pick').setup()       -- 模糊查找
require('mini.pairs').setup()      -- 括号/引号自动配对
require('mini.surround').setup()   -- 环绕编辑：sa 加、sd 删、sr 换
require('mini.trailspace').setup() -- 行尾空格高亮，:MiniTrailspace.trim 一键清理

vim.keymap.set('n', '<Leader>e', function()
  local path = vim.api.nvim_buf_get_name(0) -- 定位到当前文件所在目录
  MiniFiles.open(path ~= '' and path or nil)
end, { desc = '目录浏览器（定位当前文件）' })
vim.keymap.set('n', '<Leader>f', function() MiniPick.builtin.files() end, { desc = '查找文件' })
vim.keymap.set('n', '<Leader>b', function() MiniPick.builtin.buffers() end, { desc = '切换缓冲区' })
vim.keymap.set('n', '<Leader>g', function() MiniPick.builtin.grep_live() end, { desc = '实时全文搜索' })

-- ── 插件：nvim-treesitter（只为装 json/yaml parser；markdown 系已自带）──
-- 0.11+ 高亮/折叠由 nvim 内置引擎接管，旧式 setup({highlight=...}) 已废弃
vim.pack.add({ 'https://github.com/nvim-treesitter/nvim-treesitter' })
-- parser 声明式安装：新机器部署后自动补齐（已装则跳过、无网络动作）。
-- 注意：vim.pack.update() 升级本插件后需跑 :TSUpdate 同步 parser 版本
require('nvim-treesitter').install({ 'json', 'yaml' })
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'markdown', 'json', 'jsonc', 'yaml' },
  callback = function()
    pcall(vim.treesitter.start) -- 高亮
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.opt_local.foldlevel = 99 -- 打开时全部展开
  end,
})
