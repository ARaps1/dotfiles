# Benchling Neovim Setup Guide

Plug-and-play Neovim configuration aligned with Benchling's Aurelia monorepo tooling. Covers Python, TypeScript/React, GraphQL, and all CI linters.

## Prerequisites

| Dependency | Minimum | How to check |
|-----------|---------|-------------|
| Neovim | >= 0.11 | `nvim --version` |
| Node.js | >= 18 | `node --version` |
| npm | any | `npm --version` |
| Python | 3.12 | `python3 --version` |
| git | any | `git --version` |
| make | any | `make --version` |
| ripgrep | any | `rg --version` |
| A Nerd Font | - | Hack Nerd Font recommended |

Optional: `fd`, `unzip`, `tree-sitter-cli` (setup.sh installs these).

## Quick Start

```bash
# 1. Clone the dotfiles repo
git clone <dotfiles-repo-url> ~/dotfiles

# 2. Run the setup script (installs Neovim, deps, creates symlinks)
cd ~/dotfiles && ./setup.sh nvim

# 3. Open Neovim — Lazy installs plugins, Mason installs tools automatically
nvim

# 4. Verify everything is healthy
:checkhealth
```

First launch takes ~1 minute while plugins and LSP servers install. Treesitter parsers compile in the background.

## What's Configured

### LSP Servers (auto-installed via Mason)

