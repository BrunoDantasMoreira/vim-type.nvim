-- Como funciona:
--   O texto-alvo é colocado num buffer e o usuário digita por cima dele em
--   modo Replace (como na versão original). A cada tecla, o buffer é comparado
--   com o texto-alvo e cada caractere é colorido: certo, errado ou ainda não
--   digitado. Backspace no modo Replace restaura o texto original sozinho.

local api = vim.api
local uv = vim.uv or vim.loop
local util = require("vim-type.util")
local words = require("vim-type.words")
local history = require("vim-type.history")

local M = {}

local ns = api.nvim_create_namespace("vim-type")
local has010 = vim.fn.has("nvim-0.10") == 1

local HINT_RUN = " <Tab> reiniciar · <Esc> pausar "
local HINT_PAUSE = " i continuar · <Tab> reiniciar · q sair "
local HINT_DONE = " r de novo · s estatísticas · q sair "
local GRACE = 1.0 -- segundos em que a tela de resultado ignora teclas

---@type table|nil sessão atual (só existe uma por vez)
local S

-- ---------------------------------------------------------------------------
-- Relógio (pausável)
-- ---------------------------------------------------------------------------

local function elapsed(s)
  local e = s.acc
  if s.ticking then
    e = e + (util.now() - s.t0)
  end
  return e
end

local function clock_start(s)
  if not s.ticking then
    s.t0, s.ticking = util.now(), true
  end
end

local function clock_stop(s)
  if s.ticking then
    s.acc, s.ticking = s.acc + (util.now() - s.t0), false
  end
end

local function live_wpm(s)
  local e = elapsed(s)
  if e < 1 then
    return nil
  end
  return s.correct / 5 / (e / 60)
end

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------

local function center(cfg)
  cfg.row = math.max(0, math.floor((vim.o.lines - cfg.height) / 2) - 2)
  cfg.col = math.max(0, math.floor((vim.o.columns - cfg.width) / 2) - 1)
end

local function set_frame(s, title, footer)
  if s.frame == title .. footer then
    return -- nada mudou, evita redesenhar à toa
  end
  s.frame = title .. footer
  s.cfg.title, s.cfg.title_pos = title, "center"
  if has010 then
    s.cfg.footer, s.cfg.footer_pos = footer, "center"
  end
  if api.nvim_win_is_valid(s.win) then
    api.nvim_win_set_config(s.win, s.cfg)
  end
end

local function items_done(s)
  local n = 0
  for r = 1, s.row - 1 do
    n = n + #s.target[r].ends
  end
  for _, e in ipairs(s.target[s.row].ends) do
    if s.idx >= e then
      n = n + 1
    end
  end
  return n
end

local function refresh_frame(s)
  if s.done then
    return
  end
  local wpm = live_wpm(s)
  local wpm_txt = wpm and string.format(" · %d wpm", util.round(wpm)) or ""
  local title
  if s.paused then
    title = " pausado "
  elseif s.opts.mode == "time" then
    title = s.started
        and string.format(" %ds%s ", math.max(0, math.ceil(s.opts.time - elapsed(s))), wpm_txt)
      or string.format(" %ds · comece a digitar ", s.opts.time)
  else
    title = s.started and string.format(" %d/%d%s ", items_done(s), s.opts.words, wpm_txt)
      or string.format(" %d palavras · comece a digitar ", s.opts.words)
  end
  set_frame(s, title, s.paused and HINT_PAUSE or HINT_RUN)
end

local function scroll_to(s, row)
  local height = api.nvim_win_get_height(s.win)
  local total = api.nvim_buf_line_count(s.buf)
  local top = math.max(1, math.min(row - 1, total - height + 1))
  api.nvim_win_call(s.win, function()
    vim.fn.winrestview({ topline = top })
  end)
end

-- ---------------------------------------------------------------------------
-- Cores e contagem
-- ---------------------------------------------------------------------------

-- Marcas por caractere: "skipped" (pulou com espaço) e "extra" (letra a mais)
local function get_flag(s, kind, row, i)
  return s[kind][row] and s[kind][row][i]
end

local function set_flag(s, kind, row, i, value)
  s[kind][row] = s[kind][row] or {}
  s[kind][row][i] = value
end

