{.experimental: "codeReordering".}
import streams
import strutils
import deques

type
  TranscriptStream* = ref object of Stream
    script: Deque[(string, string)]  # (read, write)
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
  result.script = initDeque[(string, string)]()
  parse(script, result.script)
  result.atEndImpl = scriptAtEnd
  result.readDataImpl = scriptReadData
  result.writeDataImpl = scriptWriteData
  result.flushImpl = proc(s: Stream) = discard

proc scriptAtEnd(s: Stream): bool =
  let t = TranscriptStream(s)
  if t.script.len == 0:
    return true
  let (r, w) = t.script.peekFirst
  if r == "" and w == "":
    return true
  return false

proc scriptReadData(s: Stream; buffer: pointer; bufLen: int): int =
  let t = TranscriptStream(s)
  if t.script.len == 0 or bufLen == 0:
    return 0
  var (r, w) = t.script.peekFirst
  if r == "" and w == "":
    discard t.script.popFirst()
    return t.readData(buffer, bufLen)
  if r == "":
    return 0
  # Copy bytes from 'r'
  result = min(r.len, bufLen)
  copyMem(buffer, r[0].addr, result)
  discard t.script.popFirst
  let newr = r.substr(result)
  if newr != "" and w != "":
    t.script.addFirst((r.substr(result), w))

proc scriptWriteData(s: Stream; buffer: pointer; bufLen: int) =
  var temp = newString(bufLen)
  copyMem(temp[0].addr, buffer, bufLen)
  let t = TranscriptStream(s)
  if t.script.len == 0:
    raise newException(TranscriptError, "transcript contains EOF, but a write 0x$# was attempted" % [toHex(temp)])
  let (r, w) = t.script.peekFirst
  # Compare buffer with bytes from 'w'
  if not w.startsWith(temp):
    raise newException(TranscriptError, "transcript contains Write 0x$#, but a write 0x$# was attempted" % [toHex(w), toHex(temp)])
  discard t.script.popFirst
  let neww = w.substr(temp.len)
  if r != "" or neww != "":
    t.script.addFirst((r, neww))

proc parse(s: Stream, d: var Deque[(string, string)]) =
  var
    read = ""
    write = ""
    buf = ""
    dir = EOF
  while true:
    case (let b = s.readChar(); b)
    of hexDigit:
      if buf == "":
        buf.add(b)
        continue
      elif buf.len == 1 and buf[0] in hexDigit:
        # Add a hex digit to current script
        let ch = chr(buf[0].nibble * 0x10 + b.nibble)
        case dir
        of Read:  read.add(ch)
        of Write: write.add(ch)
        of EOF:   raise newException(CatchableError, "no initial direction specified in transcript")
        buf = ""
      else:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
    of '#':
      discard s.readLine()
    of ' ', '\n', '\r', '\t':
      discard
    of '-', '<', '>':
      if buf == "" and b in {'<', '-'}:
        buf.add(b)
        continue
      elif buf == "-" and b == '>':
        buf = ""
        # Switch direction to Read
        case dir
        of Read, EOF: discard
        of Write:
          if write != "":
            d.addLast((read, write))
            read = ""
            write = ""
        dir = Read
        continue
      elif buf == "<" and b == '-':
        buf = ""
        # Switch direction to Write
        dir = Write
        continue
      elif buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
      else:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $b)
    of '\0':  # EOF
      if buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
      if read != "" or write != "":
        d.addLast((read, write))
      return
    else:
      raise newException(CatchableError, "unexpected '$#' character in transcript" % $b)

const hexDigit = {'0'..'9', 'a'..'f', 'A'..'F'}

func nibble(ch: char): int =
  case ch
  of '0'..'9': return ord(ch) - ord('0')
  of 'a'..'f': return ord(ch) - ord('a') + 10
  of 'A'..'F': return ord(ch) - ord('A') + 10
  else:        raise newException(Defect, "nibble(0x$#)" % ch.int.toHex)

