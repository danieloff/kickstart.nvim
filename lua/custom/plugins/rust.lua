-- Rust: rustaceanvim (rust-analyzer from PATH via rustup), nvim-dap + UI.
-- Debugging: install a debug adapter on your PATH, e.g. `brew install codelldb`
-- (rustaceanvim prefers `codelldb`, then lldb-dap / lldb-vscode).

---@module 'lazy'
---@type LazySpec
return {
  {
    'mfussenegger/nvim-dap',
    lazy = false,
    dependencies = {
      'nvim-neotest/nvim-nio',
      'rcarriga/nvim-dap-ui',
    },
    config = function()
      local dap = require 'dap'
      local dapui = require 'dapui'
      dapui.setup()
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end,
    keys = {
      {
        '<leader>db',
        function() require('dap').toggle_breakpoint() end,
        desc = 'Dap: toggle [b]reakpoint',
      },
      {
        '<leader>dB',
        function() require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ') end,
        desc = 'Dap: conditional [B]reakpoint',
      },
      {
        '<leader>dc',
        function() require('dap').continue() end,
        desc = 'Dap: [c]ontinue / start',
      },
      {
        '<leader>di',
        function() require('dap').step_into() end,
        desc = 'Dap: step [i]nto',
      },
      {
        '<leader>do',
        function() require('dap').step_over() end,
        desc = 'Dap: step [o]ver',
      },
      {
        '<leader>dO',
        function() require('dap').step_out() end,
        desc = 'Dap: step [O]ut',
      },
      {
        '<leader>dr',
        function() require('dap').repl.toggle() end,
        desc = 'Dap: toggle [r]EPL',
      },
      {
        '<leader>du',
        function() require('dapui').toggle() end,
        desc = 'Dap: toggle [u]I',
      },
    },
  },

  {
    'mrcjkb/rustaceanvim',
    version = '^8',
    lazy = false,
    dependencies = { 'mfussenegger/nvim-dap', 'saghen/blink.cmp' },
    init = function()
      -- rust-analyzer default cmd uses vim.fn.exepath('rust-analyzer') — your rustup shim on PATH.
      vim.g.rustaceanvim = function()
        local ra_caps = require('rustaceanvim.config.server').create_client_capabilities()
        return {
          server = {
            capabilities = require('blink.cmp').get_lsp_capabilities(ra_caps),
            default_settings = {
              ['rust-analyzer'] = {
                checkOnSave = true,
                -- Do not set cargo.allFeatures = true: that is `--all-features` and enables optional
                -- features like `simd` that need nightly. Default is Cargo.toml default features only.
                procMacro = { enable = true },
              },
            },
            on_attach = function(_, bufnr)
              vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, desc = 'LSP: [G]oto [D]efinition' })
              vim.keymap.set('n', 'K', function() vim.cmd.RustLsp { 'hover', 'actions' } end, { buffer = bufnr, desc = 'Rust: hover actions' })
            end,
          },
        }
      end
    end,
  },
}