| Server | Language | Purpose |
|--------|----------|---------|
| **ts_ls** | TypeScript/JavaScript | Type checking, completions, go-to-def, inlay hints |
| **vtsls** | TypeScript/JavaScript | Alternative to ts_ls (VS Code-aligned); toggle with `vim.g.kickstart_use_vtsls = 1` |
| **eslint** | TypeScript/JavaScript | Lint via flat config (`eslint.config.js`); integrates oxlint rules |
| **ty** | Python | Type diagnostics, completions, go-to-def, import resolution (Astral's fast type checker; mirrors `ty.*` in `aurelia.code-workspace`) |
| **ruff** | Python | Real-time lint + format diagnostics (reads `pyproject.toml`) |
| **graphql** | GraphQL | Schema-aware completions, diagnostics (reads `graphql.config.yml`) |
| **lua_ls** | Lua | For editing Neovim config |
| **yamlls** | YAML | Schema validation |
| **spectral** | YAML/JSON | OpenAPI linting |

### Formatters (via conform.nvim, run on save)

| Filetype | Formatter | Config source |
|----------|-----------|---------------|
| Python | ruff_fix + ruff_format | `pyproject.toml` `[tool.ruff]` |
| JS/TS/TSX/JSX | oxfmt | `.oxfmtrc.json` (singleQuote, 110 width) |
| CSS/Less | oxfmt | `.oxfmtrc.json` |
| JSON | prettier | defaults |
| JSON5/YAML/GraphQL | prettier | defaults |
| Lua | stylua | `.stylua.toml` |

### Linters (via nvim-lint, run on save/enter)

| Filetype | Linter | Notes |
|----------|--------|-------|
| Python | mypy | Full-workspace type checking against `mypy.ini` (matches CI); complements ty's real-time diagnostics. Slower (~5-10s). |
| Markdown | markdownlint | Style checks |

**Why not more linters?** Ruff LSP already provides all Python lint diagnostics in real-time. ESLint LSP already integrates oxlint's 350+ rules via `eslint-plugin-oxlint`. Adding them to nvim-lint would duplicate every diagnostic.

### Treesitter Parsers

```
bash, c, css, diff, graphql, html, javascript, jsdoc, json, json5, lua,
luadoc, markdown, markdown_inline, python, query, regex, tsx, typescript,
vim, vimdoc, yaml
```

### Completions

**blink.cmp** with LuaSnip snippets. Sources: LSP, path, snippets.

- `<C-y>` — Accept completion (auto-imports + snippets)
- `<C-space>` — Toggle completion menu
- `<C-n>/<C-p>` — Navigate items
- `<Tab>/<S-Tab>` — Navigate snippet placeholders

## Benchling Monorepo Integration

### How root detection works

`lua/kickstart/benchling_root.lua` detects the Benchling monorepo by finding `package.json` + `eslint.config.js` at the git root. All LSP servers use this root as their working directory, matching VS Code single-folder workspace behavior.

### Environment variables (optional)

| Variable | Purpose |
|----------|---------|
| `VIRTUAL_ENV` | ty and Ruff resolve imports and packages from this environment when set |

Put the dev venv's `bin` before Mason's shims on `PATH` if you need the same tool versions as `dev run shell`.

### vim.g toggles (set in init.lua or at runtime)

| Global | Default | Effect |
|--------|---------|--------|
| `vim.g.kickstart_use_vtsls` | false | Use vtsls instead of ts_ls |
| `vim.g.aurelia_eslint_full_type_aware` | false | Use full `eslint.config.js` (slow) vs skip-type-aware (fast, default) |

### ty import resolution

ty resolves first-party imports such as `benchling.*` and `tests.*` from the active Python environment (the dev venv, or the interpreter on `PATH`). No per-project `extraPaths` configuration is needed.

## Verification Checklist

### Python (open a `.py` file in the Benchling repo)

- [ ] `:LspInfo` shows **ty** and **ruff** attached
- [ ] Ruff diagnostics appear (import sorting, unused imports)
- [ ] Save (`:w`) triggers ruff_fix + ruff_format (imports sort, code formats)
- [ ] After save, mypy diagnostics appear (may take 5-10s on first run)
- [ ] `grd` — go-to-definition works
- [ ] `<C-space>` — completions appear

### TypeScript (open a `.ts` or `.tsx` file)

- [ ] `:LspInfo` shows **ts_ls** (or vtsls) and **eslint** attached
- [ ] ESLint diagnostics appear
- [ ] Save triggers oxfmt — single quotes preserved, 110-char line width
- [ ] `<leader>th` — inlay hints toggle on/off
- [ ] `grd` — go-to-definition works

### GraphQL (open a `.graphql` file)

- [ ] `:LspInfo` shows **graphql** attached
- [ ] Schema-aware completions work

### General

- [ ] `:Mason` — all tools show green checkmarks
- [ ] `:ConformInfo` — shows correct formatter for current filetype
- [ ] `:checkhealth` — no errors

## Keybindings Reference

### LSP

| Key | Mode | Action |
|-----|------|--------|
| `grd` | n | Go to definition |
| `grr` | n | Find references |
| `gri` | n | Go to implementation |
| `grt` | n | Go to type definition |
| `grn` | n | Rename symbol |
| `gra` | n, v | Code action |
| `grD` | n | Go to declaration |
| `gO` | n | Document symbols |
| `gW` | n | Workspace symbols |
| `<leader>th` | n | Toggle inlay hints |

### Formatting & Diagnostics

| Key | Mode | Action |
|-----|------|--------|
| `<leader>f` | n, v | Format buffer |
| `<leader>q` | n | Diagnostic quickfix list |
| `[d` / `]d` | n | Previous / next diagnostic |

### Search (Telescope)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>sf` | n | Search files |
| `<leader>sg` | n | Search by grep |
| `<leader>sd` | n | Search diagnostics |
| `<leader>sw` | n, v | Search current word |
| `<leader>sh` | n | Search help |
| `<leader>sk` | n | Search keymaps |
| `<leader>sr` | n | Resume last search |
| `<leader><leader>` | n | Switch buffer |
| `<leader>/` | n | Fuzzy search current buffer |

### Git (gitsigns)

| Key | Mode | Action |
|-----|------|--------|
| `]c` / `[c` | n | Next / prev git change |
| `<leader>hs` | n, v | Stage hunk |
| `<leader>hr` | n, v | Reset hunk |
| `<leader>hp` | n | Preview hunk |
| `<leader>hb` | n | Blame line |
| `<leader>tb` | n | Toggle blame |

## Troubleshooting

### ESLint not attaching

1. Check `:LspInfo` — eslint should show `root_dir` as the repo root
2. Check `:LspLog` for errors
3. Ensure `node_modules` exists: run `yarn install` in the repo
4. Verify `eslint.config.js` exists at repo root

### ty can't resolve imports

1. Set `VIRTUAL_ENV` to your dev venv path so ty picks up the right interpreter and packages, or
2. Put the dev venv's `bin` before Mason's shims on `PATH`.

### mypy is too slow

mypy runs per-file on save and can take 5-10s. To disable:

```lua
-- In lua/kickstart/plugins/lint.lua, remove 'mypy' from python:
python = {},
```

Or disable at runtime: `:lua require('lint').linters_by_ft.python = {}`

### oxfmt not formatting / not found

1. Ensure you're in a repo with oxfmt in devDependencies
2. Run `npx oxfmt --version` from the repo root
3. Check `:ConformInfo` for the oxfmt formatter status

### Mason tool not installing

1. Open `:Mason` and press `i` on the missing tool
2. Check `:MasonLog` for errors
3. Ensure Node.js and Python are on `PATH`

### Format on save converts quotes

If single quotes become double quotes, check `:ConformInfo` — you should see `oxfmt` (not `prettier`) for JS/TS files. If prettier is listed, the conform config may not have loaded correctly.

## File Organization

```
~/.config/nvim/
├── init.lua                          # Entry point: leader key, requires core modules
├── lua/
│   ├── lazy-bootstrap.lua            # Installs lazy.nvim on first run
│   ├── lazy-plugins.lua              # Plugin specs & lazy.setup()
│   ├── options.lua                   # Vim options (numbers, clipboard, indent)
│   ├── keymaps.lua                   # Global keymaps + diagnostic config + autocmds
│   ├── custom/plugins/init.lua       # Your personal plugins (currently empty)
│   └── kickstart/
│       ├── benchling_root.lua        # Monorepo root detection helpers
│       ├── health.lua                # :checkhealth implementation
│       └── plugins/
│           ├── lspconfig.lua         # LSP servers (10 configured) + Mason
│           ├── conform.lua           # Formatters (oxfmt, ruff, stylua, prettier)
│           ├── lint.lua              # Linters (mypy, markdownlint)
│           ├── blink-cmp.lua         # Completions (blink.cmp + LuaSnip)
│           ├── treesitter.lua        # Syntax highlighting + indent (23 parsers)
│           ├── telescope.lua         # Fuzzy finder
│           ├── which-key.lua         # Keybinding hints
│           ├── gitsigns.lua          # Git integration
│           ├── mini.lua              # Text objects + surround + statusline
│           ├── neo-tree.lua          # File explorer
│           ├── tokyonight.lua        # Color scheme
│           ├── todo-comments.lua     # TODO/FIXME highlighting
│           ├── debug.lua             # DAP debugger
│           └── indent_line.lua       # Indent guides
├── BENCHLING_NEOVIM_SETUP.md         # This file
├── AURELIA_LSP.md                    # LSP parity implementation notes
└── lazy-lock.json                    # Pinned plugin versions
```

## CI Parity

Your editor formatting and linting should match what CI checks. Key mappings:

| CI Checker | Editor Equivalent |
|------------|------------------|
| `OXFMT` | conform.nvim oxfmt formatter |
| `RUFF_FORMAT` | conform.nvim ruff_format |
| `RUFF_LINT` | Ruff LSP diagnostics |
| `ESLINT` | ESLint LSP diagnostics |
| `OXLINT` | ESLint LSP (delegates via eslint-plugin-oxlint) |
| `MYPY` | nvim-lint mypy |
| `TYPESCRIPT` | ts_ls / vtsls LSP diagnostics |

To verify CI parity on specific files:
```bash
dev check lint --autofix --auto-amend-commit=false --only RUFF_FORMAT --only OXFMT
```
