-- Display a GitHub pull request's review threads on the working-tree files they
-- annotate. Threads are anchored to their lines as inline virtual text (collapsible),
-- shown in full in a floating window (with the referenced diff hunk), and the lines a
-- thread references can be highlighted. Resolved threads can be hidden or shown, and
-- threads can be replied to or resolved. Backed by the `gh` CLI (GraphQL); the pull
-- request is resolved from the current buffer's checked-out branch.

local M = {}

-- Extmark namespaces: thread virtual text, referenced-range line highlights, and
-- sign-column markers.
local COMMENT_NS = vim.api.nvim_create_namespace 'pr_comments'
local DIFF_NS = vim.api.nvim_create_namespace 'pr_comments_diff'
local SIGN_NS = vim.api.nvim_create_namespace 'pr_comments_signs'

-- File where the enabled layers are persisted so they restore across sessions.
local STATE_FILE = vim.fn.stdpath 'state' .. '/pr_comments.json'

-- Whether the inline thread overlay is active.
M._enabled = false
-- Whether referenced ranges are highlighted.
M._diff_enabled = false
-- Whether sign-column markers are shown on commented lines.
M._signs_enabled = false
-- Whether resolved threads are shown (dimmed) rather than hidden.
M._show_resolved = false
-- Default collapsed state applied to every thread, flipped by collapse-all.
M._collapse_all = false

-- Per-branch cache keyed by "repo_root\0branch". A value is an entry table
-- { number = pr_number, files = { [path] = { [anchor_line] = thread[] } } } where a
-- `thread` is { id, resolved, outdated, anchor, start, diff_hunk, comments }, and a
-- comment is { login, name, body, created_at }; or `false` when the branch has no pull
-- request. Keying by branch ties the overlay to the checked-out branch.
local cache = {}

-- In-flight loads keyed like `cache`, holding the callbacks awaiting one fetch so that
-- concurrent requests for the same branch share a single set of `gh` calls.
local inflight = {}

-- Per-thread-line collapse overrides keyed by "path\0anchor_line" -> boolean. Overrides
-- take precedence over `M._collapse_all` until collapse-all is toggled again.
local collapse_override = {}

local REVIEW_THREADS_QUERY = [[
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line startLine originalLine originalStartLine
          comments(first:100){
            nodes{ body createdAt diffHunk author{ login ... on User { name } } }
          }
        }
      }
    }
  }
}]]

local RESOLVE_MUTATION = 'mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }'
local UNRESOLVE_MUTATION = 'mutation($id:ID!){ unresolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }'
local REPLY_MUTATION =
  'mutation($id:ID!,$body:String!){ addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){ comment { id } } }'

--- @param repo_root string
--- @param branch string
--- @return string
local function branch_key(repo_root, branch)
  return repo_root .. '\0' .. branch
end

