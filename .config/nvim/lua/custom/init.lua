vim.cmd([[
  augroup ManColors
    autocmd!
    autocmd FileType man setlocal syntax=man
    autocmd FileType man setlocal conceallevel=0
    autocmd FileType man setlocal nospell
  augroup END
]])
