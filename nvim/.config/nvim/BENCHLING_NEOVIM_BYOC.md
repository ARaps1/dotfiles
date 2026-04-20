# Benchling Neovim: Bring Your Own Config

Add Benchling-aligned LSP, formatting, and linting to your **existing** Neovim setup.

**Assumptions:** You already have Neovim >= 0.11, lazy.nvim, and mason.nvim installed. You have a working config and want to add Benchling monorepo support without replacing everything.

**What you'll get:** LSP servers, formatters, and linters that match what Benchling CI checks — no more red builds from quote style, import order, or type errors that your editor didn't catch.

---

## Overview

| Layer | Tool | Languages |
|-------|------|-----------|
| LSP | pyright, ruff | Python |
| LSP | ts_ls, eslint | TypeScript / JavaScript / React |
| LSP | graphql | GraphQL |
| Formatting | oxfmt (via conform.nvim) | JS/TS/TSX/JSX/CSS/Less |
| Formatting | ruff (via conform.nvim) | Python |
| Formatting | prettier (via conform.nvim) | JSON/YAML/GraphQL |
| Linting | mypy (via nvim-lint) | Python type checking |
| Linting | ESLint LSP (includes oxlint rules) | JS/TS |
| Linting | Ruff LSP | Python |

---

## Step 1: Prerequisites

```bash
# System dependencies
# macOS:
brew install ripgrep fd neovim node

# Linux (apt):
sudo apt-get install -y ripgrep fd-find build-essential unzip
# Install Neovim >= 0.11 from https://github.com/neovim/neovim/releases

# tree-sitter CLI (needed for treesitter parser compilation)
npm install -g tree-sitter-cli

# In the Benchling repo, ensure node_modules exist
cd /path/to/benchling-repo && yarn install
```

---

## Step 2: Monorepo Root Detection

This module is the foundation — every LSP server uses it to find the Benchling repo root (where `eslint.config.js`, `tsconfig.json`, `pyproject.toml`, etc. live). Without it, servers attach to the wrong directory and can't find configs.

Create this file somewhere in your Lua path. The examples below assume `lua/benchling/root.lua` — adjust the `require` path if you put it elsewhere.

<details>
<summary><strong>lua/benchling/root.lua</strong> (click to expand)</summary>

