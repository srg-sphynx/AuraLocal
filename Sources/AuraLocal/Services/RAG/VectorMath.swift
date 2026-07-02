import Foundation
import Accelerate

enum VectorMath {
    /// Cosine similarity between two equal-length vectors (Accelerate-backed).
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    /// Dot product (Accelerate-backed). Assumes equal length.
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var d: Float = 0
        vDSP_dotpr(a, 1, b, 1, &d, vDSP_Length(a.count))
        return d
    }

    /// Return the unit-length version of `v` (zero vector returned unchanged). Used by
    /// the ANN index so nearest-by-dot equals nearest-by-cosine (spherical k-means).
    static func normalized(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return v }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return v }
        var out = v
        var inv = 1 / norm
        vDSP_vsmul(v, 1, &inv, &out, 1, vDSP_Length(v.count))
        return out
    }

    // MARK: - Float16 (half-precision) storage

    /// Vectors are persisted as little-endian Float16 blobs — half the RAM/disk of
    /// Float32 with negligible recall loss for cosine retrieval. `dim` (the logical
    /// component count) is stored alongside; the blob is `dim * 2` bytes.

    /// Encode a Float32 vector to a packed little-endian Float16 blob.
    static func encodeF16(_ vector: [Float]) -> Data {
        guard !vector.isEmpty else { return Data() }
        var halves = [Float16](repeating: 0, count: vector.count)
        for i in vector.indices { halves[i] = Float16(vector[i]) }
        return halves.withUnsafeBytes { Data($0) }
    }

    /// Decode a packed Float16 blob (from a SQLite column) back to Float32.
    /// `byteCount` bounds the read so a malformed/short blob can't over-read. Uses
    /// unaligned loads because a SQLite blob pointer isn't guaranteed 2-byte aligned.
    static func decodeF16(_ pointer: UnsafeRawPointer, byteCount: Int, dim: Int) -> [Float] {
        let stride = MemoryLayout<Float16>.size
        let count = min(dim, byteCount / stride)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let h = pointer.loadUnaligned(fromByteOffset: i * stride, as: Float16.self)
            out[i] = Float(h)
        }
        return out
    }
}
