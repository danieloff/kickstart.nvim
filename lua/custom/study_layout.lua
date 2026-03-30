-- IDE-style layout: Neo-tree | two editors + shell terminal below | full-height AI terminal.
-- Run :StudyLayout or set vim.g.study_layout_auto = true (or $NVIM_STUDY=1).
--
-- Optional: vim.g.study_cmd_term_height = number of lines for the bottom shell (default 12).
-- Optional: vim.g.study_panel_min_width = column width when side panels are "hidden" (default 3).
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
  vim.cmd 'wincmd h'

  notify('Study layout: Neo-tree | 2 editors + shell below | AI terminal')
end

function M.setup()
  vim.api.nvim_create_user_command('StudyLayout', function()
    M.open {}
  end, { desc = 'Neo-tree | 2 editors + shell | AI terminal' })

  vim.api.nvim_create_user_command('StudyTogglePanels', function()
    M.toggle_side_panels()
  end, { desc = 'Shrink/restore Neo-tree + AI terminal widths (non-destructive)' })

  vim.keymap.set('n', '<leader>sp', function()
    M.toggle_side_panels()
  end, { desc = '[S]ide [P]anels: shrink/restore tree + AI terminal' })

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
