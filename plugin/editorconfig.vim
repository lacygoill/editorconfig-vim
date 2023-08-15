vim9script noclear

import autoload '../autoload/editorconfig.vim'
import autoload '../autoload/editorconfig_core.vim'
import autoload '../autoload/editorconfig_core/handler.vim'

# plugin/editorconfig.vim: EditorConfig native Vimscript plugin file
# Copyright (c) 2011-2019 EditorConfig Team
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# check for Vim versions and duplicate script loading.
if v:version < 700 || exists('g:loaded_EditorConfig')
    finish
endif
g:loaded_EditorConfig = true

# variables {{{1

# Make sure the globals all exist
if !exists('g:EditorConfig_exec_path')
    g:EditorConfig_exec_path = ''
endif

if !exists('g:EditorConfig_verbose')
    g:EditorConfig_verbose = 0
endif

if !exists('g:EditorConfig_preserve_formatoptions')
    g:EditorConfig_preserve_formatoptions = 0
endif

if !exists('g:EditorConfig_max_line_indicator')
    g:EditorConfig_max_line_indicator = 'line'
endif

if !exists('g:EditorConfig_exclude_patterns')
    g:EditorConfig_exclude_patterns = []
endif

if !exists('g:EditorConfig_disable_rules')
    g:EditorConfig_disable_rules = []
endif

if !exists('g:EditorConfig_enable_for_new_buf')
    g:EditorConfig_enable_for_new_buf = 0
endif

if !exists('g:EditorConfig_softtabstop_space')
    g:EditorConfig_softtabstop_space = 1
endif

if !exists('g:EditorConfig_softtabstop_tab')
    g:EditorConfig_softtabstop_tab = 1
endif

# Copy some of the globals into script variables --- changes to these
# globals won't affect the plugin until the plugin is reloaded.
var editorconfig_core_mode: string
if exists('g:EditorConfig_core_mode') && !empty(g:EditorConfig_core_mode)
    editorconfig_core_mode = g:EditorConfig_core_mode
else
    editorconfig_core_mode = ''
endif

var editorconfig_exec_path: string
if exists('g:EditorConfig_exec_path') && !empty(g:EditorConfig_exec_path)
    editorconfig_exec_path = g:EditorConfig_exec_path
else
    editorconfig_exec_path = ''
endif

var initialized: bool
var old_shellslash: any = null

# }}}1

# shellslash handling {{{1
def DisableShellSlash(bufnr: number) # {{{2
    # disable shellslash for proper escaping of Windows paths

    # In Windows, 'shellslash' also changes the behavior of 'shellescape'.
    # It makes 'shellescape' behave like in UNIX environment. So ':setl
    # noshellslash' before evaluating 'shellescape' and restore the
    # settings afterwards when 'shell' does not contain 'sh' somewhere.
    var shell: string = getbufvar(bufnr, '&shell')
    if has('win32') && matchstr(shell, 'sh')->empty()
        old_shellslash = getbufvar(bufnr, '&shellslash')
        setbufvar(bufnr, '&shellslash', false)
    endif
enddef # }}}2

def ResetShellSlash(bufnr: number) # {{{2
    # reset shellslash to the user-set value, if any
    if old_shellslash != null
        setbufvar(bufnr, '&shellslash', old_shellslash)
    endif
enddef # }}}2
# }}}1

# Mode initialization functions {{{1

def InitializeVimCore(): bool
# Initialize vim core.  Returns true on failure; false on success
# At the moment, all we need to do is to check that it is installed.
    try
        var vim_core_ver: list<number> = editorconfig_core.Version()
    catch
        return true
    endtry
    return false
enddef

def InitializeExternalCommand(): bool
# Initialize external_command mode

    if empty(editorconfig_exec_path)
        echo 'Please specify a g:EditorConfig_exec_path'
        return true
    endif

    if g:EditorConfig_verbose
        echo $'Checking for external command {editorconfig_exec_path} ...'
    endif

    if !executable(editorconfig_exec_path)
        echo $'File {editorconfig_exec_path} is not executable.'
        return true
    endif

    return false
