-- pane_layout.lua — 窗格分屏佈局碼（TLC）：tab 窗格幾何 → 唯一碼 → 象形字
-- 从 herd.lua 拆出（v4 模块化）：纯几何编码，与 agent 监视无关；
-- 模块坏了只丢佈局碼显示，不影响其它。诊断：/tmp/wezterm-layout.log
--
-- 接口：
--   M.glyph(tab, panes) → 象形字（'吅'/'日'/'田'…；单格返回 '1'，调用方不显示）
--   M.code(tab, panes)  → 裸码（如 '1V(1H1)V1'，无象形字时回退显示这个）
-- 渲染约定：主配置 format-tab-title 里 N≥2 才显示，暗灰，药丸外
local wezterm = require 'wezterm'
local M = {}
local function dbg(msg)
  local f = io.open('/tmp/wezterm-layout.log', 'a')
  if f then f:write(os.date('%H:%M:%S '), tostring(msg), '\n'); f:close() end
end

-- ═══ v2.2 佈局碼（TLC）：geometry → 唯一碼 ═══
-- 三法則：①優先級 V>H（僅影響文本：H 之子免括號，V 之內嵌 H 需括號）
--        ②同向鏈 n 元合併；全單葉且 n≥3 糖寫 nH/nV（n=2 保持 1H1，與原表 N=2 行一致）
--        ③典範化：每節點先取 H 方向全部乾淨切線，無則取 V——算法即典範化
-- 幾何 → 碼：x 區間的重疊連通分量 = 可被豎切線分離的組（觸邊不算重疊 = 乾淨切線）
-- 單位注記：left_col/top_row 與 width/height 若單位不一致（格 vs 像素），
-- 分組比較將失真——首輪 dbg dump 會暴露實際值，必要時再修。

