-- LSP Plugins (Mason + mason-lspconfig + nvim-lspconfig)
---@module 'lazy'
---@type LazySpec
return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      {
        'mason-org/mason.nvim',
        ---@module 'mason.settings'
        ---@type MasonSettings
        ---@diagnostic disable-next-line: missing-fields
        opts = {},
      },
      {
        'mason-org/mason-lspconfig.nvim',
        opts = {
          -- Servers with custom `vim.lsp.config` below are excluded so Mason does not call
          -- `vim.lsp.enable` before our merged config is registered.
          automatic_enable = {
            exclude = {
              'ts_ls',
              'vtsls',
              'eslint',
              'pyright',
              'graphql',
              'ruff',
              'lua_ls',
              'spectral',
              'yamlls',
            },
          },
          ensure_installed = {
            'eslint',
            'graphql',
            'lua_ls',
            'pyright',
            'ruff',
            'spectral',
            'ts_ls',
            'vtsls',
            'yamlls',
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
            'oxlint',
            'prettier',
            'stylua',
          },
        },
        dependencies = {
          'mason-org/mason.nvim',
        },
      },

      { 'j-hui/fidget.nvim', opts = {} },
    },
    config = function()
      local root = require 'kickstart.benchling_root'

      --- Match `aurelia.code-workspace` tsserver memory (MB); also set via NODE_OPTIONS for `ts_ls`.
      local TSSERVER_MAX_MEMORY_MB = 6144

      --- Prefer repo TypeScript and ESLint from node_modules (Benchling / Yarn monorepo).
      ---@param config table
      ---@param root_dir string
      local function prepend_node_modules_bin(config, root_dir)
        if vim.fn.isdirectory(root_dir .. '/node_modules') ~= 1 then
          return
        end
        config.cmd_env = vim.tbl_extend('force', config.cmd_env or {}, {
          PATH = root_dir .. '/node_modules/.bin:' .. (vim.env.PATH or ''),
        })
      end

      ---@param config table
      local function ts_node_heap_cmd_env(config)
        local node_opts = ('--max-old-space-size=%d'):format(TSSERVER_MAX_MEMORY_MB)
        local existing = config.cmd_env and config.cmd_env.NODE_OPTIONS
        if existing and existing:find('max%-old%-space%-size', 1) then
          return
        end
        config.cmd_env = vim.tbl_extend('force', config.cmd_env or {}, {
          NODE_OPTIONS = (existing and (existing .. ' ') or '') .. node_opts,
        })
      end

      local use_vtsls = vim.g.kickstart_use_vtsls == true or vim.g.kickstart_use_vtsls == 1

      local inlay_ts = {
        parameterNames = { enabled = 'all' },
        parameterTypes = { enabled = true },
        variableTypes = { enabled = true },
        propertyDeclarationTypes = { enabled = true },
        functionLikeReturnTypes = { enabled = true },
        enumMemberValues = { enabled = true },
      }

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method('textDocument/documentHighlight', event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          if client and client:supports_method('textDocument/inlayHint', event.buf) then
            map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      ---@type table<string, vim.lsp.Config>
      local servers = {
        ts_ls = {
          root_dir = root.ts_ls_root_dir,
          before_init = function(_, config)
            local root_dir = config.root_dir
            if type(root_dir) ~= 'string' or root_dir == '' then
              return
            end
            prepend_node_modules_bin(config, root_dir)
            ts_node_heap_cmd_env(config)
            local tsjs = root_dir .. '/node_modules/typescript/lib/tsserver.js'
            if vim.fn.filereadable(tsjs) == 1 then
              config.init_options = vim.tbl_deep_extend('force', config.init_options or {}, {
                tsserver = { path = tsjs },
              })
            end
          end,
          settings = {
            typescript = {
              inlayHints = inlay_ts,
            },
            javascript = {
              inlayHints = inlay_ts,
            },
          },
        },

        -- VS Code–aligned TS stack (workspace TS, high tsserver memory). Not TSgo; see AURELIA_LSP.md.
        vtsls = {
          root_dir = root.ts_ls_root_dir,
          before_init = function(_, config)
            local root_dir = config.root_dir
            if type(root_dir) ~= 'string' or root_dir == '' then
              return
            end
            prepend_node_modules_bin(config, root_dir)
            ts_node_heap_cmd_env(config)
          end,
          settings = {
            vtsls = {
              autoUseWorkspaceTsdk = true,
            },
            typescript = {
              tsserver = {
                maxTsServerMemory = TSSERVER_MAX_MEMORY_MB,
              },
              inlayHints = inlay_ts,
            },
            javascript = {
              tsserver = {
                maxTsServerMemory = TSSERVER_MAX_MEMORY_MB,
              },
              inlayHints = inlay_ts,
            },
          },
        },

        eslint = {
          root_dir = root.eslint_root_dir,
          settings = {
            workingDirectory = { mode = 'location' },
            experimental = {
              useFlatConfig = true,
            },
          },
          before_init = function(_, config)
            local root_dir = config.root_dir
            if type(root_dir) ~= 'string' or root_dir == '' then
              return
            end
            config.settings = config.settings or {}
            config.settings.workspaceFolder = {
              uri = root_dir,
              name = vim.fn.fnamemodify(root_dir, ':t'),
            }
            prepend_node_modules_bin(config, root_dir)
            if not config.settings['eslint.execArgv'] then
              config.settings['eslint.execArgv'] = {
                '--max-old-space-size=' .. TSSERVER_MAX_MEMORY_MB,
              }
            end
            local pnp_cjs = root_dir .. '/.pnp.cjs'
            local pnp_js = root_dir .. '/.pnp.js'
            if type(config.cmd) == 'table' and (vim.uv.fs_stat(pnp_cjs) or vim.uv.fs_stat(pnp_js)) then
              config.cmd = vim.list_extend({ 'yarn', 'exec' }, config.cmd --[[@as table]])
            end
            local flat = {
              '/eslint.config.js',
              '/eslint.config.mjs',
              '/eslint.config.cjs',
              '/eslint.config.ts',
              '/eslint.config.mts',
              '/eslint.config.cts',
            }
            local has_flat = false
            for _, suffix in ipairs(flat) do
              if vim.fn.filereadable(root_dir .. suffix) == 1 then
                has_flat = true
                break
              end
            end
            if has_flat then
              config.settings.experimental = vim.tbl_deep_extend('force', config.settings.experimental or {}, {
                useFlatConfig = true,
              })
            else
              config.settings.experimental = vim.tbl_deep_extend('force', config.settings.experimental or {}, {
                useFlatConfig = false,
              })
            end
            local skip_aware = root_dir .. '/eslint.config.skip-type-aware-rules.js'
            local want_full = vim.g.aurelia_eslint_full_type_aware == true or vim.g.aurelia_eslint_full_type_aware == 1
            if not want_full and vim.fn.filereadable(skip_aware) == 1 then
              config.settings['eslint.options'] = vim.tbl_deep_extend('force', config.settings['eslint.options'] or {}, {
                overrideConfigFile = skip_aware,
              })
            end
          end,
        },

        pyright = {
          root_dir = root.ruff_root_dir,
          before_init = function(_, config)
            config.settings = config.settings or {}
            config.settings.python = config.settings.python or {}
            local rd = config.root_dir
            local benchling_js = type(rd) == 'string' and rd ~= '' and vim.fn.filereadable(rd .. '/eslint.config.js') == 1
              and vim.fn.filereadable(rd .. '/package.json') == 1
            if benchling_js then
              local extra = root.aurelia_default_pyright_extra_paths(rd)
              if type(vim.g.aurelia_pyright_extra_paths) == 'table' then
                vim.list_extend(extra, vim.g.aurelia_pyright_extra_paths)
              end
              config.settings.python.analysis = vim.tbl_deep_extend('force', config.settings.python.analysis or {}, {
                typeCheckingMode = 'off',
                autoSearchPaths = false,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
                extraPaths = extra,
              })
            else
              config.settings.python.analysis = vim.tbl_deep_extend('force', config.settings.python.analysis or {}, {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
              })
            end
            local python_path
            if vim.env.VIRTUAL_ENV and vim.fn.executable(vim.env.VIRTUAL_ENV .. '/bin/python') == 1 then
              python_path = vim.env.VIRTUAL_ENV .. '/bin/python'
            elseif vim.env.AURELIA_PYTHON and vim.fn.executable(vim.env.AURELIA_PYTHON) == 1 then
              python_path = vim.env.AURELIA_PYTHON
            elseif vim.env.AURELIA_PYTHON_VENV and vim.fn.executable(vim.env.AURELIA_PYTHON_VENV .. '/bin/python') == 1 then
              python_path = vim.env.AURELIA_PYTHON_VENV .. '/bin/python'
            end
            if python_path then
              config.settings.python = vim.tbl_deep_extend('force', config.settings.python or {}, {
                pythonPath = python_path,
              })
            end
          end,
          settings = {
            python = {
              analysis = {},
            },
          },
        },

        ruff = {
          root_dir = root.ruff_root_dir,
        },

        graphql = {
          root_dir = root.graphql_root_dir,
        },

        spectral = {
          filetypes = { 'yaml', 'json' },
          settings = {
            enable = true,
            run = 'onType',
            validateLanguages = { 'yaml', 'json' },
          },
        },

        yamlls = {
          filetypes = { 'yaml' },
        },

        lua_ls = {
          on_init = function(client)
            if client.workspace_folders then
              local path = client.workspace_folders[1].name
              if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
            end

            client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
              runtime = {
                version = 'LuaJIT',
                path = { 'lua/?.lua', 'lua/?/init.lua' },
              },
              workspace = {
                checkThirdParty = false,
                library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
                  '${3rd}/luv/library',
                  '${3rd}/busted/library',
                }),
              },
            })
          end,
          settings = {
            Lua = {},
          },
        },
      }

      for name, server in pairs(servers) do
        local skip_ts = (name == 'ts_ls' and use_vtsls) or (name == 'vtsls' and not use_vtsls)
        if not skip_ts then
          vim.lsp.config(name, server)
          vim.lsp.enable(name)
        end
      end
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
