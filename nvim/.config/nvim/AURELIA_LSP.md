# Aurelia (Benchling monorepo) — Neovim LSP parity notes

Portable reference: open the Aurelia repo at **git root** (same as a single-folder VS Code workspace). Language servers read `eslint.config.js`, `tsconfig.json`, `graphql.config.yml`, and `pyproject.toml` from that root when `cwd` / `root_dir` resolve there.

## Environment (optional)

| Variable | Purpose |
|----------|---------|
| `VIRTUAL_ENV` | ty and Ruff resolve first-party imports and third-party packages from this environment when set (e.g. after `source` on the dev venv). |

Put the dev venv’s `bin` **before** Mason’s shims on `PATH` if you need the same Ruff/Mypy/ty versions as `dev run shell`; otherwise Mason’s versions are used.

## `vim.g` toggles (optional)

| Global | Effect |
|--------|--------|
| `vim.g.kickstart_use_vtsls = 1` | Use **vtsls** instead of **ts_ls** (VS Code extension–aligned wrapper; workspace TS + `maxTsServerMemory` 6144). Default is `ts_ls` + repo `tsserver.js` + `NODE_OPTIONS=--max-old-space-size=6144`. |
| `vim.g.aurelia_eslint_full_type_aware = 1` | Use root `eslint.config.js` only (slow, type-aware). Default: if `eslint.config.skip-type-aware-rules.js` exists, ESLint LSP uses it (matches `aurelia.code-workspace` speed). |

ty resolves first-party imports such as `benchling.*` and `tests.*` from the active Python environment; no per-project `extraPaths` are needed.

**TSgo / `typescript.experimental.useTsgo`:** VS Code–only. Neovim has no native TSgo; **vtsls** is closer to the VS Code TS UX than `ts_ls` but still not TSgo.

## Config paths (relative to repo root)

| Area | Files |
|------|--------|
| TS | `tsconfig.json`, `tsconfig-base.json` |
| ESLint (flat) | `eslint.config.js`; workspace-style fast lint: `eslint.config.skip-type-aware-rules.js` |
| GraphQL | `graphql.config.yml` |
| Python | `pyproject.toml`, `mypy.ini`, `benchling/ruff.toml`, `services/monolith/pyproject.toml` |
| Editor width | `.editorconfig` (e.g. 110 cols) |

## Mason packages (this config)

Installed via `mason-lspconfig` / Mason UI: `ts_ls`, `vtsls`, `eslint`, `ty`, `ruff`, `graphql`, `lua_ls`, `spectral`, `yamlls`, `zls`. Tools via `mason-tool-installer`: `stylua`, `prettier`, `oxlint`, `mypy`, `markdownlint`.

Only one of `ts_ls` / `vtsls` is enabled (see `vim.g.kickstart_use_vtsls`).

**Pinning:** use `:Mason` to pick versions; Lua stays path-agnostic.

## Formatting (conform.nvim)

Formatters run on save via `conform.nvim` (`lua/kickstart/plugins/conform.lua`):

| Filetype | Formatter | Benchling CI checker |
|----------|-----------|---------------------|
| Python | ruff_fix → ruff_format | `RUFF_FORMAT` |
| JS/TS/TSX/JSX | oxfmt (via `npx`, stdin mode) | `OXFMT` |
| CSS/Less | oxfmt | `OXFMT` |
| JSON/JSON5/YAML/GraphQL | prettier | — |
| Lua | stylua | — |

oxfmt reads `.oxfmtrc.json` from the repo root (singleQuote, 110 width, trailingComma es5). The custom formatter definition uses `npx oxfmt --stdin-filepath $FILENAME` with stdin piping.

**Note:** oxlint is a **linter**, not a formatter — it is not in the conform config. ESLint LSP handles oxlint rules via `eslint-plugin-oxlint`.

## Linting (nvim-lint)

`nvim-lint` (`lua/kickstart/plugins/lint.lua`) runs linters on save that LSP servers don't cover:

| Filetype | Linter | Why needed |
|----------|--------|-----------|
| Python | mypy | Full-workspace type checking with Benchling's `mypy.ini` (matches CI); complements ty's real-time LSP diagnostics |
| Markdown | markdownlint | Style checks |

**Not in nvim-lint** (and why):
- **ruff** — Ruff LSP already provides all ruff diagnostics in real-time
- **oxlint** — ESLint LSP delegates oxlint rules via `eslint-plugin-oxlint`; running standalone would duplicate 350+ diagnostics
- **eslint** — ESLint LSP covers this

## Implementation in this repo

- `lua/kickstart/benchling_root.lua` — git root when `package.json` + `eslint.config.js` exist there; GraphQL root prefers that root when `graphql.config.*` exists; **ruff** / **ty** `root_dir` uses the same monorepo root with fallback to nearest `pyproject.toml` / `.git`.
- `lua/kickstart/plugins/lspconfig.lua` — repo `node_modules/.bin` on `PATH` for TS + ESLint; workspace `tsserver.js` for `ts_ls`; optional **vtsls** with `autoUseWorkspaceTsdk` and 6144 MB tsserver budget; ESLint `eslint.options.overrideConfigFile` for skip-type-aware config when present; ESLint Node heap via `eslint.execArgv`; **ty** with `diagnosticMode = openFilesOnly`, auto-import completions, and call-argument inlay hints (mirrors `ty.*` in the workspace); **ruff** registered with monorepo `root_dir`.

## CI parity (run inside Aurelia clone)

- JS/TS: `eslint` from repo root on changed paths (same flat config as the ESLint LSP).
- Python: `dev check lint` (see `CLAUDE.md` in that repo).