--- @param name string
--- @return integer|nil
local function hl_bg(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return hl and hl.bg
end

--- @param name string
--- @return integer|nil
local function hl_fg(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return hl and hl.fg
end

--- Highlight groups for the overlay. Thread lines get a solid (non-transparent)
--- background drawn from the theme so they read as a distinct panel over the code;
--- resolved threads are dimmed, and the referenced-range highlight reuses Visual.
local function ensure_highlights()
  local bg = hl_bg 'CursorLine' or hl_bg 'Pmenu' or hl_bg 'Visual'
  vim.api.nvim_set_hl(0, 'PRCommentAuthor', { fg = hl_fg 'Function' or hl_fg 'Title', bg = bg, bold = true })
  vim.api.nvim_set_hl(0, 'PRCommentBody', { fg = hl_fg 'Normal', bg = bg })
  vim.api.nvim_set_hl(0, 'PRCommentMeta', { fg = hl_fg 'Comment', bg = bg })
  vim.api.nvim_set_hl(0, 'PRCommentResolved', { fg = hl_fg 'Comment', bg = bg, italic = true })
  vim.api.nvim_set_hl(0, 'PRCommentDiff', { link = 'Visual', default = true })
  vim.api.nvim_set_hl(0, 'PRCommentSign', { link = 'DiagnosticInfo', default = true })
end

--- Git root of a buffer, or nil when the buffer is not inside a repository.
--- @param bufnr integer
--- @return string|nil
local function repo_root_of(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  return vim.fs.root(name, { '.git' })
end

--- Path of a buffer relative to its repo root, matching GitHub thread `path`.
--- @param bufnr integer
--- @param repo_root string
--- @return string|nil
local function repo_relpath(bufnr, repo_root)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  return vim.fs.relpath(repo_root, name)
end

--- Build the cached entry from decoded GraphQL review-thread nodes. Threads without a
--- placeable line (null `line` and `originalLine`) are skipped.
--- @param number integer
--- @param nodes table[]
--- @return table
local function build_entry(number, nodes)
  local files = {}
  for _, node in ipairs(nodes) do
    local anchor = node.line or node.originalLine
    if node.path and anchor then
      local comments = {}
      local diff_hunk = ''
      for _, comment in ipairs(node.comments and node.comments.nodes or {}) do
        if diff_hunk == '' and comment.diffHunk then
          diff_hunk = comment.diffHunk
        end
        table.insert(comments, {
          login = comment.author and comment.author.login or '?',
          name = comment.author and comment.author.name or nil,
          body = comment.body or '',
          created_at = comment.createdAt or '',
        })
      end
      files[node.path] = files[node.path] or {}
      files[node.path][anchor] = files[node.path][anchor] or {}
      table.insert(files[node.path][anchor], {
        id = node.id,
        resolved = node.isResolved == true,
        outdated = node.isOutdated == true,
        anchor = anchor,
        start = node.startLine or node.originalStartLine or anchor,
        diff_hunk = diff_hunk,
        comments = comments,
      })
    end
  end
  return { number = number, files = files }
end

--- Total and unresolved thread counts across an entry.
--- @param entry table
--- @return integer total
--- @return integer unresolved
local function summarize(entry)
  local total, unresolved = 0, 0
  for _, by_line in pairs(entry.files) do
    for _, threads in pairs(by_line) do
      for _, thread in ipairs(threads) do
        total = total + 1
        if not thread.resolved then
          unresolved = unresolved + 1
        end
      end
    end
  end
  return total, unresolved
end

--- Resolve every callback waiting on `key` with `entry`, optionally caching the result.
--- @param key string
--- @param entry table|nil
--- @param do_cache boolean
local function settle(key, entry, do_cache)
  if do_cache then
    cache[key] = entry or false
  end
  local waiting = inflight[key] or {}
  inflight[key] = nil
  vim.schedule(function()
    for _, waiter in ipairs(waiting) do
      waiter(entry)
    end
  end)
end

--- Resolve the pull request for the repo's checked-out branch, fetch its review threads
--- via GraphQL, cache them by branch, then invoke `cb` with the entry (or nil when the
--- branch has no pull request or a lookup fails). Concurrent requests for the same branch
--- share one fetch. Runs `git` and `gh` asynchronously.
--- @param repo_root string
--- @param cb fun(entry: table|nil)
local function load(repo_root, cb)
  vim.system({ 'git', '-C', repo_root, 'rev-parse', '--abbrev-ref', 'HEAD' }, { text = true }, function(branch_result)
    local branch = vim.trim(branch_result.stdout or '')
    if branch_result.code ~= 0 or branch == '' then
      vim.schedule(function() cb(nil) end)
      return
    end
    local key = branch_key(repo_root, branch)
    if cache[key] ~= nil then
      local cached = cache[key]
      vim.schedule(function() cb(cached or nil) end)
      return
    end
    if inflight[key] then
      table.insert(inflight[key], cb)
      return
    end
    inflight[key] = { cb }
    vim.system({ 'gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner' }, { cwd = repo_root, text = true }, function(repo_result)
      local owner, name = (vim.trim(repo_result.stdout or '')):match '([^/]+)/(.+)'
      if repo_result.code ~= 0 or not owner then
        settle(key, nil, false)
        return
      end
      vim.system({ 'gh', 'pr', 'view', branch, '--json', 'number', '--jq', '.number' }, { cwd = repo_root, text = true }, function(pr_result)
        local number = vim.trim(pr_result.stdout or '')
        if pr_result.code ~= 0 or number == '' then
          settle(key, nil, true)
          return
        end
        vim.schedule(function() vim.notify('PR comments: loading…', vim.log.levels.INFO) end)
        local args = { 'gh', 'api', 'graphql', '-f', 'query=' .. REVIEW_THREADS_QUERY, '-f', 'owner=' .. owner, '-f', 'name=' .. name, '-F', 'number=' .. number }
        vim.system(args, { cwd = repo_root, text = true }, function(api_result)
          if api_result.code ~= 0 then
            settle(key, nil, false)
            return
          end
          local ok, decoded = pcall(vim.json.decode, api_result.stdout or '', { luanil = { object = true, array = true } })
          local pr = ok and decoded and decoded.data and decoded.data.repository and decoded.data.repository.pullRequest
          if not pr then
            settle(key, nil, false)
            return
          end
          local entry = build_entry(tonumber(number), pr.reviewThreads and pr.reviewThreads.nodes or {})
          local total, unresolved = summarize(entry)
          vim.schedule(function()
            vim.notify(('PR comments: %d threads, %d unresolved'):format(total, unresolved), vim.log.levels.INFO)
          end)
          settle(key, entry, true)
        end)
      end)
    end)
  end)
end

--- The anchor-line -> threads map for a buffer, or nil when it has no cached entry.
--- @param bufnr integer
--- @param entry table
--- @return table<integer, table[]>|nil
local function threads_for_buf(bufnr, entry)
  local repo_root = repo_root_of(bufnr)
  if not repo_root then
    return nil
  end
  local relpath = repo_relpath(bufnr, repo_root)
  if not relpath then
    return nil
  end
  return entry.files[relpath]
end

--- @param thread table
--- @return boolean
local function is_visible(thread)
  return M._show_resolved or not thread.resolved
end

--- Visible threads at an anchor, honoring resolved visibility.
--- @param threads table[]
--- @return table[]
local function visible_threads(threads)
  return vim.tbl_filter(is_visible, threads)
end

--- Label for the line range a group of threads references.
--- @param threads table[]
--- @param anchor integer
--- @return string
local function range_label(threads, anchor)
  local lo = anchor
  for _, thread in ipairs(threads) do
    if thread.start < lo then
      lo = thread.start
    end
  end
  if lo == anchor then
    return 'L' .. anchor
  end
  return 'L' .. lo .. '–L' .. anchor
end

--- @param count integer
--- @return string
local function comment_word(count)
  return count == 1 and 'comment' or 'comments'
end

--- @param comment table
--- @return string
local function author_label(comment)
  if comment.name then
    return comment.name .. ' (@' .. comment.login .. ')'
  end
  return '@' .. comment.login
end

--- @param path string
--- @param anchor integer
--- @return boolean
local function is_collapsed(path, anchor)
  local override = collapse_override[path .. '\0' .. anchor]
  if override ~= nil then
    return override
  end
  return M._collapse_all
end

-- Left indent inside the overlay panel, before the "▌" gutter bar.
local LEFT_PAD = ' '

--- Build one padded virtual line: a left pad, the text, and a trailing fill so the
--- panel background spans `width` columns.
--- @param text string
--- @param hl string
--- @param width integer
--- @return table[]
local function panel_line(text, hl, width)
  local content = LEFT_PAD .. text
  local fill = width - vim.fn.strdisplaywidth(content)
  if fill <= 0 then
    return { { content, hl } }
  end
  return { { content .. string.rep(' ', fill), hl } }
end

--- Hard-split a token into pieces each within `limit` display columns, for words that
--- are themselves wider than the wrap limit.
--- @param token string
--- @param limit integer
--- @return string[]
local function split_token(token, limit)
  local pieces = {}
  local current = ''
  local current_width = 0
  for index = 0, vim.fn.strchars(token) - 1 do
    local char = vim.fn.strcharpart(token, index, 1)
    local char_width = vim.fn.strdisplaywidth(char)
    if current ~= '' and current_width + char_width > limit then
      table.insert(pieces, current)
      current = ''
      current_width = 0
    end
    current = current .. char
    current_width = current_width + char_width
  end
  if current ~= '' then
    table.insert(pieces, current)
  end
  return pieces
end

--- Word-wrap `text` into segments no wider than `limit` display columns, breaking on
--- spaces where possible and hard-splitting over-long words.
--- @param text string
--- @param limit integer
--- @return string[]
local function wrap(text, limit)
  if limit < 1 then
    limit = 1
  end
  local segments = {}
  local line = ''
  for _, word in ipairs(vim.split(text, ' ', { plain = true })) do
    if vim.fn.strdisplaywidth(word) > limit then
      if line ~= '' then
        table.insert(segments, line)
        line = ''
      end
      local pieces = split_token(word, limit)
      for index = 1, #pieces - 1 do
        table.insert(segments, pieces[index])
      end
      line = pieces[#pieces] or ''
    else
      local candidate = line == '' and word or (line .. ' ' .. word)
      if vim.fn.strdisplaywidth(candidate) <= limit then
        line = candidate
      else
        table.insert(segments, line)
        line = word
      end
    end
  end
  table.insert(segments, line)
  return segments
end

--- Append `text` to `out` as wrapped, padded panel lines. The first segment uses
--- `first_prefix`; wrapped continuations use `cont_prefix` so they align under it.
--- @param out table[][]
--- @param first_prefix string
--- @param cont_prefix string
--- @param text string
--- @param hl string
--- @param width integer
local function emit_wrapped(out, first_prefix, cont_prefix, text, hl, width)
  local reserved = vim.fn.strdisplaywidth(LEFT_PAD) + math.max(vim.fn.strdisplaywidth(first_prefix), vim.fn.strdisplaywidth(cont_prefix))
  for index, segment in ipairs(wrap(text, width - reserved)) do
    local prefix = index == 1 and first_prefix or cont_prefix
    table.insert(out, panel_line(prefix .. segment, hl, width))
  end
end

--- Virtual lines (extmark `virt_lines` chunks) for the visible threads on one line,
--- word-wrapped and padded to `width` so the panel spans the pane without overflow.
--- @param threads table[]
--- @param anchor integer
--- @param collapsed boolean
--- @param width integer
--- @return table[][]
local function build_virt_lines(threads, anchor, collapsed, width)
  local total = 0
  local any_resolved = false
  local any_outdated = false
  for _, thread in ipairs(threads) do
    total = total + #thread.comments
    any_resolved = any_resolved or thread.resolved
    any_outdated = any_outdated or thread.outdated
  end
  local summary = ('%s · %d %s'):format(range_label(threads, anchor), total, comment_word(total))
  if any_resolved then
    summary = summary .. ' ✓'
  end
  if any_outdated then
    summary = summary .. ' ⚠ outdated'
  end
  local virt_lines = {}
  if collapsed then
    emit_wrapped(virt_lines, '▌ ▸ ', '▌   ', summary .. ' · ' .. author_label(threads[1].comments[1]), 'PRCommentMeta', width)
    return virt_lines
  end
  emit_wrapped(virt_lines, '▌ ▾ ', '▌   ', summary, 'PRCommentMeta', width)
  for _, thread in ipairs(threads) do
    local author_hl = thread.resolved and 'PRCommentResolved' or 'PRCommentAuthor'
    local body_hl = thread.resolved and 'PRCommentResolved' or 'PRCommentBody'
    for _, comment in ipairs(thread.comments) do
      emit_wrapped(virt_lines, '▌ ', '▌   ', author_label(comment), author_hl, width)
      for _, body_line in ipairs(vim.split(comment.body, '\n', { plain = true })) do
        emit_wrapped(virt_lines, '▌   ', '▌   ', body_line, body_hl, width)
      end
    end
  end
  return virt_lines
end

--- Text-area width (excluding the sign/number/fold gutter) of a window showing the
--- buffer, falling back to the editor width when the buffer is not currently visible.
--- @param bufnr integer
--- @return integer
local function buf_text_width(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then
      return info.width - info.textoff
    end
  end
  return vim.o.columns
end

--- Render the inline thread overlay for one buffer.
--- @param bufnr integer
--- @param by_line table<integer, table[]>
local function render_comments(bufnr, by_line)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local width = buf_text_width(bufnr)
  for anchor, threads in pairs(by_line) do
    local shown = visible_threads(threads)
    if #shown > 0 and anchor >= 1 and anchor <= last_line then
      vim.api.nvim_buf_set_extmark(bufnr, COMMENT_NS, anchor - 1, 0, {
        virt_lines = build_virt_lines(shown, anchor, is_collapsed(path, anchor), width),
      })
    end
  end
end

--- Highlight every line each visible thread references.
--- @param bufnr integer
--- @param by_line table<integer, table[]>
local function render_diff(bufnr, by_line)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  for anchor, threads in pairs(by_line) do
    for _, thread in ipairs(visible_threads(threads)) do
      for line = thread.start, anchor do
        if line >= 1 and line <= last_line then
          vim.api.nvim_buf_set_extmark(bufnr, DIFF_NS, line - 1, 0, {
            line_hl_group = 'PRCommentDiff',
          })
        end
      end
    end
  end
end

--- Place a sign-column marker on each line with visible threads, showing the comment
--- count (capped at "9+").
--- @param bufnr integer
--- @param by_line table<integer, table[]>
local function render_signs(bufnr, by_line)
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  for anchor, threads in pairs(by_line) do
    local shown = visible_threads(threads)
    if #shown > 0 and anchor >= 1 and anchor <= last_line then
      local total = 0
      for _, thread in ipairs(shown) do
        total = total + #thread.comments
      end
      vim.api.nvim_buf_set_extmark(bufnr, SIGN_NS, anchor - 1, 0, {
        sign_text = total < 10 and tostring(total) or '9+',
        sign_hl_group = 'PRCommentSign',
      })
    end
  end
end

--- Clear all namespaces and re-render whichever layers are enabled for a buffer.
--- @param bufnr integer
--- @param entry table
local function apply_buf(bufnr, entry)
  vim.api.nvim_buf_clear_namespace(bufnr, COMMENT_NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, DIFF_NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, SIGN_NS, 0, -1)
  local by_line = threads_for_buf(bufnr, entry)
  if not by_line then
    return
  end
  if M._enabled then
    render_comments(bufnr, by_line)
  end
  if M._diff_enabled then
    render_diff(bufnr, by_line)
  end
  if M._signs_enabled then
    render_signs(bufnr, by_line)
  end
end

--- Load threads for a buffer's repo and apply the enabled layers.
--- @param bufnr integer
local function refresh_buf(bufnr)
  local repo_root = repo_root_of(bufnr)
  if not repo_root then
    return
  end
  load(repo_root, function(entry)
    if entry and vim.api.nvim_buf_is_valid(bufnr) then
      apply_buf(bufnr, entry)
    end
  end)
end

--- Clear all namespaces from every loaded buffer.
local function clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, COMMENT_NS, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, DIFF_NS, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, SIGN_NS, 0, -1)
    end
  end
end

--- Re-render every buffer currently shown in a window.
local function rerender_visible()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] then
      seen[bufnr] = true
      refresh_buf(bufnr)
    end
  end
end

--- Whether any overlay layer (comments, diff highlight, signs) is active.
--- @return boolean
local function any_layer_active()
  return M._enabled or M._diff_enabled or M._signs_enabled
end

--- Re-render when any layer is active, otherwise clear everything.
local function reconcile()
  if any_layer_active() then
    rerender_visible()
  else
    clear_all()
  end
end

--- Persist the enabled layers so they restore in the next session.
local function save_state()
  local state = {
    enabled = M._enabled,
    diff = M._diff_enabled,
    signs = M._signs_enabled,
    show_resolved = M._show_resolved,
    collapse_all = M._collapse_all,
  }
  local ok, encoded = pcall(vim.json.encode, state)
  if not ok then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ':h'), 'p')
  local file = io.open(STATE_FILE, 'w')
  if not file then
    return
  end
  file:write(encoded)
  file:close()
end

--- Load the persisted layer state into the module flags.
local function restore_state()
  local file = io.open(STATE_FILE, 'r')
  if not file then
    return
  end
  local content = file:read '*a'
  file:close()
  local ok, state = pcall(vim.json.decode, content or '')
  if not ok or type(state) ~= 'table' then
    return
  end
  M._enabled = state.enabled == true
  M._diff_enabled = state.diff == true
  M._signs_enabled = state.signs == true
  M._show_resolved = state.show_resolved == true
  M._collapse_all = state.collapse_all == true
end

--- Load the current buffer's entry and invoke `cb` with the first thread on the cursor
--- line (and that line), or notify and skip when there is none.
--- @param cb fun(bufnr: integer, entry: table, thread: table, anchor: integer)
local function with_thread_at_cursor(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local repo_root = repo_root_of(bufnr)
  if not repo_root then
    return
  end
  local anchor = vim.fn.line '.'
  load(repo_root, function(entry)
    if not entry then
      vim.notify('PR comments: no pull request for this branch', vim.log.levels.WARN)
      return
    end
    local by_line = threads_for_buf(bufnr, entry)
    local thread = by_line and by_line[anchor] and by_line[anchor][1]
    if not thread then
      vim.notify('PR comments: none on this line', vim.log.levels.INFO)
      return
    end
    cb(bufnr, entry, thread, anchor)
  end)
end

--- Toggle the inline thread overlay for the session.
function M.toggle()
  M._enabled = not M._enabled
  ensure_highlights()
  reconcile()
  save_state()
  vim.notify('PR comments: ' .. (M._enabled and 'on' or 'off'), vim.log.levels.INFO)
end

--- Turn on the full experience: inline overlay, referenced-range highlight, gutter
--- signs, expanded threads, and resolved threads hidden.
function M.enable()
  M._enabled = true
  M._diff_enabled = true
  M._signs_enabled = true
  M._show_resolved = false
  M._collapse_all = false
  ensure_highlights()
  reconcile()
  save_state()
  vim.notify('PR comments: enabled', vim.log.levels.INFO)
end

--- Turn off every layer.
function M.disable()
  M._enabled = false
  M._diff_enabled = false
  M._signs_enabled = false
  reconcile()
  save_state()
  vim.notify('PR comments: disabled', vim.log.levels.INFO)
end

--- Enable the full experience when nothing is active, otherwise turn everything off.
function M.toggle_all()
  if any_layer_active() then
    M.disable()
  else
    M.enable()
  end
end

--- Toggle highlighting of the lines each thread references.
function M.diff()
  M._diff_enabled = not M._diff_enabled
  ensure_highlights()
  reconcile()
  save_state()
  vim.notify('PR comment highlight: ' .. (M._diff_enabled and 'on' or 'off'), vim.log.levels.INFO)
end

--- Toggle whether resolved threads are shown (dimmed) or hidden.
function M.toggle_resolved()
  M._show_resolved = not M._show_resolved
  reconcile()
  save_state()
  vim.notify('PR resolved threads: ' .. (M._show_resolved and 'shown' or 'hidden'), vim.log.levels.INFO)
end

--- Collapse or expand the thread on the line under the cursor.
function M.collapse()
  with_thread_at_cursor(function(bufnr, entry, _, anchor)
    local path = vim.api.nvim_buf_get_name(bufnr)
    collapse_override[path .. '\0' .. anchor] = not is_collapsed(path, anchor)
    apply_buf(bufnr, entry)
  end)
end

--- Collapse or expand every thread, clearing per-line overrides.
function M.collapse_all()
  M._collapse_all = not M._collapse_all
  collapse_override = {}
  reconcile()
  save_state()
end

--- Toggle sign-column markers on commented lines.
function M.toggle_signs()
  M._signs_enabled = not M._signs_enabled
  ensure_highlights()
  reconcile()
  save_state()
  vim.notify('PR comment signs: ' .. (M._signs_enabled and 'on' or 'off'), vim.log.levels.INFO)
end

--- Re-fetch threads from GitHub, discarding the cache, and re-render if a layer is active.
function M.refresh()
  cache = {}
  if any_layer_active() then
    rerender_visible()
  end
end

--- Move the cursor to the next (`step` = 1) or previous (`step` = -1) commented line in
--- the current buffer, wrapping around. Only visible threads on existing lines count.
--- @param step integer
local function goto_comment(step)
  local bufnr = vim.api.nvim_get_current_buf()
  local repo_root = repo_root_of(bufnr)
  if not repo_root then
    return
  end
  load(repo_root, function(entry)
    local by_line = entry and threads_for_buf(bufnr, entry)
    local last_line = by_line and vim.api.nvim_buf_line_count(bufnr) or 0
    local anchors = {}
    for anchor, threads in pairs(by_line or {}) do
      if anchor >= 1 and anchor <= last_line and #visible_threads(threads) > 0 then
        table.insert(anchors, anchor)
      end
    end
    if #anchors == 0 then
      vim.notify('PR comments: none in this file', vim.log.levels.INFO)
      return
    end
    table.sort(anchors)
    local current = vim.fn.line '.'
    local target
    if step > 0 then
      for _, anchor in ipairs(anchors) do
        if anchor > current then
          target = anchor
          break
        end
      end
      target = target or anchors[1]
    else
      for index = #anchors, 1, -1 do
        if anchors[index] < current then
          target = anchors[index]
          break
        end
      end
      target = target or anchors[#anchors]
    end
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  end)
end

--- Jump to the next commented line in the current buffer.
function M.next()
  goto_comment(1)
end

--- Jump to the previous commented line in the current buffer.
function M.prev()
  goto_comment(-1)
end

--- Show the full thread for the line under the cursor in a floating window, including
--- the diff hunk the thread was left on.
function M.float()
  with_thread_at_cursor(function(bufnr, entry, _, anchor)
    local threads = threads_for_buf(bufnr, entry)[anchor]
    local markdown = {}
    for thread_index, thread in ipairs(threads) do
      if thread_index > 1 then
        table.insert(markdown, '---')
      end
      local status = range_label(threads, anchor)
      if thread.resolved then
        status = status .. ' · ✓ resolved'
      end
      if thread.outdated then
        status = status .. ' · ⚠ outdated'
      end
      table.insert(markdown, '_' .. status .. '_')
      if thread.diff_hunk ~= '' then
        table.insert(markdown, '```diff')
        vim.list_extend(markdown, vim.split(thread.diff_hunk, '\n', { plain = true }))
        table.insert(markdown, '```')
      end
      for _, comment in ipairs(thread.comments) do
        table.insert(markdown, '')
        local heading = '### ' .. author_label(comment)
        if comment.created_at ~= '' then
          heading = heading .. ' · ' .. comment.created_at:gsub('T', ' '):gsub('Z', ' UTC')
        end
        table.insert(markdown, heading)
        vim.list_extend(markdown, vim.split(comment.body, '\n', { plain = true }))
      end
    end
    vim.lsp.util.open_floating_preview(markdown, 'markdown', { border = 'rounded', focusable = true })
  end)
end

--- Copy the body text of the thread on the line under the cursor to the unnamed and
--- system-clipboard registers. Multiple comments are joined with a blank line.
function M.yank()
  with_thread_at_cursor(function(_, _, thread)
    local bodies = {}
    for _, comment in ipairs(thread.comments) do
      table.insert(bodies, comment.body)
    end
    local text = table.concat(bodies, '\n\n')
    vim.fn.setreg('"', text)
    vim.fn.setreg('+', text)
    vim.notify('PR comment yanked', vim.log.levels.INFO)
  end)
end

--- Run a GraphQL mutation for a thread and invoke `cb(ok)` on the main loop.
--- @param query string
--- @param thread_id string
--- @param cb fun(ok: boolean)
local function run_mutation(query, thread_id, cb)
  local args = { 'gh', 'api', 'graphql', '-f', 'query=' .. query, '-f', 'id=' .. thread_id }
  vim.system(args, { text = true }, function(result)
    vim.schedule(function() cb(result.code == 0) end)
  end)
end

--- Resolve or unresolve the thread on the line under the cursor, after confirmation.
function M.resolve()
  with_thread_at_cursor(function(_, _, thread)
    local resolving = not thread.resolved
    local prompt = (resolving and 'Resolve' or 'Unresolve') .. ' this thread?'
    if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then
      return
    end
    run_mutation(resolving and RESOLVE_MUTATION or UNRESOLVE_MUTATION, thread.id, function(ok)
      if ok then
        vim.notify('PR thread ' .. (resolving and 'resolved' or 'unresolved'), vim.log.levels.INFO)
        M.refresh()
      else
        vim.notify('PR comments: failed to update thread', vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Post a reply to a thread via GraphQL, then refresh on success.
--- @param thread_id string
--- @param body string
local function post_reply(thread_id, body)
  local payload = vim.json.encode {
    query = REPLY_MUTATION,
    variables = { id = thread_id, body = body },
  }
  local tmp = vim.fn.tempname()
  local file = io.open(tmp, 'w')
  if not file then
    return
  end
  file:write(payload)
  file:close()
  vim.system({ 'gh', 'api', 'graphql', '--input', tmp }, { text = true }, function(result)
    os.remove(tmp)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify('PR reply posted', vim.log.levels.INFO)
        M.refresh()
      else
        vim.notify('PR comments: failed to post reply', vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Number of screen rows the overlay occupies below a line, or 0 when absent.
--- @param bufnr integer
--- @param anchor integer
--- @return integer
local function overlay_height(bufnr, anchor)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, COMMENT_NS, { anchor - 1, 0 }, { anchor - 1, -1 }, { details = true })
  local detail = marks[1] and marks[1][4]
  return detail and detail.virt_lines and #detail.virt_lines or 0
end

--- Open an editable reply box floating just below the overlay for `anchor`, posting the
--- typed body on submit. `<CR>` in normal mode sends; `q` or `<Esc>` cancels.
--- @param win integer
--- @param anchor integer
--- @param thread table
local function open_reply_box(win, anchor, thread)
  local code_buf = vim.api.nvim_win_get_buf(win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  local box = vim.api.nvim_open_win(buf, true, {
    relative = 'win',
    win = win,
    bufpos = { anchor - 1, 0 },
    row = overlay_height(code_buf, anchor) + 1,
    col = 0,
    width = math.max(buf_text_width(code_buf), 20),
    height = 3,
    style = 'minimal',
    border = 'rounded',
    title = ' Reply (⏎ send · q cancel) ',
    title_pos = 'left',
  })
  vim.wo[box].wrap = true
  vim.wo[box].linebreak = true
  vim.cmd 'startinsert'

  -- Grow the box to fit wrapped input (bounded) so typed text never overflows it.
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(box) then
        return
      end
      local box_width = math.max(vim.api.nvim_win_get_width(box), 1)
      local rows = 0
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / box_width))
      end
      vim.api.nvim_win_set_height(box, math.max(3, math.min(rows, 12)))
    end,
  })

  local function close()
    if vim.api.nvim_win_is_valid(box) then
      vim.api.nvim_win_close(box, true)
    end
  end
  local function submit()
    local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    close()
    if body ~= '' then
      post_reply(thread.id, body)
    end
  end
  vim.keymap.set('n', '<CR>', submit, { buffer = buf, nowait = true })
  vim.keymap.set({ 'n', 'i' }, '<C-s>', submit, { buffer = buf })
  vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, nowait = true })
end

--- Reply to the thread on the line under the cursor in a box below the overlay.
function M.reply()
  local win = vim.api.nvim_get_current_win()
  with_thread_at_cursor(function(_, _, thread, anchor)
    open_reply_box(win, anchor, thread)
  end)
end

--- Preview text for a thread: the original diff hunk the comment was left on (stable
--- even when the working file has since drifted), followed by the thread's comments.
--- @param thread table
--- @return string[]
local function thread_preview_lines(thread)
  local lines = {}
  if thread.diff_hunk ~= '' then
    vim.list_extend(lines, vim.split(thread.diff_hunk, '\n', { plain = true }))
  else
    table.insert(lines, '(no diff context)')
  end
  for _, comment in ipairs(thread.comments) do
    table.insert(lines, '')
    table.insert(lines, '@' .. comment.login .. ':')
    vim.list_extend(lines, vim.split(comment.body, '\n', { plain = true }))
  end
  return lines
end

--- List every review thread in the pull request in a Telescope picker. The preview shows
--- the original diff hunk (stable against file drift); selecting opens the working file at
--- the comment's best-guess current line.
function M.list()
  if not pcall(require, 'telescope') then
    vim.notify('PR comments: telescope.nvim is required for the picker', vim.log.levels.ERROR)
    return
  end
  local repo_root = repo_root_of(vim.api.nvim_get_current_buf())
  if not repo_root then
    return
  end
  load(repo_root, function(entry)
    if not entry then
      vim.notify('PR comments: no pull request for this branch', vim.log.levels.WARN)
      return
    end
    local results = {}
    for path, by_line in pairs(entry.files) do
      for anchor, threads in pairs(by_line) do
        for _, thread in ipairs(threads) do
          table.insert(results, { path = path, line = anchor, thread = thread })
        end
      end
    end
    if #results == 0 then
      vim.notify('PR comments: none in this pull request', vim.log.levels.INFO)
      return
    end
    table.sort(results, function(a, b)
      if a.path == b.path then
        return a.line < b.line
      end
      return a.path < b.path
    end)

    local pickers = require 'telescope.pickers'
    local finders = require 'telescope.finders'
    local conf = require('telescope.config').values
    local previewers = require 'telescope.previewers'
    local actions = require 'telescope.actions'
    local action_state = require 'telescope.actions.state'

    pickers
      .new({}, {
        prompt_title = 'PR Comments',
        finder = finders.new_table {
          results = results,
          entry_maker = function(item)
            local thread = item.thread
            local marker = thread.resolved and '✓' or '○'
            if thread.outdated then
              marker = marker .. '⚠'
            end
            local first = vim.split(thread.comments[1].body, '\n', { plain = true })[1] or ''
            return {
              value = item,
              display = ('%s %s:%d  @%s  %s'):format(marker, item.path, item.line, thread.comments[1].login, first),
              ordinal = item.path .. ' ' .. first,
              filename = repo_root .. '/' .. item.path,
              lnum = item.line,
            }
          end,
        },
        sorter = conf.generic_sorter {},
        previewer = previewers.new_buffer_previewer {
          title = 'Comment on original diff',
          define_preview = function(self, entry)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, thread_preview_lines(entry.value.thread))
            vim.bo[self.state.bufnr].filetype = 'diff'
          end,
        },
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection then
              vim.cmd('edit ' .. vim.fn.fnameescape(selection.filename))
              vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
            end
          end)
          return true
        end,
      })
      :find()
  end)
