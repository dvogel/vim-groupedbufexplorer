"============================================================================
"    Copyright: Copyright (c) 2022, Drew Vogel
" Name Of File: groupedbufexplorer.vim
"  Description: Buffer explorer plugin that is designed to support working on
"               multiple projects within the same vim session.
"
"    Forked from:
"    Copyright: Copyright (c) 2001-2018, Jeff Lanzarotta
"               All rights reserved.
"
"               Redistribution and use in source and binary forms, with or
"               without modification, are permitted provided that the
"               following conditions are met:
"
"               * Redistributions of source code must retain the above
"                 copyright notice, this list of conditions and the following
"                 disclaimer.
"
"               * Redistributions in binary form must reproduce the above
"                 copyright notice, this list of conditions and the following
"                 disclaimer in the documentation and/or other materials
"                 provided with the distribution.
"
"               * Neither the name of the {organization} nor the names of its
"                 contributors may be used to endorse or promote products
"                 derived from this software without specific prior written
"                 permission.
"
"               THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
"               CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
"               INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
"               MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
"               DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
"               CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
"               SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
"               NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
"               LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
"               HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
"               CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
"               OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
"               EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
" Name Of File: bufexplorer.vim
"  Description: Buffer Explorer Vim Plugin
"   Maintainer: Jeff Lanzarotta (delux256-vim at outlook dot com)
" Last Changed: Saturday, 08 December 2018
"      Version: See g:bufexplorer_version for version number.
"        Usage: This file should reside in the plugin directory and be
"               automatically sourced.
"
"               You may use the default keymappings of
"
"                 <Leader>be  - Opens BufExplorer
"                 <Leader>bt  - Toggles BufExplorer open or closed
"                 <Leader>bs  - Opens horizontally split window BufExplorer
"                 <Leader>bv  - Opens vertically split window BufExplorer
"
"               Or you can override the defaults and define your own mapping
"               in your vimrc file, for example:
"
"                   nnoremap <silent> <F11> :BufExplorer<CR>
"                   nnoremap <silent> <s-F11> :ToggleBufExplorer<CR>
"                   nnoremap <silent> <m-F11> :BufExplorerHorizontalSplit<CR>
"                   nnoremap <silent> <c-F11> :BufExplorerVerticalSplit<CR>
"
"               Or you can use
"
"                 ":BufExplorer"                - Opens BufExplorer
"                 ":ToggleBufExplorer"          - Opens/Closes BufExplorer
"                 ":BufExplorerHorizontalSplit" - Opens horizontally window BufExplorer
"                 ":BufExplorerVerticalSplit"   - Opens vertically split window BufExplorer
"
"               For more help see supplied documentation.
"      History: See supplied documentation.
"=============================================================================


if &cp
    finish
endif

" This is redundant with the vim9script declaration below but it silently
" bails out instead of giving the user an error.
if v:versionlong < 9000000
    finish
endif

vim9script

var bufListLinePattern = '^\s\+\(\d\+\)\s\+.*'
var noNamePlaceholder = "[No Name]"
var defaultGroupKey = 'Ungrouped Files'
var pluginBufName = '[GroupedBufExplorer]'
var excludedBufferNames = [pluginBufName, "[BufExplorer]", "__MRU_Files__", "[Buf\ List]"]
var allBuffers: list<dict<any>> = []
var fileGroups = {}
var mruGroups = {}
var mruBuffers = {}
var mruCounter = 0
var originBufNr = 0
var running = false
var splitMode = ""

var optShowUnlisted = !!get(g:, "groupedBufExplorerShowUnlisted", false)
var optShowNoName = !!get(g:, "groupedBufExplorerShowNoName", false)
var optHelpMode = "bare"
var optSplitBelow = &splitbelow
var optSplitRight = &splitright

# Global settings that need to be temporarily overridden at times. The values
# captured here aren't used but initializing them like this ensures the
# correct types are inferred.
var _insertmode = &insertmode
var _showcmd = &showcmd
var _cpo = &cpo
var _report = &report

