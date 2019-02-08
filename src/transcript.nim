{.experimental: "codeReordering".}
import streams
import strutils

type
  TranscriptStream* = ref object of Stream
    script: Stream
    dir: Direction
    unfetchB: char
    unfetchDir: Direction
  TranscriptError* = object of CatchableError
  # TODO(akavel): use variant type instead of (Direction, char) pair - here and in `unfetch`
  Direction = enum
    EOF
    Read
    Write

proc transcript*(script: string): TranscriptStream =
  return transcript(newStringStream(script))

proc transcript*(script: Stream): TranscriptStream =
  result = new(TranscriptStream)
  result.script = script
  result.unfetchDir = EOF
  # result.closeImpl = scriptClose
  result.readDataImpl = scriptReadData
  result.writeDataImpl = scriptWriteData
  result.flushImpl = proc(s: Stream) = discard

proc scriptReadData(s: Stream; buffer: pointer; bufLen: int): int =
  let t = TranscriptStream(s)
  var temp = ""
  for i in 0..<bufLen:
    let (dir, b) = t.fetchByte()
    if dir != Read:
      t.unfetchB = b
      t.unfetchDir = dir
      if i > 0:
        copyMem(buffer, temp[0].addr, i)
      return i
    temp.add(b)
  if bufLen > 0:
    copyMem(buffer, temp[0].addr, bufLen)
  return bufLen

proc scriptWriteData(s: Stream; buffer: pointer; bufLen: int) =
  let t = TranscriptStream(s)
  var temp = newString(bufLen)
  copyMem(temp[0].addr, buffer, bufLen)
  for i in 0..<bufLen:
    let (dir, b) = t.fetchByte()
    if dir != Write:
      raise newException(TranscriptError, "transcript has $#, but a write was attempted" % $dir)
    if b != temp[i]:
      raise newException(TranscriptError, "transcript has Write of 0x$#, but a write of 0x$# was attempted" % [toHex($b), toHex($temp[i])])

# proc scriptClose(s: Stream) =
#   let t = TranscriptStream(s)
#   let (dir, b) = t.fetchByte()
#   if dir != EOF:
#     raise newException(Exception, "transcript has $# of 0x$#, but a close was attempted" % [$dir, toHex($b)])

proc fetchByte(t: TranscriptStream): (Direction, char) =
  if t.unfetchDir != EOF:
    result = (t.unfetchDir, t.unfetchB)
    t.unfetchDir = EOF
    return
  var buf = ""
  while true:
    case (let b = t.script.readChar(); b)
    of hexDigit:
      if buf == "":
        buf.add(b)
        continue
      elif buf.len == 1 and buf[0] in hexDigit:
        return (t.dir, chr(buf[0].nibble * 0x10 + buf[1].nibble))
      else:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
    of '#':
      discard t.script.readLine()
    of ' ', '\n', '\r', '\t':
      discard
    of '-', '<', '>':
      if buf == "" and b in {'<', '-'}:
        buf.add(b)
        continue
      elif buf == "<" and b == '-':
        buf = ""
        t.dir = Read
        continue
      elif buf == "-" and b == '>':
        buf = ""
        t.dir = Write
        continue
      elif buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
      else:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $b)
    of '\0':  # EOF
      if buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
      t.dir = EOF
      return (EOF, '\0')
    else:
      raise newException(CatchableError, "unexpected '$#' character in transcript" % $b)

const hexDigit = {'0'..'9', 'a'..'f', 'A'..'F'}

func nibble(ch: char): int =
  case ch
  of '0'..'9': return ord(ch) - ord('0')
  of 'a'..'f': return ord(ch) - ord('a') + 10
  of 'A'..'F': return ord(ch) - ord('A') + 10
  else:        raise newException(Defect, "nibble(0x$#)" % ch.int.toHex)

