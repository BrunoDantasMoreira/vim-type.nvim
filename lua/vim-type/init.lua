local api = vim.api
local util = require("vim-type.util")
local words = require("vim-type.words")

local M = {}

M.defaults = {
  list = "en", -- lista padrão: "en", "pt", "vim" ou uma das suas
  mode = "time", -- "time" (contra o relógio) ou "words" (quantidade de palavras)
  time = 30, -- segundos no modo "time"
  words = 25, -- palavras no modo "words"
  punctuation = false, -- maiúsculas e pontuação (não vale para a lista "vim")
  width = 70, -- largura máxima do texto
  height = 3, -- linhas visíveis
  border = "rounded",
  -- Listas próprias. Cada valor pode ser:
  --   "~/caminho/lista.txt"                 (um item por linha)
  --   { path = "~/lista.txt", raw = true }  (raw = sem pontuação automática)
  --   { "palavra", "outra", ... }
  lists = {},
}

M.config = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.highlights()
  local function set(name, val)
    val.default = true
    api.nvim_set_hl(0, name, val)
  end
  -- Só a cor do texto do Normal, para não "furar" o fundo da janela flutuante
  local ok, normal = pcall(api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and normal and normal.fg then
    set("VimTypeCorrect", { fg = normal.fg })
  else
    set("VimTypeCorrect", { link = "Normal" })
  end
  set("VimTypeUntyped", { link = "Comment" })
  -- Letras que você pulou com espaço: cor de "não digitado" sublinhada de vermelho
  local _, comment = pcall(api.nvim_get_hl, 0, { name = "Comment", link = false })
  local _, err = pcall(api.nvim_get_hl, 0, { name = "DiagnosticError", link = false })
  if type(comment) == "table" and comment.fg then
    set("VimTypeMissed", { fg = comment.fg, underline = true, sp = type(err) == "table" and err.fg or nil })
  else
    set("VimTypeMissed", { link = "DiagnosticUnderlineError" })
  end
  set("VimTypeWrong", { link = "DiagnosticError" })
  set("VimTypeWrongSpace", { link = "DiffDelete" })
  set("VimTypeResult", { link = "Title" })
  set("VimTypeLabel", { link = "Comment" })
  set("VimTypeGraph", { link = "Function" })
  set("VimTypeRecord", { link = "DiagnosticOk" })
end

--- Lê os argumentos do :Type. Ex: { "pt", "60s", "punct" }
---@return table|nil opts, string|nil erro
function M.parse(args)
  local c = M.config
  local o = { list = c.list, mode = c.mode, time = c.time, words = c.words, punctuation = c.punctuation }

  for _, arg in ipairs(args or {}) do
    local lower = arg:lower()
    local secs = lower:match("^(%d+)s$")
    if secs then
      o.mode, o.time = "time", tonumber(secs)
    elseif lower:match("^%d+$") then
      o.mode, o.words = "words", tonumber(lower)
    elseif lower == "punct" or lower == "p" then
      o.punctuation = true
    elseif lower == "nopunct" then
      o.punctuation = false
    elseif words.exists(arg, c.lists) then
      o.list = arg == "words" and "en" or arg
    elseif words.exists(lower, c.lists) then
      o.list = lower
    else
      return nil, "argumento desconhecido: '" .. arg .. "' (veja :h vim-type)"
    end
  end

  if o.mode == "time" and o.time < 1 then
    return nil, "o tempo precisa ser de pelo menos 1s"
  end
  if o.mode == "words" and o.words < 1 then
    return nil, "precisa de pelo menos 1 palavra"
  end
  return o
end

--- Ponto de entrada do comando :Type.
---@param args string[]|table lista de argumentos ou tabela de opções
function M.start(args)
  if vim.fn.has("nvim-0.9") == 0 then
    return util.notify("vim-type precisa do Neovim 0.9 ou mais novo", vim.log.levels.ERROR)
  end
  args = args or {}

  if args[1] == "stats" then
    if args[2] == "clear" then
      local answer = vim.fn.confirm("Apagar todo o histórico do vim-type?", "&Sim\n&Não", 2)
      if answer == 1 then
        require("vim-type.history").clear()
        util.notify("histórico apagado")
      end
      return
    end
    M.highlights()
    return require("vim-type.stats").show()
  end

  local opts, err
  local islist = vim.islist or vim.tbl_islist
  if islist(args) then
    opts, err = M.parse(args)
  else
    -- chamado pelo Lua com uma tabela: require("vim-type").start({ list = "pt" })
    opts = vim.tbl_extend("force", M.parse({}), args)
  end
  if not opts then
    return util.notify(err, vim.log.levels.WARN)
  end

  local items, raw = words.load(opts.list, M.config.lists)
  if not items then
    return util.notify(raw, vim.log.levels.WARN)
  end

  opts.items, opts.raw = items, raw
  opts.width, opts.height, opts.border = M.config.width, M.config.height, M.config.border

  M.highlights()
  require("vim-type.game").start(opts)
end

M.run = M.start

function M.complete(arglead, cmdline)
  local parts = vim.split(cmdline, "%s+", { trimempty = true })
  local choices
  if parts[2] == "stats" and (#parts > 2 or arglead == "") then
    choices = { "clear" }
  else
    choices = words.names(M.config.lists)
    vim.list_extend(choices, { "15s", "30s", "60s", "120s", "10", "25", "50", "100", "punct", "stats" })
  end
  return vim.tbl_filter(function(c)
    return c:find(arglead, 1, true) == 1
  end, choices)
end

return M
