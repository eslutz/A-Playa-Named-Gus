import Foundation

/// Jellyfin's progressive muxer uses hev1 for copied HEVC. Apple requires hvc1.
/// AVAssetExportSession passthrough preserves the incompatible tag, so update only
/// the sample-entry metadata; the encoded media and every file offset stay intact.
enum OfflineMP4Compatibility {
    static func normalizeHEVCTag(in url: URL) throws {
        let file = try FileHandle(forUpdating: url)
        defer { try? file.close() }
        let length = try file.seekToEnd()
        var offset: UInt64 = 0
        while offset + 8 <= length {
            try file.seek(toOffset: offset)
            guard let header = try file.read(upToCount: 8), header.count == 8 else { throw corruptFile() }
            var size = integer(header, at: 0, count: 4)
            let tag = String(decoding: header[4 ..< 8], as: UTF8.self)
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let extended = try file.read(upToCount: 8), extended.count == 8 else { throw corruptFile() }
                size = integer(extended, at: 0, count: 8)
                headerSize = 16
            } else if size == 0 {
                size = length - offset
            }
            guard size >= headerSize, size <= length - offset else { throw corruptFile() }
            if tag == "moov" {
                // Bound metadata allocation independently of the media file size.
                guard size <= 32 * 1024 * 1024 else { throw corruptFile() }
                try file.seek(toOffset: offset)
                guard let metadata = try file.read(upToCount: Int(size)), metadata.count == Int(size) else { throw corruptFile() }
                let patches = try hev1Entries(in: metadata, range: 0 ..< metadata.count)
                for patch in patches {
                    try file.seek(toOffset: offset + UInt64(patch))
                    try file.write(contentsOf: Data(AVPlayerContainerCompatibility.nativeHEVCTag.utf8))
                }
                if !patches.isEmpty {
                    try file.synchronize()
                }
                return
            }
            offset += size
        }
        throw corruptFile()
    }

    private struct Box {
        var offset: Int
        var payload: Int
        var end: Int
        var tag: String
    }

    private static func boxes(in data: Data, range: Range<Int>) throws -> [Box] {
        var result: [Box] = []
        var offset = range.lowerBound
        while offset < range.upperBound {
            guard range.upperBound - offset >= 8 else { throw corruptFile() }
            var size = integer(data, at: offset, count: 4)
            let tag = String(decoding: data[offset + 4 ..< offset + 8], as: UTF8.self)
            var header = 8
            if size == 1 {
                guard range.upperBound - offset >= 16 else { throw corruptFile() }
                size = integer(data, at: offset + 8, count: 8)
                header = 16
            } else if size == 0 {
                size = UInt64(range.upperBound - offset)
            }
            guard size >= UInt64(header), size <= UInt64(range.upperBound - offset) else { throw corruptFile() }
            let end = offset + Int(size)
            result.append(Box(offset: offset, payload: offset + header, end: end, tag: tag))
            offset = end
        }
        return result
    }

    private static func hev1Entries(in data: Data, range: Range<Int>, depth: Int = 0) throws -> [Int] {
        guard depth < 16 else { throw corruptFile() }
        var patches: [Int] = []
        for box in try boxes(in: data, range: range) {
            if ["moov", "trak", "mdia", "minf", "stbl"].contains(box.tag) {
                patches += try hev1Entries(in: data, range: box.payload ..< box.end, depth: depth + 1)
            } else if box.tag == "stsd" {
                guard box.end - box.payload >= 8 else { throw corruptFile() }
                let entries = try boxes(in: data, range: box.payload + 8 ..< box.end)
                guard UInt64(entries.count) == integer(data, at: box.payload + 4, count: 4) else { throw corruptFile() }
                for entry in entries where AVPlayerContainerCompatibility.requiresHEVCRemux(codecTag: entry.tag) {
                    // A visual sample entry has 78 bytes before its codec boxes.
                    guard entry.end - entry.payload >= 78 else { throw corruptFile() }
                    let children = try boxes(in: data, range: entry.payload + 78 ..< entry.end)
                    guard let configuration = children.first(where: { $0.tag == "hvcC" }), configuration.end - configuration.payload >= 23 else { throw corruptFile() }
                    try validateParameterSets(data, range: configuration.payload ..< configuration.end)
                    patches.append(entry.offset + 4)
                }
            }
        }
        return patches
    }

    private static func validateParameterSets(_ data: Data, range: Range<Int>) throws {
        guard data[range.lowerBound] == 1 else { throw corruptFile() }
        var cursor = range.lowerBound + 23
        var types: Set<UInt8> = []
        for _ in 0 ..< Int(data[range.lowerBound + 22]) {
            guard range.upperBound - cursor >= 3 else { throw corruptFile() }
            let type = data[cursor] & 0x3F
            let count = integer(data, at: cursor + 1, count: 2)
            cursor += 3
            for _ in 0 ..< count {
                guard range.upperBound - cursor >= 2 else { throw corruptFile() }
                let length = integer(data, at: cursor, count: 2)
                cursor += 2
                guard length > 0, length <= UInt64(range.upperBound - cursor) else { throw corruptFile() }
                cursor += Int(length)
            }
            if count > 0 {
                types.insert(type)
            }
        }
        guard types.isSuperset(of: [32, 33, 34]), cursor == range.upperBound else { throw corruptFile() }
    }

    private static func integer(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        data[offset ..< offset + count].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func corruptFile() -> CocoaError {
        CocoaError(.fileReadCorruptFile)
    }
}
