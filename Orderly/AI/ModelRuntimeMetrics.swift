import Darwin
import Foundation

enum FoundationInferencePurpose: String, CaseIterable, Sendable, Hashable {
    case agentDecision
    case documentSemantic
    case imageStructuring
    case imageRelationship
}

struct LocalInferencePurposeStat: Sendable, Equatable {
    let inferenceCount: Int
    let totalInferenceSeconds: Double
    let totalPromptCharacters: Int
    let totalOutputCharacters: Int

    var averageInferenceSeconds: Double {
        guard inferenceCount > 0 else { return 0 }
        return totalInferenceSeconds / Double(inferenceCount)
    }
}

struct LocalModelRuntimeStat: Sendable, Equatable {
    let modelName: String
    let loadCount: Int
    let totalLoadSeconds: Double
    let inferenceCount: Int
    let totalInferenceSeconds: Double
    let totalPromptCharacters: Int
    let totalOutputCharacters: Int
    let residentBytesAfterLoad: UInt64?

    var averageInferenceSeconds: Double {
        guard inferenceCount > 0 else { return 0 }
        return totalInferenceSeconds / Double(inferenceCount)
    }

    var averagePromptCharacters: Double {
        guard inferenceCount > 0 else { return 0 }
        return Double(totalPromptCharacters) / Double(inferenceCount)
    }

    var averageOutputCharacters: Double {
        guard inferenceCount > 0 else { return 0 }
        return Double(totalOutputCharacters) / Double(inferenceCount)
    }
}

struct LocalModelRuntimeSnapshot: Sendable, Equatable {
    let foundationModel: LocalModelRuntimeStat
    let foundationByPurpose: [FoundationInferencePurpose: LocalInferencePurposeStat]
    let fastVLM: LocalModelRuntimeStat