```lua
-- Monorepo root helpers for Benchling repos.
-- Detects the git root when it looks like a Benchling monorepo
-- (package.json + eslint.config.js at the same root).

local util = require 'lspconfig.util'

local M = {}

--- Detect if a buffer is inside a Benchling-style JS monorepo.
--- Returns the git root if package.json + eslint.config.js exist there, else nil.
---@param bufnr integer
---@return string|nil
function M.benchling_js_monorepo_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then return nil end
  local git = vim.fs.root(path, { '.git' })
  if not git then return nil end
  if vim.fn.filereadable(git .. '/package.json') ~= 1 then return nil end
  if vim.fn.filereadable(git .. '/eslint.config.js') ~= 1 then return nil end
  return git
end

--- root_dir for ts_ls / vtsls. Prefers Benchling monorepo root, else standard lockfile detection.
---@param bufnr integer
---@param on_dir fun(path: string)
function M.ts_ls_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    on_dir(br)
    return
  end
  local root_markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' }
  root_markers = vim.fn.has 'nvim-0.11.3' == 1 and { root_markers, { '.git' } }
    or vim.list_extend(root_markers, { '.git' })
  local deno_lock_root = vim.fs.root(bufnr, { 'deno.lock' })
  local deno_root = vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc' })
  local project_root = vim.fs.root(bufnr, root_markers)
  if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then return end
  if deno_root and (not project_root or #deno_root >= #project_root) then return end
  on_dir(project_root or vim.fn.getcwd())
end

local eslint_config_files = {
  '.eslintrc', '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.yaml',
  '.eslintrc.yml', '.eslintrc.json', 'eslint.config.js', 'eslint.config.mjs',
  'eslint.config.cjs', 'eslint.config.ts', 'eslint.config.mts', 'eslint.config.cts',
}

--- root_dir for ESLint. Prefers Benchling monorepo root, else nearest eslint config.
---@param bufnr integer
---@param on_dir fun(path: string)
function M.eslint_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    on_dir(br)
    return
  end
  local root_markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' }
  root_markers = vim.fn.has 'nvim-0.11.3' == 1 and { root_markers, { '.git' } }
    or vim.list_extend(root_markers, { '.git' })
  if vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc', 'deno.lock' }) then return end
  local project_root = vim.fs.root(bufnr, root_markers) or vim.fn.getcwd()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local eslint_config_files_with_package_json = util.insert_package_json(eslint_config_files, 'eslintConfig', filename)
  local is_buffer_using_eslint = vim.fs.find(eslint_config_files_with_package_json, {
    path = filename, type = 'file', limit = 1, upward = true,
    stop = vim.fs.dirname(project_root),
  })[1]
  if not is_buffer_using_eslint then return end
  on_dir(project_root)
end

--- root_dir for GraphQL. Prefers Benchling root when graphql.config.* exists there.
---@param bufnr integer
---@param on_dir fun(path: string)
function M.graphql_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    for _, name in ipairs { 'graphql.config.yml', 'graphql.config.yaml', 'graphql.config.js' } do
      if vim.fn.filereadable(br .. '/' .. name) == 1 then
        on_dir(br)
        return
      end
    end
  end
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname == '' then
    on_dir(vim.fn.getcwd())
    return
  end
  local resolved = util.root_pattern('.graphqlrc*', '.graphql.config.*', 'graphql.config.*')(fname)
  on_dir(resolved or vim.fs.root(fname, { '.git' }) or vim.fn.fnamemodify(fname, ':p:h'))
end

--- root_dir for Ruff / Pyright. Monorepo root or nearest pyproject.toml.
---@param bufnr integer
---@param on_dir fun(path: string)
function M.ruff_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    on_dir(br)
    return
  end
  on_dir(vim.fs.root(bufnr, { 'pyproject.toml', 'ruff.toml', '.git' }) or vim.fn.getcwd())
end

--- Default Pyright extra paths for Benchling repos (matches VS Code workspace config).
---@param repo_root string
---@return string[]
function M.aurelia_default_pyright_extra_paths(repo_root)
  if vim.fn.isdirectory(repo_root) ~= 1 then return {} end
  local out = {}
  for _, rel in ipairs { '.', 'src', 'tests', 'scripts', 'services/monolith' } do
    local full = rel == '.' and repo_root or (repo_root .. '/' .. rel)
    if vim.fn.isdirectory(full) == 1 then
      out[#out + 1] = rel
    end
  end
  return out
end

return M
```

</details>

---

## Step 3: LSP Servers

Add this plugin spec to your lazy.nvim setup. It configures all LSP servers with Benchling-specific settings.

**What it does:**
- TypeScript: uses the repo's `node_modules/typescript` and allocates 6GB memory
- ESLint: flat config support, uses `eslint.config.skip-type-aware-rules.js` for speed
- Pyright: `typeCheckingMode = off` for Benchling (mypy is the real type checker), auto-resolves `benchling.*` imports
- Ruff: real-time Python lint + format diagnostics
- GraphQL: schema-aware completions from `graphql.config.yml`

<details>
<summary><strong>Plugin spec: LSP</strong> (click to expand)</summary>