export def GBufDebugDump(): void
    echo keys(fileGroups)

    echo "----------------"
    echo "MRU Group Stack:"
    for groupMruItem in sort(items(copy(mruGroups)), (a, b) => a[1] - b[1])
        echo "MRU " .. groupMruItem[1] .. " GROUP " .. groupMruItem[0]
    endfor

    echo "-----------------"
    echo "MRU Buffer Stack:"
    for bufMruItem in sort(items(copy(mruBuffers)), (a, b) => a[1] - b[1])
        var bufName = bufname(str2nr(bufMruItem[0]))
        echo "MRU " .. bufMruItem[1] .. " => BUF #" .. bufMruItem[0] .. " - " .. bufName
    endfor
    echo mruCounter
    for bufObj in allBuffers
        echo bufObj
    endfor
enddef


export def GBufExplorerSetup(): void
    allBuffers = CollectBufferInfo()
    Reset()

    # Now that the MRUList is created, add the other autocmds.
    augroup GroupedBufExplorer
        autocmd!
        autocmd BufEnter,BufNew * ActivateBuffer()
        autocmd BufWipeOut * DeactivateBuffer()
        autocmd BufDelete * DeactivateBuffer()
        autocmd BufWinEnter \[GroupedBufExplorer\] Initialize()
        autocmd BufWinLeave \[GroupedBufExplorer\] Cleanup()
    augroup END
enddef

def Reset()
    # Build initial MRU tables. This makes sure all the files specified on the
    # command line are picked up correctly.
	for bufObj in allBuffers
        mruBuffers[bufObj.bufnr] = NextMRUCounter()
        mruGroups[bufObj.groupkey] = NextMRUCounter()
    endfor
enddef

def ActivateBuffer(): void
    var bufnr = bufnr("%")
    MRUPush(bufnr)
enddef

def DeactivateBuffer(): void
    var bufnr = str2nr(expand("<abuf>"))
    MRUPop(bufnr)
enddef

def LookupBuf(bufnr: number): any
    for bufObj in allBuffers
        if bufObj.bufnr == bufnr
            return bufObj
        endif
    endfor
	return v:null
enddef

def MRUTick(bufnr: number): void
	var bufObj = LookupBuf(bufnr)
	if bufObj != v:null
		mruGroups[bufObj.groupkey] = NextMRUCounter()
		mruBuffers[bufnr] = NextMRUCounter()
	endif
enddef

def MRUPop(bufnr: number): void
	var bufObj = LookupBuf(bufnr)
	if bufObj != v:null
		if has_key(mruGroups, bufObj.groupkey)
			remove(mruGroups, bufObj.groupkey)
		endif
		if has_key(mruBuffers, bufnr)
			remove(mruBuffers, bufnr)
		endif
	endif
enddef

def MRUPush(bufnr: number): void
    # Skip temporary buffer with buftype set. Don't add the BufExplorer window
    # to the list.
    if ShouldIgnore(bufnr)
        return
    endif

    MRUTick(bufnr)
enddef

def ShouldIgnore(bufnr: number): bool
    # Ignore temporary buffers with buftype set. empty() returns 0 instead of
    # false for non-empty
    if empty(getbufvar(bufnr, "&buftype")) == 0
        return true
    endif

    # Ignore buffers with no name.
    if empty(bufname(bufnr)) == 1
        return true
    endif

    # Ignore the BufExplorer buffer.
    if fnamemodify(bufname(bufnr), ":t") == pluginBufName
        return true
    endif

    # Ignore any buffers in the exclude list.
    if index(excludedBufferNames, bufname(bufnr)) >= 0
        return true
    endif

    # Else return 0 to indicate that the buffer was not ignored.
    return false
enddef

def Initialize()
    SetLocalSettings()
    optSplitBelow = &splitbelow
    optSplitRight = &splitright
    running = true
enddef

def Cleanup(): void
    if _insertmode != v:null
        &insertmode = _insertmode
    endif

    if _showcmd != v:null
        &showcmd = _showcmd
    endif

    if _cpo != v:null
        &cpo = _cpo
    endif

    if _report != v:null
        &report = _report
    endif

    running = false
    splitMode = ""

    delmarks!
