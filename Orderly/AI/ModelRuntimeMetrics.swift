import Darwin
import Foundation

struct LocalModelRuntimeStat: Sendable, Equatable {
    let modelName: String
    let loadCount: Int
    let totalLoadSeconds: Double
    let inferenceCount: Int
    let totalInferenceSeconds: Double
    let residentBytesAfterLoad: UInt64?

    var averageInferenceSeconds: Double {
        guard inferenceCount > 0 else { return 0 }
        return totalInferenceSeconds / Double(inferenceCount)
    }
}

struct LocalModelRuntimeSnapshot: Sendable, Equatable {
    let qwen: LocalModelRuntimeStat
    let fastVLM: LocalModelRuntimeStat

    func debugSummary() -> String {
        """
        Qwen model=\(qwen.modelName)
        Qwen loads=\(qwen.loadCount)
        Qwen loadSeconds=\(Self.number(qwen.totalLoadSeconds))
        Qwen inferences=\(qwen.inferenceCount)
        Qwen totalInferenceSeconds=\(Self.number(qwen.totalInferenceSeconds))
        Qwen averageInferenceSeconds=\(Self.number(qwen.averageInferenceSeconds))
        Qwen residentBytesAfterLoad=\(Self.bytes(qwen.residentBytesAfterLoad))
        FastVLM model=\(fastVLM.modelName)
        FastVLM loads=\(fastVLM.loadCount)
        FastVLM loadSeconds=\(Self.number(fastVLM.totalLoadSeconds))
        FastVLM inferences=\(fastVLM.inferenceCount)
        FastVLM totalInferenceSeconds=\(Self.number(fastVLM.totalInferenceSeconds))
        FastVLM averageInferenceSeconds=\(Self.number(fastVLM.averageInferenceSeconds))
        FastVLM residentBytesAfterLoad=\(Self.bytes(fastVLM.residentBytesAfterLoad))
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "unavailable" }
        return String(value)
    }
}

actor LocalModelRuntimeMetrics {
    static let shared = LocalModelRuntimeMetrics()

    private struct MutableStat {
        var modelName: String
        var loadCount = 0
        var totalLoadSeconds = 0.0
        var inferenceCount = 0
        var totalInferenceSeconds = 0.0
        var residentBytesAfterLoad: UInt64?
    }

    private var qwen = MutableStat(modelName: QwenModelManager.modelName)
    private var fastVLM = MutableStat(modelName: FastVLMModelManager.modelName)

    func reset() {
        qwen = MutableStat(modelName: QwenModelManager.modelName)
        fastVLM = MutableStat(modelName: FastVLMModelManager.modelName)
    }

    func recordQwenLoad(seconds: Double, residentBytes: UInt64?) {
        qwen.loadCount += 1
        qwen.totalLoadSeconds += max(0, seconds)
        qwen.residentBytesAfterLoad = residentBytes
    }

    func recordFastVLMLoad(seconds: Double, residentBytes: UInt64?) {
        fastVLM.loadCount += 1
        fastVLM.totalLoadSeconds += max(0, seconds)
        fastVLM.residentBytesAfterLoad = residentBytes
    }

    func recordQwenInference(seconds: Double) {
        qwen.inferenceCount += 1
        qwen.totalInferenceSeconds += max(0, seconds)
    }

    func recordFastVLMInference(seconds: Double) {
        fastVLM.inferenceCount += 1
        fastVLM.totalInferenceSeconds += max(0, seconds)
    }

    func snapshot() -> LocalModelRuntimeSnapshot {
        LocalModelRuntimeSnapshot(
            qwen: Self.snapshot(qwen),
            fastVLM: Self.snapshot(fastVLM)
        )
    }

    private static func snapshot(_ stat: MutableStat) -> LocalModelRuntimeStat {
        LocalModelRuntimeStat(
            modelName: stat.modelName,
            loadCount: stat.loadCount,
            totalLoadSeconds: stat.totalLoadSeconds,
            inferenceCount: stat.inferenceCount,
            totalInferenceSeconds: stat.totalInferenceSeconds,
            residentBytesAfterLoad: stat.residentBytesAfterLoad
        )
    }
}

enum ResidentMemorySampler {
    static func currentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}