```lua
{
  'neovim/nvim-lspconfig',
  dependencies = {
    { 'mason-org/mason.nvim', opts = {} },
    {
      'mason-org/mason-lspconfig.nvim',
      opts = {
        automatic_enable = {
          -- Exclude servers we configure manually below so Mason doesn't
          -- call vim.lsp.enable before our merged config is registered.
          exclude = {
            'ts_ls', 'vtsls', 'eslint', 'pyright', 'graphql',
            'ruff', 'lua_ls', 'spectral', 'yamlls',
          },
        },
        ensure_installed = {
          'eslint', 'graphql', 'lua_ls', 'pyright', 'ruff',
          'spectral', 'ts_ls', 'vtsls', 'yamlls',
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
          'markdownlint',  -- markdown linting
          'mypy',          -- python type checking
          'oxlint',        -- JS/TS linting (used by ESLint plugin)
          'prettier',      -- JSON/YAML/GraphQL formatting
          'stylua',        -- Lua formatting
        },
      },
      dependencies = { 'mason-org/mason.nvim' },
    },
    { 'j-hui/fidget.nvim', opts = {} }, -- LSP progress indicator
  },
  config = function()
    -----------------------------------------------------------------------
    -- Adjust this require path to wherever you placed benchling/root.lua
    -----------------------------------------------------------------------
    local root = require 'benchling.root'

    local TSSERVER_MAX_MEMORY_MB = 6144

    --- Prepend repo node_modules/.bin to PATH so LSP uses workspace versions.
    local function prepend_node_modules_bin(config, root_dir)
      if vim.fn.isdirectory(root_dir .. '/node_modules') ~= 1 then return end
      config.cmd_env = vim.tbl_extend('force', config.cmd_env or {}, {
        PATH = root_dir .. '/node_modules/.bin:' .. (vim.env.PATH or ''),
      })
    end

    --- Set NODE_OPTIONS for tsserver memory budget.
    local function ts_node_heap_cmd_env(config)
      local node_opts = ('--max-old-space-size=%d'):format(TSSERVER_MAX_MEMORY_MB)
      local existing = config.cmd_env and config.cmd_env.NODE_OPTIONS
      if existing and existing:find('max%-old%-space%-size', 1) then return end
      config.cmd_env = vim.tbl_extend('force', config.cmd_env or {}, {
        NODE_OPTIONS = (existing and (existing .. ' ') or '') .. node_opts,
      })
    end

    -- Set vim.g.benchling_use_vtsls = 1 to use vtsls instead of ts_ls.
    local use_vtsls = vim.g.benchling_use_vtsls == true or vim.g.benchling_use_vtsls == 1

    local inlay_ts = {
      parameterNames = { enabled = 'all' },
      parameterTypes = { enabled = true },
      variableTypes = { enabled = true },
      propertyDeclarationTypes = { enabled = true },
      functionLikeReturnTypes = { enabled = true },
      enumMemberValues = { enabled = true },
    }

    ------------------------------------------------------------------
    -- LSP keybindings (set on attach, buffer-local)
    ------------------------------------------------------------------
    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('benchling-lsp-attach', { clear = true }),
      callback = function(event)
        local map = function(keys, func, desc, mode)
          mode = mode or 'n'
          vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
        end

        map('grn', vim.lsp.buf.rename, 'Rename')
        map('gra', vim.lsp.buf.code_action, 'Code Action', { 'n', 'x' })
        map('grD', vim.lsp.buf.declaration, 'Go to Declaration')

        -- Highlight references under cursor
        local client = vim.lsp.get_client_by_id(event.data.client_id)
        if client and client:supports_method('textDocument/documentHighlight', event.buf) then
          local hl_group = vim.api.nvim_create_augroup('benchling-lsp-highlight', { clear = false })
          vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
            buffer = event.buf, group = hl_group,
            callback = vim.lsp.buf.document_highlight,
          })
          vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
            buffer = event.buf, group = hl_group,
            callback = vim.lsp.buf.clear_references,
          })
          vim.api.nvim_create_autocmd('LspDetach', {
            group = vim.api.nvim_create_augroup('benchling-lsp-detach', { clear = true }),
            callback = function(event2)
              vim.lsp.buf.clear_references()
              vim.api.nvim_clear_autocmds { group = 'benchling-lsp-highlight', buffer = event2.buf }
            end,
          })
        end

        -- Toggle inlay hints
        if client and client:supports_method('textDocument/inlayHint', event.buf) then
          map('<leader>th', function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
          end, 'Toggle Inlay Hints')
        end
      end,
    })

    ------------------------------------------------------------------
    -- Server configurations
    ------------------------------------------------------------------
    local servers = {
      -- TypeScript / JavaScript (default)
      ts_ls = {
        root_dir = root.ts_ls_root_dir,
        before_init = function(_, config)
          local root_dir = config.root_dir
          if type(root_dir) ~= 'string' or root_dir == '' then return end
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
          typescript = { inlayHints = inlay_ts },
          javascript = { inlayHints = inlay_ts },
        },
      },

      -- TypeScript / JavaScript (VS Code-aligned alternative)
      vtsls = {
        root_dir = root.ts_ls_root_dir,
        before_init = function(_, config)
          local root_dir = config.root_dir
          if type(root_dir) ~= 'string' or root_dir == '' then return end
          prepend_node_modules_bin(config, root_dir)
          ts_node_heap_cmd_env(config)
        end,
        settings = {
          vtsls = { autoUseWorkspaceTsdk = true },
          typescript = {
            tsserver = { maxTsServerMemory = TSSERVER_MAX_MEMORY_MB },
            inlayHints = inlay_ts,
          },
          javascript = {
            tsserver = { maxTsServerMemory = TSSERVER_MAX_MEMORY_MB },
            inlayHints = inlay_ts,
          },
        },
      },

      -- ESLint (flat config, skip-type-aware for speed)
      eslint = {
        root_dir = root.eslint_root_dir,
        settings = {
          workingDirectory = { mode = 'location' },
          experimental = { useFlatConfig = true },
        },
        before_init = function(_, config)
          local root_dir = config.root_dir
          if type(root_dir) ~= 'string' or root_dir == '' then return end
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
          -- Yarn PnP support
          local pnp_cjs = root_dir .. '/.pnp.cjs'
          local pnp_js = root_dir .. '/.pnp.js'
          if type(config.cmd) == 'table' and (vim.uv.fs_stat(pnp_cjs) or vim.uv.fs_stat(pnp_js)) then
            config.cmd = vim.list_extend({ 'yarn', 'exec' }, config.cmd)
          end
          -- Detect flat config
          local flat_suffixes = {
            '/eslint.config.js', '/eslint.config.mjs', '/eslint.config.cjs',
            '/eslint.config.ts', '/eslint.config.mts', '/eslint.config.cts',
          }
          local has_flat = false
          for _, suffix in ipairs(flat_suffixes) do
            if vim.fn.filereadable(root_dir .. suffix) == 1 then
              has_flat = true
              break
            end
          end
          config.settings.experimental = vim.tbl_deep_extend('force', config.settings.experimental or {}, {
            useFlatConfig = has_flat,
          })
          -- Use skip-type-aware config for speed (default). Set
          -- vim.g.benchling_eslint_full_type_aware = 1 to use full config.
          local skip_aware = root_dir .. '/eslint.config.skip-type-aware-rules.js'
          local want_full = vim.g.benchling_eslint_full_type_aware == true
            or vim.g.benchling_eslint_full_type_aware == 1
          if not want_full and vim.fn.filereadable(skip_aware) == 1 then
            config.settings['eslint.options'] = vim.tbl_deep_extend(
              'force', config.settings['eslint.options'] or {}, {
                overrideConfigFile = skip_aware,
              })
          end
        end,
      },

      -- Python: type analysis + completions
      pyright = {
        root_dir = root.ruff_root_dir,
        before_init = function(_, config)
          config.settings = config.settings or {}
          config.settings.python = config.settings.python or {}
          local rd = config.root_dir
          -- Detect Benchling monorepo
          local is_benchling = type(rd) == 'string' and rd ~= ''
            and vim.fn.filereadable(rd .. '/eslint.config.js') == 1
            and vim.fn.filereadable(rd .. '/package.json') == 1
          if is_benchling then
            local extra = root.aurelia_default_pyright_extra_paths(rd)
            if type(vim.g.benchling_pyright_extra_paths) == 'table' then
              vim.list_extend(extra, vim.g.benchling_pyright_extra_paths)
            end
            config.settings.python.analysis = vim.tbl_deep_extend(
              'force', config.settings.python.analysis or {}, {
                typeCheckingMode = 'off',   -- mypy is the real type checker
                autoSearchPaths = false,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
                extraPaths = extra,
              })
          else
            config.settings.python.analysis = vim.tbl_deep_extend(
              'force', config.settings.python.analysis or {}, {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
              })
          end
          -- Resolve python path: VIRTUAL_ENV > BENCHLING_PYTHON > fallback
          local python_path
          if vim.env.VIRTUAL_ENV and vim.fn.executable(vim.env.VIRTUAL_ENV .. '/bin/python') == 1 then
            python_path = vim.env.VIRTUAL_ENV .. '/bin/python'
          end
          if python_path then
            config.settings.python = vim.tbl_deep_extend('force', config.settings.python or {}, {
              pythonPath = python_path,
            })
          end
        end,
        settings = { python = { analysis = {} } },
      },

      -- Python: lint + format diagnostics (reads pyproject.toml)
      ruff = {
        root_dir = root.ruff_root_dir,
      },

      -- GraphQL: schema-aware completions
      graphql = {
        root_dir = root.graphql_root_dir,
      },

      -- YAML
      yamlls = {
        filetypes = { 'yaml' },
      },

      -- OpenAPI / AsyncAPI linting
      spectral = {
        filetypes = { 'yaml', 'json' },
        settings = {
          enable = true,
          run = 'onType',
          validateLanguages = { 'yaml', 'json' },
        },
      },

      -- Lua (for editing Neovim config)
      lua_ls = {
        on_init = function(client)
          if client.workspace_folders then
            local path = client.workspace_folders[1].name
            if path ~= vim.fn.stdpath 'config'
              and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
            then
              return
            end
          end
          client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
            runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
            workspace = {
              checkThirdParty = false,
              library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
                '${3rd}/luv/library',
                '${3rd}/busted/library',
              }),
            },
          })
        end,
        settings = { Lua = {} },
      },
    }

    -- Register and enable servers (only one of ts_ls/vtsls)
    for name, server in pairs(servers) do
      local skip = (name == 'ts_ls' and use_vtsls) or (name == 'vtsls' and not use_vtsls)
      if not skip then
        vim.lsp.config(name, server)
        vim.lsp.enable(name)
      end
    end
  end,
}
```

