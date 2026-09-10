-- Copy text to the host machine's clipboard over OSC 52. The terminal emulator writes
-- the sequence to the OS clipboard, so it works across container and SSH boundaries
-- where the `+` register only reaches a local (in-container) clipboard.

local M = {}

--- @param text string
function M.copy(text)
  local ok, osc52 = pcall(require, 'vim.ui.clipboard.osc52')
  if not ok then
    return
  end
  pcall(osc52.copy '+', vim.split(text, '\n', { plain = true }))
end

return M
-- vim: ts=2 sts=2 sw=2 et
