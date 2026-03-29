-- TODO: Replace this with your actual Neovim configuration.
-- This is a minimal starter config. Copy your existing ~/.config/nvim/init.lua
-- (or init.vim) content here.

-- Set leader key to space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- General options
vim.opt.number = true               -- Show line numbers
vim.opt.ignorecase = true            -- Case insensitive search
vim.opt.smartcase = true             -- Except when using capitals
vim.opt.hlsearch = true              -- Highlight search results
vim.opt.mouse = "a"                  -- Enable mouse
vim.opt.swapfile = false             -- Disable swap files
vim.opt.autoindent = true
vim.opt.termguicolors = true         -- Enable 24-bit color
