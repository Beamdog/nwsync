import options, logging, critbits, std/sha1, strutils, sequtils,
  os, ospaths, algorithm, math, times, json, sets, tables

import neverwinter/erf, neverwinter/resfile, neverwinter/resdir,
  neverwinter/gff, neverwinter/resman, neverwinter/key,
  neverwinter/compressedbuf

import libmanifest
import libshared
import libversion

type Limits* = tuple
  fileSize: uint64

let GobalResTypeSkipList = [getResType("nss")]

proc allowedToExpose(it: ResRef): bool =
  not GobalResTypeSkipList.contains(it.resType)

proc readAndRewrite(res: Res): string =
  var data = res.readAll(useCache=false)

  if toLowerAscii($res.resRef) == "module.ifo":
    info "Rewriting module.ifo to strip all HAKs"
    let ifo = readGffRoot(newStringStream(data), false)
    ifo.del("Mod_HakList")
    let outstr = newStringStream()
    write(outstr, ifo)
    outstr.setPosition(0)
    data = outstr.readAll()

  return data

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
    compressWith: Algorithm,
    updateLatest: bool,
    additionalStringMeta: openArray[(string, string)],
    additionalIntMeta: openArray[(string, int)],
    limits: Limits,
    writeOrigins: bool): string =
  ## Reindexes the given module.

  if not dirExists(rootDirectory):
    abort "Target sync directory does not exist."

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

  var filesTooBig = newSeq[(string, uint64)]()
  for r in entriesToExpose:
    let rr = resman[r].get()
    let sz = rr.len().uint64
    if sz > limits.fileSize:
      filesTooBig.add(($rr, sz))
  for ftb in filesTooBig:
    error ftb[0], " exceeds configured file limit: ",
      formatSize(ftb[1].int64), " > ", formatSize(limits.fileSize.int64)
  if filesTooBig.len > 0: quit(1)

  var moduleName = ""
  var moduleDescription = ""
  let ifo = resman["module.ifo"]
  if ifo.isSome:
    let rr = ifo.get()
    rr.seek()
    let g = readGffRoot(rr.io(), false)
    let nm = g["Mod_Name", GffCExoLocString].entries
    if nm.hasKey(0):
      moduleName = nm[0]
      info "Module name: ", moduleName

    let dm = g["Mod_Description", GffCExoLocString].entries
    if dm.hasKey(0):
      moduleDescription = dm[0]

  var writtenHashes: CritBitTree[string]
  if forceWriteIfExists:
    info "Rewirting all data unconditionally"
  else:
    info "Reading existing data in storage"
    writtenHashes = getFilesInStorage(rootDirectory)

  info "Calculating complete manifest size"
  let totalbytes: int64 = entriesToExpose.mapIt(int64 resman[it].get().len).sum()
  info "Generating data for ", totalfiles, " resrefs, ",
    formatSize(totalbytes), " (This might take a while, we need to checksum it all)"

  let manifest = newManifest()

  var dedupbytes: int64 = 0
  var diskbytes: int64 = 0

  var origins = initTable[string, seq[string]]()

  for idx, resRef in entriesToExpose:
    let res = resman[resRef].get()
    if not origins.hasKey($res.origin):
      origins[$res.origin] = newSeq[string]()
    origins[$res.origin].add($resRef)
    let size = res.len

    let data = readAndRewrite(res)
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
      compress(outstr, data, compressWith, makeMagic("NSYC"))
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

  if writeOrigins:
    info "Writing origin metadata"
    let originmeta = newFileStream(rootDirectory / "manifests" / newManifestSha1 & ".origin", fmWrite)
    for origin, entries in origins:
      originmeta.write(origin, "\n")
      for entry in sorted(entries):
        originmeta.write("\t", entry, "\n")
    originmeta.close()

  if updateLatest:
    if fileExists(rootDirectory / "latest"):
      info "Updating `latest` to point to ", newManifestSha1
    else:
      info "Repository has no `latest`, not creating."
    writefile(rootDirectory / "latest", newManifestSha1)

  writeFile(rootDirectory / "manifests" / newManifestSha1, newManifestData)

  var jdata = %*{
    "version": %int manifest.version,
    "sha1": %newManifestSha1,
    "hash_tree_depth": %int manifest.hashTreeDepth,
    "module_name": moduleName,
    "description": moduleDescription,
    "includes_module_contents": withModuleContents,
    "total_files": totalfiles,
    "total_bytes": totalbytes,
    "on_disk_bytes": diskbytes,
    "created": %int epochTime(),
    "created_with": "nwsync.nim " & VersionString
  }

  for pair in additionalStringMeta:
    if pair[1] != "": jdata[pair[0]] = %pair[1]

  for pair in additionalIntMeta:
    if pair[1] != 0: jdata[pair[0]] = %pair[1]

  let retinfo = pretty(jdata) & "\c\L"

  writeFile(rootDirectory / "manifests" / newManifestSha1 & ".json", retinfo)

  info "Reindex done, manifest version ", manifest.version, " written: ", newManifestSha1
  info "Manifest contains ", formatsize(totalbytes), " in ", totalfiles, " files"
  info "We wrote ", formatSize(totalbytes - dedupbytes), " of new data"

  result = retinfo
