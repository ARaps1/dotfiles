# Aurelia (Benchling monorepo) — Neovim LSP parity notes

Portable reference: open the Aurelia repo at **git root** (same as a single-folder VS Code workspace). Language servers read `eslint.config.js`, `tsconfig.json`, `graphql.config.yml`, and `pyproject.toml` from that root when `cwd` / `root_dir` resolve there.

## Environment (optional)

| Variable | Purpose |
|----------|---------|
| `VIRTUAL_ENV` | Pyright uses `…/bin/python` when set (e.g. after `source` on the dev venv). |
| `AURELIA_PYTHON` | Absolute path to a `python` binary for Pyright when not using `VIRTUAL_ENV`. |
| `AURELIA_PYTHON_VENV` | Path to a venv root; Pyright uses `…/bin/python`. |

Put the dev venv’s `bin` **before** Mason’s shims on `PATH` if you need the same Ruff/Mypy versions as `dev run shell`; otherwise Mason’s `ruff` is used.

## `vim.g` toggles (optional)

| Global | Effect |
|--------|--------|
| `vim.g.kickstart_use_vtsls = 1` | Use **vtsls** instead of **ts_ls** (VS Code extension–aligned wrapper; workspace TS + `maxTsServerMemory` 6144). Default is `ts_ls` + repo `tsserver.js` + `NODE_OPTIONS=--max-old-space-size=6144`. |
| `vim.g.aurelia_eslint_full_type_aware = 1` | Use root `eslint.config.js` only (slow, type-aware). Default: if `eslint.config.skip-type-aware-rules.js` exists, ESLint LSP uses it (matches `aurelia.code-workspace` speed). |
| `vim.g.aurelia_pyright_extra_paths` | Extra strings **appended** after auto-detected paths (see below). |

When the Aurelia/Benchling root heuristic matches, Pyright uses `autoSearchPaths = false` (like the workspace). Without `extraPaths`, first-party imports such as `benchling.*` and `tests.*` (under `src/`) fail. This config adds defaults for any of these that exist: `.`, `src`, `tests`, `scripts`, `services/monolith`, then your `vim.g.aurelia_pyright_extra_paths`.

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

Installed via `mason-lspconfig` / Mason UI: `ts_ls`, `vtsls`, `eslint`, `pyright`, `ruff`, `graphql`, `lua_ls`, `spectral`, `yamlls`, `zls`. Tools via `mason-tool-installer`: `stylua`, `prettier`, `oxlint`.

Only one of `ts_ls` / `vtsls` is enabled (see `vim.g.kickstart_use_vtsls`).

To use **basedpyright** instead of Pyright, install Mason `basedpyright`, add it to `ensure_installed`, put `basedpyright` in `automatic_enable.exclude` and remove `pyright` from that exclude list, and register `basedpyright` in the `servers` table like `pyright` (only one Python analyzer should attach).

**Pinning:** use `:Mason` to pick versions; Lua stays path-agnostic.

## Implementation in this repo

- `lua/kickstart/benchling_root.lua` — git root when `package.json` + `eslint.config.js` exist there; GraphQL root prefers that root when `graphql.config.*` exists; **ruff** / **pyright** `root_dir` uses the same monorepo root with fallback to nearest `pyproject.toml` / `.git`.
- `lua/kickstart/plugins/lspconfig.lua` — repo `node_modules/.bin` on `PATH` for TS + ESLint; workspace `tsserver.js` for `ts_ls`; optional **vtsls** with `autoUseWorkspaceTsdk` and 6144 MB tsserver budget; ESLint `eslint.options.overrideConfigFile` for skip-type-aware config when present; ESLint Node heap via `eslint.execArgv`; Pyright `typeCheckingMode = off` + `autoSearchPaths = false` on Benchling root (aligns with Pylance-off + mypy story); **ruff** registered with monorepo `root_dir`.

## CI parity (run inside Aurelia clone)

- JS/TS: `eslint` from repo root on changed paths (same flat config as the ESLint LSP).
- Python: `dev check lint` (see `CLAUDE.md` in that repo).