</details>

---

## Step 4: Formatting (conform.nvim)

Runs formatters on save that match what Benchling CI checks (`OXFMT`, `RUFF_FORMAT`).

<details>
<summary><strong>Plugin spec: Formatting</strong> (click to expand)</summary>

```lua
{
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function() require('conform').format { async = true, lsp_format = 'fallback' } end,
      mode = '',
      desc = 'Format buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then return nil end
      return { timeout_ms = 2500, lsp_format = 'fallback' }
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      json = { 'prettier' },
      json5 = { 'prettier' },
      yaml = { 'prettier' },
      graphql = { 'prettier' },
      python = { 'ruff_fix', 'ruff_format' },
      javascript = { 'oxfmt' },
      javascriptreact = { 'oxfmt' },
      typescript = { 'oxfmt' },
      typescriptreact = { 'oxfmt' },
      css = { 'oxfmt' },
      less = { 'oxfmt' },
    },
    formatters = {
      oxfmt = {
        command = 'npx',
        args = { 'oxfmt', '--stdin-filepath', '$FILENAME' },
        stdin = true,
      },
    },
  },
}
```

</details>

**How it works:**
- `oxfmt` reads `.oxfmtrc.json` from the repo root (singleQuote: true, printWidth: 110)
- `ruff_fix` sorts imports, `ruff_format` formats code (reads `pyproject.toml`)
- `prettier` handles JSON/YAML/GraphQL where no Benchling-specific formatter exists
- The custom `oxfmt` definition pipes buffer contents via stdin using `npx`

