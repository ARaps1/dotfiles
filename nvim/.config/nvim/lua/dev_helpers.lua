-- Editor helpers for the Benchling monorepo: copy the current file's repo-relative
-- path, and run its unit tests via the dev CLI, resolving a production file to its test
-- with the same conventions as `dev test diff`.

local M = {}

-- Top-level directories whose Python files map into tests/unit/.
local PY_TEST_ROOTS = { benchling = true, migrations = true, scripts = true, tests = true }

-- Frontend extensions, including the `.rtl.ts` / `.rtl.tsx` variants so rtl test files match.
local JS_EXTS = { '.rtl.tsx', '.rtl.ts', '.tsx', '.ts', '.jsx', '.js' }

--- Repo-relative path of the current buffer (relative to its git root, falling back to
--- the working directory), plus the root used. Returns nil when the buffer has no file.
--- @return string|nil relpath
--- @return string root
local function current_rel_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return nil, ''
  end
  local root = vim.fs.root(name, { '.git' }) or vim.fn.getcwd()
  return vim.fs.relpath(root, name), root
end

--- Run a command in a terminal opened in a bottom split, from `cwd`.
--- @param cmd string[]
--- @param cwd string
local function run_in_terminal(cmd, cwd)
  vim.cmd 'botright new'
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
end

--- Repo-relative pyunit test path for a `.py` file, or nil when there is no mapping.
--- A file that is already a test runs as-is; a production file maps into tests/unit/.
--- @param rel string
--- @return string|nil
local function py_test_for(rel)
  if rel:match '_test%.py$' then
    return rel
  end
  local segments = vim.split(rel, '/', { plain = true })
  if not PY_TEST_ROOTS[segments[1]] then
    return nil
  end
  local filename = table.remove(segments)
  if segments[1] == 'benchling' then
    table.remove(segments, 1)
  elseif segments[1] == 'migrations' then
    for index, segment in ipairs(segments) do
      if segment == 'versions' then
        table.remove(segments, index)
        break
      end
    end
  end
  local parts = { 'tests', 'unit' }
  vim.list_extend(parts, segments)
  table.insert(parts, (filename:gsub('%.py$', '_test.py')))
  return table.concat(parts, '/')
end

--- @param rel string
--- @return boolean
local function is_js_test(rel)
  for _, ext in ipairs(JS_EXTS) do
    if rel:sub(-#('-test' .. ext)) == '-test' .. ext then
      return true
    end
  end
  return false
end

--- Existing repo-relative jsunit test paths for a frontend file. A test file returns
--- itself; a production file maps to `<dir>/__tests__/<name>-test.<ext>` candidates.
--- @param rel string
--- @param root string
--- @return string[]
local function js_tests_for(rel, root)
  if is_js_test(rel) then
    return { rel }
  end
  local segments = vim.split(rel, '/', { plain = true })
  if segments[1] ~= 'client' then
    return {}
  end
  local filename = table.remove(segments)
  local base = filename:gsub('%.[^.]+$', '')
  local dir = table.concat(segments, '/')
  local found = {}
  for _, ext in ipairs(JS_EXTS) do
    local candidate = dir .. '/__tests__/' .. base .. '-test' .. ext
    if vim.fn.filereadable(root .. '/' .. candidate) == 1 then
      table.insert(found, candidate)
    end
  end
  return found
end

--- Copy the current file's repo-relative path to the unnamed and system-clipboard registers.
function M.copy_rel_path()
  local rel = current_rel_path()
  if not rel then
    vim.notify('No file in the current buffer', vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('"', rel)
  vim.fn.setreg('+', rel)
  vim.notify('Copied: ' .. rel, vim.log.levels.INFO)
end

--- Run the unit test for the current file in a terminal split. A production file is
--- resolved to its test file; a test file is run directly.
function M.run_test_file()
  local rel, root = current_rel_path()
  if not rel then
    vim.notify('No file in the current buffer', vim.log.levels.WARN)
    return
  end
  if rel:match '%.py$' then
    local test_rel = py_test_for(rel)
    if not test_rel or vim.fn.filereadable(root .. '/' .. test_rel) ~= 1 then
      vim.notify('No pyunit test found for ' .. rel, vim.log.levels.WARN)
      return
    end
    run_in_terminal({ 'dev', 'test', 'pyunit', 'run', test_rel }, root)
  elseif rel:match '%.[jt]sx?$' then
    local tests = js_tests_for(rel, root)
    if #tests == 0 then
      vim.notify('No jsunit test found for ' .. rel, vim.log.levels.WARN)
      return
    end
    run_in_terminal(vim.list_extend({ 'dev', 'test', 'jsunit', 'run' }, tests), root)
  else
    vim.notify('Not a Python or frontend file: ' .. rel, vim.log.levels.WARN)
  end
end

--- Run the changed-file test suite (`dev test diff`) in a terminal split.
function M.run_test_diff()
  local root = vim.fs.root(0, { '.git' }) or vim.fn.getcwd()
  run_in_terminal({ 'dev', 'test', 'diff' }, root)
end

function M.setup()
  vim.api.nvim_create_user_command('CopyRelPath', M.copy_rel_path, { desc = 'Copy the current file repo-relative path' })
  vim.api.nvim_create_user_command('RunTestFile', M.run_test_file, { desc = 'Run the current file unit test via dev test' })
  vim.api.nvim_create_user_command('RunTestDiff', M.run_test_diff, { desc = 'Run dev test diff for changed files' })
  vim.keymap.set('n', '<leader>yp', M.copy_rel_path, { desc = '[Y]ank relative [P]ath' })
  vim.keymap.set('n', '<leader>rt', M.run_test_file, { desc = '[R]un [T]est file' })
  vim.keymap.set('n', '<leader>rd', M.run_test_diff, { desc = '[R]un test [D]iff' })
end

return M
-- vim: ts=2 sts=2 sw=2 et