enddef
# }}}1

def Initialize(): bool # Initialize the plugin.  {{{1
    # Returns truthy on error, falsy on success.

    if empty(editorconfig_core_mode)
        editorconfig_core_mode = 'vim_core'   # Default core choice
    endif

    if editorconfig_core_mode ==? 'external_command'
        if InitializeExternalCommand()
            echohl WarningMsg
            echo 'EditorConfig: Failed to initialize external_command mode.  ' ..
                'Falling back to vim_core mode.'
            echohl None
            editorconfig_core_mode = 'vim_core'
        endif
    endif

    if editorconfig_core_mode ==? 'vim_core'
        if InitializeVimCore()
            echohl ErrorMsg
            echo 'EditorConfig: Failed to initialize vim_core mode.  ' ..
                'The plugin will not function.'
            echohl None
            return true
        endif

    elseif editorconfig_core_mode ==? 'external_command'
        # Nothing to do here, but this elseif is required to avoid
        # external_command falling into the else clause.

    else    # neither external_command nor vim_core
        echohl ErrorMsg
        echo "EditorConfig: I don't know how to use mode " .. editorconfig_core_mode
        echohl None
        return true
    endif

    initialized = true
    return false
enddef # }}}1

def GetFilenames(_path: string, filename: string): list<string> # {{{1
# Yield full filepath for filename in each directory in and above path

    var path_list: list<string>
    var path: string = _path
    while true
        path_list += [$'{path}/{filename}']
        var newpath: string = fnamemodify(path, ':h')
        if path == newpath
            break
        endif
        path = newpath
    endwhile
    return path_list
enddef # }}}1

def UseConfigFiles(from_autocmd: bool) # Apply config to the current buffer {{{1
    # from_autocmd is truthy if called from an autocmd, falsy otherwise.

    # Get the properties of the buffer we are working on
    var bufnr: number
    var buffer_name: string
    var buffer_path: string
    if from_autocmd
        bufnr = expand('<abuf>')->str2nr()
        buffer_name = expand('<afile>:p')
        buffer_path = expand('<afile>:p:h')
    else
        bufnr = bufnr('%')
        buffer_name = expand('%:p')
        buffer_path = expand('%:p:h')
    endif
    setbufvar(bufnr, 'editorconfig_tried', true)

    # Only process normal buffers (do not treat help files as '.txt' files)
    # When starting Vim with a directory, the buftype might not yet be set:
    # Therefore, also check if buffer_name is a directory.
    if index(['', 'acwrite'], &buftype) == -1 || isdirectory(buffer_name)
        return
    endif

    if empty(buffer_name)
        if g:EditorConfig_enable_for_new_buf
            buffer_name = getcwd() .. '/.'
        else
            if g:EditorConfig_verbose
                echo 'Skipping EditorConfig for unnamed buffer'
            endif
            return
        endif
    endif

    if getbufvar(bufnr, 'EditorConfig_disable', false)
        if g:EditorConfig_verbose
            echo $'EditorConfig disabled --- skipping buffer "{buffer_name}"'
        endif
        return
    endif

    # Ignore specific patterns
    for pattern: string in g:EditorConfig_exclude_patterns
        if buffer_name =~ pattern
            if g:EditorConfig_verbose
                echo 'Skipping EditorConfig for buffer "' .. buffer_name ..
                    $'" based on pattern "{pattern}"'
            endif
            return
        endif
    endfor

    # Check if any .editorconfig does exist
    var conf_files: list<string> = GetFilenames(buffer_path, '.editorconfig')
    var conf_found: bool
    for conf_file: string in conf_files
        if filereadable(conf_file)
            conf_found = true
            break
        endif
    endfor
    if !conf_found
        return
    endif

    if !initialized
        if Initialize()
            return
        endif
    endif

    if g:EditorConfig_verbose
        echo 'Applying EditorConfig ' .. editorconfig_core_mode ..
            $' on file "{buffer_name}"'
    endif

    if editorconfig_core_mode ==? 'vim_core'
        if !UseConfigFiles_VimCore(bufnr, buffer_name)
            setbufvar(bufnr, 'editorconfig_applied', true)
        endif
    elseif editorconfig_core_mode ==? 'external_command'
        UseConfigFiles_ExternalCommand(bufnr, buffer_name)
        setbufvar(bufnr, 'editorconfig_applied', true)
    else
        echohl Error
        echo $'Unknown EditorConfig Core: {editorconfig_core_mode}'
        echohl None
    endif
