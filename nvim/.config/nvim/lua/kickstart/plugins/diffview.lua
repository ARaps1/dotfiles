-- Git diff and file history viewer. The file panel lists every changed file; selecting
-- one opens a side-by-side diff. Press `g?` inside any diffview window for its keymaps.

-- Diff the working tree against the merge-base of `base` and HEAD. This matches the
-- file list GitHub shows on a PR into `base`, plus any uncommitted changes, and excludes
-- commits that landed on `base` after this branch forked.
local function diff_against_merge_base(base)
  local merge_base = vim.fn.systemlist({ 'git', 'merge-base', base, 'HEAD' })[1]
  if vim.v.shell_error ~= 0 or not merge_base then
    vim.notify('diffview: no merge-base between ' .. base .. ' and HEAD', vim.log.levels.ERROR)
    return
  end
  vim.cmd('DiffviewOpen ' .. merge_base)
end

---@module 'lazy'
---@type LazySpec
return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gd', function() diff_against_merge_base 'origin/dev' end, desc = '[G]it [d]iff branch + working tree against origin/dev (PR view)' },
    { '<leader>gu', '<cmd>DiffviewOpen @{u}<CR>', desc = '[G]it diff working tree against [u]pstream (unpushed changes)' },
    { '<leader>gh', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it file [h]istory' },
    { '<leader>gq', '<cmd>DiffviewClose<CR>', desc = '[G]it diff [q]uit' },
  },
  opts = {},
}
-- vim: ts=2 sts=2 sw=2 et
