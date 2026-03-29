-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()` / `:help nvim_set_keymap()`
--
-- Uses vim.keymap.set when available (Neovim 0.7+). Falls back to nvim_set_keymap so very
-- old distro packages (e.g. nvim from dnf without upgrading) do not crash on nil vim.keymap.

---@param mode string|'n'|'i'|'x'|'t' etc.
---@param lhs string
---@param rhs string|function
---@param opts? vim.keymap.set.Opts
local function map(mode, lhs, rhs, opts)
  opts = vim.tbl_extend('force', { silent = true }, opts or {})
  if vim.keymap and vim.keymap.set then
    vim.keymap.set(mode, lhs, rhs, opts)
    return
  end
  local o = { noremap = true, silent = true }
  if opts.desc and vim.fn.has 'nvim-0.8' == 1 then
    o.desc = opts.desc
  end
  if type(rhs) == 'function' then
    -- nvim 0.7+ supports callback; pre-0.7 use string for the only function map we use
    if vim.fn.has 'nvim-0.7' == 1 then
      o.callback = rhs
      rhs = ''
    else
      rhs = '<cmd>lua vim.diagnostic.setloclist()<cr>'
    end
  end
  vim.api.nvim_set_keymap(mode, lhs, rhs --[[@as string]], o)
end

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
map('n', '<Esc>', '<cmd>nohlsearch<cr>')

-- Diagnostic keymaps
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit of experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
map('n', '<left>', '<cmd>echo "Use h to move!!"<cr>')
map('n', '<right>', '<cmd>echo "Use l to move!!"<cr>')
map('n', '<up>', '<cmd>echo "Use k to move!!"<cr>')
map('n', '<down>', '<cmd>echo "Use j to move!!"<cr>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
map('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
map('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
map('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
map('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
