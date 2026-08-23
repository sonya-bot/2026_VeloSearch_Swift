import Foundation

enum StoredZIPWriter {
  private struct Entry {
    let nameData: Data
    let crc32: UInt32
    let size: UInt32
    let offset: UInt32
  }

  static func write(files: [URL], to destination: URL) throws {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }

    var currentOffset: UInt32 = 0
    var entries: [Entry] = []

    for file in files {
      let nameData = Data(file.lastPathComponent.utf8)
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
      guard fileSize <= UInt32.max, nameData.count <= UInt16.max else {
        throw RecordingFileStoreError.archiveTooLarge
      }
      let size = UInt32(fileSize)
      let checksum = try crc32(file)

      var header = Data()
      appendUInt32(0x0403_4b50, to: &header)
      appendUInt16(20, to: &header)
      appendUInt16(0x0800, to: &header)  // UTF-8 file name
      appendUInt16(0, to: &header)  // Stored (no compression)
      appendUInt16(0, to: &header)
      appendUInt16(0, to: &header)
      appendUInt32(checksum, to: &header)
      appendUInt32(size, to: &header)
      appendUInt32(size, to: &header)
      appendUInt16(UInt16(nameData.count), to: &header)
      appendUInt16(0, to: &header)
      header.append(nameData)
      try output.write(contentsOf: header)

      let input = try FileHandle(forReadingFrom: file)
      while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
        try output.write(contentsOf: chunk)
      }
      try input.close()

      entries.append(Entry(nameData: nameData, crc32: checksum, size: size, offset: currentOffset))
      let nextOffset = UInt64(currentOffset) + UInt64(header.count) + UInt64(size)
      guard nextOffset <= UInt32.max else { throw RecordingFileStoreError.archiveTooLarge }
      currentOffset = UInt32(nextOffset)
    }

    guard entries.count <= UInt16.max else { throw RecordingFileStoreError.archiveTooLarge }
    let centralDirectoryOffset = currentOffset
    var centralDirectory = Data()
    for entry in entries {
      appendUInt32(0x0201_4b50, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(20, to: &centralDirectory)
      appendUInt16(0x0800, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(entry.crc32, to: &centralDirectory)
      appendUInt32(entry.size, to: &centralDirectory)
      appendUInt32(entry.size, to: &centralDirectory)
      appendUInt16(UInt16(entry.nameData.count), to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt16(0, to: &centralDirectory)
      appendUInt32(0, to: &centralDirectory)
      appendUInt32(entry.offset, to: &centralDirectory)
      centralDirectory.append(entry.nameData)
    }

    try output.write(contentsOf: centralDirectory)
    var footer = Data()
    appendUInt32(0x0605_4b50, to: &footer)
    appendUInt16(0, to: &footer)
    appendUInt16(0, to: &footer)
    appendUInt16(UInt16(entries.count), to: &footer)
    appendUInt16(UInt16(entries.count), to: &footer)
    appendUInt32(UInt32(centralDirectory.count), to: &footer)
    appendUInt32(centralDirectoryOffset, to: &footer)
    appendUInt16(0, to: &footer)
    try output.write(contentsOf: footer)
  }

  private static func crc32(_ file: URL) throws -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    let input = try FileHandle(forReadingFrom: file)
    while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
      for byte in chunk {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
          crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb8_8320 : 0)
        }
      }
    }
    try input.close()
    return crc ^ 0xffff_ffff
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
  }

  private static func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }
}