local function strip_groups(panes, is_h)
  local keyed = {}
  for _, p in ipairs(panes) do
    local lo = is_h and p.left or p.top
    local hi = is_h and (p.left + p.width) or (p.top + p.height)
    keyed[#keyed + 1] = { lo = lo, hi = hi, p = p }
  end
  table.sort(keyed, function(a, b) return a.lo < b.lo end)
  local groups, cur, cur_hi = {}, nil, 0
  for _, e in ipairs(keyed) do
    if cur and e.lo < cur_hi then -- 區間重疊 → 同組
      cur[#cur + 1] = e.p
      if e.hi > cur_hi then cur_hi = e.hi end
    else
      cur = { e.p }
      cur_hi = e.hi
      groups[#groups + 1] = cur
    end
  end
  return groups
end

local function enc_layout(panes, axis) -- 返回 code, used_axis
  if #panes == 1 then return '1', nil end
  local groups = strip_groups(panes, axis == 'H')
  if #groups == 1 then
    axis = (axis == 'H') and 'V' or 'H'
    groups = strip_groups(panes, axis == 'H')
    if #groups == 1 then
      return tostring(#panes) .. '?', axis -- 非 guillotine 兜底（wezterm 理論上不會產生）
    end
  end
  local child_axis = (axis == 'H') and 'V' or 'H'
  local parts, all_single = {}, true
  for i, g in ipairs(groups) do
    local s, child_used = enc_layout(g, child_axis)
    if axis == 'V' and child_used == 'H' then
      s = '(' .. s .. ')'
    end
    if s ~= '1' then all_single = false end
    parts[i] = s
  end
  if all_single and #groups >= 3 then
    return tostring(#groups) .. axis, axis
  end
  return table.concat(parts, axis), axis
end

local layout_dumped = {}
local layout_probe = false
function M.layout_code(tab, panes3)
  -- 一次性探针：逐项体检 tab.panes 与第三参数 panes 的可访问性
  if not layout_probe then
    layout_probe = true
    local function try(label, f)
      local ok, v = pcall(f)
      dbg('probe ' .. label .. ': ' .. (ok and tostring(v) or ('ERR ' .. tostring(v))))
    end
    local tp = tab and tab.panes
    try('type(tab)', function() return type(tab) end)
    try('type(tab.panes)', function() return type(tp) end)
    try('#tab.panes', function() return #tp end)
    try('tp[1] type', function() return type(tp[1]) end)
    try('tp[1].pane_id', function() return tostring(tp[1].pane_id) end)
    try('tp[1].left_col', function() return tostring(tp[1].left_col) end)
    try('tp[1].width', function() return tostring(tp[1].width) end)
    try('ipairs(tp) count', function() local n = 0 for _ in ipairs(tp) do n = n + 1 end return n end)
    try('type(p3)', function() return type(panes3) end)
    if type(panes3) == 'table' or type(panes3) == 'userdata' then
      try('#p3', function() return #panes3 end)
      try('p3[1].pane_id', function() return tostring(panes3[1].pane_id) end)
      try('p3[1].left_col', function() return tostring(panes3[1].left_col) end)
      try('p3[1].width', function() return tostring(panes3[1].width) end)
      try('ipairs(p3) count', function() local n = 0 for _ in ipairs(panes3) do n = n + 1 end return n end)
    end
  end
  local panes = tab and tab.panes
  if type(panes) ~= 'table' or #panes == 0 then
    dbg('layout guard 拦截: type=' .. type(panes))
    return ''
  end
  local ok, code = pcall(enc_layout, panes, 'H')
  if not ok then
    dbg('layout ENC ERR: ' .. tostring(code))
    return ''
  end
  -- 驗證協議：每 (tab, 窗格数) 组合首次渲染时落一份幾何+碼的證據
  local key = tostring(tab.tab_id) .. '#' .. #panes
  if not layout_dumped[key] then
    layout_dumped[key] = true
    local bits = {}
    for _, p in ipairs(panes) do
      bits[#bits + 1] = string.format('%d:[%d,%d %dx%d]',
        p.pane_id or -1, p.left or -1, p.top or -1, p.width or -1, p.height or -1)
    end
    dbg('layout tab' .. key .. ' {' .. table.concat(bits, ' ') .. '} => ' .. code)
  end
  return code
end

-- ═══ 渲染層（可插拔）：典範碼 → 象形字；未命中 → 原碼 ═══
-- 框格家族：日=两横格  目=三横格  田=四宫格  品=上1下2  吅=左右二分
-- 卦象家族（三行模式：实线=該行1格，断线=該行左右2格；字體隨緣=Adwaita Mono 兜底）：
--   ☱兌上断[2,1,1] ☲离中虚[1,2,1] ☳震仰盂[2,2,1] ☴巽下断[1,1,2]
--   ☵坎中满[2,1,2] ☶艮覆碗[1,2,2] ☷坤六断[2,2,2]
--   ☰乾三连[1,1,1]=3V 与 目 重复，不入表；旧=丨+日（左1右2，无奈之选）
--   镜像 1V1H1（左2右1）无对应字 → 回退码
-- 弃用记录：朋（伪左三右三，正主䀠=目目，Maple 无）、吕（两盒不如日一框两格）、
-- 三/亖/川/罒（裸笔画与罒形不达标，均回退码）、卌（梯状八格）、
-- B/E 字母象形系（否决）、⊞⊟⊡⌗⁞⫼（两字体皆无）、
-- 3H/4H/4V/1H1V1 等无合格象形 → 回退码。换皮只需改这张表。
local LAYOUT_GLYPH = {
  ['1H1'] = '吅',
  ['1V1'] = '日',
  ['1H1V1'] = '旧', -- 丨=左高格 + 日=右疊二（全 Unicode 无更优解，无奈之选）
  ['3V'] = '目',
  ['1V1H1V1'] = '田',
  ['1V(1H1)'] = '品',
  ['(1H1)V1V1'] = '☱',
  ['1V(1H1)V1'] = '☲',
  ['(1H1)V(1H1)V1'] = '☳',
  ['1V1V(1H1)'] = '☴',
  ['(1H1)V1V(1H1)'] = '☵',
  ['1V(1H1)V(1H1)'] = '☶',
  ['3VH3V'] = '☷',
}

function M.layout_glyph(tab, panes3)
  local code = M.layout_code(tab, panes3)
  if code == '' or code == '1' then return '' end
  return LAYOUT_GLYPH[code] or code
end

return M