---

## Step 5: Linting (nvim-lint)

Adds linters that LSP servers don't already cover. Specifically: **mypy** for Python type checking (Pyright is set to `typeCheckingMode = off` for Benchling, so mypy fills the gap).

<details>
<summary><strong>Plugin spec: Linting</strong> (click to expand)</summary>

```lua
{
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require 'lint'
    lint.linters_by_ft = {
      markdown = { 'markdownlint' },
      python = { 'mypy' },
    }

    local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      group = lint_augroup,
      callback = function()
        if vim.bo.modifiable then
          lint.try_lint()
        end
      end,
    })
  end,
}
```

</details>

**Why only mypy?**
- **Ruff lint** — already covered by Ruff LSP (real-time diagnostics)
- **ESLint** — already covered by ESLint LSP
- **oxlint** — already integrated into ESLint via `eslint-plugin-oxlint`; running standalone would duplicate 350+ diagnostics

**Performance note:** mypy is slow (~5-10s per file). It only runs on save, not on every keystroke. To disable it: remove `python = { 'mypy' }` from the config, or at runtime: `:lua require('lint').linters_by_ft.python = {}`.

---

## Step 6: Treesitter Parsers

If you already have `nvim-treesitter`, add these parsers for full Benchling language coverage. How you add them depends on your treesitter config — just make sure these are in your parser list:

```lua
'bash', 'c', 'css', 'diff', 'graphql', 'html', 'javascript', 'jsdoc',
'json', 'json5', 'lua', 'luadoc', 'markdown', 'markdown_inline',
'python', 'query', 'regex', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml'
```

