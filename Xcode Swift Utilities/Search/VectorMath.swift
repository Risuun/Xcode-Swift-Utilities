// VectorMath.swift // Search
//
// Accelerated vector scoring and normalization using Accelerate.framework.
//

import Foundation
import Accelerate

public enum VectorMath {
    /// L2 Normalizes a float vector in-place so dot products equal cosine similarities.
    public static func l2Normalize(_ vector: inout [Float]) {
        guard !vector.isEmpty else { return }
        var sumOfSquares: Float = 0.0
        vDSP_svesq(vector, 1, &sumOfSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumOfSquares)
        if norm > 0.000001 {
            var normVar = norm
            vDSP_vsdiv(vector, 1, &normVar, &vector, 1, vDSP_Length(vector.count))
        }
    }
    
    /// Single vector dot product using vDSP_dotpr
    public static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var result: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
    
    /// Batch matrix-vector multiplication using cblas_sgemv
    /// matrix: Row-major matrix of dimensions (rows x cols)
    /// vector: Vector of dimension (cols)
    /// Returns scores vector of dimension (rows)
    public static func batchCosineSimilarities(matrix: [Float], rows: Int, cols: Int, queryVector: [Float]) -> [Float] {
        guard rows > 0, cols > 0, matrix.count == rows * cols, queryVector.count == cols else {
            return []
        }
        var scores = [Float](repeating: 0.0, count: rows)
        cblas_sgemv(
            CblasRowMajor,
            CblasNoTrans,
            Int32(rows),
            Int32(cols),
            1.0,
            matrix,
            Int32(cols),
            queryVector,
            1,
            0.0,
            &scores,
            1
        )
        return scores
    }
}
