-- IDE-style layout: Neo-tree | two editors + shell terminal below | full-height AI terminal.
-- Run :StudyLayout or set vim.g.study_layout_auto = true (or $NVIM_STUDY=1).
--
-- Optional: vim.g.study_cmd_term_height = number of lines for the bottom shell (default 12).

local M = {}

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

  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.cmd 'only'
  end

  -- [ Neo-tree | [ editors (top) / shell (bottom) ] | AI terminal (full height) ]
  vim.cmd 'Neotree filesystem position=left'
  vim.cmd 'wincmd l'
  vim.cmd 'vsplit'
  vim.cmd 'wincmd l'

  local term_cmd = vim.g.study_ai_cmd
  if type(term_cmd) == 'string' and term_cmd ~= '' then
    vim.cmd({ 'terminal', unpack(vim.split(term_cmd, '%s+', { trimempty = true })) })
  else
    vim.cmd 'terminal'
  end

  vim.cmd 'wincmd h'
  -- splitbelow: new window is below and cursor moves there — vsplit must run on the *top*
  -- pane so we get two editors above and one full-width shell terminal below.
  vim.cmd 'split'
  vim.cmd 'wincmd k'
  vim.cmd 'vsplit'
  vim.cmd 'wincmd j'
  vim.cmd 'terminal'

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