--- Recolore o buffer e recalcula quantos caracteres estão certos.
local function render(s)
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local correct, typed = 0, 0

  for r, line in ipairs(lines) do
    local target = s.target[r]
    if not target then
      break
    end
    if r > s.row then
      -- linha inteira ainda não digitada
      api.nvim_buf_set_extmark(s.buf, ns, r - 1, 0, { end_col = #line, hl_group = "VimTypeUntyped" })
    else
      local run_hl, run_s, run_e
      local function flush()
        if run_hl then
          api.nvim_buf_set_extmark(s.buf, ns, r - 1, run_s, { end_col = run_e, hl_group = run_hl })
        end
      end
      for i, c in ipairs(util.chars(line)) do
        local hl
        if r < s.row or i <= s.idx then
          typed = typed + 1
          if get_flag(s, "skipped", r, i) then
            hl = "VimTypeMissed" -- pulou com espaço
          elseif get_flag(s, "extra", r, i) then
            hl = "VimTypeWrongSpace" -- digitou letras a mais antes deste espaço
          elseif c.ch == target.chars[i] then
            hl, correct = "VimTypeCorrect", correct + 1
          elseif c.ch == " " then
            hl = "VimTypeWrongSpace" -- espaço onde devia ter letra
          else
            hl = "VimTypeWrong"
          end
        else
          hl = "VimTypeUntyped"
        end
        if hl == run_hl then
          run_e = c.e
        else
          flush()
          run_hl, run_s, run_e = hl, c.s, c.e
        end
      end
      flush()
    end
  end
  s.correct, s.typed = correct, typed
end

local function append_lines(s, n)
  local new = s.source:lines(n, s.width)
  local texts = {}
  for _, l in ipairs(new) do
    s.target[#s.target + 1] = l
    texts[#texts + 1] = l.text
  end
  api.nvim_buf_set_lines(s.buf, -1, -1, false, texts)
end

-- ---------------------------------------------------------------------------
-- Fim do teste
-- ---------------------------------------------------------------------------

local function show_results(s, r, previous)
  local b = util.builder()
  local L, R = "VimTypeLabel", "VimTypeResult"

  b:blank()
  b:line({
    { string.format("%d wpm", util.round(r.wpm)), R },
    { "   " },
    { string.format("%d%%", util.round(r.acc)), R },
    { " de precisão", L },
  })
  b:blank()
  b:line({
    { util.pad("bruto", 9), L }, { util.pad(string.format("%d wpm", util.round(r.raw)), 11) },
    { util.pad("tempo", 9), L }, { util.duration(r.time) },
  })
  b:line({
    { util.pad("certos", 9), L }, { util.pad(tostring(r.correct), 11) },
    { util.pad("errados", 9), L }, { tostring(r.wrong) },
  })
  b:line({
    { util.pad("teclas", 9), L }, { util.pad(tostring(r.keys), 11) },
    { util.pad("erros", 9), L }, { tostring(r.errors) },
  })
  if #s.samples >= 3 then
    b:blank()
    b:line({ { "wpm ao longo do teste", L } })
    b:line({ { util.sparkline(s.samples, 40), "VimTypeGraph" } })
  end
  b:blank()
  if not previous then
    b:line({ { "primeiro teste com essa configuração", L } })
  elseif r.wpm > previous.wpm then
    b:line({
      { "★ novo recorde!", "VimTypeRecord" },
      { string.format("  antes: %d wpm", util.round(previous.wpm)), L },
    })
  else
    b:line({ { string.format("recorde: %d wpm", util.round(previous.wpm)), L } })
  end
  b:line({ { history.label(r), L } })

  vim.bo[s.buf].modifiable = true
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  api.nvim_buf_set_lines(s.buf, 0, -1, false, b.lines)
  b:apply(s.buf, ns)
  vim.bo[s.buf].modifiable = false

  s.cfg.width = math.max(b:width() + 2, 42)
  s.cfg.height = #b.lines
  center(s.cfg)
  s.frame = nil
  set_frame(s, " resultado ", HINT_DONE)
  api.nvim_win_set_cursor(s.win, { 1, 0 })
  scroll_to(s, 1)
end

local function finish(s)
  if s.done then
    return
  end
  s.done = true
  s.done_at = util.now()
  clock_stop(s)
  s.timer:stop()
  render(s)

  local secs = s.acc
  if s.opts.mode == "time" then
    secs = math.min(secs, s.opts.time)
  end
  secs = math.max(secs, 1)
  local minutes = secs / 60

  local result = {
    date = os.time(),
    list = s.opts.list,
    mode = s.opts.mode,
    value = s.opts.mode == "time" and s.opts.time or s.opts.words,
    punct = s.opts.punctuation and not s.opts.raw or nil,
    wpm = s.correct / 5 / minutes,
    raw = s.typed / 5 / minutes,
    acc = s.keys > 0 and (s.keys - s.errors) / s.keys * 100 or 0,
    time = secs,
    correct = s.correct,
    wrong = s.typed - s.correct,
    keys = s.keys,
    errors = s.errors,
  }

  local previous = history.add(result)

  if api.nvim_get_current_buf() == s.buf and api.nvim_get_mode().mode ~= "n" then
    -- Ainda no modo Replace: o resultado só é desenhado depois de sair dele
    -- (mexer no buffer antes disso gera "E21: 'modifiable' is off").
    s.pending = function()
      show_results(s, result, previous)
    end
    vim.cmd.stopinsert()
  else
    show_results(s, result, previous)
  end
end

-- ---------------------------------------------------------------------------
-- Eventos de digitação
-- ---------------------------------------------------------------------------

--- Chamado antes de cada caractere entrar no buffer: conta acertos/erros,
--- trata letra a mais e espaço no meio da palavra (como no Monkeytype).
local function on_char(s)
  if s.done or s.paused then
    vim.v.char = ""
    return
  end
  local char = vim.v.char
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local idx = vim.fn.strchars(line:sub(1, col))
  if idx >= #s.target[row].chars and s.target[row + 1] then
    -- Fim da linha e as teclas chegaram em rajada (antes do TextChangedI
    -- conseguir pular de linha): move o cursor agora para não perder a tecla.
    row, idx = row + 1, 0
    api.nvim_win_set_cursor(0, { row, 0 })
    line = api.nvim_get_current_line()
  end
  local target = s.target[row]
  local expected = target.chars[idx + 1]
  if not expected then
    vim.v.char = ""
    return
  end

  -- Em qual item (palavra) o cursor está e onde ele começa.
  -- ends[k] = posição logo após o último caractere do item k.
  local item, item_start = #target.ends, 0
  for k, e in ipairs(target.ends) do
    if idx < e then
      item, item_start = k, k > 1 and target.ends[k - 1] + 1 or 0
      break
    end
  end

  if char == " " and expected ~= " " then
    if idx == item_start then
      vim.v.char = "" -- espaço antes de começar a palavra: ignora
      return
    end
    -- Espaço no meio da palavra: marca o resto como perdido e pula para o
    -- separador, que este espaço vai preencher.
    local item_end = target.ends[item] or #target.chars
    for i = idx + 1, item_end do
      set_flag(s, "skipped", row, i, true)
    end
    if not s.started then
      s.started = true
      clock_start(s)
    end
    s.keys, s.errors = s.keys + 1, s.errors + 1
    if item_end >= #target.chars then
      -- era a última palavra do teste
      vim.v.char = ""
      s.row, s.idx = row, item_end
      vim.schedule(function()
        if S == s then
          finish(s)
        end
      end)
      return
    end
    api.nvim_win_set_cursor(0, { row, vim.fn.byteidx(line, item_end) })
    return
  end

  if expected == " " and char ~= " " then
    -- Letra a mais no fim da palavra: não entra (senão desalinha todo o
    -- resto), mas conta como erro e deixa o espaço marcado em vermelho.
    vim.v.char = ""
    if s.started then
      s.keys, s.errors = s.keys + 1, s.errors + 1
      set_flag(s, "extra", row, idx + 1, true)
      vim.schedule(function()
        if S == s and not s.done then
          render(s)
        end
      end)
    end
    return
  end

  if not s.started then
    s.started = true
    clock_start(s)
  end
  set_flag(s, "skipped", row, idx + 1, nil) -- voltou e digitou aqui
  s.keys = s.keys + 1
  if char ~= expected then
    s.errors = s.errors + 1
  end
end

--- Chamado depois que o texto muda ou o cursor anda.
local function on_change(s)
  if s.done or not api.nvim_win_is_valid(s.win) then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(s.win))
  local line = api.nvim_buf_get_lines(s.buf, row - 1, row, false)[1] or ""
  local idx = vim.fn.strchars(line:sub(1, col))

  if idx >= #s.target[row].chars then
    if row >= #s.target then
      if s.opts.mode == "words" then
        s.row, s.idx = row, idx
        return finish(s)
      end
    else
      -- terminou a linha: pula para a próxima
      row, idx = row + 1, 0
      api.nvim_win_set_cursor(s.win, { row, 0 })
      if s.opts.mode == "time" and row + 3 > #s.target then
        append_lines(s, 6) -- modo tempo: texto infinito
      end
      scroll_to(s, row)
    end
  end

  s.row, s.idx = row, idx
  s.pos = api.nvim_win_get_cursor(s.win) -- para continuar daqui depois de pausar
  render(s)
  refresh_frame(s)
end

local function tick(s)
  if S ~= s or s.done then
    return
  end
  if s.ticking then
    local e = elapsed(s)
    -- guarda o wpm de cada segundo para o gráfico do resultado
    while #s.samples < math.floor(e) do
      s.samples[#s.samples + 1] = s.correct / 5 / ((#s.samples + 1) / 60)
    end
    if s.opts.mode == "time" and e >= s.opts.time then
      return finish(s)
    end
  end
  refresh_frame(s)
end

-- ---------------------------------------------------------------------------
-- Controle
-- ---------------------------------------------------------------------------

local function resume(s)
  if not s.paused or s.done then
    return
  end
  s.paused = false
  vim.bo[s.buf].modifiable = true
  local row, col = s.pos[1], s.pos[2]
  local line = api.nvim_buf_get_lines(s.buf, row - 1, row, false)[1] or ""
  api.nvim_win_set_cursor(s.win, { row, math.min(col, #line) })
  vim.cmd(col >= #line and "startreplace!" or "startreplace")
  refresh_frame(s)
end

function M.close()
  if not S then
    return
  end
  local s = S
  S = nil
  s.timer:stop()
  if not s.timer:is_closing() then
    s.timer:close()
  end
  pcall(api.nvim_del_augroup_by_id, s.group)
  if api.nvim_get_current_buf() == s.buf and api.nvim_get_mode().mode ~= "n" then
    vim.cmd.stopinsert()
  end
  if api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
end

function M.restart()
  if not S then
    return
  end
  local opts = S.opts
  M.close()
  vim.schedule(function()
    M.start(opts)
  end)
end

local function set_keymaps(s)
  local buf = s.buf
  local function map(mode, lhs, rhs, extra)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = buf, nowait = true, silent = true }, extra or {}))
  end

  -- Teclas que bagunçariam o texto ou o cursor durante o teste
  for _, key in ipairs({
    "<CR>", "<NL>", "<C-j>", "<C-m>", "<S-Tab>", "<Del>", "<Insert>",
    "<Up>", "<Down>", "<Left>", "<Right>", "<Home>", "<End>", "<PageUp>", "<PageDown>",
    "<C-u>", "<C-o>", "<C-r>", "<C-n>", "<C-p>", "<C-a>", "<C-t>", "<C-d>",
    "<C-e>", "<C-y>", "<C-x>", "<C-v>", "<C-q>", "<C-Space>",
    "<LeftMouse>", "<2-LeftMouse>", "<ScrollWheelUp>", "<ScrollWheelDown>",
  }) do
    map("i", key, "<Nop>")
  end

  -- Backspace funciona, mas não volta para a linha anterior
  local function guarded(key)
    return function()
      return api.nvim_win_get_cursor(0)[2] == 0 and "" or key
    end
  end
  map("i", "<BS>", guarded("<BS>"), { expr = true })
  map("i", "<C-h>", guarded("<BS>"), { expr = true })
  map("i", "<C-w>", guarded("<C-w>"), { expr = true })
  map("i", "<C-BS>", guarded("<C-w>"), { expr = true })

  -- <C-c> não dispara InsertLeave; troca por <Esc> para pausar direito
  map("i", "<C-c>", "<Esc>")
  map("i", "<Tab>", M.restart)

  -- Modo normal (pausado ou na tela de resultado).
  -- Quando o tempo acaba você provavelmente ainda está digitando: essas teclas
  -- caem no modo normal. Por isso, teclas soltas não fazem nada (nada de
  -- disparar <leader>... sem querer) e os comandos só valem depois de um
  -- pequeno intervalo.
  local function ready()
    return not s.done or (util.now() - s.done_at) > GRACE
  end
  local function action(fn)
    return function()
      if ready() then
        fn()
      end
    end
  end

  local reserved = { i = 1, a = 1, I = 1, A = 1, R = 1, o = 1, O = 1, q = 1, r = 1, s = 1, [":"] = 1 }
  local special = { ["<"] = "<lt>", ["|"] = "<Bar>", ["\\"] = "<Bslash>" }
  for code = 33, 126 do
    local c = string.char(code)
    if not reserved[c] then
      map("n", special[c] or c, "<Nop>")
    end
  end
  map("n", "<Space>", "<Nop>")
  map("n", ":", action(function()
    api.nvim_feedkeys(":", "n", false)
  end))

  for _, key in ipairs({ "i", "a", "I", "A", "R", "o", "O" }) do
    map("n", key, function()
      resume(s)
    end)
  end
  map("n", "<CR>", action(function()
    if s.done then
      M.close()
    else
      resume(s)
    end
  end))
  map("n", "s", action(function()
    if s.done then
      M.close()
      require("vim-type.stats").show()
    else
      resume(s)
    end
  end))
  map("n", "q", action(M.close))
  map("n", "<Esc>", action(M.close))
  map("n", "r", action(M.restart))
  map("n", "<Tab>", action(M.restart))
end

local function set_autocmds(s)
  s.group = api.nvim_create_augroup("VimTypeSession", { clear = true })
  local function au(event, fn)
    api.nvim_create_autocmd(event, {
      group = s.group,
      buffer = s.buf,
      callback = function()
        if S == s then
          fn()
        end
      end,
    })
  end

  au("InsertCharPre", function()
    on_char(s)
  end)
  au({ "TextChangedI", "CursorMovedI" }, function()
    on_change(s)
  end)
  au("InsertEnter", function()
    if s.started and not s.done then
      clock_start(s)
    end
  end)
  au("InsertLeave", function()
    if s.done then
      if s.pending then
        local show = s.pending
        s.pending = nil
        vim.schedule(function()
          if S == s then
            show()
          end
        end)
      end
      return
    end
    s.paused = true
    clock_stop(s)
    vim.bo[s.buf].modifiable = false
    refresh_frame(s)
  end)
  au("WinLeave", function()
    vim.schedule(function()
      if S == s and api.nvim_get_current_win() ~= s.win then
        M.close()
      end
    end)
  end)

  api.nvim_create_autocmd("VimResized", {
    group = s.group,
    callback = function()
      if S == s and api.nvim_win_is_valid(s.win) then
        center(s.cfg)
        api.nvim_win_set_config(s.win, s.cfg)
      end
    end,
  })
end

---@param opts table opções já resolvidas (ver init.lua)
function M.start(opts)
  M.close()

  local width = math.max(20, math.min(opts.width, vim.o.columns - 8))
  local source = words.source(opts.items, {
    punctuation = opts.punctuation and not opts.raw,
    limit = opts.mode == "words" and opts.words or nil,
  })
  local target = source:lines(opts.mode == "words" and math.huge or opts.height + 6, width)

  if opts.mode == "words" then
    -- a última linha não precisa do espaço final
    local last = target[#target]
    last.text = last.text:sub(1, -2)
    last.chars[#last.chars] = nil
  end

  local texts = {}
  for _, l in ipairs(target) do
    texts[#texts + 1] = l.text
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "vimtype"
  vim.bo[buf].textwidth = 0
  vim.bo[buf].formatoptions = ""
  vim.bo[buf].undolevels = -1

  local cfg = {
    relative = "editor",
    width = width + 2,
    height = math.min(opts.height, #texts),
    style = "minimal",
    border = opts.border,
    zindex = 60,
    title = " vim-type ",
    title_pos = "center",
  }
  if has010 then
    cfg.footer, cfg.footer_pos = HINT_RUN, "center"
  end
  center(cfg)

  local win = api.nvim_open_win(buf, true, cfg)
  -- Sem isso, cada atualização do título reaplicaria o estilo "minimal"
  -- e desfaria as opções da janela abaixo.
  cfg.style = nil
  local wo = vim.wo[win]
  wo.wrap = false
  wo.foldcolumn = "1" -- margem à esquerda
  wo.scrolloff = 0
  wo.sidescrolloff = 0
  wo.cursorline = false
  wo.spell = false
  wo.list = false
  wo.winhighlight = "Normal:NormalFloat,FoldColumn:NormalFloat,EndOfBuffer:NormalFloat"

  -- Desliga o autocompletar neste buffer (nvim-cmp e blink.cmp)
  vim.b[buf].completion = false
  pcall(function()
    require("cmp").setup.buffer({ enabled = false })
  end)

  local s = {
    opts = opts,
    buf = buf,
    win = win,
    cfg = cfg,
    width = width,
    source = source,
    target = target,
    row = 1,
    idx = 0,
    pos = { 1, 0 },
    started = false,
    paused = false,
    done = false,
    ticking = false,
    acc = 0,
    t0 = 0,
    keys = 0,
    errors = 0,
    correct = 0,
    typed = 0,
    samples = {},
    skipped = {},
    extra = {},
    timer = uv.new_timer(),
  }
  S = s

  set_keymaps(s)
  set_autocmds(s)
  render(s)
  refresh_frame(s)
  s.timer:start(100, 100, vim.schedule_wrap(function()
    tick(s)
  end))

  vim.cmd("startreplace")
end

return M
