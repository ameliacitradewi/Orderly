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
        toolRouter: ToolRouter = ToolRouter()
    ) {
        self.llm = llm
        self.toolRouter = toolRouter
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

                    let feedback = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Your proposed finding was rejected by validation.

                        Issues:
                        \(issues.map { "- \($0)" }.joined(separator: "\n"))

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
                observation = try toolRouter.execute(
                    decision: decision,
                    environment: environment,
                    observations: state.observations
                )
            } catch let error as AgentToolError {
                // Argument mistakes are repairable model output, not a failed scan.
                // Keep infrastructure errors fatal and retain the iteration limit.
                switch error {
                case .wrongFileCount, .invalidFileReference, .unobservedGlobalReference, .comparisonOutsideCandidate:
                    let validReferences = environment.evidenceByCandidate[candidate.id]?
                        .files.map(\.reference).joined(separator: ", ") ?? "none"
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Tool request failed: \(decision.action.rawValue), fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        Valid file references for this candidate: \(validReferences).
                        compareFiles requires two distinct F references; compareGlobalFiles requires two distinct observed G references including a current candidate file.
                        inspectFile, inspectPDFContent, and findRelatedFiles require one F reference. inspectGlobalFile requires one observed G reference. Use G references from this candidate's observations, never paths or guessed IDs.
                        Correct the arguments and retry. This failed request is not factual evidence.
                        """
                    )
                    state.executedToolCalls.remove(signature)
                default:
                    throw error
                }
            } catch let error as ContentInspectionError {
                guard decision.action == .inspectPDFContent else { throw error }
                switch error {
                case .unsupportedFileType, .cannotOpenPDF:
                    // A failed read supplies no content evidence. Retain its signature
                    // so the same unsupported or unreadable file is not retried.
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Content inspection failed: inspectPDFContent, fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        No content was inspected. Do not retry PDF inspection for these references or infer their contents.
                        inspectPDFContent supports PDF files only, not TXT, Markdown, Pages, or images.
                        Use metadata or findRelatedFiles for further investigation, or finish with review when allowed if purpose remains unknown.
                        This error is feedback only and cannot be cited as factual evidence.
                        """,
                        unavailablePDFReferences: decision.fileReferences
                    )
                case .fileOutsideAnalyzedFolder:
                    throw error
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
}
