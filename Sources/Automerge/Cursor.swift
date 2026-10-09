import enum AutomergeUniffi.Position

typealias FfiPosition = AutomergeUniffi.Position

/// A opaque type that represents a stable location of the character following the location reference at creation within an array or text object that adjusts with insertions and deletions to
/// maintain its relative position.
///
/// Create a cursor using ``Document/cursor(obj:position:)``, or ``Document/cursor(obj:position:heads:)`` to place a
/// cursor at the point in time indicated by the `heads` parameter.
/// Retrieve the position of the cursor reference from the document using ``Document/position(obj:cursor:)``, or use
/// ``Document/position(obj:cursor:heads:)`` to get the position at a previous point in time.
public struct Cursor: Equatable, Hashable, Sendable {
    var bytes: [UInt8]

    /// Reconstruct a cursor from the opaque bytes `description`/`bytesValue`
    /// encodes. Declared here (not in an extension) so it replaces the
    /// synthesized memberwise init rather than colliding with it, and so the
    /// opaque bytes can be rebuilt across clients to resolve a shared location
    /// with ``Document/position(obj:cursor:)`` — e.g. a collaborator's caret
    /// (holos SPA-3893). The bytes are opaque; pass exactly what `description`
    /// (or `bytesValue`) produced.
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

extension Cursor: CustomStringConvertible {
    /// The bytes that describe the cursor.
    public var description: String {
        bytes.map { Swift.String(format: "%02hhx", $0) }.joined().uppercased()
    }
}

public extension Cursor {
    /// Reconstruct a cursor from its `description` hex string (case-insensitive).
    /// Returns nil if the string is not an even-length run of hex digits.
    init?(_ hexDescription: String) {
        guard hexDescription.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexDescription.count / 2)
        var index = hexDescription.startIndex
        while index < hexDescription.endIndex {
            let next = hexDescription.index(index, offsetBy: 2)
            guard let byte = UInt8(hexDescription[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.bytes = bytes
    }

    /// The opaque bytes that identify this cursor, for byte-exact transport.
    var bytesValue: [UInt8] { bytes }
}

/// An umbrella type that represents a location within an array or text object.
///
/// ### See Also
/// - ``Document/cursor(obj:position:)``
/// - ``Document/cursor(obj:position:heads:)``
public enum Position {
    /// A stable location character or array position that follows that location regardless of Document changes.
    case cursor(Cursor)
    /// An absolute index position within an array or text object.
    case index(UInt64)
}

extension Position {
    func toFfi() -> FfiPosition {
        switch self {
        case let .cursor(cursor):
            return .cursor(position: cursor.bytes)
        case let .index(index):
            return .index(position: index)
        }
    }
}
