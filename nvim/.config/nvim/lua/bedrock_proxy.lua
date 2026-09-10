-- Lifecycle for the local LiteLLM -> Bedrock proxy used by minuet-ai. Neovim starts the
-- proxy (shared, detached) on launch along with a watchdog that reaps it once no Neovim
-- process remains, so it never outlives the editor regardless of how nvim exits (:q, tab
-- close, or crash). The proxy holds memory but no CPU/GPU while idle.

local M = {}

local CONFIG = vim.fn.expand '~/dotfiles/litellm.yaml'

-- Watchdog: sleep while any nvim is alive, then stop the proxy and exit. Polls every 30s,
-- so the proxy is reclaimed within ~30s of the last nvim closing, however it closed.
local WATCHDOG = "while pgrep -x nvim >/dev/null 2>&1; do sleep 30; done; pkill -f 'litellm --config'"

--- Whether the proxy is already listening. Checked by port rather than process name so
--- it never mistakes the watchdog (whose command line contains "litellm --config") for
--- the proxy itself.
--- @return boolean
local function proxy_running()
  vim.fn.system { 'curl', '-s', '-o', '/dev/null', '--max-time', '2', 'http://127.0.0.1:4000/health/liveliness' }
  return vim.v.shell_error == 0
end

--- Start the proxy (detached, shared by all Neovims) plus its watchdog. No-op in headless
--- sessions, when already running, or when litellm/config are unavailable.
function M.start()
  if #vim.api.nvim_list_uis() == 0 then
    return
  end
  if vim.fn.executable 'litellm' ~= 1 or vim.fn.filereadable(CONFIG) ~= 1 then
    return
  end
  if proxy_running() then
    return
  end
  vim.system({ 'litellm', '--config', CONFIG, '--host', '127.0.0.1', '--port', '4000' }, {
    detach = true,
    env = { AWS_PROFILE = 'dev.ai-inference' },
  })
  vim.system({ 'sh', '-c', WATCHDOG }, { detach = true })
end

function M.setup()
  vim.api.nvim_create_autocmd('VimEnter', {
    group = vim.api.nvim_create_augroup('bedrock-proxy', { clear = true }),
    callback = M.start,
  })
end

return M
-- vim: ts=2 sts=2 sw=2 et