enddef # }}}1

# Custom commands, and autoloading {{{1

# Autocommands, and function to enable/disable the plugin {{{2
def EditorConfigEnable(should_enable: bool)
    augroup editorconfig
        autocmd!
        if should_enable
            autocmd BufNewFile,BufReadPost,BufFilePost * UseConfigFiles(true)
            autocmd VimEnter,BufNew * UseConfigFiles(true)
        endif
    augroup END
enddef

# }}}2

# Commands {{{2
command EditorConfigEnable EditorConfigEnable(true)
command EditorConfigDisable EditorConfigEnable(false)

command EditorConfigReload UseConfigFiles(false) # Reload EditorConfig files
# }}}2

# On startup, enable the autocommands
EditorConfigEnable(true)

# }}}1

# UseConfigFiles function for different modes {{{1

def UseConfigFiles_VimCore(bufnr: number, target: string): bool
# Use the vimscript EditorConfig core
    try
        var config: dict<string> = handler.Get_configurations({target: target})
        ApplyConfig(bufnr, config)
        return false   # success
    catch
        return true    # failure
    endtry
enddef

def UseConfigFiles_ExternalCommand(bufnr: number, target: string)
# Use external EditorConfig core (e.g., the C core)

    DisableShellSlash(bufnr)
    var exec_path: string = shellescape(editorconfig_exec_path)
    ResetShellSlash(bufnr)

    SpawnExternalParser(bufnr, exec_path, target)
enddef

def SpawnExternalParser(bufnr: number, _cmd: string, target: string) # {{{2
# Spawn external EditorConfig. Used by UseConfigFiles_ExternalCommand()

    var cmd: string = _cmd

    if empty(cmd)
        throw 'No cmd provided'
    endif

    var config: dict<string>

    DisableShellSlash(bufnr)
    cmd ..= ' ' .. shellescape(target)
    ResetShellSlash(bufnr)

    var parsing_result: list<string> = system(cmd)
        ->split('\v[\r\n]+')

    # if editorconfig core's exit code is not zero, give out an error
    # message
    if v:shell_error != 0
        echohl ErrorMsg
        echo $'Failed to execute "{cmd}". Exit code: {v:shell_error}'
        echo ''
        echo 'Message:'
        echo parsing_result
        echohl None
        return
    endif

    if g:EditorConfig_verbose
        echo 'Output from EditorConfig core executable:'
        echo parsing_result
    endif

    for one_line: string in parsing_result
        var eq_pos: number = stridx(one_line, '=')

        if eq_pos == -1  # = is not found. Skip this line
            continue
        endif

        var eq_left: string = strpart(one_line, 0, eq_pos)
        var eq_right: string
        if eq_pos + 1 < strlen(one_line)
            eq_right = strpart(one_line, eq_pos + 1)
        else
            eq_right = ''
        endif

        config[eq_left] = eq_right
    endfor

    ApplyConfig(bufnr, config)
enddef # }}}2

# }}}1

