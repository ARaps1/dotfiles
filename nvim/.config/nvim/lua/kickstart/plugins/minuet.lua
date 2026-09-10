-- AI code completion (ghost text) via minuet-ai, backed by AWS Bedrock through a local
-- OpenAI-compatible LiteLLM proxy.
--
-- Prerequisite: run the LiteLLM proxy locally so the endpoint below is reachable. It
-- runs on this machine; the only parties are you and AWS Bedrock.
--   uv tool install 'litellm[proxy]'                                    # one-time
--   litellm --config ~/dotfiles/litellm.yaml --host 127.0.0.1 --port 4000   # needs `aws sso login`
--
-- Accept a suggestion with <Tab> (wired through blink.cmp in blink-cmp.lua); the Alt
-- keymaps below handle line-accept, cycling, and dismiss. Switch the Bedrock model at
-- runtime with :MinuetModel or <leader>am.

-- Bedrock models exposed by the local LiteLLM proxy (each is a `model_name` in
-- litellm.yaml). bedrock-haiku is the startup default; the rest are opt-in via the
-- runtime switcher.
local BEDROCK_MODELS = { 'bedrock-haiku', 'bedrock-sonnet' }

---@module 'lazy'
---@type LazySpec
return {
  {
    'milanglacier/minuet-ai.nvim',
    event = 'InsertEnter',
    opts = {
      provider = 'openai_compatible',
      -- One suggestion per request to bound Bedrock cost.
      n_completions = 1,
      notify = 'error',
      provider_options = {
        openai_compatible = {
          end_point = 'http://127.0.0.1:4000/v1/chat/completions',
          model = 'bedrock-haiku',
          api_key = function() return 'dummy' end,
          name = 'Bedrock',
          stream = true,
        },
      },
      virtualtext = {
        auto_trigger_ft = { 'python', 'lua', 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
        keymap = {
          accept = nil, -- accepted via <Tab>, wired through blink.cmp
          accept_line = '<A-a>',
          prev = '<A-[>',
          next = '<A-]>',
          dismiss = '<A-e>',
        },
      },
    },
    config = function(_, opts)
      require('minuet').setup(opts)

      local function pick_model()
        vim.ui.select(BEDROCK_MODELS, { prompt = 'minuet model (Bedrock):' }, function(choice)
          if choice then
            require('minuet').change_model('openai_compatible:' .. choice)
          end
        end)
      end

      vim.api.nvim_create_user_command('MinuetModel', pick_model, { desc = 'Switch the minuet Bedrock completion model' })
      vim.keymap.set('n', '<leader>am', pick_model, { desc = '[A]I completion [m]odel' })

      local function show_cost() require('minuet_cost').show() end
      vim.api.nvim_create_user_command('MinuetCost', show_cost, { desc = 'Show minuet autocomplete token usage and cost' })
      vim.keymap.set('n', '<leader>ac', show_cost, { desc = '[A]I completion [c]ost' })
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