enddef

def SetLocalSettings(): void
    _insertmode = &insertmode
    set noinsertmode

    _showcmd = &showcmd
    set noshowcmd

    _cpo = &cpo
    set cpo&vim

    _report = &report
    &report = 10000

    setlocal nonumber
    setlocal foldcolumn=0
    setlocal nofoldenable
    setlocal cursorline
    setlocal nospell
    setlocal nobuflisted
    setlocal filetype=bufexplorer
enddef

export def GBufExplorerHorizontalSplit(): void
    splitMode = "sp"
    GBufExplorer()
enddef

export def GBufExplorerVerticalSplit(): void
    splitMode = "vsp"
    GBufExplorer()
enddef

export def GToggleBufExplorer(): void
    if running && bufname(winbufnr(0)) == pluginBufName
        Close()
    else
        GBufExplorer()
    endif
enddef

export def GBufExplorer(): void
    var escapedBufName = pluginBufName

    if !has("win32")
        # On non-Windows boxes, escape the name so that is shows up correctly.
        escapedBufName = escape(pluginBufName, "[]")
    endif

    # Make sure there is only one explorer open at a time.
    if running 
        # Go to the open buffer.
        if has("gui")
            execute "drop" escapedBufName
        endif

        return
    endif

    # Add zero to ensure the variable is treated as a number.
    originBufNr = bufnr("%") + 0

    fileGroups = {}

    allBuffers = CollectBufferInfo()
    for bufObj in allBuffers
        var gk = bufObj.groupkey
        var grpList = []
        if has_key(fileGroups, gk)
            grpList = fileGroups[gk]
        endif
        extend(grpList, [bufObj])
        fileGroups[gk] = grpList
    endfor

    # We may have to split the current window.
    if splitMode != ""
        # Save off the original settings.
        var [_splitbelow, _splitright] = [&splitbelow, &splitright]

        # Set the setting to ours.
        [&splitbelow, &splitright] = [optSplitBelow, optSplitRight]

        execute 'keepalt ' .. splitMode

        # Restore the original settings.
        [&splitbelow, &splitright] = [_splitbelow, _splitright]
    endif

    if !exists("b:displayMode")
        # Do not use keepalt when opening bufexplorer to allow the buffer that
        # we are leaving to become the new alternate buffer
        execute "silent keepjumps hide edit " .. escapedBufName
    endif

    DisplayBufferList()
enddef

def DisplayBufferList(): void
    # Do not set bufhidden since it wipes out the data if we switch away from
    # the buffer using CTRL-^.
    setlocal buftype=nofile
    setlocal modifiable
    setlocal noswapfile
    setlocal nowrap

    SetupSyntax()
    MapKeys()

    var lines = BuildBufferLines()
    RenderBufferLines(lines)
    MoveCursorToFirstBuffer()

    setlocal nomodifiable
enddef

def MapKeys(): void
    nnoremap <script> <silent> <nowait> <buffer> <2-leftmouse>   :call <SID>SelectBuffer()<CR>
    nnoremap <script> <silent> <nowait> <buffer> <CR>            :call <SID>SelectBuffer()<CR>
    nnoremap <script> <silent> <nowait> <buffer> J               /---.*\n\s\+\zs\d<CR>
    nnoremap <script> <silent> <nowait> <buffer> K               ?---.*\n\s\+\zs\d\+\s<CR>
    nnoremap <script> <silent> <nowait> <buffer> <F1>            :call <SID>ToggleHelp()<CR>
    nnoremap <script> <silent> <nowait> <buffer> d               :call <SID>MaybeDeleteBuffer("delete")<CR>
    xnoremap <script> <silent> <nowait> <buffer> d               :call <SID>MaybeDeleteBuffer("delete")<CR>
    nnoremap <script> <silent> <nowait> <buffer> D               :call <SID>MaybeDeleteBuffer("wipe")<CR>
    xnoremap <script> <silent> <nowait> <buffer> D               :call <SID>MaybeDeleteBuffer("wipe")<CR>
    nnoremap <script> <silent> <nowait> <buffer> q               :call <SID>Close()<CR>
    nnoremap <script> <silent> <nowait> <buffer> u               :call <SID>ToggleShowUnlisted()<CR>
    nnoremap <script> <silent> <nowait> <buffer> N               :call <SID>ToggleNoNameBuffers()<CR>