# Set the buffer options {{{1
def SetCharset(bufnr: number, charset: string) # apply config['charset']

    # Remember the buffer's state so we can set `nomodifed` at the end
    # if appropriate.
    var orig_fenc: string = getbufvar(bufnr, '&fileencoding')
    var orig_enc: string = getbufvar(bufnr, '&encoding')
    var orig_modified: bool = getbufvar(bufnr, '&modified')

    if charset == 'utf-8'
        setbufvar(bufnr, '&fileencoding', 'utf-8')
        setbufvar(bufnr, '&bomb', false)
    elseif charset == 'utf-8-bom'
        setbufvar(bufnr, '&fileencoding', 'utf-8')
        setbufvar(bufnr, '&bomb', true)
    elseif charset == 'latin1'
        setbufvar(bufnr, '&fileencoding', 'latin1')
        setbufvar(bufnr, '&bomb', false)
    elseif charset == 'utf-16be'
        setbufvar(bufnr, '&fileencoding', 'utf-16be')
        setbufvar(bufnr, '&bomb', true)
    elseif charset == 'utf-16le'
        setbufvar(bufnr, '&fileencoding', 'utf-16le')
        setbufvar(bufnr, '&bomb', true)
    endif

    var new_fenc: string = getbufvar(bufnr, '&fileencoding')

    # If all we did was change the fileencoding from the default to a copy
    # of the default, we didn't actually modify the file.
    if !orig_modified && (orig_fenc == '') && (new_fenc == orig_enc)
        if g:EditorConfig_verbose
            echo 'Setting nomodified on buffer ' .. bufnr
        endif
        setbufvar(bufnr, '&modified', false)
    endif
enddef

