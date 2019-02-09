{.experimental: "codeReordering".}
import streams
import strutils
import deques

type
  TranscriptStream* = ref object of Stream
    reads: string
    writes: string
    rPos, wPos: int
    barriers: Barriers
  TranscriptError* = object of CatchableError

  Barriers = Deque[tuple[w: int, r: int]]
  Direction = enum
    EOF
    Read
    Write
  # Substring = distinct string

proc transcript*(script: string): TranscriptStream =
  return transcript(newStringStream(script))

proc transcript*(script: Stream): TranscriptStream =
  result = new(TranscriptStream)
  result.barriers = initDeque[(int, int)]()
  parse(script, result.reads, result.writes, result.barriers)
  result.atEndImpl = scriptAtEnd
  result.readDataImpl = scriptReadData
  result.writeDataImpl = scriptWriteData
  result.flushImpl = proc(s: Stream) = discard

proc endPos(t: TranscriptStream): int =
  while t.barriers.len > 0 and t.wPos >= t.barriers.peekFirst.w:
    t.barriers.popFirst()
  if t.barriers.len > 0:
    return t.barriers.peekFirst.r
  else:
    return t.reads.len

proc scriptAtEnd(s: Stream): bool =
  let t = TranscriptStream(s)
  return t.rPos >= t.endPos

proc scriptReadData(s: Stream; buffer: pointer; bufLen: int): int =
  let t = TranscriptStream(s)
  if t.atEnd or bufLen == 0:
    return 0
  result = min(t.endPos - t.rPos, bufLen)
  copyMem(buffer, t.reads[t.rPos].addr, result)
  t.rPos += result

proc scriptWriteData(s: Stream; buffer: pointer; bufLen: int) =
  var temp = newString(bufLen)
  copyMem(temp[0].addr, buffer, bufLen)
  let t = TranscriptStream(s)
  if t.wPos >= t.writes.len:
    raise newException(TranscriptError, "transcript contains EOF, but a write 0x$# was attempted" % [toHex(temp)])
  if bufLen == 0:
    return
  # Compare buffer with bytes from 'w'
  let master = t.writes.substr(t.wPos, t.wPos+temp.len-1)
  if master != temp:
    raise newException(TranscriptError, "transcript contains Write 0x$#, but a write 0x$# was attempted" % [toHex(master), toHex(temp)])
  t.wPos += temp.len

proc parse(s: Stream, reads: var string, writes: var string, barriers: var Barriers) =
  var
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
        of Read:  reads.add(ch)
        of Write: writes.add(ch)
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
        if dir == Write:
          # Until this write position is passed, only so many bytes can be read from transcript
          barriers.addLast((w: writes.len, r: reads.len))
        dir = Read
        continue
      elif buf == "<" and b == '-':
        buf = ""
        dir = Write
        continue
      elif buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
      else:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $b)
    of '\0':  # EOF
      if buf.len == 1:
        raise newException(CatchableError, "unexpected '$#' character in transcript" % $buf[0])
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

