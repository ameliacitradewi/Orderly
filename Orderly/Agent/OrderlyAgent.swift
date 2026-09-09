import Foundation

final class OrderlyAgent {
    private let llm: any LLMService
    private let toolRouter: ToolRouter
    private let contextBuilder = AgentContextBuilder()
    private let decoder = AgentDecisionDecoder()
    private let planValidator = AgentPlanValidator()
    private let maxIterationsPerCandidate = 8

    init(
        llm: any LLMService,
        toolRouter: ToolRouter? = nil
    ) {
        self.llm = llm
        self.toolRouter = toolRouter ?? ToolRouter(
            documentSemanticAnalyzer: QwenDocumentSemanticAnalyzer(llm: llm)
        )
    }

    func run(
        analysis: AnalysisResult,
        evidence: [CandidateEvidence]
    ) async throws -> AgentState {
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: evidence
        )
        var state = AgentState(
            goal: """
            Safely investigate file clutter and propose one evidence-based
            disposition for every file without changing the filesystem.
            """,
            pendingCandidates: analysis.candidates
        )
        state.status = .investigating

        for candidate in analysis.candidates {
            try Task.checkCancellation()

            state.currentCandidate = candidate
            state.iteration = 0

            print("")
            print("======== AGENT CANDIDATE ========")
            print("Candidate:", candidate.id)
            print("Type:", candidate.type.rawValue)

            let finding = try await investigate(
                candidate: candidate,
                state: &state,
                environment: environment
            )
            state.findings.append(finding)
            state.pendingCandidates.removeAll {
                $0.id == candidate.id
            }
        }

        state.currentCandidate = nil
        state.status = .completed

        print("======== AGENT COMPLETE ========")
        print("Findings:", state.findings.count)

