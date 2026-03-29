-- LSP configuration & related tooling (aligned with github.com/bingcao/dotfiles lua/plugins/lsp.lua;
-- Mason packages use mason-org/*.)
return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('nvim-treesitter.configs').setup {
        ensure_installed = { 'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc' },
        -- Autoinstall languages that are not installed
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<CR>',
            node_incremental = '<CR>',
            scope_incremental = '<TAB>',
            node_decremental = '<S-TAB>',
          },
        },
      }
    end,
  },

  {
    'mason-org/mason-lspconfig.nvim',
    opts = {
      ensure_installed = {
        'oxlint',
        'ruff',
        'ty',
        'tsgo',
        'graphql',
        'spectral',
        'yamlls',
        'lua_ls',
        'zls',
      },
    },
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'neovim/nvim-lspconfig',
    },
  },

  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    opts = {
      ensure_installed = {
        'prettier',
        'stylua',
      },
    },
    dependencies = {
      'mason-org/mason.nvim',
    },
  },

  { -- Autoformat
    'stevearc/conform.nvim',
    opts = {
      notify_on_error = false,
      format_on_save = {
        timeout_ms = 2500,
        lsp_fallback = false,
      },
      formatters_by_ft = {
        lua = { 'stylua' },
        json = { 'prettier' },
        python = { 'ruff_fix', 'ruff_format' },
        javascript = { 'prettier', 'oxlint' },
        typescript = { 'prettier', 'oxlint' },
        typescriptreact = { 'prettier', 'oxlint' },
      },
    },
  },

  { -- Autocomplete
    'saghen/blink.cmp',
    dependencies = 'rafamadriz/friendly-snippets',

    -- use a release tag to download pre-built binaries
    version = '*',

    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      keymap = { preset = 'default' },

      appearance = {
        use_nvim_cmp_as_default = false,
        nerd_font_variant = 'mono',
      },

      completion = {
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 250,
        },
        list = {
          selection = { preselect = true, auto_insert = false },
        },
      },

      signature = { enabled = true },

      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
    },
    opts_extend = { 'sources.default' },
  },

  -- types for neovim
  {
    'folke/lazydev.nvim',
    ft = 'lua', -- only load on lua files
    opts = {
      library = {
        -- See the configuration section for more details
        -- Load luvit types when the `vim.uv` word is found
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
}
