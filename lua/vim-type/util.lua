local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

--- Segundos com precisão de nanossegundos (relógio monotônico).
function M.now()
  return uv.hrtime() / 1e9
end

function M.round(x)
  return math.floor(x + 0.5)
end

--- Divide uma string em caracteres (respeitando UTF-8), com o intervalo
--- de bytes de cada um: { { ch = "ã", s = 0, e = 2 }, ... }
function M.chars(str)
  local out, byte = {}, 0
  for _, ch in ipairs(vim.fn.split(str, "\\zs")) do
    out[#out + 1] = { ch = ch, s = byte, e = byte + #ch }
    byte = byte + #ch
  end
  return out
end

--- Lista simples de caracteres: "não" -> { "n", "ã", "o" }
function M.char_list(str)
  return vim.fn.split(str, "\\zs")
end

--- Completa com espaços até `width` colunas (conta acentos certo).
function M.pad(str, width)
  return str .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(str)))
end

function M.duration(secs)
  secs = M.round(secs)
  if secs < 60 then
    return secs .. "s"
  elseif secs < 3600 then
    return string.format("%dmin %02ds", math.floor(secs / 60), secs % 60)
  end
  return string.format("%dh %02dmin", math.floor(secs / 3600), math.floor(secs % 3600 / 60))
end

local BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

--- Gráfico de uma linha: { 40, 55, 60 } -> "▁▆█"
function M.sparkline(values, max_width)
  if #values == 0 then
    return ""
  end
  -- Se houver mais valores que colunas, agrupa tirando a média de cada grupo
  if max_width and #values > max_width then
    local grouped, size = {}, #values / max_width
    for i = 1, max_width do
      local from, to = math.floor((i - 1) * size) + 1, math.floor(i * size)
      local sum = 0
      for j = from, to do
        sum = sum + values[j]
      end
      grouped[i] = sum / (to - from + 1)
    end
    values = grouped
  end
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(values) do
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  local out = {}
  for _, v in ipairs(values) do
    local i = hi == lo and 4 or math.floor((v - lo) / (hi - lo) * 7 + 0.5) + 1
    out[#out + 1] = BLOCKS[i]
  end
  return table.concat(out)
end

--- Monta linhas de texto com trechos coloridos.
---   local b = util.builder()
---   b:line({ { "87 wpm", "VimTypeResult" }, { " precisão", "VimTypeLabel" } })
function M.builder()
  local b = { lines = {}, hls = {} }

  function b:line(segments)
    local text = ""
    for _, seg in ipairs(segments or {}) do
      local start = #text
      text = text .. seg[1]
      if seg[2] then
        self.hls[#self.hls + 1] = { #self.lines, start, #text, seg[2] }
      end
    end
    self.lines[#self.lines + 1] = text
  end

  function b:blank()
    self.lines[#self.lines + 1] = ""
  end

  function b:width()
    local w = 0
    for _, l in ipairs(self.lines) do
      w = math.max(w, vim.fn.strdisplaywidth(l))
    end
    return w
  end

  function b:apply(buf, ns)
    for _, h in ipairs(self.hls) do
      api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
    end
  end

  return b
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "vim-type" })
end

return M
