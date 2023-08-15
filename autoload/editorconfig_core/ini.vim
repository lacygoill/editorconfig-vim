vim9script noclear

import autoload './fnmatch.vim'
import autoload './util.vim'

# autoload/editorconfig_core/ini.vim: Config-file parser for
# editorconfig-core-vimscript and editorconfig-vim.
# Modifed from the Python core's ini.py.

# Copyright (c) 2012-2019 EditorConfig Team {{{2
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
# POSSIBILITY OF SUCH DAMAGE. }}}2

# variables {{{2
if !exists('g:editorconfig_core_vimscript_debug')
    g:editorconfig_core_vimscript_debug = false
endif
# }}}2
# === Constants, including regexes ====================================== {{{2
# Regular expressions for parsing section headers and options.
# Allow ``]`` and escaped ``;`` and ``#`` characters in section headers.
# In fact, allow \ to escape any single character - it needs to cover at
# least \ * ? [ ! ] { }.
const SECTCRE: string = '\v^\s*\[(%([^\\#;]|\\.)+)\]'

# Regular expression for parsing option name/values.
# Allow any amount of whitespaces, followed by separator
# (either ``:`` or ``=``), followed by any amount of whitespace and then
# any characters to eol
const OPTCRE: string = '\v\s*([^:=[:space:]][^:=]*)\s*([:=])\s*(.*)$'

const MAX_SECTION_NAME: number = 4'096
const MAX_PROPERTY_NAME: number = 1'024
const MAX_PROPERTY_VALUE: number = 4'096

# }}}2
# === Main ============================================================== {{{1

# Read \p config_filename and return the options applicable to
# \p target_filename.  This is the main entry point in this file.
export def Read_ini_file(config_filename: string, target_filename: string): dict<any>
    if !filereadable(config_filename)
        return {}
    endif

    var result: dict<any>
    try
        var lines: list<string> = readfile(config_filename)
        if &encoding !=? 'utf-8'
            # strip BOM
            if len(lines) > 0 && lines[0][: 2] == "\xEF\xBB\xBF"
                lines[0] = lines[0][3 :]
            endif
            # convert from UTF-8 to 'encoding'
            lines->map((_, line: string) => iconv(line, 'utf-8', &encoding))
        endif
        result = Parse(config_filename, target_filename, lines)
    catch
        # rethrow, but with a prefix since throw 'Vim...' fails.
        throw 'Could not read editorconfig file at ' .. v:throwpoint .. ': ' .. string(v:exception)
    endtry

    return result
enddef

def Parse(config_filename: string, target_filename: string, lines: list<string>): dict<any>
#    Parse a sectioned setup file.
#    The sections in setup file contains a title line at the top,
#    indicated by a name in square brackets (`[]'), plus key/value
#    options lines, indicated by `name: value' format lines.
#    Continuations are represented by an embedded newline then
#    leading whitespace.  Blank lines, lines beginning with a '#',
#    and just about everything else are ignored.

    var in_section: bool
    var matching_section: bool
    var optname: string
    var lineno: number
    var e: list<string> = []    # Errors, if any

    var options: dict<string>  # Options applicable to this file
    var is_root: bool   # Whether config_filename declares root=true

    while true
        if lineno == len(lines)
            break
        endif

        var line: string = lines[lineno]
        ++lineno

        # comment or blank line?
        if line->trim()->empty()
            continue
        endif
        if line =~ '\v^[#;]'
            continue
        endif

        # is it a section header?
        if g:editorconfig_core_vimscript_debug
            echomsg $'Header? <{line}>'
        endif

        var mo: list<string> = matchlist(line, SECTCRE)
        if len(mo) > 0
            var sectname = mo[1]
            in_section = true
            if strlen(sectname) > MAX_SECTION_NAME
                # Section name too long => ignore the section
                matching_section = false
            else
                matching_section = Matches_filename(
                    config_filename, target_filename, sectname)
            endif

            if g:editorconfig_core_vimscript_debug
                echomsg 'In section ' .. sectname .. ', which ' ..
                    (matching_section ? 'matches' : 'does not match')
                    ' file ' .. target_filename .. ' (config ' ..
                    config_filename .. ')'
            endif

            # So sections can't start with a continuation line
            optname = ''

        # Is it an option line?
        else
            mo = matchlist(line, OPTCRE)
            if len(mo) > 0
                optname = mo[1]
                var optval: string = mo[3]

                if g:editorconfig_core_vimscript_debug
                    echomsg printf('Saw raw opt <%s>=<%s>', optname, optval)
                endif

                optval = optval->trim()
                # allow empty values
                if optval ==? '""'
                    optval = ''
                endif
                optname = Optionxform(optname)
                if !in_section && optname ==? 'root'
                    is_root = (optval ==? 'true')
                endif
                if g:editorconfig_core_vimscript_debug
                    echomsg printf('Saw opt <%s>=<%s>', optname, optval)
                endif

                if matching_section &&
                        strlen(optname) <= MAX_PROPERTY_NAME &&
                        strlen(optval) <= MAX_PROPERTY_VALUE
                    options[optname] = optval
                endif
            else
                # a non-fatal parsing error occurred.  set up the
                # exception but keep going. the exception will be
                # raised at the end of the file and will contain a
                # list of all bogus lines
                e->add(printf(
                    "Parse error in '%s' at line %s: '%s'",
                    config_filename,
                    lineno,
                    line
                ))
            endif
        endif
    endwhile

    # if any parsing errors occurred, raise an exception
    if len(e) > 0
        throw string(e)
    endif

    return {root: is_root, options: options}
