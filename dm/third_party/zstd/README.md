# zstd (decoder)

The decoder part of [Zstandard](https://github.com/facebook/zstd) 1.5.6: `lib/zstd.h`, `lib/zstd_errors.h`, `lib/common/` and `lib/decompress/` without `huf_decompress_amd64.S` (the app is arm64 only). Unmodified. The iOS app compiles it (`dm/ios/project.yml`) for the game import, which reads the zstd-compressed sections of NCZ / XCZ dumps (`dm/ios/Sources/importer.c`). License: BSD, [LICENSE](LICENSE).
