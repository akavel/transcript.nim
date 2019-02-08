{.experimental: "codeReordering".}
import unittest
import strutils
import streams
import transcript

const script = """
# simple comment -> foobar 00 01 02 03
<-
2f 6e 69 78 2f 73 74 6f 72 65 2f 67 32 79 6b 35   # /nix/store/g2yk5 |
34 68 69 66 71 6c 73 6a 69 68 61 33 73 7a 72 34   # 4hifqlsjiha3szr4 |
71 33 63 63 6d 64 7a 79 72 64 76 2d 67 6c 69 62   # q3ccmdzyrdv-glib |
63 2d 32 2e 32 37 00 00                           # c-2.27..         |

# 1463  write(1, "\313\356RT\0\0\0\0\4\2\0\0\0\0\0\0", 16) = 16
-> # 0s  16 bytes
cb ee 52 54 00 00 00 00 04 02 00 00 00 00 00 00   # ..RT............ |

# 1463  read(0, "\353\235\f9\0\0\0\0\4\2\0\0\0\0\0\0", 8192) = 16
<- # 0s  16 bytes
eb 9d 0c 39 00 00 00 00 04 02 00 00 00 00 00 00   # ...9............ |
"""

test "simple session, arrow-style, with comments":
  let session = transcript(script)
  check session.readAll().toHex == strip_space"""
2f 6e 69 78 2f 73 74 6f 72 65 2f 67 32 79 6b 35
34 68 69 66 71 6c 73 6a 69 68 61 33 73 7a 72 34
71 33 63 63 6d 64 7a 79 72 64 76 2d 67 6c 69 62
63 2d 32 2e 32 37 00 00"""
  session.write(strip_space"""
cb ee 52 54 00 00 00 00 04 02 00 00 00 00 00 00""".parseHexStr)
  check session.readAll().toHex == strip_space"""
eb 9d 0c 39 00 00 00 00 04 02 00 00 00 00 00 00"""

test "partial read & write":
  let session = transcript(script)
  check session.atEnd.not
  check session.readStr(4) == "/nix"
  check session.readAll() == "/store/g2yk54hifqlsjiha3szr4q3ccmdzyrdv-glibc-2.27\x00\x00"
  session.write("cb ee 52 54".strip_space.parseHexStr)
  session.write("00 00 00 00 04 02 00 00 00 00 00 00".strip_space.parseHexStr)
  check session.readAll().toHex == strip_space"""
eb 9d 0c 39 00 00 00 00 04 02 00 00 00 00 00 00"""
  check session.atEnd

test "exception on bad byte write":
  let session = transcript(script)
  discard session.readAll()
  session.write("cb ee 52 54".strip_space.parseHexStr)
  expect TranscriptError:
    session.write("00 01".strip_space.parseHexStr)

test "exception on write instead of read":
  let session = transcript(script)
  expect TranscriptError:
    session.write("cb ee 52 54".strip_space.parseHexStr)

test "read EOFs when ended":
  skip

proc strip_space(s: string): string =
  return s.multiReplace(("\n", ""), (" ", "")).toUpper
