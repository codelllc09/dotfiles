-- Neovim 配置索引
-- 搜索 @ 加章节或小节名可直达对应标题。
--   core        基础选项、文件自动重读、输入法
--   documents   Markdown、Snacks、PDF 文本阅读
--   editing     mini.nvim、快捷键提示、文件和文本导航
--   git         Neogit、状态页缩进、Gitsigns
--   avante      Codex ACP 对话
--   statusline  lualine 主题与布局
--   languages   Treesitter、Python LSP

-- ## @core 基础设置
-- ### @options 快捷键前缀与编辑器选项
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

-- ### @autoread 文件自动重读
-- AI/外部程序改文件后，回到 nvim 自动刷新（本地有未保存修改时不覆盖）
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
  callback = function(args)
    if vim.bo[args.buf].buftype == '' and not vim.bo[args.buf].modified then
      vim.cmd('checktime')
    end
  end,
})

-- ### @input-method Fcitx5 / IBus 输入法
-- 非插入模式切回英文，插入模式由用户手动切换。
do
  local backends = {
    fcitx5 = {
      check = { 'fcitx5-remote', '--check' },
      english = { 'fcitx5-remote', '--check', '-c' },
    },
    ibus = {
      check = { 'ibus', 'engine' },
      english = { 'ibus', 'engine', 'xkb:us::eng' },
    },
  }

  -- 优先探测桌面会话声明的输入法，未声明时先探测 Fcitx5。
  local preferred = 'fcitx5'
  for _, hint in ipairs({
    (vim.env.XMODIFIERS or ''):match('@im=([^%s]+)') or '',
    vim.env.GTK_IM_MODULE or '',
    vim.env.QT_IM_MODULE or '',
  }) do
    if hint == 'fcitx' then hint = 'fcitx5' end
    if backends[hint] then
      preferred = hint
      break
    end
  end
  local fallback = preferred == 'fcitx5' and 'ibus' or 'fcitx5'
  local candidates = { backends[preferred], backends[fallback] }
  local english, detecting
  local focused = true

  local function switch_to_english()
    if focused and #vim.api.nvim_list_uis() > 0 and vim.api.nvim_get_mode().mode:sub(1, 1) ~= 'i' then
      vim.system(english, { timeout = 500 })
    end
  end

  local function detect(index)
    local backend = candidates[index]
    if not backend then
      detecting = false
      return
    end
    if vim.fn.executable(backend.check[1]) ~= 1 then return detect(index + 1) end
    vim.system(backend.check, { timeout = 500 }, vim.schedule_wrap(function(result)
      if result.code ~= 0 then return detect(index + 1) end
      english = backend.english
      detecting = false
      switch_to_english()
    end))
  end

  vim.api.nvim_create_autocmd({ 'UIEnter', 'FocusGained', 'FocusLost', 'ModeChanged' }, {
    group = vim.api.nvim_create_augroup('InputMethodEnglish', { clear = true }),
    callback = function(ev)
      if ev.event == 'FocusLost' then
        focused = false
        return
      end
      if ev.event ~= 'ModeChanged' then focused = true end
      local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
      if not focused or mode == 'i' or #vim.api.nvim_list_uis() == 0 then return end
      if ev.event == 'ModeChanged' and vim.v.event.old_mode:sub(1, 1) == mode then return end
      if english then
        switch_to_english()
      elseif not detecting and (detecting == nil or ev.event ~= 'ModeChanged') then
        detecting = true
        detect(1)
      end
    end,
  })
end

-- ### @avante-runtime 首次安装或更新时下载匹配的预编译库
-- 锁文件中的插件可能在第一次 vim.pack.add() 时安装，提前注册下载钩子。
local avante_version = 'v0.5.0'
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('AvanteRuntime', { clear = true }),
  callback = function(ev)
    if ev.data.spec.name ~= 'avante.nvim' then return end
    if ev.data.kind ~= 'install' and ev.data.kind ~= 'update' then return end
    vim.system({ 'bash', vim.fs.joinpath(ev.data.path, 'build.sh'), avante_version }, {
      timeout = 60000,
    }, vim.schedule_wrap(function(result)
      if result.code == 0 then return end
      vim.notify('Avante 预编译库下载失败，可用 :AvanteBuild 重试。\n'
        .. vim.trim(result.stderr or ''), vim.log.levels.WARN)
    end))
  end,
})

-- ## @documents 文档阅读
-- ### @draft 只对 draft 命令打开的文件自动保存
vim.api.nvim_create_autocmd('User', {
  pattern = 'DraftAutosave',
  once = true,
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    local keys = 0
    local function save()
      keys = 0
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function() vim.cmd('silent update') end)
      end
    end

    -- 与交换文件一样，使用 updatetime 和 updatecount 的保存间隔。
    vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, { buffer = buf, callback = save })
    vim.api.nvim_create_autocmd('BufWritePost', { buffer = buf, callback = function() keys = 0 end })
    local listener = vim.on_key(function(_, typed)
      if typed == '' or vim.api.nvim_get_current_buf() ~= buf or vim.o.updatecount == 0 then return end
      keys = keys + 1
      if keys < vim.o.updatecount then return end
      keys = 0
      vim.schedule(save)
    end)
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function() vim.on_key(nil, listener) end,
    })
  end,
})

-- ### @markdown Markdown 渲染
-- 用 nvim 0.12 内置的 vim.pack 管理（无需 lazy/packer），首次启动自动下载
vim.pack.add({ 'https://github.com/MeanderingProgrammer/render-markdown.nvim' })

local markdown_globe = '\u{f0ac} '
local markdown_web_extensions = {
  avif = true, bmp = true, gif = true, heic = true, heif = true, ico = true,
  jpeg = true, jpg = true, pdf = true, png = true, svg = true, tif = true,
  tiff = true, webp = true,
}

-- 在插件计算渲染宽度前套用 Explorer 的文件图标，远程图片和 PDF 加地球。
local function attach_markdown_file_icons(ctx)
  local config = require('render-markdown.state').get(ctx.buf)
  local set_link_text = config.set_link_text

  function config:set_link_text(destination, icon)
    local target = destination:match('^<(.*)>$') or destination
    local original_icon = icon[1]
    set_link_text(self, target, icon)

    local path = target:match('^[^?#]+')
    if not path then return end
    local web_url = path:match('^[Hh][Tt][Tt][Pp][Ss]?:(//.*)$') or path
    local host, web_path = web_url:match('^//([^/]+)(/.*)$')
    if web_path then
      -- GitHub 的 blob 路径打开的是文件浏览页。
      if host:lower() == 'github.com' and web_path:match('^/[^/]+/[^/]+/blob/') then return end
      local filename = vim.uri_decode(web_path)
      local extension = filename:lower():match('%.(%w+)$')
      if markdown_web_extensions[extension] then
        local glyph, highlight = Snacks.util.icon(filename, 'file')
        icon[1], icon[2] = markdown_globe .. vim.trim(glyph) .. ' ', highlight or icon[2]
      end
      return
    end

    if icon[1] ~= original_icon or path:sub(1, 2) == '//' then return end
    if path:match('^%a[%w+.-]*:') then
      path = path:match('^file://(/.*)$') or path:match('^file://localhost(/.*)$')
      if not path then return end
    end

    path = vim.uri_decode((path:gsub('\\(%p)', '%1')))
    if path:find('\0', 1, true) then return end
    local trailing_slash = path:sub(-1) == '/'
    if path:sub(1, 1) ~= '/' and path:sub(1, 2) ~= '~/' then
      path = vim.fs.joinpath(vim.fs.dirname(vim.api.nvim_buf_get_name(ctx.buf)), path)
    end
    path = vim.fs.abspath(path)
    local category = (trailing_slash or vim.fn.isdirectory(path) == 1) and 'directory' or 'file'
    local glyph, highlight = Snacks.util.icon(path, category)
    icon[1], icon[2] = vim.trim(glyph) .. ' ', highlight or icon[2]
  end
end

require('render-markdown').setup({
  file_types = { 'markdown', 'Avante' },
  on = { attach = attach_markdown_file_icons },
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
  -- 这里统一地球兜底，补国内常用站。本地路径沿用 Snacks Explorer 的图标。
  link = {
    hyperlink = markdown_globe, -- fa-globe 地球兜底
    custom = {
      web = { icon = markdown_globe, pattern = '^https?://' }, -- 普通网站 → 地球
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

-- #### @markdown-colors 代码、标题与行内高亮配色
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

-- #### @markdown-wrap Markdown 软换行
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

-- ### @snacks Snacks 图片预览与项目树
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

-- #### @document-keys 文档阅读快捷键
-- \i：预览光标处图片（悬浮窗，按 q 或 Esc 关闭）
vim.keymap.set('n', '<LocalLeader>i', function() require('snacks.image').hover() end, { desc = '预览光标处图片' })
vim.keymap.set('n', '<LocalLeader>m', '<Cmd>RenderMarkdown toggle<CR>', { desc = '切换 Markdown 渲染' })

-- ### @pdf PDF 文本阅读
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

-- ## @editing 编辑与导航
-- ### @mini mini.nvim 模块
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

-- ### @which-key 快捷键提示
-- 按下 Space 等前缀键后，显示当前实际生效的后续键与中文说明
vim.pack.add({ 'https://github.com/folke/which-key.nvim' })
require('which-key').setup({
  preset = 'classic',
  delay = 300,
  spec = {
    { '<Leader>a', group = 'Avante' },
    { '<Leader>h', group = 'Git' },
  },
})

-- ### @navigation 文件、缓冲区与全文搜索快捷键
vim.keymap.set('n', '<Leader>e', function() Snacks.explorer() end, { desc = '左侧项目树' })
vim.keymap.set('n', '<Leader>E', function()
  local path = vim.api.nvim_buf_get_name(0) -- 定位到当前文件所在目录
  MiniFiles.open(path ~= '' and path or nil)
end, { desc = 'MiniFiles（定位当前文件）' })
vim.keymap.set('n', '<Leader>f', function() MiniPick.builtin.files() end, { desc = '查找文件' })
vim.keymap.set('n', '<Leader>b', function() MiniPick.builtin.buffers() end, { desc = '切换缓冲区' })
vim.keymap.set('n', '<Leader>g', function() MiniPick.builtin.grep_live() end, { desc = '实时全文搜索' })

-- ## @git Git 仓库操作与改动预览
-- ### @neogit Neogit 状态页、区段配色与折叠图标
vim.pack.add({ 'https://github.com/NeogitOrg/neogit' })
vim.api.nvim_set_hl(0, 'NeogitUntrackedfiles', { fg = '#94e2d5', bold = true })
vim.api.nvim_set_hl(0, 'NeogitUnstagedchanges', { fg = '#f9e2af', bold = true })
vim.api.nvim_set_hl(0, 'NeogitStagedchanges', { fg = '#a6e3a1', bold = true })
require('neogit').setup({
  signs = {
    section = { '▸', '▾' },
    item = { '›', '⌄' },
  },
})

-- #### @neogit-indent 状态页显示缩进
-- 用折叠层级做显示缩进，保留 Neogit 用来定位 diff 的原始文本。
local neogit_indent = vim.api.nvim_create_namespace('NeogitStatusIndent')
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('NeogitStatusIndent', { clear = true }),
  pattern = 'NeogitStatus',
  callback = function(args)
    local buf = args.buf
    local pending = false
    local function refresh_indent()
      if pending then return end
      pending = true
      -- 等 Neogit 写完文本和折叠后再计算层级。
      vim.schedule(function()
        pending = false
        if not vim.api.nvim_buf_is_loaded(buf) then return end
        local win = vim.fn.win_findbuf(buf)[1]
        if not win then return end

        vim.api.nvim_win_call(win, function()
          vim.api.nvim_buf_clear_namespace(buf, neogit_indent, 0, -1)
          for line = 1, vim.api.nvim_buf_line_count(buf) do
            local depth = vim.fn.foldlevel(line) - 1
            if depth > 0 then
              vim.api.nvim_buf_set_extmark(buf, neogit_indent, line - 1, 0, {
                virt_text = { { ('  '):rep(depth) } },
                virt_text_pos = 'inline',
              })
            end
          end
        end)
      end)
    end

    vim.api.nvim_buf_attach(buf, false, { on_lines = refresh_indent })
    refresh_indent()
  end,
})

-- #### @neogit-keymap 状态页快捷键
vim.keymap.set('n', '<Leader>hs', '<Cmd>Neogit<CR>', { desc = '打开 Git 仓库状态' })

-- ### @gitsigns Gitsigns 行级改动与快捷键
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

-- #### @gitsigns-colors 工作区与暂存区配色
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

-- ## @avante Codex ACP 对话
vim.pack.add({
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
  'https://github.com/ColinKennedy/mega.logging',
  'https://github.com/ColinKennedy/mega.cmdparse',
  { src = 'https://github.com/avante-corp/avante.nvim', version = avante_version },
})
require('avante').setup({
  provider = 'codex', -- 内置 ACP provider，从 PATH 启动 codex-acp
  acp_providers = {
    codex = {
      -- 优先复用已安装的 Codex CLI，避免 ACP 内置版本不支持当前模型。
      env = { CODEX_PATH = vim.env.CODEX_PATH or vim.fn.exepath('codex') },
    },
  },
  behaviour = { auto_approve_tool_permissions = false },
})

-- ## @statusline 状态栏
-- ### @lualine-theme lualine 插件与主题
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

-- ### @lualine-layout 当前目录与状态栏布局
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

-- ## @languages 语言支持
-- ### @treesitter Treesitter 解析器
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

-- #### @treesitter-display Treesitter 高亮与折叠
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

-- ### @pyright Python LSP（Pyright）
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
