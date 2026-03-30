-- IDE-style layout: Neo-tree | two editors + shell terminal below | full-height AI terminal.
-- Run :StudyLayout or set vim.g.study_layout_auto = true (or $NVIM_STUDY=1).
--
-- Optional: vim.g.study_cmd_term_height = number of lines for the bottom shell (default 12).
-- Optional: vim.g.study_panel_min_width = column width when side panels are "hidden" (default 3).
-- Optional: vim.g.study_expand_ratio = fraction of the middle pair for the focused editor (default 0.82).
-- Optional: vim.g.study_expand_min_other = minimum columns for the other editor (default 12).
-- :StudyTogglePanels — shrinks/restores Neo-tree (left) and the AI terminal (right) instead of closing them.

local M = {}

---@class StudyPanelState
---@field collapsed boolean
---@field tree_width integer?
---@field ai_width integer?
local panel_state = {
  collapsed = false,
  tree_width = nil,
  ai_width = nil,
}

--- Terminal buffers from a previous :StudyLayout (still listed after :only closed their windows).
---@return integer? ai_buf
---@return integer? shell_buf
local function find_study_terminal_buffers()
  local ai_buf, shell_buf = nil, nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' and vim.fn.bufwinnr(buf) == -1 then
      local ok_ai, is_ai = pcall(vim.api.nvim_buf_get_var, buf, 'study_ai_terminal')
      if ok_ai and is_ai then
        ai_buf = buf
      end
      local ok_sh, is_sh = pcall(vim.api.nvim_buf_get_var, buf, 'study_shell_terminal')
      if ok_sh and is_sh then
        shell_buf = buf
      end
    end
  end
  return ai_buf, shell_buf
end

local function find_neo_tree_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'neo-tree' then
      return win
    end
  end
  return nil
end

--- Prefer buffer marked at layout open; else the rightmost terminal (study layout: AI is full-height right).
local function find_ai_terminal_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].study_ai_terminal then
      return win
    end
  end
  local best_win, best_col = nil, -1
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == 'terminal' then
      local col = vim.fn.win_screenpos(win)[2]
      if col > best_col then
        best_col = col
        best_win = win
      end
    end
  end
  return best_win
end

local function find_shell_terminal_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].study_shell_terminal then
      return win
    end
  end
  return nil
end

--- Tag each StudyLayout pane so commands can resize by role (`study_window` win var).
local function label_study_window(win, role)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_var(win, 'study_window', role)
  end
end

--- Collapse or restore left (Neo-tree) and right (AI terminal) to minimal width vs saved sizes.
function M.toggle_side_panels()
  local min_w = vim.g.study_panel_min_width
  if type(min_w) ~= 'number' or min_w < 1 then
    min_w = 3
  end

  local tree_win = find_neo_tree_win()
  local ai_win = find_ai_terminal_win()

  if panel_state.collapsed then
    if tree_win and panel_state.tree_width and panel_state.tree_width >= min_w then
      vim.api.nvim_win_set_width(tree_win, panel_state.tree_width)
    end
    if ai_win and panel_state.ai_width and panel_state.ai_width >= min_w then
      vim.api.nvim_win_set_width(ai_win, panel_state.ai_width)
    end
    panel_state.collapsed = false
    panel_state.tree_width = nil
    panel_state.ai_width = nil
  else
    if tree_win then
      panel_state.tree_width = vim.api.nvim_win_get_width(tree_win)
      vim.api.nvim_win_set_width(tree_win, min_w)
    end
    if ai_win then
      panel_state.ai_width = vim.api.nvim_win_get_width(ai_win)
      vim.api.nvim_win_set_width(ai_win, min_w)
    end
    panel_state.collapsed = true
  end
end

