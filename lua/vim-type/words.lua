local util = require("vim-type.util")

local M = {}

-- Pasta raiz do plugin (lua/vim-type/words.lua -> ../../..).
-- Assim as listas são lidas de dentro do plugin, onde quer que ele esteja instalado.
local source_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source_path, ":p:h:h:h")

M.builtin = {
  en = { file = "en.txt", desc = "palavras comuns do inglês" },
  pt = { file = "pt.txt", desc = "palavras comuns do português" },
  vim = { file = "vim.txt", desc = "comandos e movimentos do Vim", raw = true },
}

-- Nomes antigos continuam funcionando (`:Type words`)
local aliases = { words = "en" }

math.randomseed(os.time() + math.floor((vim.uv or vim.loop).hrtime() % 1e6))

--- Lê um arquivo com um item por linha (um item pode ter espaços, ex: ":set nu").
local function read_items(path)
  local file = io.open(vim.fn.expand(path), "r")
  if not file then
    return nil
  end
  local items = {}
  for line in file:lines() do
    line = vim.trim(line)
    if line ~= "" then
      items[#items + 1] = line
    end
  end
  file:close()
  return items
end

function M.names(custom)
  local names = vim.tbl_keys(M.builtin)
  for name in pairs(custom or {}) do
    if not M.builtin[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function M.exists(name, custom)
  name = aliases[name] or name
  return M.builtin[name] ~= nil or (custom or {})[name] ~= nil
end

--- Retorna os itens da lista e se ela é "crua" (sem pontuação automática).
---@return string[]|nil items, boolean|string raw_or_error
function M.load(name, custom)
  name = aliases[name] or name
  local spec = (custom or {})[name]
  local items, raw

  if spec then
    if type(spec) == "string" then
      items, raw = read_items(spec), false
    elseif type(spec) == "table" and spec.path then
      items, raw = read_items(spec.path), spec.raw == true
    elseif type(spec) == "table" and spec.items then
      items, raw = spec.items, spec.raw == true
    elseif type(spec) == "table" then
      items, raw = spec, false
    end
  elseif M.builtin[name] then
    items = read_items(root .. "/lists/" .. M.builtin[name].file)
    raw = M.builtin[name].raw == true
  else
    return nil, "lista desconhecida: '" .. name .. "'"
  end

  if not items or #items == 0 then
    return nil, "não foi possível ler a lista '" .. name .. "'"
  end
  return items, raw
end

local function capitalize(word)
  return vim.fn.toupper(vim.fn.strcharpart(word, 0, 1)) .. vim.fn.strcharpart(word, 1)
end

local ENDINGS = { ".", ".", ".", "?", "!" }

--- Cria uma fonte de texto que vai sorteando itens e quebrando em linhas.
---@param items string[]
---@param opts { punctuation?: boolean, limit?: integer }
function M.source(items, opts)
  local self = {
    remaining = opts.limit or math.huge,
    pending = nil,
    last = nil,
    sentence_left = 0,
  }

  local function pick()
    local item
    repeat
      item = items[math.random(#items)]
    until #items == 1 or item ~= self.last
    self.last = item
    return item
  end

  function self:next_item()
    if self.remaining <= 0 then
      return nil
    end
    self.remaining = self.remaining - 1
    local item = pick()

    if opts.punctuation then
      if self.sentence_left <= 0 then
        item = capitalize(item)
        self.sentence_left = math.random(4, 10)
      end
      self.sentence_left = self.sentence_left - 1
      if self.sentence_left == 0 or self.remaining == 0 then
        item = item .. ENDINGS[math.random(#ENDINGS)]
      elseif math.random() < 0.08 then
        item = item .. ","
      end
    end
    return item
  end

  --- Gera até `n` linhas de no máximo `width` colunas. Toda linha termina
  --- com um espaço (o separador para o próximo item).
  --- Cada linha: { text = "...", chars = {...}, ends = { fim de cada item } }
  function self:lines(n, width)
    local out = {}
    while #out < n do
      local parts, ends, cols, count = {}, {}, 0, 0
      while true do
        local item = self.pending or self:next_item()
        self.pending = nil
        if not item then
          break
        end
        local w = vim.fn.strdisplaywidth(item)
        if #parts > 0 and cols + w + 1 > width then
          self.pending = item -- não coube: vai para a próxima linha
          break
        end
        parts[#parts + 1] = item
        count = count + vim.fn.strchars(item)
        ends[#ends + 1] = count
        count = count + 1
        cols = cols + w + 1
      end
      if #parts == 0 then
        break -- acabaram os itens
      end
      local text = table.concat(parts, " ") .. " "
      out[#out + 1] = { text = text, chars = util.char_list(text), ends = ends }
    end
    return out
  end

  return self
end

return M
