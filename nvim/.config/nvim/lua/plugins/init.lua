-- Aggregates lazy.nvim plugin specs. Per-plugin files:
--   core.lua — UI, Telescope, Treesitter, completion, format, etc.
--   lsp.lua  — LSP, Mason, diagnostics, server list
-- Custom additions: lua/custom/plugins/*.lua (imported below).

local specs = {}
vim.list_extend(specs, require 'plugins.core')
vim.list_extend(specs, require 'plugins.lsp')
vim.list_extend(specs, {
  { import = 'custom.plugins' },
})
return specs