If you don't have treesitter yet:

```lua
{
  'nvim-treesitter/nvim-treesitter',
  lazy = false,
  build = ':TSUpdate',
  branch = 'main',
  config = function()
    local parsers = {
      'bash', 'c', 'css', 'diff', 'graphql', 'html', 'javascript', 'jsdoc',
      'json', 'json5', 'lua', 'luadoc', 'markdown', 'markdown_inline',
      'python', 'query', 'regex', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml',
    }
    require('nvim-treesitter').install(parsers, { prefer_git = true })
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        local language = vim.treesitter.language.get_lang(args.match)
        if not language then return end
        if not vim.treesitter.language.add(language) then return end
        vim.treesitter.start(args.buf, language)
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
```

---

## Step 7: Environment Variables

Add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
# Tell Pyright where your dev Python lives.
# Use ONE of these (first match wins):
export VIRTUAL_ENV="/path/to/your/dev/venv"
# OR: export AURELIA_PYTHON="/path/to/python3"
# OR: export AURELIA_PYTHON_VENV="/path/to/venv/root"
```

---

## Verification

After restarting Neovim and opening a file in the Benchling repo:

### Python (.py file)
```
:LspInfo
```
Should show **pyright** and **ruff** attached. Save the file — imports should sort and code should format. After a few seconds, mypy diagnostics appear.

### TypeScript (.ts / .tsx file)
```
:LspInfo
```
Should show **ts_ls** (or **vtsls**) and **eslint** attached. Save — single quotes should be preserved (oxfmt). ESLint diagnostics should appear.

### GraphQL (.graphql file)
```
:LspInfo
```
Should show **graphql** attached with schema-aware completions.

### General
```
:Mason              " All tools should have green checkmarks
:ConformInfo        " Should show the correct formatter for current filetype
:checkhealth        " Should pass without errors
```

---

## Benchling Tool → Editor Mapping

| CI Checker | What runs in your editor |
|------------|-------------------------|
| `OXFMT` | conform.nvim → oxfmt (on save) |
| `RUFF_FORMAT` | conform.nvim → ruff_format (on save) |
| `RUFF_LINT` | Ruff LSP (real-time) |
| `ESLINT` | ESLint LSP (real-time) |
| `OXLINT` | ESLint LSP via eslint-plugin-oxlint (real-time) |
| `MYPY` | nvim-lint → mypy (on save) |
| `TYPESCRIPT` | ts_ls / vtsls LSP (real-time) |

---

## Troubleshooting

**ESLint not attaching:**
Check that `node_modules` exists (`yarn install`). Check `:LspLog` for errors. Verify `eslint.config.js` exists at the repo root.

**Pyright can't resolve `benchling.*` imports:**
Set `VIRTUAL_ENV` in your shell, or add paths via `vim.g.benchling_pyright_extra_paths = { 'extra/path' }` in your init.lua.

**oxfmt not found / not formatting:**
Run `npx oxfmt --version` from the repo root. If it fails, run `yarn install`. Check `:ConformInfo` to see if oxfmt is listed for the current filetype.

**Single quotes becoming double quotes:**
`:ConformInfo` should show `oxfmt` (not `prettier`) for JS/TS files. If prettier is listed, the conform config didn't load — check for Lua errors on startup.

**mypy too slow:**
Disable per-buffer: `:lua require('lint').linters_by_ft.python = {}`. Or remove `python = { 'mypy' }` from the lint config entirely.

**Mason tool won't install:**
Open `:Mason`, find the tool, press `i`. Check `:MasonLog` for errors. Ensure Node.js and Python are on `PATH`.

---

## Summary Checklist

- [ ] Created `lua/benchling/root.lua` (monorepo root detection)
- [ ] Added LSP plugin spec (9 servers configured)
- [ ] Added conform.nvim plugin spec (oxfmt, ruff, prettier, stylua)
- [ ] Added nvim-lint plugin spec (mypy, markdownlint)
- [ ] Added treesitter parsers (23 languages)
- [ ] Set `VIRTUAL_ENV` in shell profile
- [ ] Ran `yarn install` in the Benchling repo
- [ ] Opened Neovim, ran `:checkhealth`, verified `:Mason` and `:LspInfo`
