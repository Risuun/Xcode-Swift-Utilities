// CodeVectorIndex.swift // Search
//
// Vector embedding engine, disk caching, and similarity ranking.
//

import Foundation
import Accelerate
import llama
import SwiftLlama

public final class EmbeddingEngine: @unchecked Sendable {
    public static let shared: EmbeddingEngine? = {
        guard let path = ModelResolver.resolveModelPath() else {
            return nil
        }
        return try? EmbeddingEngine(modelPath: path)
    }()
    
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    public let dimension: Int
    private let n_ctx: Int32 = 512
    
    public init(modelPath: String) throws {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        llama_numa_init(GGML_NUMA_STRATEGY_DISABLED)
        
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 0
        
        guard let modelPtr = llama_model_load_from_file(modelPath, mparams) else {
            throw SwiftLlamaError.others("Failed to load GGUF embedding model at: \(modelPath)")
        }
        self.model = modelPtr
        
        guard let vocabPtr = llama_model_get_vocab(modelPtr) else {
            llama_model_free(modelPtr)
            throw SwiftLlamaError.others("Failed to get vocab from embedding model")
        }
        self.vocab = vocabPtr
        
        var cparams = llama_context_default_params()
        let procCount = max(1, min(16, ProcessInfo.processInfo.processorCount - 2))
        cparams.n_ctx = UInt32(n_ctx)
        cparams.n_threads = Int32(procCount)
        cparams.n_threads_batch = Int32(procCount)
        cparams.embeddings = true
        cparams.pooling_type = LLAMA_POOLING_TYPE_MEAN
        
        guard let ctxPtr = llama_init_from_model(modelPtr, cparams) else {
            llama_model_free(modelPtr)
            throw SwiftLlamaError.others("Failed to create context for embedding model")
        }
        self.context = ctxPtr
        self.dimension = Int(llama_model_n_embd(modelPtr))
    }
    
    deinit {
        llama_free(context)
        llama_model_free(model)
    }
    
    public func embed(text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let utf8Count = trimmed.utf8.count
        var maxTokens = utf8Count + 8
        var tokenBuffer = [llama_token](repeating: 0, count: maxTokens)
        
        var tokenCount = llama_tokenize(
            vocab,
            trimmed,
            Int32(utf8Count),
            &tokenBuffer,
            Int32(tokenBuffer.count),
            true, // add BOS
            false // special
        )
        
        if tokenCount < 0 {
            maxTokens = Int(-tokenCount) + 4
            tokenBuffer = [llama_token](repeating: 0, count: maxTokens)
            tokenCount = llama_tokenize(
                vocab,
                trimmed,
                Int32(utf8Count),
                &tokenBuffer,
                Int32(tokenBuffer.count),
                true,
                false
            )
        }
        
        guard tokenCount > 0 else { return nil }
        
        let effectiveCount = min(Int32(tokenCount), n_ctx)
        var batch = llama_batch_init(effectiveCount, 0, 1)
        defer { llama_batch_free(batch) }
        
        for i in 0..<Int(effectiveCount) {
            batch.token[i] = tokenBuffer[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]?[0] = 0
            batch.logits[i] = 1
        }
        batch.n_tokens = effectiveCount
        
        guard llama_decode(context, batch) == 0 else {
            llama_kv_self_clear(context)
            return nil
        }
        
        guard let embdPtr = llama_get_embeddings_seq(context, 0) ??
                            llama_get_embeddings_ith(context, -1) ??
                            llama_get_embeddings(context) else {
            llama_kv_self_clear(context)
            return nil
        }
        
        var vector = [Float](UnsafeBufferPointer(start: embdPtr, count: dimension))
        llama_kv_self_clear(context)
        
        VectorMath.l2Normalize(&vector)
        return vector
    }
}

public struct CachedFileEntry: Codable {
    public let filePath: String
    public let mtime: Double
    public let chunks: [CodeChunk]
    public let vectors: [[Float]]
}

public struct CodeIndexStore: Codable {
    public let version: Int
    public var files: [String: CachedFileEntry]
    
    public init(version: Int = 1, files: [String: CachedFileEntry] = [:]) {
        self.version = version
        self.files = files
    }
}

public struct SearchResult {
    public let chunk: CodeChunk
    public let score: Float
}

public final class CodeVectorIndex {
    private let engine: EmbeddingEngine
    private let projectRoot: URL
    private let cacheFileURL: URL
    private var store: CodeIndexStore
    
    public init(engine: EmbeddingEngine, targetPath: String) {
        self.engine = engine
        self.projectRoot = findProjectRoot(from: targetPath)
        
        let fileManager = FileManager.default
        let buildDir = projectRoot.appendingPathComponent(".build")
        if fileManager.fileExists(atPath: buildDir.path) || (try? fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)) != nil {
            self.cacheFileURL = buildDir.appendingPathComponent("xcswiftmap.index")
        } else {
            let pathHash = abs(projectRoot.path.hashValue)
            self.cacheFileURL = URL(fileURLWithPath: "/tmp/.xcswiftmap_\(pathHash).index")
        }
        
        if let data = try? Data(contentsOf: cacheFileURL),
           let loaded = try? JSONDecoder().decode(CodeIndexStore.self, from: data),
           loaded.version == 1 {
            self.store = loaded
        } else {
            self.store = CodeIndexStore()
        }
    }
    
    private func fileMTime(for url: URL) -> Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modDate = attrs?[.modificationDate] as? Date {
            return modDate.timeIntervalSince1970
        }
        return 0.0
    }
    
    @discardableResult
    public func indexFiles(_ files: [URL]) -> (totalChunks: Int, fileCount: Int) {
        var updated = false
        var currentFilePaths = Set<String>()
        
        for fileURL in files {
            let pathKey = fileURL.standardizedFileURL.path
            currentFilePaths.insert(pathKey)
            let mtime = fileMTime(for: fileURL)
            
            if let cached = store.files[pathKey], cached.mtime == mtime {
                continue
            }
            
            // Re-chunk and re-embed
            let chunks = CodeChunker.chunk(fileURL: fileURL, relativeTo: projectRoot)
            var vectors: [[Float]] = []
            
            for chunk in chunks {
                if let vec = engine.embed(text: chunk.embeddingText) {
                    vectors.append(vec)
                } else {
                    // Fallback to zero vector if embedding failed
                    vectors.append([Float](repeating: 0.0, count: engine.dimension))
                }
            }
            
            store.files[pathKey] = CachedFileEntry(
                filePath: pathKey,
                mtime: mtime,
                chunks: chunks,
                vectors: vectors
            )
            updated = true
        }
        
        if updated {
            saveIndex()
        }
        
        var totalChunks = 0
        var totalFiles = 0
        for (_, entry) in store.files {
            totalChunks += entry.chunks.count
            totalFiles += 1
        }
        
        return (totalChunks, totalFiles)
    }
    
    private func saveIndex() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(store) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }
    
    public func search(query: String, threshold: Float = 0.55, limit: Int = 5) -> [SearchResult] {
        guard let queryVector = engine.embed(text: query) else {
            return []
        }
        
        var results: [SearchResult] = []
        
        for (_, entry) in store.files {
            let count = min(entry.chunks.count, entry.vectors.count)
            for i in 0..<count {
                let chunkVec = entry.vectors[i]
                let score = VectorMath.dotProduct(queryVector, chunkVec)
                if score >= threshold {
                    results.append(SearchResult(chunk: entry.chunks[i], score: score))
                }
            }
        }
        
        results.sort { $0.score > $1.score }
        if results.count > limit {
            return Array(results.prefix(limit))
        }
        return results
    }
}