---@param opts? { silent?: boolean }
function M.open(opts)
  opts = opts or {}
  local function notify(msg, level)
    if not opts.silent then
      vim.notify(msg, level or vim.log.levels.INFO)
    end
  end

  local book = vim.g.study_book_root
  if book and book ~= '' and vim.fn.isdirectory(vim.fn.expand(book)) == 0 then
    notify('vim.g.study_book_root is not a directory: ' .. book, vim.log.levels.WARN)
  end
  local work = vim.g.study_work_root
  if work and work ~= '' and vim.fn.isdirectory(vim.fn.expand(work)) == 0 then
    notify('vim.g.study_work_root is not a directory: ' .. work, vim.log.levels.WARN)
  end

  -- :only keeps the *current* window. If that window is a terminal, :vsplit duplicates
  -- it into both middle panes (then the new :terminal lands wrong). If Neo-tree is
  -- focused, :only leaves only the tree. Normalize before splitting.
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    if vim.bo.filetype == 'neo-tree' then
      vim.cmd 'wincmd l'
    end
    vim.cmd 'only'
  end
  do
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype == 'terminal' then
      vim.cmd 'enew'
    elseif vim.bo[buf].filetype == 'neo-tree' then
      vim.cmd 'wincmd l'
      buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype == 'neo-tree' then
        vim.cmd 'enew'
      end
    end
  end

  -- After :only, prior study terminals are hidden (bufwinnr -1) so we can reuse them.
  local reuse_ai_buf, reuse_shell_buf = find_study_terminal_buffers()

  -- [ Neo-tree | [ editors (top) / shell (bottom) ] | AI terminal (full height) ]
  vim.cmd 'Neotree filesystem position=left'
  vim.cmd 'wincmd l'
  vim.cmd 'vsplit'
  vim.cmd 'wincmd l'

  local term_cmd = vim.g.study_ai_cmd
  if reuse_ai_buf then
    vim.cmd('buffer ' .. reuse_ai_buf)
  elseif type(term_cmd) == 'string' and term_cmd ~= '' then
    vim.cmd({ 'terminal', unpack(vim.split(term_cmd, '%s+', { trimempty = true })) })
    vim.b.study_ai_terminal = true
  else
    vim.cmd 'terminal'
    vim.b.study_ai_terminal = true
  end

  vim.cmd 'wincmd h'
  -- splitbelow: new window is below and cursor moves there — vsplit must run on the *top*
  -- pane so we get two editors above and one full-width shell terminal below.
  vim.cmd 'split'
  vim.cmd 'wincmd k'
  vim.cmd 'vsplit'
  vim.cmd 'wincmd j'
  if reuse_shell_buf then
    vim.cmd('buffer ' .. reuse_shell_buf)
  else
    vim.cmd 'terminal'
    vim.b.study_shell_terminal = true
  end

  local cmd_h = vim.g.study_cmd_term_height
  if type(cmd_h) ~= 'number' or cmd_h < 1 then
    cmd_h = 12
  end
  vim.cmd('resize ' .. cmd_h)

  vim.cmd 'wincmd k'
  -- From the left middle editor, `wincmd h` lands in Neo-tree. Neovide often focuses
  -- that left editor after `wincmd k`, so we must not label the tree as editor_left.
  vim.cmd 'wincmd h'
  if vim.bo.filetype == 'neo-tree' then
    vim.cmd 'wincmd l'
  end

  label_study_window(find_neo_tree_win(), 'tree')
  label_study_window(find_ai_terminal_win(), 'ai')
  label_study_window(find_shell_terminal_win(), 'shell')
  local ed_left = vim.api.nvim_get_current_win()
  label_study_window(ed_left, 'editor_left')
  vim.cmd 'wincmd l'
  label_study_window(vim.api.nvim_get_current_win(), 'editor_right')

  notify('Study layout: Neo-tree | 2 editors + shell below | AI terminal')
end

---@return integer? w_left
---@return integer? w_right
local function find_middle_editors()
  local w_left, w_right
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ok, role = pcall(vim.api.nvim_win_get_var, win, 'study_window')
    if ok and role == 'editor_left' then
      w_left = win
    elseif ok and role == 'editor_right' then
      w_right = win
    end
  end
  if not w_left or not w_right or not vim.api.nvim_win_is_valid(w_left) or not vim.api.nvim_win_is_valid(w_right) then
    return nil, nil
  end
  return w_left, w_right
end

--- 50/50 width for the two middle editor splits (uses `study_window` labels from :StudyLayout).
function M.equalize_middle_editors()
  local w_left, w_right = find_middle_editors()
  if not w_left then
    vim.notify('Study layout: inner editors not labeled — run :StudyLayout first', vim.log.levels.WARN)
    return
  end
  local w1w = vim.api.nvim_win_get_width(w_left)
  local w2w = vim.api.nvim_win_get_width(w_right)
  local total = w1w + w2w + 1
  local half = math.floor(total / 2)
  vim.api.nvim_set_current_win(w_left)
  vim.api.nvim_win_set_width(w_left, half)