enddef

def SetupSyntax(): void
    if has("syntax")
        syn match GBufExHeader       /^--- .*:$/ contains=GBufExHeaderGroupKey
        syn match GBufExHeaderGroupKey /--- \zs.*\ze:$/ contained
        syn match GBufListEntry /\s\s\s\s\d\+.*$/ contains=GBufExBufNr
        syn match GBufExBufNr /\s\s\s\s\zs\d\+/ contained nextgroup=GBufExFilename skipwhite
        syn match GBufExFilename /[^\d\s].*$/ contained
    endif
enddef

def CreateHeaderLines(): list<string>
    return [
        "# Grouped Buffer Explorer",
        "# -----------------------",
        ""
        ]
enddef

def CreateHelpLines(): list<string>
    if optHelpMode == 'none'
        return []
    elseif optHelpMode == 'detailed'
        return [
            "# <F1>     Toggle help mode.",
            "# <enter>  Enter currently selected buffer.",
            "# q        Quit and return to original buffer.",
            "# u        Toggle showing unlisted buffers",
            "# N        Toggle showing buffers without a name",
            "# j        Move down 1 line.",
            "# k        Move up 1 line.",
            "# J        Move down to first buffer in the group below.",
            "# K        Move up to first buffer in the group above.",
            "",
            ]
    elseif optHelpMode == 'bare'
        return [
            "# Press <F1> for help",
            ""
            ]
    else
        # Should never happen, but just in case.
        return []
    endif
enddef

def InferBufferGroupKey(bufObj: dict<any>): void
    if bufObj.ftype == "dir"
        bufObj.listname = "[DIR] " .. bufObj.listname
        bufObj.groupkey = bufObj.listname
        return
    endif

    if bufObj.ftype == ""
        bufObj.listname = "[VIRTUAL] " .. fnamemodify(bufObj.name, ":t")
        bufObj.groupkey = defaultGroupKey
        return
    endif

    if bufObj.ftype != "file"
        bufObj.listname = bufObj.name
        bufObj.groupkey = bufObj.ftype
        return
    endif

    var HookFunc = get(g:, 'GroupedBufExplorerGroupingHook')
    if type(HookFunc) == 2 # 2 == Funcref
        HookFunc(bufObj)
    else
        bufObj.listname = bufObj.name
        bufObj.groupkey = defaultGroupKey
    endif
enddef

def CollectBufferInfo(): list<dict<any>>
    var all = []

    for nativeBufObj in getbufinfo()
        if nativeBufObj.name == ""
            continue
        endif

        if nativeBufObj.name == pluginBufName
            continue
        endif

        if bufname(nativeBufObj.bufnr) == pluginBufName
            continue
        endif

        var bufObj = {
            'bufnr': nativeBufObj.bufnr,
            'hidden': nativeBufObj.hidden,
            'listed': !!(nativeBufObj.listed == 1),
            'name': nativeBufObj.name,
            'loaded': nativeBufObj.loaded,
            'line': nativeBufObj.lnum,
            'ftype': getftype(nativeBufObj.name),
            'listname': bufname(nativeBufObj.bufnr),
            'groupkey': defaultGroupKey,
            }

        if bufObj.ftype == "link"
            var realPath = resolve(bufObj.name)
            bufObj.ftype = getftype(realPath)
        endif

        InferBufferGroupKey(bufObj)

        add(all, bufObj)
    endfor

    return all
enddef

def NextMRUCounter(): number
    mruCounter += 1
    return mruCounter
enddef

def GetBufGroupKey(bufnr: number): string
    for bufObj in allBuffers
        if bufObj.bufnr == bufnr
            return bufObj.groupkey
        endif
    endfor
    return getbufvar(bufnr, 'bufExplorerGroupKey')
