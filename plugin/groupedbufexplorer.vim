vim9script

import "groupedbufexplorer.vim" as gbe

command! GBufExplorer gbe.GBufExplorer()
command! GToggleBufExplorer gbe.GToggleBufExplorer()
command! GBufExplorerHorizontalSplit gbe.GBufExplorerHorizontalSplit()
command! GBufExplorerVerticalSplit gbe.GBufExplorerVerticalSplit()
command! GBEDebug gbe.GBufDebugDump()
command! GBufExNextGroupHeader keeppatterns normal /---.*\n\s\+\zs\d<CR>
command! GBufExPrevGroupHeader keeppatterns normal ?---.*\n\s\+\zs\d\+\s<CR>

augroup GroupedBufExplorer
    autocmd!
    autocmd! VimEnter * gbe.GBufExplorerSetup()
augroup END

# vim:ft=vim foldmethod=marker sw=4

