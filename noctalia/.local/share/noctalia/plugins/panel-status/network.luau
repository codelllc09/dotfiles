local previous = {}
local previousTime
local units = { "B", "K", "M", "G", "T" }

local function compact(rate)
  local unit = 1
  while rate >= 999.5 and unit < #units do
    rate /= 1000
    unit += 1
  end
  local format = unit > 1 and rate < 9.95 and "%.1f%s" or "%.0f%s"
  return string.format(format, rate, units[unit])
end

local function render(down, up)
  barWidget.render(ui.column({ gap = 0, width = 40, align = "start", justify = "center",
                              tooltip = "下載 / 上傳 · 每秒" }, {
    ui.label({ text = "↓ " .. down, fontSize = 10, height = 12 }),
    ui.label({ text = "↑ " .. up, fontSize = 10, height = 12 }),
  }))
end

function update()
  local raw = noctalia.readFile("/proc/net/dev")
  local uptime = noctalia.readFile("/proc/uptime")
  local now = uptime and tonumber(uptime:match("^[%d.]+"))
  if not raw or not now then
    render("—", "—")
    return
  end

  local current = {}
  local down, up = 0, 0
  for row in raw:gmatch("[^\n]+") do
    local name, counters = row:match("^%s*([^:%s]+):%s*(.+)$")
    if name and name ~= "lo" then
      local rx, tx = counters:match("^(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
      if rx and tx then
        rx, tx = tonumber(rx), tonumber(tx)
        current[name] = { rx, tx }
        local old = previous[name]
        if old and rx >= old[1] and tx >= old[2] then
          down += rx - old[1]
          up += tx - old[2]
        end
      end
    end
  end

  local elapsed = previousTime and now - previousTime
  previous, previousTime = current, now
  if elapsed and elapsed > 0 then
    render(compact(down / elapsed), compact(up / elapsed))
  else
    render("—", "—")
  end
end

noctalia.setUpdateInterval(2000)
