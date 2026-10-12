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

    // MARK: - Opid-string form (cross-client interop, holos SPA-3893)
    //
    // The JS/wasm Automerge binding serializes a cursor as its *opid string*
    // (`[-]{ctr}@{actorHex}`), not the opaque bytes Swift carries. To resolve a
    // web author's caret on the headset — and for a headset caret to resolve on
    // the web — both sides must speak the same form. These convert between the
    // opid string and the op-cursor byte layout automerge 0.7.2 uses:
    //
    //   [VERSION=1][OP_TAG=3][uLEB(actorLen)][actor bytes][uLEB(ctr)][move]
    //
    // where `move` is 1 for Before (a leading "-") or 2 for After. The start /
    // end sentinels ("s" / "e") are not op cursors and aren't handled here.

    /// Reconstruct a cursor from automerge's opid string form, e.g. `56@b29b43…`
    /// (or `-56@b29b43…` for a before-cursor). Returns nil for a malformed
    /// string or the `s`/`e` start/end sentinels.
    init?(opId string: String) {
        var rest = Substring(string)
        let moveTag: UInt8
        if rest.first == "-" { moveTag = 1; rest = rest.dropFirst() } else { moveTag = 2 }
        guard let at = rest.firstIndex(of: "@") else { return nil }
        let ctrText = rest[rest.startIndex ..< at]
        let actorHex = String(rest[rest.index(after: at)...])
        guard let ctr = UInt64(ctrText),
              !actorHex.isEmpty, actorHex.count % 2 == 0,
              let actor = Cursor.hexToBytes(actorHex) else { return nil }
        var bytes: [UInt8] = [1, 3]
        Cursor.appendULEB(&bytes, UInt64(actor.count))
        bytes.append(contentsOf: actor)
        Cursor.appendULEB(&bytes, ctr)
        bytes.append(moveTag)
        self.bytes = bytes
    }

    /// This cursor's opid string form (`[-]{ctr}@{actorHex}`), for transport to
    /// a JS/wasm client. Nil if the bytes aren't an op cursor in the known
    /// layout (e.g. a start/end sentinel).
    var opIdString: String? {
        var i = bytes.startIndex
        func next() -> UInt8? { i < bytes.endIndex ? bytes[i] : nil }
        guard next() == 1 else { return nil }; i += 1          // VERSION
        guard next() == 3 else { return nil }; i += 1          // OP_TAG
        guard let actorLen = Cursor.readULEB(bytes, &i), actorLen > 0 else { return nil }
        guard i + Int(actorLen) <= bytes.endIndex else { return nil }
        let actor = bytes[i ..< i + Int(actorLen)]
        i += Int(actorLen)
        guard let ctr = Cursor.readULEB(bytes, &i) else { return nil }
        guard let move = next() else { return nil }; i += 1    // MOVE
        let prefix = move == 1 ? "-" : ""
        let actorHex = actor.map { Swift.String(format: "%02hhx", $0) }.joined()
        return "\(prefix)\(ctr)@\(actorHex)"
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    private static func appendULEB(_ bytes: inout [UInt8], _ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while v != 0
    }

    private static func readULEB(_ bytes: [UInt8], _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < bytes.endIndex {
            let byte = bytes[i]; i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
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
