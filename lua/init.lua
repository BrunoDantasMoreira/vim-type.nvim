
local vim_type = {}

local function trim(str)
  return str:match("^%s*(.-)%s*$") or ""
end

local function split(str, delimiter)
  local result = {}
  for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
    if #match > 0 then  -- Verifica se não é vazio
      table.insert(result, match)
    end
  end
  return result
end

local function shuffle(tbl)
  math.randomseed(os.time())
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
end

local function read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then return nil end 
  local content = file:read("*all")
  file:close()
  -- Remove quebras de linha e espaços extras
  return trim(content:gsub("[\n\r]+", " "):gsub("%s+", " "))
end

function vim_type.start(args)
  local file_map = {
    words = 'words.txt',
    vim = 'vim_commands.txt'
  }

  local file_key = args[1] and file_map[args[1]] or 'words.txt'
  local filepath = vim.fn.stdpath('config') .. '/lua/vim-type/' .. file_key

  -- Lê o conteúdo do arquivo como frase
  local phrase = read_file(filepath)
  if not phrase then
    print("Erro: Não foi possível ler o arquivo words.txt")
    return
  end

  -- Divide o conteúdo em palavras
  local words = split(phrase, " ")
  shuffle(words)

  -- Cria um novo buffer
  local buf = vim.api.nvim_create_buf(false, true)  -- false para não listar e true para ser um buffer flutuante

  -- Define as linhas no buffer (todas na mesma linha)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { table.concat(words, " ") })  -- Concatena as palavras em uma única linha

  -- Define a posição do buffer flutuante
  local width = 100
  local height = 1
  local row = (vim.o.lines - height) / 2
  local col = (vim.o.columns - width) / 2

  -- Cria uma janela flutuante
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded'
  })

  -- Entra no modo de inserção
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat') -- Opcional: Altera a cor de fundo
  vim.api.nvim_input(":startr<CR>") 

return vim_type

