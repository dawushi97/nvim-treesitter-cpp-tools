vim.cmd [[set runtimepath+=.]]
-- vim.cmd [[set runtimepath+=/home/bhashith/lazy/nvim-treesitter/]]  -- nvim-treesitter plugin no longer needed
vim.cmd [[set runtimepath+=/home/bhashith/lazy/plenary.nvim/]]
vim.cmd [[runtime! plugin/plenary.vim]]
-- vim.cmd [[runtime! plugin/nvim-treesitter.lua]]  -- no longer needed
vim.cmd [[runtime! plugin/nt-cpp-tools.vim]]

vim.o.swapfile = false
vim.bo.swapfile = false
vim.o.filetype = 'cpp'

-- New version no longer requires nvim-treesitter.configs.setup
-- TreeSitter functionality is now provided natively by Neovim
-- require("nvim-treesitter.configs").setup {}

-- Ensure C++ parser is installed (if needed)
-- vim.treesitter.language.add('cpp')
