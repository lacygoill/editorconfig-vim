vim9script noclear

# autoload/editorconfig.vim: EditorConfig native Vimscript plugin
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

if v:version < 700
    finish
endif

# variables {{{1
var hook_list: list<func>

export def AddNewHook(func: any) # {{{1
# TODO(lgc): If we  declare the type  of the  `func` argument as  `func`, more
# tests fail.  But this function is not even called during the tests.

    # Add a new hook

    add(hook_list, func)
enddef

export def ApplyHooks(config: dict<string>) # {{{1
    # apply hooks

    for Hook: func in hook_list
        var hook_ret: any = Hook(config)

        if typename(hook_ret) != 'number' && hook_ret != 0
            # TODO print some debug info here
        endif
    endfor
enddef

# }}}

# vim: fdm=marker fdc=3