enddef

# }}}1
# === Helpers =========================================================== {{{1

# Preprocess option names
def Optionxform(optionstr: string): string
    return optionstr->trim()->tolower()
enddef

# Return true if \p glob matches \p target_filename
def Matches_filename(config_filename: string, target_filename: string, _glob: string): bool
#    config_dirname = normpath(dirname(config_filename)).replace(sep, '/')
    var config_dirname: string = fnamemodify(config_filename, ':p:h') .. '/'

    if util.Is_win()
        # Regardless of whether shellslash is set, make everything slashes
        config_dirname = config_dirname
            ->substitute('\v\\', '/', 'g')
            ->tolower()
    endif

    var glob: string = substitute(_glob, '\v\\([#;])', '\1', 'g')

    # Take account of the path to the editorconfig file.
    # editorconfig-core-c/src/lib/editorconfig.c says:
    #  "Pattern would be: /dir/of/editorconfig/file[double_star]/[section] if
    #   section does not contain '/', or /dir/of/editorconfig/file[section]
    #   if section starts with a '/', or /dir/of/editorconfig/file/[section] if
    #   section contains '/' but does not start with '/'."

    if stridx(glob, '/') != -1    # contains a slash
        if glob[0] == '/'
            glob = glob[1 :]     # trim leading slash
        endif
# This will be done by fnmatch
#        glob = config_dirname .. glob
    else                            # does not contain a slash
        config_dirname = config_dirname[: -2]
            # Trim trailing slash
        glob = '**/' .. glob
    endif

    if g:editorconfig_core_vimscript_debug
        echomsg printf(
            '- ini#Matches_filename: checking <%s> against <%s> with respect to config file <%s>',
            target_filename,
            glob,
            config_filename
        )
        echomsg '- ini#Matches_filename: config_dirname is ' .. config_dirname
    endif

    return fnmatch.Fnmatch(
        target_filename,
        config_dirname,
        glob
    )
enddef # Matches_filename

# }}}1
# === Copyright notices ================================================= {{{2
# Based on code from ConfigParser.py file distributed with Python 2.6.
# Portions Copyright (c) 2001-2010 Python Software Foundation;
# All Rights Reserved.  Licensed under PSF License (see LICENSE.PSF file).
#
# Changes to original ConfigParser:
#
# - Special characters can be used in section names
# - Octothorpe can be used for comments (not just at beginning of line)
# - Only track INI options in sections that match target filename
# - Stop parsing files with when ``root = true`` is found
# }}}2

# vi: set fdm=marker fdl=1:
