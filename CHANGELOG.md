## 0.6.0-dev

- Improve error messages when reading a tar entry after, or during, a call to
  `moveNext()`.

## 0.5.2

- This package now supports being compiled to JavaScript.

## 0.5.1

- Improve performance when reading large archives

## 0.5.0

- Support sync encoding with `tarConverter`.

## 0.4.0

- Support generating tar files with GNU-style long link names
 - Add `format` parameter to `tarWritingSink` and `tarWriterWith`

## 0.3.3

- Drop `chunked_stream` dependency in favor of `package:async`.

## 0.3.2

- Allow arbitrarily many zero bytes at the end of an archive when
  `disallowTrailingData` is enabled.

## 0.3.1

- Add `disallowTrailingData` parameter to `TarReader`. When the option is set,
  `readNext` will ensure that the input stream does not emit further data after
  the tar archive has been read fully.

## 0.3.0

- Remove outdated references in the documentation

## 0.3.0-nullsafety.0

- Remove `TarReader.contents` and `TarReader.header`. Use `current.contents` and `current.header`, respectively.
- Fix some minor implementation details

## 0.2.0-nullsafety

Most of the tar package has been rewritten, it's now based on the
implementation written by [Garett Tok Ern Liang](https://github.com/walnutdust)
in the GSoC 2020.

- Added `tar` prefix to exported symbols.
- Remove `MemoryEntry`. Use `TarEntry.data` to create a tar entry from bytes.
- Make `WritingSink` private. Use `tarWritingSink` to create a general `StreamSink<tar.Entry>`.
- `TarReader` is now a [`StreamIterator`](https://api.dart.dev/stable/2.10.4/dart-async/StreamIterator-class.html),
  the transformer had some design flaws.

## 0.1.0-nullsafety.1

- Support writing user and group names
- Better support for PAX-headers and large files

## 0.1.0-nullsafety.0

- Initial version
