-- Monorepo root helpers for Benchling "Aurelia"-style repos (flat ESLint, root graphql.config.yml).
-- Language servers resolve configs from the buffer project root; these helpers prefer the git root
-- when it matches a single-folder VS Code workspace (package.json + eslint.config.js at repo root).

local util = require 'lspconfig.util'

local M = {}

--- @param bufnr integer
--- @return string|nil
function M.benchling_js_monorepo_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    return nil
  end
  local git = vim.fs.root(path, { '.git' })
  if not git then
    return nil
  end
  if vim.fn.filereadable(git .. '/package.json') ~= 1 then
    return nil
  end
  if vim.fn.filereadable(git .. '/eslint.config.js') ~= 1 then
    return nil
  end
  return git
end

-- Matches nvim-lspconfig lsp/ts_ls.lua root_dir (deno excluded, lockfile or git).
--- @param bufnr integer
--- @param on_dir fun(path: string)
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
  if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
    return
  end
  if deno_root and (not project_root or #deno_root >= #project_root) then
    return
  end
  on_dir(project_root or vim.fn.getcwd())
end

local eslint_config_files = {
  '.eslintrc',
  '.eslintrc.js',
  '.eslintrc.cjs',
  '.eslintrc.yaml',
  '.eslintrc.yml',
  '.eslintrc.json',
  'eslint.config.js',
  'eslint.config.mjs',
  'eslint.config.cjs',
  'eslint.config.ts',
  'eslint.config.mts',
  'eslint.config.cts',
}

-- Matches nvim-lspconfig lsp/eslint.lua root_dir, with Benchling git root first.
--- @param bufnr integer
--- @param on_dir fun(path: string)
function M.eslint_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    on_dir(br)
    return
  end

  local root_markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' }
  root_markers = vim.fn.has 'nvim-0.11.3' == 1 and { root_markers, { '.git' } }
    or vim.list_extend(root_markers, { '.git' })

  if vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc', 'deno.lock' }) then
    return
  end

  local project_root = vim.fs.root(bufnr, root_markers) or vim.fn.getcwd()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local eslint_config_files_with_package_json = util.insert_package_json(eslint_config_files, 'eslintConfig', filename)
  local is_buffer_using_eslint = vim.fs.find(eslint_config_files_with_package_json, {
    path = filename,
    type = 'file',
    limit = 1,
    upward = true,
    stop = vim.fs.dirname(project_root),
  })[1]
  if not is_buffer_using_eslint then
    return
  end

  on_dir(project_root)
end

--- @param bufnr integer
--- @param on_dir fun(path: string)
local function has_graphql_config_at_root(root)
  for _, name in ipairs { 'graphql.config.yml', 'graphql.config.yaml', 'graphql.config.js' } do
    if vim.fn.filereadable(root .. '/' .. name) == 1 then
      return true
    end
  end
  return false
end

function M.graphql_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br and has_graphql_config_at_root(br) then
    on_dir(br)
    return
  end
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname == '' then
    on_dir(vim.fn.getcwd())
    return
  end
  local resolved = util.root_pattern('.graphqlrc*', '.graphql.config.*', 'graphql.config.*')(fname)
  on_dir(resolved or vim.fs.root(fname, { '.git' }) or vim.fn.fnamemodify(fname, ':p:h'))
end

-- Paths Pylance uses via python.analysis.extraPaths in aurelia.code-workspace; required when
-- autoSearchPaths is false so Pyright resolves `benchling.*`, `tests.*` under `src/`, etc.
--- @param repo_root string
--- @return string[]
function M.aurelia_default_pyright_extra_paths(repo_root)
  if vim.fn.isdirectory(repo_root) ~= 1 then
    return {}
  end
  local out = {}
  for _, rel in ipairs { '.', 'src', 'tests', 'scripts', 'services/monolith' } do
    local full = rel == '.' and repo_root or (repo_root .. '/' .. rel)
    if vim.fn.isdirectory(full) == 1 then
      out[#out + 1] = rel
    end
  end
  return out
end

-- Ruff / Pyright: monorepo root matches VS Code single-folder workspace (git root with markers).
--- @param bufnr integer
--- @param on_dir fun(path: string)
function M.ruff_root_dir(bufnr, on_dir)
  local br = M.benchling_js_monorepo_root(bufnr)
  if br then
    on_dir(br)
    return
  end
  on_dir(vim.fs.root(bufnr, { 'pyproject.toml', 'ruff.toml', '.git' }) or vim.fn.getcwd())
end

return M
