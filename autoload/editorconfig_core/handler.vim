vim9script noclear

import autoload '../editorconfig_core.vim'
import autoload './ini.vim'
import autoload './util.vim'

# autoload/editorconfig_core/handler.vim: Main worker for
# editorconfig-core-vimscript and editorconfig-vim.
# Modified from the Python core's handler.py.

# Copyright (c) 2012-2019 EditorConfig Team {{{1
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
#
# Return full filepath for filename in each directory in and above path. {{{1
# Input path must be an absolute path.
# TODO shellslash/shellescape?
def Get_filenames(_path: string, config_filename: string): list<string>
    var path: string = _path
    var path_list: list<string>
    while true
        add(path_list, util.Path_join(path, config_filename))
        var newpath: string = fnamemodify(path, ':h')
        if path ==? newpath || path == ''
            break
        endif
        path = newpath
    endwhile
    return path_list
enddef # Get_filenames

# }}}1
# === Main ============================================================== {{{1

# Find EditorConfig files and return all options matching target_filename.
# Throws on failure.
# @param job    {Dictionary}    required 'target'; optional 'config' and 'version'
export def Get_configurations(_job: dict<string>): dict<string>
    # TODO? support VERSION checks?

    #    Special exceptions that may be raised by this function include:
    #    - ``VersionError``: self.version is invalid EditorConfig version
    #    - ``PathError``: self.filepath is not a valid absolute filepath
    #    - ``ParsingError``: improperly formatted EditorConfig file found

    var job: dict<any> = deepcopy(_job)

    var config_filename: string
    if has_key(job, 'config')
        config_filename = job.config
    else
        config_filename = '.editorconfig'
        job.config = config_filename
    endif

    if has_key(job, 'version')
        # TODO(lgc): `version` is not referred outside this block.
        # What is this assignment supposed to achieve?
        var version: list<number> = job.version
    else
        var version: list<number> = editorconfig_core.Version()
        job.version = version
    endif

    var target_filename: string = job.target

    #echomsg 'Beginning job ' .. string(job)
    if !Check_assertions(job)
        throw 'Assertions failed'
    endif

    var fullpath: string = fnamemodify(target_filename, ':p')
    var path: string = fnamemodify(fullpath, ':h')
    var conf_files: list<string> = Get_filenames(path, config_filename)

    # echomsg 'fullpath ' .. fullpath
    # echomsg 'path ' .. path

    var retval: dict<any>

    # Attempt to find and parse every EditorConfig file in filetree
    for conf_fn: string in conf_files
        #echomsg 'Trying ' .. conf_fn
        var parsed: dict<any> = ini.Read_ini_file(conf_fn, target_filename)
        if !has_key(parsed, 'options')
            continue
        endif
        # echomsg '  Has options'

        # Merge new EditorConfig file's options into current options
        var old_options: dict<any> = retval
        retval = parsed.options
        # echomsg 'Old options ' .. string(old_options)
        # echomsg 'New options ' .. string(retval)
        extend(retval, old_options, 'force')

        # Stop parsing if parsed file has a ``root = true`` option
        if parsed.root
            break
        endif
    endfor

    Preprocess_values(job, retval)
    return retval
enddef # Get_configurations

def Check_assertions(job: dict<any>): bool
# TODO
#    """Raise error if filepath or version have invalid values"""

#    # Raise ``PathError`` if filepath isn't an absolute path
#    if not os.path.isabs(self.filepath):
#        raise PathError("Input file must be a full path name.")

    # Throw if version specified is greater than current
    var v: list<number> = job.version
    var us: list<number> = editorconfig_core.Version()
    # echomsg 'Comparing requested version ' .. string(v) ..
    #     ' to our version ' .. string(us)
    if v[0] > us[0] || v[1] > us[1] || v[2] > us[2]
        throw 'Required version ' .. string(v) ..
            ' is greater than the current version ' .. string(us)
    endif

    return true    # All OK if we got here
enddef # Check_assertions

# }}}1

# Preprocess option values for consumption by plugins.  {{{1
# Modifies its argument in place.
def Preprocess_values(job: dict<any>, opts: dict<string>)
    # Lowercase option value for certain options
    for name: string in ['end_of_line', 'indent_style', 'indent_size',
            'insert_final_newline', 'trim_trailing_whitespace',
            'charset']
        if has_key(opts, name)
            opts[name] = opts[name]->tolower()
        endif
    endfor

    # Set indent_size to "tab" if indent_size is unspecified and
    # indent_style is set to "tab", provided we are at least v0.10.0.
    if get(opts, 'indent_style', '') ==? 'tab'
            && !has_key(opts, 'indent_size')
            && (job.version[0] > 0 || job.version[1] >= 10)
        opts.indent_size = 'tab'
    endif

    # Set tab_width to indent_size if indent_size is specified and
    # tab_width is unspecified
    if has_key(opts, 'indent_size')
            && !has_key(opts, 'tab_width')
            && get(opts, 'indent_size', '') !=? 'tab'
        opts.tab_width = opts.indent_size
    endif

    # Set indent_size to tab_width if indent_size is "tab"
    if has_key(opts, 'indent_size')
            && has_key(opts, 'tab_width')
            && get(opts, 'indent_size', '') ==? 'tab'
        opts.indent_size = opts.tab_width
    endif
enddef # Preprocess_values

# }}}1

# vi: set fdm=marker fdl=1:
