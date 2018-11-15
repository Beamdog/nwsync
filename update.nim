import docopt; let ARGS = docopt """
nwsync update

This utility creates or updates a serverside http repository
for nwsync.

<root> is the storage directory into which the repository will
be written. When starting out, make sure to give a empty
directory. A <root> can hold multiple manifests.

All given <spec> are added to the manifest in order, with the
latest coming on top (for purposes of shadowing resources).

After a manifest is written, the repository /latest file is
updated to point at it. This file is queried by game servers
if the server admin does not specify a hash to serve explicitly.

<spec> can be:

* a .mod file, which will read the module and add all HAKs and
  the optional TLK as the game would
* any valid other erf container (HAK, ERF)
* single files, including a TLK file
* a directory containing single files


Usage:
  update [options] [--description=D] <root> <spec>...
  update (-h | --help)
  update --version

Options:
  --with-module     Include module contents. This is only useful when packing up
                    a module for full distribution.
                    DO NOT USE THIS FOR PERSISTENT WORLDS.

  --no-latest       Don't update the latest pointer.

  --description=D   Add a human-readable description to metadata [default: ]

  -h --help         Show this screen.
  --version         Show version.
  -v                Verbose operation (>= DEBUG).
  -q                Quiet operation (>= WARN).

  -f                Force rewrite of existing data.
  --compression=T   Compress repostory data. [default: zlib]
                    This saves disk space and speeds up transfers if your
                    webserver does not speak gzip or deflate compression.
                    Supported compression types:
                      * none
                      * zlib (with the default level)
"""

import logging, sequtils, strutils

import libupdate, libshared

let ForceWriteIfExists = ARGS["-f"]
let WithModule = ARGS["--with-module"]
let UpdateLatest = not ARGS["--no-latest"]
let CompressionType =
  case toLowerAscii($ARGS["--compression"])
  of "none": CompressionType.None
  of "zlib": CompressionType.Zlib
  else: quit("Unsupported compression type: " & $ARGS["--compression"])

addHandler newFileLogger(stderr, fmtStr = verboseFmtStr)
setLogFilter(if ARGS["-v"]: lvlDebug elif ARGS["-q"]: lvlWarn else: lvlInfo)

let root = $ARGS["<root>"]
let filesToIndex = ARGS["<spec>"].mapIt($it)

if filesToIndex.len == 0:
  abort "You didn't give me anything to index."

echo reindex(
  root,
  filesToIndex,
  ForceWriteIfExists,
  $ARGS["--description"],
  WithModule,
  CompressionType,
  UpdateLatest)