def ApplyConfig(bufnr: number, config: dict<string>)
    if g:EditorConfig_verbose
        echo 'Options: ' .. string(config)
    endif

    if IsRuleActive('indent_style', config)
        if config.indent_style == 'tab'
            setbufvar(bufnr, '&expandtab', false)
        elseif config.indent_style == "space"
            setbufvar(bufnr, '&expandtab', true)
        endif
    endif

    var tabstop: number
    if IsRuleActive('tab_width', config)
        tabstop = config.tab_width->str2nr()
        setbufvar(bufnr, '&tabstop', tabstop)
    else
        # Grab the current ts so we can use it below
        tabstop = getbufvar(bufnr, '&tabstop')
    endif

    if IsRuleActive('indent_size', config)
        # if indent_size is 'tab', set shiftwidth to tabstop;
        # if indent_size is a positive integer, set shiftwidth to the integer
        # value
        if config.indent_size == 'tab'
            setbufvar(bufnr, '&shiftwidth', tabstop)
            if typename(g:EditorConfig_softtabstop_tab) !~ '^list<'
                setbufvar(bufnr, '&softtabstop',
                    g:EditorConfig_softtabstop_tab > 0 ?
                    tabstop : g:EditorConfig_softtabstop_tab)
            endif
        else
            var indent_size: number = config.indent_size->str2nr()
            if indent_size > 0
                setbufvar(bufnr, '&shiftwidth', indent_size)
                if typename(g:EditorConfig_softtabstop_space) !~ '^list<'
                    setbufvar(bufnr, '&softtabstop',
                        g:EditorConfig_softtabstop_space > 0 ?
                        indent_size : g:EditorConfig_softtabstop_space)
                endif
            endif
        endif

    endif

    if IsRuleActive('end_of_line', config) &&
            getbufvar(bufnr, '&modifiable')
        if config['end_of_line'] == 'lf'
            setbufvar(bufnr, '&fileformat', 'unix')
        elseif config['end_of_line'] == 'crlf'
            setbufvar(bufnr, '&fileformat', 'dos')
        elseif config.end_of_line == 'cr'
            setbufvar(bufnr, '&fileformat', 'mac')
        endif
    endif

    if IsRuleActive('charset', config) &&
            getbufvar(bufnr, '&modifiable')
        SetCharset(bufnr, config.charset)
    endif

    augroup editorconfig_trim_trailing_whitespace
        autocmd! BufWritePre <buffer>
        if IsRuleActive('trim_trailing_whitespace', config) &&
                    get(config, 'trim_trailing_whitespace', 'false') == 'true'
            execute $'autocmd BufWritePre <buffer={bufnr}> TrimTrailingWhitespace()'
        endif
    augroup END

    if IsRuleActive('insert_final_newline', config)
        if exists('+fixendofline')
            if config.insert_final_newline == 'false'
                setbufvar(bufnr, '&fixendofline', false)
            else
                setbufvar(bufnr, '&fixendofline', true)
            endif
        elseif exists(':SetNoEOL') == 2
            if config.insert_final_newline == 'false'
                silent! execute 'SetNoEOL'    # Use the PreserveNoEOL plugin to accomplish it
            endif
        endif
    endif

    # highlight the columns following max_line_length
    if IsRuleActive('max_line_length', config) &&
            config.max_line_length != 'off'
        var max_line_length: number = config.max_line_length->str2nr()

        if max_line_length >= 0
            setbufvar(bufnr, '&textwidth', max_line_length)
            if g:EditorConfig_preserve_formatoptions == 0
                # setlocal formatoptions+=tc
                var fo: string = getbufvar(bufnr, '&formatoptions')
                if fo !~ 't'
                    fo ..= 't'
                endif
                if fo !~ 'c'
                    fo ..= 'c'
                endif
                setbufvar(bufnr, '&formatoptions', fo)
            endif
        endif

        if exists('+colorcolumn')
            if max_line_length > 0
                if g:EditorConfig_max_line_indicator == 'line'
                    # setlocal colorcolumn+=+1
                    var cocol: string = getbufvar(bufnr, '&colorcolumn')
                    if !empty(cocol)
                        cocol ..= ','
                    endif
                    cocol ..= '+1'
                    setbufvar(bufnr, '&colorcolumn', cocol)
                elseif g:EditorConfig_max_line_indicator == 'fill' &&
                        max_line_length < getbufvar(bufnr, '&columns')
                    # Fill only if the columns of screen is large enough
                    setbufvar(bufnr, '&colorcolumn',
                        range(max_line_length + 1, getbufvar(bufnr, '&columns'))
                        ->join(','))
                elseif g:EditorConfig_max_line_indicator == 'exceeding'
                    setbufvar(bufnr, '&colorcolumn', '')
                    for match: dict<any> in getmatches()
                        if get(match, 'group', '') == 'ColorColumn'
                            get(match, 'id')->matchdelete()
                        endif
                    endfor
                    matchadd('ColorColumn', '\%' .. (max_line_length + 1) .. 'v.', 100)
                elseif g:EditorConfig_max_line_indicator == 'fillexceeding'
                    &l:colorcolumn = ''
                    for match: dict<any> in getmatches()
                        if get(match, 'group', '') == 'ColorColumn'
                            get(match, 'id')->matchdelete()
                        endif
                    endfor
                    matchadd('ColorColumn', '\%' .. (max_line_length + 1) .. 'v.\+', -1)
                endif
            endif
        endif
    endif

    editorconfig.ApplyHooks(config)
enddef

# }}}1

def TrimTrailingWhitespace() # {{{1
    # Called from within a buffer-specific autocmd, so we can use '%'
    if getbufvar('%', '&modifiable')
        # don't lose user position when trimming trailing whitespace
        var view: dict<number> = winsaveview()
        try
            silent! keeppatterns keepjumps :% substitute/\s\+$//e
        finally
            winrestview(view)
        endtry
    endif
enddef # }}}1

def IsRuleActive(name: string, config: dict<string>): bool # {{{1
    return index(g:EditorConfig_disable_rules, name) < 0
        && has_key(config, name)
enddef #}}}1


# vim: fdm=marker fdc=3
