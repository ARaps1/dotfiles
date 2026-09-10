-- Summarize minuet autocomplete token usage and cost from the proxy's usage log
-- (~/.local/state/minuet-usage.jsonl, written by litellm_usage_logger.py), split into
-- today (per calendar day) and all-time, broken down by model.

local M = {}

local USAGE_FILE = vim.fn.expand '~/.local/state/minuet-usage.jsonl'

--- Epoch of local midnight today, the start of the per-calendar-day window.
--- @return integer
local function start_of_today()
  local t = os.date '*t'
  return os.time { year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
end

--- @return table
local function blank()
  return { models = {}, tin = 0, tout = 0, cost = 0 }
end

--- Fold one log entry into an accumulator, both in total and per model.
--- @param acc table
--- @param entry table
local function add(acc, entry)
  local tin = entry['in'] or 0
  local tout = entry.out or 0
  local cost = entry.cost or 0
  acc.tin = acc.tin + tin
  acc.tout = acc.tout + tout
  acc.cost = acc.cost + cost
  local model = acc.models[entry.model] or { tin = 0, tout = 0, cost = 0 }
  model.tin = model.tin + tin
  model.tout = model.tout + tout
  model.cost = model.cost + cost
  acc.models[entry.model] = model
end

--- Markdown lines for one window: a per-model line each, then a total.
--- @param title string
--- @param acc table
--- @return string[]
local function section(title, acc)
  local lines = { '## ' .. title }
  local names = vim.tbl_keys(acc.models)
  table.sort(names)
  for _, name in ipairs(names) do
    local model = acc.models[name]
    table.insert(lines, ('- %s — %d in / %d out · $%.4f'):format(name, model.tin, model.tout, model.cost))
  end
  table.insert(lines, ('**Total — %d in / %d out · $%.4f**'):format(acc.tin, acc.tout, acc.cost))
  return lines
end

--- Show today's and all-time usage in a floating window.
function M.show()
  local file = io.open(USAGE_FILE, 'r')
  if not file then
    vim.notify('minuet usage: nothing logged yet at ' .. USAGE_FILE, vim.log.levels.INFO)
    return
  end
  local midnight = start_of_today()
  local today, all = blank(), blank()
  for line in file:lines() do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == 'table' and entry.model then
      add(all, entry)
      if (entry.ts or 0) >= midnight then
        add(today, entry)
      end
    end
  end
  file:close()

  local out = { '# minuet autocomplete usage', '' }
  vim.list_extend(out, section('Today (' .. os.date '%Y-%m-%d' .. ')', today))
  table.insert(out, '')
  vim.list_extend(out, section('All-time', all))
  vim.lsp.util.open_floating_preview(out, 'markdown', { border = 'rounded', focusable = true })
end

return M
-- vim: ts=2 sts=2 sw=2 et
