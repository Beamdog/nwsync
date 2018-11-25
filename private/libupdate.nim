import options, logging, critbits, std/sha1, strutils, sequtils,
  os, ospaths, algorithm, math, times, json, sets, tables

import neverwinter/erf, neverwinter/resfile, neverwinter/resdir,
  neverwinter/gff, neverwinter/resman, neverwinter/key

import libmanifest
import libshared

import zip/zlib

type CompressionType* {.pure.} = enum None, Zlib

let GobalResTypeSkipList = [getResType("nss")]

proc allowedToExpose(it: ResRef): bool =
  not GobalResTypeSkipList.contains(it.resType)

proc pathForEntry*(manifest: Manifest, rootDirectory, sha1str: string, create: bool): string =
  result = rootDirectory / "data" / "sha1"
  for i in 0..<manifest.hashTreeDepth:
    let pfx = sha1str[i*2..<(i*2+2)]
    result = result / pfx
    if create: createDir result
  result = result / sha1str

proc reindex*(rootDirectory: string,
    entries: seq[string],
    forceWriteIfExists: bool,
    withModuleContents: bool,
    compressWith: CompressionType,
    updateLatest: bool,
    additionalMeta: openArray[(string, string)]): string =
  ## Reindexes the given module.

  if not dirExists(rootDirectory):
    abort "Target sync directory does not exist."

  if updateLatest and fileExists(rootDirectory / "latest"):
    info "Directory already has `latest` manifest, that's OK. Updating!"

  createDir(rootDirectory / "manifests")
  createDir(rootDirectory / "data")
  createDir(rootDirectory / "data" / "sha1")

  info "Reindexing"
  let resman = newResMan(entries, withModuleContents)

  info "Preparing data set to expose"
  let entriesToExpose = toSeq(resman.contents.items).filter do (it: ResRef) -> bool:
    if not lookupResExt(it.resType).isSome:
      error "ResRef ", it, " is not resolvable (we don't know the file type); origin: ",
        resman[it].get().origin
      quit(1)
    allowedToExpose(it)

  let totalfiles = entriesToExpose.len

  if totalfiles == 0:
    raise newException(ValueError, "You gave me no files to index (nothing contained)")

  var moduleName = ""
  let ifo = resman["module.ifo"]
  if ifo.isSome:
    let rr = ifo.get()
    rr.seek()
    let g = readGffRoot(rr.io(), false)
    let nm = g["Mod_Name", GffCExoLocString].entries
    if nm.hasKey(0):
      moduleName = nm[0]
      info "Module name: ", moduleName

  info "Reading existing data in storage"
  var writtenHashes = getFilesInStorage(rootDirectory)

  info "Calculating complete manifest size"
  let totalbytes = entriesToExpose.mapIt(resman[it].get().len).sum()
  info "Generating data for ", totalfiles, " resrefs, ",
    formatSize(totalbytes), " (This might take a while, we need to checksum it all)"

  let manifest = newManifest()

  var dedupbytes: BiggestInt = 0
  var diskbytes: BiggestInt = 0

  for idx, resRef in entriesToExpose:
    let res = resman[resRef].get()
    let size = res.len

    let data = res.readAll(useCache=false)
    let sha1 = secureHash(data)
    let sha1str = toLowerAscii($sha1)

    manifest.entries.add ManifestEntry(sha1: sha1str, size: uint32 size, resref: resRef)

    let alreadyWrittenOut = writtenHashes.contains(sha1str)

    let divisor = (entriesToExpose.len / 100)
    let percent = if divisor > 0: $(clamp(int round(idx.float / divisor), 0, 100)) else: "??"
    let percentPrefix = "[" & percent & "%] "

    if alreadyWrittenOut:
      dedupbytes += size
      debug percentPrefix, "Exists: ", sha1str, " (", $resRef, ")"

    else:
      # Not in storage yet, write it to disk.
      let path = pathForEntry(manifest, rootDirectory, sha1str, true)

      info percentPrefix, "Writing: ", path, " (", $resRef, ")"

      let outstr = newFilestream(path, fmWrite)

      case compressWith
      of CompressionType.Zlib:
        # compressedbuffer header
        outstr.write("NSYC")                           # magic
        outstr.write(uint32 3)                         # version
        outstr.write(uint32 1)                         # cp1=zlib
        outstr.write(uint32 data.len)                  # uncompressedSize
        # zlib header
        outstr.write(uint32 1)                         # version
        # payload
        outstr.write(compress(data, Z_DEFAULT_COMPRESSION, ZLIB_STREAM))
      of CompressionType.None:
        # raw file is fastest
        outstr.write(data)

      outstr.close()

    let path = pathForEntry(manifest, rootDirectory, sha1str, true)
    diskbytes += getFileSize(path)

  doAssert(manifest.entries.len == totalfiles)

  info "Writing new binary manifest"
  let strim = newStringStream()
  writeManifest(strim, manifest)
  strim.setPosition(0)
  let newManifestData = strim.readAll()
  let newManifestSha1 = toLowerAscii($secureHash(newManifestData))

  if updateLatest:
    if fileExists(rootDirectory / "latest"):
      info "Updating `latest` to point to ", newManifestSha1
    writefile(rootDirectory / "latest", newManifestSha1)

  writeFile(rootDirectory / "manifests" / newManifestSha1, newManifestData)

  var jdata = %*{
    "version": %int manifest.version,
    "sha1": %newManifestSha1,
    "hash_tree_depth": %int manifest.hashTreeDepth,
    "module_name": moduleName,
    "includes_module_contents": withModuleContents,
    "total_files": totalfiles,
    "total_bytes": totalbytes,
    "on_disk_bytes": diskbytes,
    "created": %int epochTime()
  }

  for pair in additionalMeta:
    jdata[pair[0]] = %pair[1]

  let retinfo = pretty(jdata) & "\c\L"

  writeFile(rootDirectory / "manifests" / newManifestSha1 & ".json", retinfo)

  info "Reindex done, manifest version ", manifest.version, " written: ", newManifestSha1
  info "Manifest contains ", formatsize(totalbytes), " in ", totalfiles, " files"
  info "We wrote ", formatSize(totalbytes - dedupbytes), " of new data"

  result = retinfo
