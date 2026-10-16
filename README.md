# vim-type.nvim

Treino de digitação dentro do Neovim, no estilo do Monkeytype.

Você digita por cima do texto numa janela flutuante e vê na hora o que acertou e o que errou. No fim aparecem as palavras por minuto, a precisão e um gráfico do seu ritmo. Os resultados ficam salvos, então dá para acompanhar a evolução e bater os próprios recordes.

Além de palavras em inglês e português, tem uma lista de **comandos do Vim** (`ciw`, `dap`, `:%s/foo/bar/g`...) para treinar a memória muscular.

## Instalação

Precisa do Neovim 0.9 ou mais novo.

Com [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "BrunoDantasMoreira/vim-type.nvim",
  cmd = "Type",
  opts = {},
}
```

Com [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "BrunoDantasMoreira/vim-type.nvim",
  config = function()
    require("vim-type").setup()
  end,
})
```

O `setup()` é opcional. Sem ele, o plugin usa as configurações padrão.

## Uso

```
:Type                  teste padrão (inglês, 30 segundos)
:Type pt               palavras em português
:Type vim              comandos do Vim
:Type 60s              contra o relógio, 60 segundos
:Type 50               50 palavras
:Type pt 15s punct     dá para combinar; punct liga maiúsculas e pontuação
:Type stats            histórico e recordes
:Type stats clear      apaga o histórico
```

Os argumentos podem vir em qualquer ordem, e o `<Tab>` completa todos eles.

### Durante o teste

O relógio só começa na primeira tecla. O título da janela mostra o tempo restante (ou quantas palavras você já fez) e o wpm ao vivo.

| Tecla | O que faz |
|---|---|
| `<Tab>` | reinicia com outras palavras |
| `<Esc>` | pausa (o relógio para e o texto trava) |
| `i` | continua de onde parou |
| `q` | sai (quando pausado) |
| `<BS>`, `<C-w>` | apagam, mas não voltam para a linha anterior |

Erros funcionam como no Monkeytype:

- **Letra errada** fica vermelha. Dá para apagar e corrigir.
- **Letra a mais** no fim da palavra não entra no texto, mas conta como erro e deixa o espaço marcado. Assim um erro não desalinha todo o resto.
- **Espaço no meio da palavra** pula para a próxima. As letras que faltaram ficam sublinhadas como perdidas.
- **Espaço duplo** é ignorado.

### Tela de resultado

Mostra wpm, wpm bruto (contando os erros), precisão, tempo, acertos, erros, um gráfico do wpm ao longo do teste e se você bateu o recorde para aquela configuração.

| Tecla | O que faz |
|---|---|
| `r` / `<Tab>` | faz de novo com a mesma configuração |
| `s` | abre as estatísticas |
| `q` / `<Esc>` / `<CR>` | fecha |

Durante o primeiro segundo a tela ignora as teclas, porque quando o tempo acaba você provavelmente ainda está digitando. Teclas soltas nunca disparam atalhos seus (como os de `<leader>`) enquanto a janela está aberta.

## Como o wpm é calculado

Como no Monkeytype, uma "palavra" vale 5 caracteres, contando os espaços.

- **wpm**: caracteres certos ÷ 5 ÷ minutos
- **bruto**: todos os caracteres digitados ÷ 5 ÷ minutos
- **precisão**: teclas certas ÷ total de teclas. Um erro que você corrigiu ainda conta como erro aqui.

Recordes só são comparados entre testes com a mesma lista, o mesmo modo e a mesma opção de pontuação.

## Configuração

Valores padrão:

```lua
require("vim-type").setup({
  list = "en",          -- "en", "pt", "vim" ou uma das suas listas
  mode = "time",        -- "time" (contra o relógio) ou "words"
  time = 30,            -- segundos no modo "time"
  words = 25,           -- palavras no modo "words"
  punctuation = false,  -- maiúsculas e pontuação (não vale para a lista "vim")
  width = 70,           -- largura máxima do texto
  height = 3,           -- linhas visíveis
  border = "rounded",
  lists = {},
})
```

### Listas próprias

```lua
require("vim-type").setup({
  lists = {
    -- arquivo com um item por linha (um item pode ter espaços)
    python = "~/listas/python.txt",

    -- raw = true desliga a pontuação automática (bom para código e comandos)
    atalhos = { path = "~/listas/atalhos.txt", raw = true },

    -- ou direto no Lua
    frutas = { "banana", "maçã", "uva", "manga", "laranja" },
  },
})
```

Depois é só usar `:Type python` ou `:Type frutas 30s`.

### Cores

Os grupos de destaque podem ser alterados depois do seu tema:

| Grupo | Uso | Padrão |
|---|---|---|
| `VimTypeCorrect` | letra certa | cor do texto normal |
| `VimTypeWrong` | letra errada | `DiagnosticError` |
| `VimTypeWrongSpace` | espaço errado ou letra a mais | `DiffDelete` |
| `VimTypeMissed` | letra pulada | `Comment` sublinhado |
| `VimTypeUntyped` | ainda não digitado | `Comment` |
| `VimTypeResult` | números do resultado | `Title` |
| `VimTypeLabel` | rótulos | `Comment` |
| `VimTypeGraph` | gráficos | `Function` |
| `VimTypeRecord` | novo recorde | `DiagnosticOk` |

```lua
vim.api.nvim_set_hl(0, "VimTypeWrong", { fg = "#ff5555", bold = true })
```

## Histórico

Os resultados ficam em `~/.local/share/nvim/vim-type/history.json` (os últimos 1000 testes).

## Funciona com

Testado no Neovim 0.9 e 0.11, junto com nvim-cmp, nvim-autopairs e LuaSnip. O autocompletar é desligado automaticamente na janela do teste.
