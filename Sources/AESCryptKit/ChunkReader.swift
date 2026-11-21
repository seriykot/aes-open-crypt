import Foundation

/// The read side of the encrypt path.
///
/// `FileHandle` is the only production implementation; the protocol exists so
/// tests can inject reads that fail part way through a file.
protocol ChunkReader: AnyObject {
    func read(upToCount count: Int) throws -> Data?
    func seekToEnd() throws -> UInt64
    func seek(toOffset offset: UInt64) throws
}

extension FileHandle: ChunkReader {}
