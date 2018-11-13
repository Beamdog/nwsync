import db_sqlite
import sequtils
import sqlite3

type
  DbValueKind* = enum
    dvkInt
    dvkFloat
    dvkString
    dvkBlob
    dvkNull

  DbValue* = object
    case kind *: DbValueKind
    of dvkInt:
      i*: int64
    of dvkFloat:
      f*: float
    of dvkString:
      s*: string
    of dvkBlob:
      b*: string
    of dvkNull:
      discard

proc dbValue*(v: int):     DbValue = DbValue(kind: dvkInt,   i: v.int64)
proc dbValue*(v: int32):   DbValue = DbValue(kind: dvkInt,   i: v.int64)
proc dbValue*(v: int64):   DbValue = DbValue(kind: dvkInt,   i: v)
proc dbValue*(v: float):   DbValue = DbValue(kind: dvkFloat, f: v)
proc dbValue*(v: DbValue): DbValue = v

proc dbValue*(v: string): DbValue =
  if v.isNil:
    DbValue(kind: dvkNull)
  else:
    DbValue(kind: dvkString, s: v)

proc dbBlob*(v: string): DbValue =
  if v.isNil:
    DbValue(kind: dvkNull)
  else:
    DbValue(kind: dvkBlob, b: v)

proc bindVal(db: DbConn, stmt: sqlite3.Pstmt, idx: int32, value: DbValue): int32 =
  case value.kind:
  of dvkInt:
    bind_int64(stmt, idx, value.i)
  of dvkFloat:
    bind_double(stmt, idx, value.f)
  of dvkString:
    bind_text(stmt, idx, value.s.cstring, value.s.len.int32, SQLITE_TRANSIENT)
  of dvkBlob:
    bind_blob(stmt, idx, value.b.cstring, value.b.len.int32, SQLITE_TRANSIENT)
  of dvkNull:
    bind_null(stmt, idx)

proc setupQueryEx(db: DbConn, query: SqlQuery, args: seq[DbValue]): Pstmt =
  var idx: int32 = 0
  var stmt: sqlite3.Pstmt
  var rc = prepare_v2(db, query.cstring, query.string.len.cint, stmt, nil)
  if rc != SQLITE_OK:
    dbError(db)
  for arg in args:
    inc idx
    rc = db.bindVal(stmt, idx, arg)
    if rc != SQLITE_OK:
      dbError(db)
  return stmt

proc newRow(L: int): Row =
  newSeq(result, L)
  for i in 0..L-1: result[i] = ""

proc setRow(stmt: Pstmt, r: var Row, cols: cint) =
  for col in 0..cols-1:
    setLen(r[col], column_bytes(stmt, col)) # set capacity
    setLen(r[col], 0)
    let x = column_text(stmt, col)
    if not isNil(x): add(r[col], x)

proc execEx*(db: DbConn, query: SqlQuery, args: varargs[DbValue, dbValue])  {.
  tags: [ReadDbEffect, WriteDbEffect].} =
  ## executes the query and raises DbError if not successful.
  let stmt = db.setupQueryEx(query, @args)
  if step(stmt) != SQLITE_DONE:
    dbError(db)
  if finalize(stmt) != SQLITE_OK:
    dbError(db)

iterator fastRowsEx*(db: DbConn, query: SqlQuery,
                     args: varargs[DbValue, dbValue]): Row {.
  tags: [ReadDbEffect].} =
  ## Executes the query and iterates over the result dataset.
  ##
  ## This is very fast, but potentially dangerous.  Use this iterator only
  ## if you require **ALL** the rows.
  ##
  ## Breaking the fastRows() iterator during a loop will cause the next
  ## database query to raise a DbError exception ``unable to close due to ...``.
  var stmt = setupQueryEx(db, query, @args)
  var L = (column_count(stmt))
  var result = newRow(L)
  while step(stmt) == SQLITE_ROW:
    setRow(stmt, result, L)
    yield result
  if finalize(stmt) != SQLITE_OK: dbError(db)