end

--- Give the focused middle editor most of the width between the pair (complement to equalize).
function M.expand_focused_middle_editor()
  local w_left, w_right = find_middle_editors()
  if not w_left then
    vim.notify('Study layout: inner editors not labeled — run :StudyLayout first', vim.log.levels.WARN)
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if cur ~= w_left and cur ~= w_right then
    vim.notify('Study layout: focus one of the two middle editors first', vim.log.levels.WARN)
    return
  end
  local w1w = vim.api.nvim_win_get_width(w_left)
  local w2w = vim.api.nvim_win_get_width(w_right)
  local total = w1w + w2w + 1
  local available = total - 1
  local min_other = vim.g.study_expand_min_other
  if type(min_other) ~= 'number' or min_other < 1 then
    min_other = 12
  end
  local ratio = vim.g.study_expand_ratio
  if type(ratio) ~= 'number' or ratio <= 0 or ratio >= 1 then
    ratio = 0.82
  end
  if available <= min_other then
    vim.notify('Study layout: middle area too narrow to expand', vim.log.levels.WARN)
    return
  end
  -- Prefer ~ratio of the pair for the focused editor, but never leave the other below min_other.
  local focus_w = math.min(math.floor(available * ratio), available - min_other)
  -- If ratio would starve the focused side, give it at least min_other columns when possible.
  focus_w = math.max(min_other, focus_w)
  focus_w = math.min(focus_w, available - min_other)
  if cur == w_left then
    vim.api.nvim_set_current_win(w_left)
    vim.api.nvim_win_set_width(w_left, focus_w)
  else
    vim.api.nvim_set_current_win(w_right)
    vim.api.nvim_win_set_width(w_right, focus_w)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('StudyLayout', function()
    M.open {}
  end, { desc = 'Neo-tree | 2 editors + shell | AI terminal' })

  vim.api.nvim_create_user_command('StudyTogglePanels', function()
    M.toggle_side_panels()
  end, { desc = 'Shrink/restore Neo-tree + AI terminal widths (non-destructive)' })

  vim.api.nvim_create_user_command('StudyEqualizeEditors', function()
    M.equalize_middle_editors()
  end, { desc = 'Equal width for the two middle editor splits' })

  vim.api.nvim_create_user_command('StudyExpandFocusedEditor', function()
    M.expand_focused_middle_editor()
  end, { desc = 'Widen focused middle editor (StudyLayout pair)' })

  vim.keymap.set('n', '<leader>sp', function()
    M.toggle_side_panels()
  end, { desc = '[S]ide [P]anels: shrink/restore tree + AI terminal' })

  vim.keymap.set('n', '<leader>se', function()
    M.equalize_middle_editors()
  end, { desc = '[S]tudy [E]qualize: 50/50 width for the two editor splits' })

  vim.keymap.set('n', '<leader>sm', function()
    M.expand_focused_middle_editor()
  end, { desc = '[S]tudy [M]aximize: widen focused middle editor vs the other split' })

  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      local auto = vim.g.study_layout_auto
      if auto == nil then
        auto = vim.env.NVIM_STUDY == '1'
      end
      if auto then
        vim.defer_fn(function()
          local ok, err = pcall(M.open, { silent = true })
          if not ok then
            vim.notify('StudyLayout: ' .. tostring(err), vim.log.levels.ERROR)
          end
        end, 120)
      end
    end,
  })

  vim.keymap.set('n', '<leader>sB', function()
    local root = vim.g.study_book_root
    if not root or root == '' or vim.fn.isdirectory(vim.fn.expand(root)) == 0 then
      vim.notify('Set vim.g.study_book_root to your book repo path', vim.log.levels.WARN)
      return
    end
    require('telescope.builtin').find_files {
      cwd = vim.fn.expand(root),
      prompt_title = 'Book files',
    }
  end, { desc = '[S]earch [B]ook root' })

  vim.keymap.set('n', '<leader>sW', function()
    local root = vim.g.study_work_root
    if not root or root == '' or vim.fn.isdirectory(vim.fn.expand(root)) == 0 then
      vim.notify('Set vim.g.study_work_root to your work repo path', vim.log.levels.WARN)
      return
    end
    require('telescope.builtin').find_files {
      cwd = vim.fn.expand(root),
      prompt_title = 'Work files',
    }
  end, { desc = '[S]earch [W]ork root' })
end

return M
