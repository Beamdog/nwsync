import docopt; let ARGS = docopt """
nwsync_write

This utility creates a new manifest in a serverside nwsync
repository.

<root> is the storage directory into which the manifest will
be written. A <root> can hold multiple manifests.

All given <spec> are added to the manifest in order, with the
latest coming on top (for purposes of shadowing resources).

Each <spec> will be unpacked, hashed, optionally compressed
and written to the data subdirectory. This process can take a
long time, so be patient.

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
  nwsync_write [options] [--description=D] <root> <spec>...
  nwsync_write (-h | --help)
  nwsync_write --version

Options:
  -h --help              Show this screen.
  -V --version           Show version.
  -v --verbose           Verbose operation (>= DEBUG).
  -q --quiet             Quiet operation (>= WARN).

  --with-module          Include module contents. This is only useful when packing up
                         a module for full distribution.
                         DO NOT USE THIS FOR PERSISTENT WORLDS.

  --no-latest            Don't update the latest pointer.

  --name=N               Override the visible name. Will extract the module name
                         if a module is sourced.

  --description=D        Override the visible description. Will extract module
                         description if a module is sourced.

  -f                     Force rewrite of existing data.
  --compression=T        Compress repostory data. [default: zstd]
                         This saves disk space and speeds up transfers if your
                         webserver does not speak gzip or deflate compression.
                         Supported compression types:
                           * none
                           * zlib (with the default level) - DEPRECATED
                           * zstd (with the default level)

  --group-id ID          Set a group ID. Do this if you run multiple data sets
                         from the same repository. Manifests with the same ID
                         are considered for auto-removal by clients when
                         superseded by a newer download. [default: 0]

  --limit-file-size MB   Error out if any file in the manifest written would
                         exceed the stated limit (in megabytes). [default: 15]

  --write-origins        Write out .origins file, which can be used to reconstruct
                         the hak structure from a NWSync manifest.
"""

from libversion import handleVersion
if ARGS["--version"]: handleVersion()

import logging, sequtils, strutils

import libupdate, libshared
import neverwinter/compressedbuf

let ForceWriteIfExists = ARGS["-f"]
let WithModule = ARGS["--with-module"]
let UpdateLatest = not ARGS["--no-latest"]
let CompressionType = parseEnum[Algorithm]($ARGS["--compression"])
let GroupId = clamp(parseInt($ARGS["--group-id"]), 0, int32.high)

addHandler newFileLogger(stderr, fmtStr = verboseFmtStr)
setLogFilter(if ARGS["--verbose"]: lvlDebug elif ARGS["--quiet"]: lvlWarn else: lvlInfo)

let root = $ARGS["<root>"]
let filesToIndex = ARGS["<spec>"].mapIt($it)

if filesToIndex.len == 0:
  abort "You didn't give me anything to index."

echo reindex(
  root,
  filesToIndex,
  ForceWriteIfExists,
  WithModule,
  CompressionType,
  UpdateLatest, [
    ("module_name", if ARGS["--name"]: $ARGS["--name"] else: ""),
    ("description", if ARGS["--description"]: $ARGS["--description"] else: "")
  ], [
    ("group_id", GroupId)
  ],
  (fileSize: parseInt($ARGS["--limit-file-size"]).uint64 * 1024 * 1024),
  ARGS["--write-origins"])
