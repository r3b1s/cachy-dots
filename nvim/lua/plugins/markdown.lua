-- Preserve code block fences (```) in render-markdown.nvim if installed
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    optional = true,
    opts = {
      code = {
        conceal_delimiters = false,
      },
    },
  },
}
