# Neovim configuration guide

This config is a **modular** fork of [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). Plugins are managed by [lazy.nvim](https://github.com/folke/lazy.nvim). All paths below are relative to this directory (`nvim/.config/nvim/` when symlinked as `~/.config/nvim`).

## Entry point

| File | Purpose |
|------|---------|
| `init.lua` | Sets `mapleader` / `maplocalleader`, loads `opts`, `keymaps`, and `autocmds`, bootstraps `lazy.nvim`, then runs `require('lazy').setup(require('plugins'), { ui = … })`. |

Nothing heavy should run before `lazy.nvim` is on the runtime path except leaders and the three `require` calls above.

## Non-plugin Lua (`lua/`)

| File | Purpose |
|------|---------|
| `lua/opts.lua` | `vim.o` / `vim.opt` / `vim.g` (e.g. `have_nerd_font`, line numbers, clipboard). |
| `lua/keymaps.lua` | Keymaps that do **not** depend on a plugin’s `config` hook. |
| `lua/autocmds.lua` | `vim.api.nvim_create_autocmd` definitions shared across the editor. |

LSP-specific autocommands (e.g. `LspAttach`) live in `lua/plugins/lsp.lua` with the LSP stack.

## Plugins (`lua/plugins/`)

`lua/plugins/init.lua` **merges** three sources (order matters for clarity, not usually for resolution):

1. `require('plugins.core')` — Telescope, theme, Treesitter, conform, blink.cmp, mini.nvim, etc.
2. `require('plugins.lsp')` — lazydev (Lua), `nvim-lspconfig`, Mason, diagnostics, Mason tool installer, `servers` table.
3. `{ import = 'custom.plugins' }` — the module **`custom.plugins`**, i.e. **`lua/custom/plugins/init.lua`** only. Extra `.lua` files in that folder are **not** auto-loaded unless `init.lua` requires them.

To understand “what loads what,” start with `init.lua`, then `lua/plugins/init.lua`, then `core.lua` / `lsp.lua`.

### Adding a new plugin (recommended: personal / experimental)

1. **Easiest:** append a plugin spec to the table in **`lua/custom/plugins/init.lua`**.
2. **Split file:** add e.g. `lua/custom/plugins/myplugin.lua` that `return { … }`, then merge it from `init.lua`, for example:
   `return vim.list_extend({ …existing… }, require('custom.plugins.myplugin'))`, or `return { require('custom.plugins.myplugin'), … }` depending on shape (each side should be a list of specs).
3. Restart Neovim (or run `:Lazy`). lazy.nvim will install; versions are pinned in **`lazy-lock.json`** (commit when you are happy).

### Adding a plugin to the “main” stack

- Put shared / default plugins in **`lua/plugins/core.lua`** (or **`lua/plugins/lsp.lua`** if it is LSP-, Mason-, or diagnostics-related).
- Keep `core` vs `lsp` split so LSP and Mason stay easy to find.

### Plugin spec shape (lazy.nvim)

Each spec is a Lua table, e.g. `'owner/repo'`, or `{ 'owner/repo', opts = { … } }`, or `{ 'owner/repo', config = function() … end }`. See `:help lazy.nvim-plugin` in Neovim.

## LSP and Mason

| Location | What to edit |
|----------|----------------|
| `lua/plugins/lsp.lua` | `servers = { … }` for per-server settings, `ensure_installed` via `mason-tool-installer`, `LspAttach` keymaps, `vim.diagnostic.config`. |

Use **`:Mason`** inside Neovim to install or inspect LSP binaries. Server names must match what `mason-lspconfig` / `lspconfig` expect.

## Optional kickstart extras (not loaded by default)

Under **`lua/kickstart/plugins/`** there are sample specs (debug, lint, neo-tree, autopairs, …). They are **not** imported unless you add them to a plugin list (e.g. in `core.lua` or `custom/plugins/init.lua`) with something like `require 'kickstart.plugins.neo-tree'` inside the returned table.

## Housekeeping

| File | Notes |
|------|--------|
| `lazy-lock.json` | Lockfile for lazy.nvim; update with `:Lazy update`. |
| `doc/kickstart.txt` | Short kickstart-oriented help tags. |
| `README.md` | Upstream-oriented readme; this `CLAUDE.md` is specific to **this** modular layout. |

## Quick commands

- **`:Lazy`** — plugin UI (install / update / enable).
- **`:Mason`** — LSP / formatter / linter binaries.
- **`:checkhealth`** — diagnostics for tools and optional deps.

When suggesting edits, prefer **small, focused changes**: one file per concern (`opts` vs `keymaps` vs `plugins/core` vs `plugins/lsp` vs `custom/plugins`).
