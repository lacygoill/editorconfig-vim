Fork of https://github.com/editorconfig/editorconfig-vim re-written in Vim9 script.

To check that the code compiles in a given script, write `:defcompile` at the end, and source it.  For example:

    $ echo 'defcompile' >>plugin/editorconfig.vim
    $ vim -Nu NONE -S plugin/editorconfig.vim

To run the tests:

    $ ./tests/travis-test.sh plugin
