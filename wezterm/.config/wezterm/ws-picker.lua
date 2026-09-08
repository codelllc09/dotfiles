-- ws-picker.lua — 工作区选择器 TUI（LuaJIT，yazi 风抽屉，运行于 wezterm top-level split）
-- ─────────────────────────────────────────────────────────────
-- 由 workspace.lua 经 pane:split 拉起：
--   luajit ws-picker.lua <当前工作区> <名字:pane数> ...
-- 清单快照由配置侧传参（零子进程，启动即绘，~3ms 级）。自绘圆角边框面板。
-- 结果写唯一命名的 result 文件（{"op":"goto"|"new"|"del"|"cancel","name":...}）后退出，
-- pane 随进程消亡自动关闭；配置侧轮询该文件执行跳转/新建/删除。
-- 键位：字符过滤（完整行编辑：←→/Home/End/Ctrl+A·E·B·F·D，Backspace/Del 删字符）
--       · Tab 补全 · ↑↓/Ctrl+P·N 移动 · Enter 跳转（无匹配=新建）
--       · Ctrl+D 行尾=删除选中工作区（default 拒删；y 确认 n 取消）· Esc 即退
-- 注意：参与宽度对齐/填充的行一律 ASCII（边框字符不参与填充），
--       避免模糊宽字符（●▸▏等）在 wezterm 下 1/2 列歧义导致边框错位。
-- 结果路径由配置侧生成（唯一名，经 argv[1] 传入）：配置侧对该路径零写入，
-- 规避本 build 配置 io 写影子（实测：配置写过同路径后读到的永远是自己的空影子）
local RESULT = arg[1]
local CUR = arg[2] or 'default'

