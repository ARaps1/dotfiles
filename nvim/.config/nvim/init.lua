--[[
  Modular config layout (same general idea as https://github.com/bingcao/dotfiles/tree/main/.config/nvim )

  lua/opts.lua          — options and vim.g (e.g. have_nerd_font)
  lua/keymaps.lua       — keymaps that do not depend on plugins
  lua/autocmds.lua      — autocommands
  lua/plugins/init.lua  — merges lazy.nvim specs
  lua/plugins/core.lua  — Telescope, theme, Treesitter, blink, conform, …
  lua/plugins/lsp.lua   — LSP, Mason, diagnostics, `servers` table

  Kickstart intro text lives in doc/kickstart.txt.
--]]

-- Set <space> as the leader key (before plugins load). See `:help mapleader`
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

do
  local v = vim.version()
  if v.major == 0 and v.minor < 7 then
    error(
      ('This config needs Neovim 0.7+ (vim.keymap). Found %d.%d.%d.\n'):format(v.major, v.minor, v.patch)
        .. 'Upgrade nvim (see dotfiles setup.sh), or run `which nvim` / `nvim --version` if an old system binary is first in PATH.'
    )
  end
end

require 'opts'
require 'keymaps'
require 'autocmds'

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]  Run :Lazy to inspect; :Lazy update to upgrade
require('lazy').setup(require 'plugins', {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