end

--- @class PRCommentsOpts
--- @field auto_refresh? boolean Re-fetch threads when Neovim regains focus while a layer is active. Defaults to true.

--- @param opts? PRCommentsOpts
function M.setup(opts)
  opts = opts or {}
  local auto_refresh = opts.auto_refresh ~= false

  restore_state()
  if any_layer_active() then
    ensure_highlights()
  end

  local actions = {
    enable = M.enable,
    disable = M.disable,
    toggle = M.toggle,
    diff = M.diff,
    signs = M.toggle_signs,
    resolved = M.toggle_resolved,
    collapse = M.collapse,
    collapse_all = M.collapse_all,
    next = M.next,
    prev = M.prev,
    list = M.list,
    float = M.float,
    yank = M.yank,
    reply = M.reply,
    resolve = M.resolve,
    refresh = M.refresh,
  }
  vim.api.nvim_create_user_command('PRComments', function(command)
    local action = actions[command.args]
    if action then
      action()
    else
      vim.notify('PRComments: expected ' .. table.concat(vim.tbl_keys(actions), ' | '), vim.log.levels.ERROR)
    end
  end, {
    nargs = 1,
    complete = function() return vim.tbl_keys(actions) end,
  })

  local group = vim.api.nvim_create_augroup('pr-comments', { clear = true })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = ensure_highlights,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(event)
      if any_layer_active() then
        refresh_buf(event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      if M._enabled then
        rerender_visible()
      end
    end,
  })

  if auto_refresh then
    vim.api.nvim_create_autocmd('FocusGained', {
      group = group,
      callback = function()
        if any_layer_active() then
          M.refresh()
        end
      end,
    })
  end

  -- Render restored layers once the startup file is displayed. When setup runs after
  -- startup, render immediately instead.
  if any_layer_active() then
    if vim.v.vim_did_enter == 1 then
      vim.schedule(rerender_visible)
    else
      vim.api.nvim_create_autocmd('VimEnter', {
        group = group,
        once = true,
        callback = rerender_visible,
      })
    end
  end

  vim.keymap.set('n', '<leader>ce', M.toggle_all, { desc = 'PR comments: [E]nable/disable all' })
  vim.keymap.set('n', '<leader>ct', M.toggle, { desc = 'PR comments: [T]oggle inline overlay' })
  vim.keymap.set('n', '<leader>cd', M.diff, { desc = 'PR comments: toggle [D]iff highlight' })
  vim.keymap.set('n', '<leader>cs', M.toggle_signs, { desc = 'PR comments: toggle gutter [S]igns' })
  vim.keymap.set('n', '<leader>cl', M.list, { desc = 'PR comments: [L]ist all in picker' })
  vim.keymap.set('n', '<leader>cv', M.toggle_resolved, { desc = 'PR comments: toggle resolved [V]isibility' })
  vim.keymap.set('n', '<leader>cc', M.collapse, { desc = 'PR comments: [C]ollapse/expand this line' })
  vim.keymap.set('n', '<leader>cC', M.collapse_all, { desc = 'PR comments: [C]ollapse/expand all' })
  vim.keymap.set('n', '<leader>cn', M.next, { desc = 'PR comments: [N]ext comment in file' })
  vim.keymap.set('n', '<leader>cp', M.prev, { desc = 'PR comments: [P]revious comment in file' })
  vim.keymap.set('n', '<leader>cf', M.float, { desc = 'PR comments: [F]loat thread on line' })
  vim.keymap.set('n', '<leader>cy', M.yank, { desc = 'PR comments: [Y]ank comment text' })
  vim.keymap.set('n', '<leader>cR', M.reply, { desc = 'PR comments: [R]eply to thread' })
  vim.keymap.set('n', '<leader>cx', M.resolve, { desc = 'PR comments: resolve/unresolve thread' })
  vim.keymap.set('n', '<leader>cr', M.refresh, { desc = 'PR comments: [R]efresh from GitHub' })
end

return M
-- vim: ts=2 sts=2 sw=2 et