        return state
    }

    private func investigate(
        candidate: AnalysisCandidate,
        state: inout AgentState,
        environment: AgentEnvironment
    ) async throws -> AgentFinding {
        while state.iteration < maxIterationsPerCandidate {
            try Task.checkCancellation()
            state.iteration += 1

            let prompt = contextBuilder.build(
                state: state,
                candidate: candidate
            )

            print("")
            print("======== AGENT STEP \(state.iteration) ========")

            let rawResponse = try await llm.generate(
                prompt: prompt
            )
            let decision = try decoder.decode(rawResponse)

            try validate(
                decision,
                currentCandidate: candidate
            )

            print("Action:", decision.action.rawValue)
            print("Reason:", decision.reason)
            print("File references:", decision.fileReferences)

            if decision.action == .finishCandidate {
                guard let finding = decision.finding else {
                    throw AgentError.finishWithoutFinding
                }
                guard finding.candidateID == candidate.id else {
                    throw AgentError.wrongCandidate
                }
                guard finding.confidence.isFinite,
                      (0...1).contains(finding.confidence)
                else {
                    throw AgentError.invalidConfidence
                }
                guard let evidence = environment.evidenceByCandidate[candidate.id] else {
                    throw AgentToolError.unknownCandidate
                }

                let issues = planValidator.validate(
                    finding: finding,
                    candidate: candidate,
                    evidence: evidence,
                    observations: state.observations
                )
                if !issues.isEmpty {
                    print("======== AGENT FINDING REJECTED ========")
                    for issue in issues {
                        print("-", issue)
                    }

                    let expectedReferences = evidence.files
                        .map(\.reference)
                        .sorted()
                        .joined(separator: ", ")
                    let feedback = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Your proposed finding was rejected by validation.

                        Issues:
                        \(issues.map { "- \($0)" }.joined(separator: "\n"))

                        When finishing this candidate, proposals must contain exactly one entry for each of these local references: \(expectedReferences).
                        Do not propose actions for G references or outside files.
                        Revise the finding using factual tool observations. Error observations are feedback only and cannot be cited as evidence. Gather additional evidence if necessary.
                        """
                    )
                    state.observations.append(feedback)

                    print("======== VALIDATION FEEDBACK ========")
                    print(feedback.content)
                    continue
                }

                print("======== AGENT FINDING ========")
                print("Relationship:", finding.relationship.rawValue)
                print("Summary:", finding.summary)
                print("Evidence:")
                for reference in finding.evidence {
                    print(
                        "-",
                        reference.observationID.uuidString,
                        "->",
                        reference.description
                    )
                }
                print("Proposals:")
                for proposal in finding.proposals {
                    print(
                        proposal.fileReference,
                        "->",
                        proposal.disposition.rawValue,
                        "|",
                        proposal.reason
                    )
                }
                print("Confidence:", finding.confidence)
                print("======== AGENT FINDING VALIDATION PASS ========")

                return finding
            }

            let signature = AgentToolCallSignature(
                action: decision.action,
                candidateID: candidate.id,
                fileReferences: decision.fileReferences
            )
            guard state.executedToolCalls.insert(signature).inserted else {
                let requestDescription = [
                    decision.action.rawValue,
                    signature.fileReferences.joined(separator: ",")
                ].joined(separator: ":")
                let observation = AgentObservation(
                    type: .error,
                    candidateID: candidate.id,
                    content: """
                    Rejected repeated tool request: \(requestDescription).
                    This inspection has already been attempted. Use the existing observations and choose a different action or finishCandidate.
                    """
                )
                state.observations.append(observation)

                print("======== TOOL OBSERVATION ========")
                print(observation.content)
                continue
            }

            let observation: AgentObservation
            do {
                observation = try await toolRouter.executeAsync(
                    decision: decision,
                    environment: environment,
                    observations: state.observations
                )
            } catch let error as AgentToolError {
                // Argument mistakes are repairable model output, not a failed scan.
                // Keep infrastructure errors fatal and retain the iteration limit.
                switch error {
                case .wrongFileCount, .invalidFileReference, .unobservedGlobalReference, .comparisonOutsideCandidate:
                    let localReferences = environment.evidenceByCandidate[candidate.id]?
                        .files.map(\.reference).sorted() ?? []
                    let visibleGlobalReferences = environment.visibleGlobalReferences(
                        candidateID: candidate.id,
                        observations: state.observations
                    ).sorted()
                    let localGlobalReferences = Set(
                        environment.evidenceByCandidate[candidate.id]?
                            .files.compactMap {
                                environment.globalReferenceByFileID[$0.fileID]
                            } ?? []
                    )
                    let observedExternalPDFReferences = Set(
                        state.observations
                            .filter {
                                $0.candidateID == candidate.id && $0.type != .error
                            }
                            .flatMap { $0.pdfGlobalReferences ?? [] }
                    )
                    .subtracting(localGlobalReferences)
                    .sorted()
                    let inspectedPDFReferences = Set(
                        state.observations
                            .filter {
                                $0.candidateID == candidate.id && $0.type == .content
                            }
                            .compactMap(\.contentObservation)
                            .map(\.globalReference)
                    ).sorted()

                    let actionSpecificRepair: String
                    switch decision.action {
                    case .inspectFile, .inspectPDFContent, .findRelatedFiles:
                        actionSpecificRepair = "Retry with exactly one local F reference from: \(Self.render(localReferences))."
                    case .compareFiles:
                        actionSpecificRepair = "Retry with exactly two distinct local F references from: \(Self.render(localReferences))."
                    case .inspectGlobalFile:
                        actionSpecificRepair = "Retry with exactly one already-observed G reference from: \(Self.render(visibleGlobalReferences))."
                    case .inspectGlobalPDFContent:
                        actionSpecificRepair = "Retry with exactly one observed external PDF G reference from: \(Self.render(observedExternalPDFReferences))."
                    case .compareGlobalFiles:
                        actionSpecificRepair = "Retry with exactly two distinct observed G references from: \(Self.render(visibleGlobalReferences)); at least one must belong to the current candidate."
                    case .compareDocumentContent:
                        actionSpecificRepair = "Retry with exactly two distinct inspected PDF G references from: \(Self.render(inspectedPDFReferences)); at least one must belong to the current candidate."
                    case .inspectCandidate, .finishCandidate:
                        actionSpecificRepair = "Choose an available action using the exact reference shape shown in the prompt."
                    }

                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Tool request failed: \(decision.action.rawValue), fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        \(actionSpecificRepair)
                        Valid file references for this candidate: \(Self.render(localReferences)).
                        Observed global references: \(Self.render(visibleGlobalReferences)).
                        Correct the arguments and retry. This failed request is not factual evidence.
                        """
                    )
                    state.executedToolCalls.remove(signature)
                default:
                    throw error
                }
            } catch let error as ContentInspectionError {
                guard decision.action == .inspectPDFContent
                        || decision.action == .inspectGlobalPDFContent else {
                    throw error
                }
                switch error {
                case .unsupportedFileType, .cannotOpenPDF:
                    // A failed read supplies no content evidence. Retain its signature
                    // so the same unsupported or unreadable file is not retried.
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Content inspection failed: \(decision.action.rawValue), fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        No content was inspected. Do not retry PDF inspection for these references or infer their contents.
                        PDF content inspection supports PDF files only, not TXT, Markdown, Pages, or images.
                        Use metadata or findRelatedFiles for further investigation, or finish with review when allowed if purpose remains unknown.
                        This error is feedback only and cannot be cited as factual evidence.
                        """,
                        unavailablePDFReferences: decision.fileReferences
                    )
                case .fileOutsideAnalyzedFolder:
                    throw error
                }
            } catch let error as DocumentComparisonError {
                switch error {
                case .missingContentEvidence:
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Document comparison failed because both requested G references do not yet have content observations.
                        Inspect the local PDF with inspectPDFContent and any external PDF with inspectGlobalPDFContent, then retry compareDocumentContent.
                        This error is feedback only and cannot be cited as factual evidence.
                        """
                    )
                    state.executedToolCalls.remove(signature)
                case .invalidSemanticResponse:
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        The semantic comparison model returned an invalid structured response.
                        You may retry compareDocumentContent once after considering the existing evidence, or finish with uncertain/review when appropriate.
                        This error is feedback only and cannot be cited as factual evidence.
                        """
                    )
                    state.executedToolCalls.remove(signature)
                }
            }
            state.observations.append(observation)

            print("======== TOOL OBSERVATION ========")
            print(observation.content)
        }

        throw AgentError.maximumIterationsReached
    }

    private func validate(
        _ decision: AgentDecision,
        currentCandidate: AnalysisCandidate
    ) throws {
        guard decision.candidateID == currentCandidate.id else {
            throw AgentError.wrongCandidate
        }
    }

    private static func render(_ references: [String]) -> String {
        references.isEmpty ? "none" : references.joined(separator: ", ")
    }
}
