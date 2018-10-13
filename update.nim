import docopt; let ARGS = docopt """
nwsync update

This utility creates or updates a serverside http repository
for nwsync.

Usage:
  update [options] [--description=D] <root> <spec>...
  update (-h | --help)
  update --version

Options:
  --with-module     Include module contents. This is only useful when packing up
                    a module for full distribution.
                    DO NOT USE THIS FOR PERSISTENT WORLDS.

  --description=D   Add a human-readable description to metadata [default: ]

  -h --help         Show this screen.
  --version         Show version.
  -v                Verbose operation (>= DEBUG).
  -q                Quiet operation (>= WARN).

  -f                Force rewrite of existing data.
"""

import logging, sequtils

import libupdate, libshared

let ForceWriteIfExists = ARGS["-f"]
let WithModule = ARGS["--with-module"]

addHandler newFileLogger(stderr, fmtStr = verboseFmtStr)
setLogFilter(if ARGS["-v"]: lvlDebug elif ARGS["-q"]: lvlWarn else: lvlInfo)

let root = $ARGS["<root>"]
let filesToIndex = ARGS["<spec>"].mapIt($it)

if filesToIndex.len == 0:
  abort "You didn't give me anything to index."

echo reindex(root, filesToIndex, ForceWriteIfExists, $ARGS["--description"], WithModule)