enddef

def GetBufGroupKeyOrDefault(bufnr: number): string
    var gk = GetBufGroupKey(bufnr)
    if gk == ""
        return defaultGroupKey
    endif
    return gk
enddef

def FocalBufGroupKey(): string
    if originBufNr == v:null
        return defaultGroupKey
    endif

    return GetBufGroupKeyOrDefault(originBufNr)
enddef

def BuildGroupHeaderLine(gk: string): string
    return "--- " .. gk .. ":"
enddef

def CalcFieldWidths(bufList: list<dict<any>>): list<number>
    var widths = [0, 0]
    for bufObj in bufList
        widths[0] = max([widths[0], strcharlen("" .. bufObj.bufnr)])
        widths[1] = max([widths[1], strcharlen("" .. bufObj.listname)])
    endfor
    return widths
enddef

def BuildBufferListLine(bufObj: dict<any>, mru: number, w: list<number>): string
    var fieldFmtStr = "    %" .. w[0] .. "S [%4d]  %S"
    return printf(fieldFmtStr, bufObj.bufnr, mru, bufObj.listname)
enddef

def BuildGroupBufferLines(grpList: list<dict<any>>): list<string>
    var tmpGrpList = copy(grpList)
    sort(tmpGrpList, (a, b) => get(mruBuffers, b.bufnr, 0) - get(mruBuffers, a.bufnr, 0))
    var lines = []

    var widths = CalcFieldWidths(grpList)

    for bufObj in tmpGrpList
        if !optShowUnlisted && !bufObj.listed
            continue
        endif

        if !optShowNoName && bufObj.name == noNamePlaceholder
            continue
        endif

        if bufObj.name == pluginBufName
            continue
        endif

        add(lines, BuildBufferListLine(bufObj, get(mruBuffers, bufObj.bufnr, -1), widths))
    endfor
    return lines
enddef

def BuildBufferLines(): list<string>
    var lines = []

    extend(lines, CreateHeaderLines())
    extend(lines, CreateHelpLines())

    var groupKeys = keys(fileGroups)
    sort(groupKeys, (a, b) => get(mruGroups, b, 0) - get(mruGroups, a, 0))

    for gk in groupKeys
        var grpLines = BuildGroupBufferLines(fileGroups[gk])
        if len(grpLines) > 0
            add(lines, BuildGroupHeaderLine(gk))
            extend(lines, grpLines)
            add(lines, "")
        endif
    endfor

    return lines
enddef

def RenderBufferLines(lines: list<string>): void
    # Wipe out any existing lines in case BufExplorer buffer exists and the
    # user had changed any global settings that might reduce the number of
    # lines needed in the buffer.
    silent keepjumps :1,$d _
    normal ggdG

    # Squelch the warning that the plugin's buffer is technically 'readonly'
    # when launched with 'vim -R' or 'view'.
    silent setline(1, lines)
enddef

export def SelectBuffer(): void
    # Sometimes messages are not cleared when we get here so it looks like an
    # error has occurred when it really has not.
    echo ""

    var _bufNbr = -1

    # Bail out if the current line does not correspond to a buffer.
    var matches = matchlist(getline('.'), bufListLinePattern)
    if matches == []
        execute "normal! \<CR>"
        return
    endif

    # Works because str2nr ignores everything after the initial series of digits.
    _bufNbr = str2nr(getline('.'))

    echo "Launching into buffer " .. _bufNbr
    if bufexists(_bufNbr)
        if bufnr("#") == _bufNbr
            Close()
            return
        endif

        # Switch to the selected buffer.
        execute "keepjumps keepalt silent b!" _bufNbr

        # Make the buffer 'listed' again.
        setbufvar(_bufNbr, "&buflisted", true)

        # Call any associated function references. g:bufExplorerFuncRef may be
        # an individual function reference or it may be a list containing
        # function references. It will ignore anything that's not a function
        # reference.
        #
        # See  :help FuncRef  for more on function references.
        if exists("g:BufExplorerFuncRef")
            if type(g:BufExplorerFuncRef) == 2
                keepj g:BufExplorerFuncRef()
            elseif type(g:BufExplorerFuncRef) == 3
                for FncRef in g:BufExplorerFuncRef
                    if type(FncRef) == 2
                        keepj FncRef()
                    endif
                endfor
            endif
        endif
    else
        Error("Sorry, that buffer no longer exists, please select another")
        DeleteBuffer(_bufNbr, "wipe")
    endif
enddef

def MaybeDeleteBuffer(mode: string): void
    # Bail out if the current line does not correspond to a buffer.
    var matches = matchlist(getline('.'), bufListLinePattern)
    if matches == []
        return
    endif

    var realMode = mode

    var _bufNbr = str2nr(getline('.'))

    if getbufvar(_bufNbr, '&modified')
        # Calling confirm() requires Vim built with dialog option
        if !has("dialog_con") && !has("dialog_gui")
            Error("Sorry, no write since last change for buffer " .. _bufNbr .. " unable to delete")
            return
        endif

        var answer = confirm("No write since last change for buffer " .. _bufNbr .. ". Delete anyway?", "&Yes\n&No", 2)

        if mode == "delete" && answer == 1
            realMode = "force_delete"
        elseif mode == "wipe" && answer == 1
            realMode = "force_wipe"
        else
            return
        endif

    endif

    # Okay, everything is good, delete or wipe the buffer.
    DeleteBuffer(_bufNbr, realMode)
enddef

def DeleteBuffer(bufnr: number, mode: string): void
    # This routine assumes that the buffer to be removed is on the current line.
    try
        # Wipe/Delete buffer from Vim.
        if mode == "wipe"
            execute "silent bwipe" bufnr
        elseif mode == "force_wipe"
            execute "silent bwipe!" bufnr
        elseif mode == "force_delete"
            execute "silent bdelete!" bufnr
        else
            execute "silent bdelete" bufnr
        endif

        # Delete the buffer from the list on screen.
        setlocal modifiable
        normal! "_dd
        setlocal nomodifiable

        # Delete the buffer from the raw buffer list.
        filter(allBuffers, (idx, bufObj) => bufObj.bufnr != bufnr)
        # In case the file was the last buffer in the group, remove the group
        # so the header is not re-rendered the next time the buffer list is
        # rebuilt.
        for gk in copy(keys(fileGroups))
            if len(fileGroups[gk]) == 0
                remove(fileGroups, gk)
                remove(mruGroups, gk)
                remove(mruBuffers, bufnr)
            endif
        endfor

    catch
        Error(v:exception)
    endtry
enddef

def Close(): void
    # If we needed to split the main window, close the split one.
    if splitMode != "" && bufwinnr(originBufNr) != -1
        execute "wincmd c"
    endif

	# Clear any message that may be left behind
    echo
	execute "keepjumps silent b " .. originBufNr
	return
enddef

def ToggleHelp()
    if optHelpMode == "none"
        optHelpMode = "bare"
    elseif optHelpMode == "bare"
        optHelpMode = "detailed"
    elseif optHelpMode == "detailed"
        optHelpMode = "none"
    endif
    RebuildBufferList()
enddef

def ToggleNoNameBuffers()
    optShowNoName = !optShowNoName
    RebuildBufferList()
enddef

def ToggleShowUnlisted()
    optShowUnlisted = !optShowUnlisted
    RebuildBufferList()
enddef

def MoveCursorToFirstBuffer(): void
    cursor(1, 1)
    silent! normal J
enddef

def RebuildBufferList(): void
    var lines = BuildBufferLines()
    setlocal modifiable
    RenderBufferLines(lines)
    MoveCursorToFirstBuffer()
    setlocal nomodifiable
enddef

# Display a message using ErrorMsg highlight group.
def Error(msg: string): void
    echohl ErrorMsg
    echomsg msg
    echohl None
enddef

# Display a message using WarningMsg highlight group.
def Warning(msg: string): void
    echohl WarningMsg
    echomsg msg
    echohl None
enddef

defcompile

# vim:ft=vim foldmethod=marker sw=4