    func debugSummary() -> String {
        let purposeSummary = FoundationInferencePurpose.allCases.map { purpose in
            let stat = foundationByPurpose[purpose] ?? LocalInferencePurposeStat(
                inferenceCount: 0,
                totalInferenceSeconds: 0,
                totalPromptCharacters: 0,
                totalOutputCharacters: 0
            )
            return "FoundationModel purpose.\(purpose.rawValue) inferences=\(stat.inferenceCount) totalSeconds=\(Self.number(stat.totalInferenceSeconds)) averageSeconds=\(Self.number(stat.averageInferenceSeconds)) promptCharacters=\(stat.totalPromptCharacters) outputCharacters=\(stat.totalOutputCharacters)"
        }.joined(separator: "\n")

        return """
        FoundationModel model=\(foundationModel.modelName)
        FoundationModel inferences=\(foundationModel.inferenceCount)
        FoundationModel totalInferenceSeconds=\(Self.number(foundationModel.totalInferenceSeconds))
        FoundationModel averageInferenceSeconds=\(Self.number(foundationModel.averageInferenceSeconds))
        FoundationModel totalPromptCharacters=\(foundationModel.totalPromptCharacters)
        FoundationModel averagePromptCharacters=\(Self.number(foundationModel.averagePromptCharacters))
        FoundationModel totalOutputCharacters=\(foundationModel.totalOutputCharacters)
        FoundationModel averageOutputCharacters=\(Self.number(foundationModel.averageOutputCharacters))
        \(purposeSummary)
        FastVLM model=\(fastVLM.modelName)
        FastVLM loads=\(fastVLM.loadCount)
        FastVLM loadSeconds=\(Self.number(fastVLM.totalLoadSeconds))
        FastVLM inferences=\(fastVLM.inferenceCount)
        FastVLM totalInferenceSeconds=\(Self.number(fastVLM.totalInferenceSeconds))
        FastVLM averageInferenceSeconds=\(Self.number(fastVLM.averageInferenceSeconds))
        FastVLM totalPromptCharacters=\(fastVLM.totalPromptCharacters)
        FastVLM averagePromptCharacters=\(Self.number(fastVLM.averagePromptCharacters))
        FastVLM totalOutputCharacters=\(fastVLM.totalOutputCharacters)
        FastVLM averageOutputCharacters=\(Self.number(fastVLM.averageOutputCharacters))
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
        var totalPromptCharacters = 0
        var totalOutputCharacters = 0
        var residentBytesAfterLoad: UInt64?
    }

    private struct MutablePurposeStat {
        var inferenceCount = 0
        var totalInferenceSeconds = 0.0
        var totalPromptCharacters = 0
        var totalOutputCharacters = 0
    }

    private var foundationModel = MutableStat(
        modelName: AppleFoundationModelService.modelName
    )
    private var foundationByPurpose: [
        FoundationInferencePurpose: MutablePurposeStat
    ] = [:]
    private var fastVLM = MutableStat(
        modelName: FastVLMModelManager.modelName
    )

    func reset() {
        foundationModel = MutableStat(
            modelName: AppleFoundationModelService.modelName
        )
        foundationByPurpose = [:]
        fastVLM = MutableStat(
            modelName: FastVLMModelManager.modelName
        )
    }

    func recordFoundationInference(
        seconds: Double,
        purpose: FoundationInferencePurpose = .agentDecision,
        promptCharacters: Int = 0,
        outputCharacters: Int = 0
    ) {
        let boundedSeconds = max(0, seconds)
        let boundedPrompt = max(0, promptCharacters)
        let boundedOutput = max(0, outputCharacters)

        foundationModel.inferenceCount += 1
        foundationModel.totalInferenceSeconds += boundedSeconds
        foundationModel.totalPromptCharacters += boundedPrompt
        foundationModel.totalOutputCharacters += boundedOutput

        var purposeStat = foundationByPurpose[purpose] ?? MutablePurposeStat()
        purposeStat.inferenceCount += 1
        purposeStat.totalInferenceSeconds += boundedSeconds
        purposeStat.totalPromptCharacters += boundedPrompt
        purposeStat.totalOutputCharacters += boundedOutput
        foundationByPurpose[purpose] = purposeStat
    }

    func recordFastVLMLoad(
        seconds: Double,
        residentBytes: UInt64?
    ) {
        fastVLM.loadCount += 1
        fastVLM.totalLoadSeconds += max(0, seconds)
        fastVLM.residentBytesAfterLoad = residentBytes
    }

    func recordFastVLMInference(
        seconds: Double,
        promptCharacters: Int = 0,
        outputCharacters: Int = 0
    ) {
        fastVLM.inferenceCount += 1
        fastVLM.totalInferenceSeconds += max(0, seconds)
        fastVLM.totalPromptCharacters += max(0, promptCharacters)
        fastVLM.totalOutputCharacters += max(0, outputCharacters)
    }

    func snapshot() -> LocalModelRuntimeSnapshot {
        LocalModelRuntimeSnapshot(
            foundationModel: Self.snapshot(foundationModel),
            foundationByPurpose: foundationByPurpose.mapValues {
                Self.snapshot($0)
            },
            fastVLM: Self.snapshot(fastVLM)
        )
    }

    private static func snapshot(
        _ stat: MutableStat
    ) -> LocalModelRuntimeStat {
        LocalModelRuntimeStat(
            modelName: stat.modelName,
            loadCount: stat.loadCount,
            totalLoadSeconds: stat.totalLoadSeconds,
            inferenceCount: stat.inferenceCount,
            totalInferenceSeconds: stat.totalInferenceSeconds,
            totalPromptCharacters: stat.totalPromptCharacters,
            totalOutputCharacters: stat.totalOutputCharacters,
            residentBytesAfterLoad: stat.residentBytesAfterLoad
        )
    }

    private static func snapshot(
        _ stat: MutablePurposeStat
    ) -> LocalInferencePurposeStat {
        LocalInferencePurposeStat(
            inferenceCount: stat.inferenceCount,
            totalInferenceSeconds: stat.totalInferenceSeconds,
            totalPromptCharacters: stat.totalPromptCharacters,
            totalOutputCharacters: stat.totalOutputCharacters
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
