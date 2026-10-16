if vim.g.loaded_vim_type then
  return
end
vim.g.loaded_vim_type = 1

vim.api.nvim_create_user_command("Type", function(cmd)
  require("vim-type").start(cmd.fargs)
end, {
  nargs = "*",
  desc = "vim-type: teste de digitação",
  complete = function(arglead, cmdline)
    return require("vim-type").complete(arglead, cmdline)
  end,
})
