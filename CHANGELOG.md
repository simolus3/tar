## 0.2.0-dev

- Remove `MemoryEntry`. Use `Entry.data` to create a tar entry from bytes.
- Make `WritingSink` private. Use `createWritingSink` to create a general `StreamSink<tar.Entry>`.
- Make `Reader` private. Use `createReader` to create a custom tar reader.

## 0.1.0-nullsafety.1

- Support writing user and group names
- Better support for PAX-headers and large files

## 0.1.0-nullsafety.0

- Initial version
