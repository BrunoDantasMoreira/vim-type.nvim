local M = {}

local MAX_ENTRIES = 1000

function M.path()
  return vim.fn.stdpath("data") .. "/vim-type/history.json"
end

---@return table[]
function M.load()
  local file = io.open(M.path(), "r")
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

local function save(list)
  vim.fn.mkdir(vim.fn.fnamemodify(M.path(), ":h"), "p")
  local file = io.open(M.path(), "w")
  if file then
    file:write(vim.json.encode(list))
    file:close()
  end
end

--- Testes só são comparáveis com a mesma configuração.
function M.key(e)
  return table.concat({ e.list, e.mode, tostring(e.value), e.punct and "p" or "" }, ":")
end

function M.label(e)
  local what = e.mode == "time" and (e.value .. "s") or (e.value .. " palavras")
  return e.list .. " · " .. what .. (e.punct and " · pontuação" or "")
end

---@return table|nil melhor resultado salvo para a mesma configuração
function M.best(list, key)
  local best
  for _, e in ipairs(list) do
    if M.key(e) == key and (not best or e.wpm > best.wpm) then
      best = e
    end
  end
  return best
end

--- Salva o resultado e devolve o recorde anterior (se havia).
function M.add(entry)
  local list = M.load()
  local previous = M.best(list, M.key(entry))
  list[#list + 1] = entry
  while #list > MAX_ENTRIES do
    table.remove(list, 1)
  end
  save(list)
  return previous
end

function M.clear()
  os.remove(M.path())
end

return M
