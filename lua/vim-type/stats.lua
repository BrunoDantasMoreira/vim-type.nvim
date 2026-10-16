local api = vim.api
local util = require("vim-type.util")
local history = require("vim-type.history")

local M = {}

local ns = api.nvim_create_namespace("vim-type-stats")

local function build()
  local list = history.load()
  local b = util.builder()
  local L, R = "VimTypeLabel", "VimTypeResult"

  if #list == 0 then
    b:line({ { "Nenhum teste feito ainda.", L } })
    b:line({ { "Use " }, { ":Type", R }, { " para começar!" } })
    return b
  end

  -- Resumo geral
  local total_time = 0
  for _, e in ipairs(list) do
    total_time = total_time + (e.time or 0)
  end
  b:line({
    { "testes ", L }, { tostring(#list), R },
    { "    tempo digitando ", L }, { util.duration(total_time), R },
  })

  local last, wpm_sum, acc_sum = math.min(10, #list), 0, 0
  for i = #list - last + 1, #list do
    wpm_sum, acc_sum = wpm_sum + list[i].wpm, acc_sum + list[i].acc
  end
  b:line({
    { "média dos últimos " .. last .. "  ", L },
    { string.format("%d wpm", util.round(wpm_sum / last)), R },
    { " · ", L },
    { string.format("%d%%", util.round(acc_sum / last)), R },
  })

  -- Evolução
  if #list >= 2 then
    local values = {}
    for i = math.max(1, #list - 39), #list do
      values[#values + 1] = list[i].wpm
    end
    b:blank()
    b:line({ { "evolução (últimos " .. #values .. " testes)", L } })
    b:line({ { util.sparkline(values, 40), "VimTypeGraph" } })
  end

  -- Recordes por configuração
  local bests, seen = {}, {}
  for _, e in ipairs(list) do
    local key = history.key(e)
    if not seen[key] then
      seen[key] = true
      bests[#bests + 1] = history.best(list, key)
    end
  end
  table.sort(bests, function(a, c)
    return a.wpm > c.wpm
  end)

  b:blank()
  b:line({ { "recordes", L } })
  for i = 1, math.min(8, #bests) do
    local e = bests[i]
    b:line({
      { util.pad(history.label(e), 28) },
      { util.pad(string.format("%d wpm", util.round(e.wpm)), 9), R },
      { util.pad(string.format("%d%%", util.round(e.acc)), 6) },
      { os.date("%d/%m/%y", e.date), L },
    })
  end

  -- Últimos testes
  b:blank()
  b:line({ { "últimos testes", L } })
  for i = #list, math.max(1, #list - 7), -1 do
    local e = list[i]
    b:line({
      { os.date("%d/%m %H:%M", e.date) .. "   ", L },
      { util.pad(history.label(e), 28) },
      { util.pad(string.format("%d wpm", util.round(e.wpm)), 9), R },
      { string.format("%d%%", util.round(e.acc)) },
    })
  end
  return b
end

function M.show()
  local b = build()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, b.lines)
  b:apply(buf, ns)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "vimtype-stats"

  local width = math.min(b:width() + 2, vim.o.columns - 4)
  local height = math.min(#b.lines, vim.o.lines - 6)
  local cfg = {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 2),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
    style = "minimal",
    border = require("vim-type").config.border,
    title = " vim-type · estatísticas ",
    title_pos = "center",
    zindex = 60,
  }
  if vim.fn.has("nvim-0.10") == 1 then
    cfg.footer = " q fechar "
    cfg.footer_pos = "center"
  end
  local win = api.nvim_open_win(buf, true, cfg)
  vim.wo[win].foldcolumn = "1"
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "Normal:NormalFloat,FoldColumn:NormalFloat"

  local function close()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
  end
  api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = vim.schedule_wrap(close) })
end

return M