-- ── 数据：argv 传入 name:tabs:panes 三元组 ──
local names, counts, tabs_n = {}, {}, {}
for i = 2, #arg do
  local n, tb, pn = arg[i]:match('^(.-):(%d+):(%d+)$')
  if n and n ~= '' then
    names[#names + 1] = n
    tabs_n[n] = tonumber(tb) or 0
    counts[n] = tonumber(pn) or 1
  end
end
if #names == 0 then names[1] = 'default' end
table.sort(names, function(a, b) -- default 恒 1，余字母序（与右栏 n/m 一致）
  if a == 'default' then return b ~= 'default' end
  if b == 'default' then return false end
  return a < b
end)
local index_of = {}
for i, n in ipairs(names) do index_of[n] = i end

-- ── FFI：poll（键等待/超时 tick）+ ioctl（取尺寸）+ read（绕过 stdio 缓冲）──
local ffi = require 'ffi'
ffi.cdef[[
  typedef struct { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; } winsize_t;
  typedef struct { int fd; short events; short revents; } pollfd_t;
  int ioctl(int fd, unsigned long req, void *arg);
  int poll(pollfd_t *fds, unsigned long nfds, int timeout);
  ssize_t read(int fd, void *buf, size_t count);
]]
local TIOCGWINSZ = 0x5413

local function term_size()
  local ws = ffi.new('winsize_t')
  if ffi.C.ioctl(0, TIOCGWINSZ, ws) == 0 and ws.ws_col > 4 then
    return ws.ws_row, ws.ws_col
  end
  return 24, 80
end

local KEYLOG = '/tmp/ws-keys.log'
local function klog(bytes, note)
  local f = io.open(KEYLOG, 'a')
  if f then
    local hex = {}
    for i = 1, #bytes do hex[#hex + 1] = string.format('%02x', bytes:byte(i)) end
    f:write(os.date('%H:%M:%S '), '[' .. table.concat(hex, ' ') .. '] ', note or '', '\n')
    f:close()
  end
end

local function key_ready(ms)
  local pfd = ffi.new('pollfd_t[1]')
  pfd[0].fd = 0
  pfd[0].events = 1 -- POLLIN
  return ffi.C.poll(pfd, 1, ms) > 0
end

local function read_byte()
  local buf = ffi.new('char[1]')
  if ffi.C.read(0, buf, 1) == 1 then return bit.band(buf[0], 0xff) end
  return nil
end

-- ── Catppuccin Mocha ──
local C = {
  dim = '\27[38;2;88;91;112m', text = '\27[38;2;205;214;244m',
  accent = '\27[38;2;180;190;252m', green = '\27[38;2;166;228;161m',
  red = '\27[38;2;243;139;168m', selbg = '\27[48;2;69;71;90m',
  bold = '\27[1m', reset = '\27[0m',
}

-- ── 宽度/截断（UTF-8 感知；参与填充的内容仅 ASCII + 2字节窄符）──
local function vwidth(s)
  local w, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then w = w + 1; i = i + 1
    elseif b >= 0xF0 then w = w + 2; i = i + 4
    elseif b >= 0xE0 then w = w + 2; i = i + 3
    elseif b >= 0xC0 then w = w + 1; i = i + 2 -- 2字节窄符（·等）
    else i = i + 1 end
  end
  return w
end

local function truncate(s, w)
  local out, vw, i = {}, 0, 1
  while i <= #s do
    local b = s:byte(i)
    local len, cw
    if b < 0x80 then len, cw = 1, 1
    elseif b >= 0xF0 then len, cw = 4, 2
    elseif b >= 0xE0 then len, cw = 3, 2
    elseif b >= 0xC0 then len, cw = 2, 1
    else len, cw = 1, 0 end
    if cw > 0 then
      if vw + cw > w then break end
      vw = vw + cw
      out[#out + 1] = s:sub(i, i + len - 1)
    end
    i = i + len
  end
  return table.concat(out)
end

local function padn(plain, w)
  local n = math.max(w - vwidth(plain), 0)
  if n == 0 then return '' end
  return (' '):rep(n)
end

-- ── 状态 ──
local fltr, sel, msg, running = '', 0, nil, true
local cursor = 1 -- 光标字节位（1..#fltr+1）；输入限 ASCII，字节即字符
local matches = {}

local function refresh()
  matches = {}
  if fltr == '' then
    for _, n in ipairs(names) do matches[#matches + 1] = n end
  else
    for _, n in ipairs(names) do
      if n:sub(1, #fltr) == fltr then matches[#matches + 1] = n end
    end
  end
  if sel > math.max(#matches - 1, 0) then sel = math.max(#matches - 1, 0) end
end
refresh()

local function complete()
  if #matches == 1 then
    fltr = matches[1]
  elseif #matches > 1 then
    local p = matches[1]
    for _, s in ipairs(matches) do
      while #p > 0 and s:sub(1, #p) ~= p do p = p:sub(1, -2) end
    end
    if #p > #fltr then fltr = p end
  end
  refresh()
end

local function jstr(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function finish(op, name)
  local f = io.open(RESULT, 'w')
  if f then
    f:write('{"op":"', op, '","name":', name and jstr(name) or 'null', '}')
    f:close()
  end
  -- 动作编码进 pane 标题（OSC2）：本 build 配置 Lua 看不见 pane 子进程新建的
  -- /tmp 文件（实测 No such file），但标题经 mux 可靠流动（rime 同款机制）。
  -- 配置侧 update-right-status 扫描本标题完成派发。
  -- cancel 无需配置侧动作：不广播、不保活，即退（Esc 零延迟）。
  if op ~= 'cancel' then
    io.write('\27]2;ws-pick:' .. op .. ':' .. (name or '') .. '\27\\')
    io.flush()
    -- mux 级触发（pane OSC 不唤醒配置侧，rime 同款机制保险）
    os.execute('wezterm cli set-tab-title ">" >/dev/null 2>&1')
    -- 保活窗口：让配置侧来得及读到标题（随后本进程退出、pane 关闭、标题消失）
    os.execute('sleep 1.2 2>/dev/null')
  end
  running = false
end

local function resolve() -- 选中行优先，否则过滤首项
  return matches[sel + 1] or matches[1]
end

local function on_enter()
  if fltr ~= '' and #matches == 0 then return finish('new', fltr) end
  if fltr ~= '' and fltr == matches[1] then return finish('goto', fltr) end
  local t = resolve()
  if t then return finish('goto', t) end
  if fltr ~= '' then return finish('new', fltr) end
  msg = 'empty'
end

-- 刪除工作區功能已拆除(2026-09-09):批量異步 kill-pane = 窗口 churn 風暴,
-- 餵 wayland panic(主配置守則⑨)。要刪工作區:進去手動關 tab

-- ── 绘制（每帧一次 io.write；填充行纯 ASCII 保对齐）──
local function draw(r, c)
  local iw = c - 4 -- '│ ' + 内容 + ' ' + '│'
  local out = { '\27[H\27[2J' }
  local edge = C.dim .. '╭' .. ('─'):rep(c - 2) .. '╮' .. C.reset
  out[#out + 1] = edge

  -- 头部
  local title_plain = ' Workspace '
  local hint = 'Enter=jump/create · Tab=complete · Esc=quit'
  local room = math.max(iw - vwidth(title_plain), 0)
  local hint_cut = truncate(hint, room)
  out[#out + 1] = '│ ' .. C.accent .. C.bold .. title_plain .. C.reset .. C.dim
    .. hint_cut .. C.reset .. padn(title_plain .. hint_cut, iw) .. ' ' .. C.dim .. '│' .. C.reset

  -- 输入行（光标 '_' 插在字节位 cursor 处）
  local before = fltr:sub(1, cursor - 1)
  local after = fltr:sub(cursor)
  local in_plain = '> ' .. before .. '_' .. after
  local msg_plain = msg and (' !' .. msg) or ''
  out[#out + 1] = '│ ' .. C.text .. '> ' .. before .. C.accent .. '_' .. C.text .. after .. C.reset
    .. (msg and (C.red .. msg_plain .. C.reset) or '') .. padn(in_plain .. msg_plain, iw)
    .. ' ' .. C.dim .. '│' .. C.reset

  -- 分隔
  out[#out + 1] = C.dim .. '│ ' .. ('-'):rep(iw) .. ' ' .. C.reset .. '│'

  -- 列表
  local list_rows = math.max(r - 5, 1)
  for i = 1, list_rows do
    local n = matches[i]
    if n then
      local mark = (n == CUR) and '*' or ' '
      local body = string.format('%2d. %s %s', index_of[n] or 1, mark, n)
      local tp, pc = tabs_n[n], counts[n]
      if tp and tp > 1 then body = body .. ' ' .. tostring(tp) .. 't' end
      if pc and pc > 1 then body = body .. ' ' .. tostring(pc) .. 'p' end
      if i == sel + 1 then
        out[#out + 1] = '│ ' .. C.selbg .. C.text .. C.bold .. body .. C.reset
          .. C.selbg .. padn(body, iw) .. C.reset .. ' ' .. C.dim .. '│' .. C.reset
      else
        local color = (n == CUR) and C.accent or C.text
        out[#out + 1] = '│  ' .. color .. body .. C.reset .. padn('  ' .. body, iw)
          .. ' ' .. C.dim .. '│' .. C.reset
      end
    else
      out[#out + 1] = '│' .. (' '):rep(c - 2) .. '│'
    end
  end

  out[#out + 1] = C.dim .. '╰' .. ('─'):rep(c - 2) .. '╯' .. C.reset
  -- raw 模式下 ONLCR 已關：必須 '\r\n'，且幀尾不加換行（避免每次繪製累積上捲）
  io.write(table.concat(out, '\r\n'))
  io.flush()
end

-- ── 终端原始模式 ──
local saved_tty = ''
do
  local p = io.popen('stty -g 2>/dev/null')
  if p then saved_tty = p:read('*l') or '' p:close() end
end
os.execute('stty raw -echo 2>/dev/null')
io.write('\27[?25l')
io.flush()

-- 行编辑原语（cursor = 字节位 1..#fltr+1）
local function insert(ch)
  fltr = fltr:sub(1, cursor - 1) .. ch .. fltr:sub(cursor)
  cursor = cursor + #ch
  if #fltr > 32 then -- 超长回退
    fltr = fltr:sub(1, 32)
    cursor = math.min(cursor, 33)
  end
  refresh()
end

local function backspace()
  if cursor > 1 then
    fltr = fltr:sub(1, cursor - 2) .. fltr:sub(cursor)
    cursor = cursor - 1
    refresh()
  end
end

local function delete_at()
  if cursor <= #fltr then
    fltr = fltr:sub(1, cursor - 1) .. fltr:sub(cursor + 1)
    refresh()
  end
end

-- ── 主循环 ──
key_ready(300) -- 等分割重排落定（首帧必须用排定后的尺寸，画早了必碎）
local last_r, last_c = term_size()
while running do
  draw(last_r, last_c)
  while running do
    if key_ready(250) then
      local b = read_byte()
      if not b then running = false break end
      local seq = string.char(b)
      if b == 27 then
        -- 规范 CSI/SS3 解析：只吃一个完整序列，后续独立按键留给下一轮派发
        if key_ready(25) then
          local b2 = read_byte()
          if b2 == 91 then -- CSI：参数字节(0x30-0x3F等) + 终止字节(0x40-0x7E)
            seq = seq .. string.char(b2)
            while key_ready(15) do
              local m = read_byte()
              if not m then break end
              seq = seq .. string.char(m)
              if m >= 0x40 and m <= 0x7E then break end
            end
          elseif b2 == 79 then -- SS3：再吃一字节
            seq = seq .. string.char(b2)
            if key_ready(15) then
              local m = read_byte()
              if m then seq = seq .. string.char(m) end
            end
          else
            seq = seq .. string.char(b2)
          end
        end
      end
      klog(seq)
      if seq == '\r' or seq == '\n' or seq == '\27[13u' or seq == '\27[27u' then
        on_enter()
      elseif seq == '\27' then
        finish('cancel')
      elseif seq == '\127' or seq == '\8' or seq == '\27[127u' or seq == '\27[3~' then
        if seq == '\27[3~' then delete_at() else backspace() end
      elseif seq == '\t' or seq == '\27[9u' then
        complete()
      elseif seq == '\27[A' or seq == '\27[1;2A' or seq == '\16' then
        sel = math.max(sel - 1, 0)
      elseif seq == '\27[B' or seq == '\27[1;2B' or seq == '\14' then
        sel = math.min(sel + 1, math.max(#matches - 1, 0))
      elseif seq == '\27[D' or seq == '\27[1;2D' or seq == '\2' then
        cursor = math.max(cursor - 1, 1)
      elseif seq == '\27[C' or seq == '\27[1;2C' or seq == '\6' then
        cursor = math.min(cursor + 1, #fltr + 1)
      elseif seq == '\27[H' or seq == '\27[1~' or seq == '\1' then
        cursor = 1
      elseif seq == '\27[F' or seq == '\27[4~' or seq == '\5' then
        cursor = #fltr + 1
-- Ctrl+D 整鍵已摘(2026-09-09):刪字符用 Backspace/Del 即可
      elseif #seq == 1 and seq:byte(1) >= 32 and seq:byte(1) < 127 then
        if #fltr < 32 then
          insert(seq)
        end
      end
      break -- 重绘
    else
      local r, c = term_size()
      if r ~= last_r or c ~= last_c then -- 分割/拖拽重排 → 重绘
        last_r, last_c = r, c
        break
      end
    end
  end
end

-- ── 收尾还原 ──
io.write('\27[?25h\27[0m')
io.flush()
if saved_tty ~= '' then
  os.execute('stty ' .. saved_tty .. ' 2>/dev/null')
else
  os.execute('stty sane 2>/dev/null')
end
