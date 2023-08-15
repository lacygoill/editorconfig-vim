vim9script noclear

import autoload './editorconfig_core/handler.vim'

# autoload/editorconfig_core.vim: top-level functions for
# editorconfig-core-vimscript and editorconfig-vim.

# Copyright (c) 2018-2020 EditorConfig Team, including Chris White {{{1
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
# POSSIBILITY OF SUCH DAMAGE. }}}1

# Variables {{{1

# Note: we create this variable in every script that accesses it.  Normally, I
# would put this in plugin/editorconfig.vim.  However, in some of my tests,
# the command-line testing environment did not load plugin/* in the normal
# way.  Therefore, I do the check everywhere so I don't have to special-case
# the command line.

if !exists('g:editorconfig_core_vimscript_debug')
    g:editorconfig_core_vimscript_debug = false
endif
# }}}1

# The latest version of the specification that we support.
# See discussion at https://github.com/editorconfig/editorconfig/issues/395
export def Version(): list<number>
    return [0, 13, 0]
enddef

# === CLI =============================================================== {{{1

# For use from the command line.  Output settings for in_name to
# the buffer named out_name.  If an optional argument is provided, it is the
# name of the config file to use (default '.editorconfig').
# TODO support multiple files
#
# filename (if any)
# @param names  {Dictionary}    The names of the files to use for this run
#   - output    [required]  Where the editorconfig settings should be written
#   - target    [required]  A string or list of strings to process.  Each
#                           must be a full path.
#   - dump      [optional]  If present, write debug info to this file
# @param job    {Dictionary}    What to do - same format as the input of
#                               editorconfig_core#handler#Get_configurations(),
#                               except without the target member.

export def Currbuf_cli(names: dict<any>, _job: dict<string>) # out_name, in_name, ...
    var output: list<string>

    # Preprocess the job
    var job: dict<any> = deepcopy(_job)

    if has_key(job, 'version')    # string to list
        job.version = job.version
            ->trim()
            ->split('\v\.')
            ->map((_, s: string): number => s->str2nr())
    endif

    # TODO provide version output from here instead of the shell script
    #    if string(names) ==? 'version'
    #        return
    #    endif
    #
    if typename(names) !~ '^dict<' || typename(_job) !~ '^dict<'
        throw 'Need two Dictionary arguments'
    endif

    if has_key(names, 'dump')
        execute $'redir! > {fnameescape(names.dump)}'
        echomsg $'Names: {string(names)}'
        echomsg $'Job: {string(job)}'
        g:editorconfig_core_vimscript_debug = true
    endif

    var targets: list<string>
    if typename(names.target) =~ '^list<'
        targets = names.target
    else
        targets = [names.target]
    endif

    for _target: string in targets

        # Pre-process quoting weirdness so we are more flexible in the face
        # of CMake+CTest+BAT+Powershell quoting.

        # Permit wrapping in double-quotes
        var target: string = substitute(_target, '\v^"(.*)"$', '\1', '')

        # Permit empty ('') entries in targets
        if strlen(target) < 1
            continue
        endif

        if has_key(names, 'dump')
            echom $'Trying: {string(target)}'
        endif

        job.target = target
        var options: dict<string> = handler.Get_configurations(job)

        if has_key(names, 'dump')
            echom $'editorconfig_core#Currbuf_cli result: {string(options)}'
        endif

        if len(targets) > 1
            output += [$'[{target}]']
        endif

        for [key: string, value: string] in items(options)
            output += [$'{key}={value}']
        endfor

    endfor #foreach target

    # Write the output file
    writefile(output, names.output)
enddef #Currbuf_cli

# }}}1

# vi: set fdm=marker fo-=ro:
