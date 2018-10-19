import docopt; let ARGS = docopt """
nwsync print

This utility prints a manifest in human-readable form.

Usage:
  print [options] <manifest>
  print (-h | --help)
  print --version

Options:
  -h --help         Show this screen.
  --version         Show version.
  -v                Verbose operation (>= DEBUG).
  -q                Quiet operation (>= WARN).
"""

import logging, sequtils, streams, strutils, options, os

import libupdate, libshared, manifest, neverwinter/resref

addHandler newFileLogger(stderr, fmtStr = verboseFmtStr)
setLogFilter(if ARGS["-v"]: lvlDebug elif ARGS["-q"]: lvlWarn else: lvlInfo)

doAssert(fileExists($ARGS["<manifest>"]))
let mf = readManifest(newFileStream($ARGS["<manifest>"], fmRead))


echo "--"
echo "Version:          ", mf.version
echo "Hash algorithm:   ", mf.algorithm
echo "Hash tree depth:  ", mf.hashTreeDepth
echo "Entries:          ", mf.entries.len
echo "Size:             ", formatSize(totalSize(mf))
echo "--"
echo ""

for entry in mf.entries:
  let resolved = entry.resref.resolve()

  let rystr = if resolved.isSome:
    resolved.unsafeGet().resExt
  else:
    $entry.resref.resType.int

  echo entry.sha1,
    " ",
    align($entry.size, 15),
    " ",
    align(rystr, 7),
    " ",
    escape(entry.resref.resref, "", "")
