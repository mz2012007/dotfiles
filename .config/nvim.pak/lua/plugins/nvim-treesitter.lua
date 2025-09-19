return {
  "nvim-treesitter/nvim-treesitter",
  debendincies = {
    "nvim-treesitter/nvim-treesitter-textobjects",
  },
  branch = "master",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    local config = require("nvim-treesitter.configs")
    config.setup({
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    })
  end,
}
