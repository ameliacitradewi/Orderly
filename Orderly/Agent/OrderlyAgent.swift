import Foundation

final class OrderlyAgent {
    private let llm: any LLMService
    private let toolRouter: ToolRouter
    private let contextBuilder = AgentContextBuilder()
    private let decoder = AgentDecisionDecoder()
    private let referenceResolver = AgentDecisionReferenceResolver()
    private let planValidator = AgentPlanValidator()
    private let maxIterationsPerCandidate = 8

    init(
        llm: any LLMService,
        visionLanguageService: (any VisionLanguageService)? = nil,
        toolRouter: ToolRouter? = nil
    ) {
        self.llm = llm
        if let toolRouter {
            self.toolRouter = toolRouter
        } else {
            let imageSemanticAnalyzer = visionLanguageService.map {
                StructuredImageSemanticAnalyzer(
                    visionModel: $0,
                    textModel: llm
                )
            }
            self.toolRouter = ToolRouter(
                documentSemanticAnalyzer: QwenDocumentSemanticAnalyzer(llm: llm),
                imageSemanticAnalyzer: imageSemanticAnalyzer,
                imagePairSemanticAnalyzer: imageSemanticAnalyzer == nil
                    ? nil
                    : QwenImagePairSemanticAnalyzer(llm: llm)
            )
        }
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
            let decodedDecision = try decoder.decode(rawResponse)
            let decision = referenceResolver.resolve(
                decodedDecision,
                candidate: candidate,
                environment: environment,
                observations: state.observations
            )

            try validate(
                decision,
                currentCandidate: candidate
            )

            print("Action:", decision.action.rawValue)
            print("Reason:", decision.reason)
            print("File references:", decision.fileReferences)

            if decision.action == .finishCandidate {
                guard var finding = decision.finding else {
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

                var issues = planValidator.validate(
                    finding: finding,
                    candidate: candidate,
                    evidence: evidence,
                    observations: state.observations
                )

                if Self.onlyUnsupportedRevisionOrdering(issues),
                   !finding.proposals.contains(where: { $0.disposition == .trash }) {
                    let groundedFinding = Self.canonicalizeRevisionFinding(finding)
                    let groundedIssues = planValidator.validate(
                        finding: groundedFinding,
                        candidate: candidate,
                        evidence: evidence,
                        observations: state.observations
                    )
                    if groundedIssues.isEmpty {
                        print("======== AGENT FINDING LANGUAGE REPAIR ========")
                        print("Replaced unsupported revision directionality with symmetric wording.")
                        finding = groundedFinding
                        issues = []
                    }
                }

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
                    let observedExternalImageReferences = Set(
                        state.observations
                            .filter {
                                $0.candidateID == candidate.id && $0.type != .error
                            }
                            .flatMap { $0.imageGlobalReferences ?? [] }
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
                    let inspectedImageReferences = Set(
                        state.observations
                            .filter {
                                $0.candidateID == candidate.id && $0.type == .imageContent
                            }
                            .compactMap(\.imageSemantic)
                            .map(\.globalReference)
                    ).sorted()

                    let actionSpecificRepair: String
                    switch decision.action {
                    case .inspectFile, .inspectPDFContent, .inspectImageContent, .findRelatedFiles:
                        actionSpecificRepair = "Retry with exactly one local F reference from: \(Self.render(localReferences))."
                    case .compareFiles:
                        actionSpecificRepair = "Retry with exactly two distinct local F references from: \(Self.render(localReferences))."
                    case .inspectGlobalFile:
                        actionSpecificRepair = "Retry with exactly one already-observed G reference from: \(Self.render(visibleGlobalReferences))."
                    case .inspectGlobalPDFContent:
                        actionSpecificRepair = "Retry with exactly one observed external PDF G reference from: \(Self.render(observedExternalPDFReferences))."
                    case .inspectGlobalImageContent:
                        actionSpecificRepair = "Retry with exactly one observed external image G reference from: \(Self.render(observedExternalImageReferences))."
                    case .compareGlobalFiles:
                        actionSpecificRepair = "Retry with exactly two distinct observed G references from: \(Self.render(visibleGlobalReferences)); at least one must belong to the current candidate."
                    case .compareDocumentContent:
                        actionSpecificRepair = "Retry with exactly two distinct inspected PDF G references from: \(Self.render(inspectedPDFReferences)); at least one must belong to the current candidate."
                    case .compareImageContent:
                        actionSpecificRepair = "Retry with exactly two distinct inspected image G references from: \(Self.render(inspectedImageReferences)); at least one must belong to the current candidate."
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
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Content inspection failed: \(decision.action.rawValue), fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        No content was inspected. Do not retry PDF inspection for these references or infer their contents.
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
            } catch let error as ImageEvidenceError {
                guard decision.action == .inspectImageContent
                        || decision.action == .inspectGlobalImageContent
                        || decision.action == .compareImageContent else {
                    throw error
                }
                switch error {
                case .fileOutsideAnalyzedFolder:
                    throw error
                default:
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Image inspection failed: \(decision.action.rawValue), fileReferences=\(decision.fileReferences).
                        \(error.localizedDescription)
                        Do not infer visual content from this failure. Use metadata/discovery or finish with review when appropriate.
                        This error is feedback only and cannot be cited as factual evidence.
                        """,
                        unavailableImageReferences: decision.action == .compareImageContent
                            ? nil
                            : decision.fileReferences
                    )
                }
            } catch let error as ImageSemanticError {
                guard decision.action == .inspectImageContent
                        || decision.action == .inspectGlobalImageContent else {
                    throw error
                }
                observation = AgentObservation(
                    type: .error,
                    candidateID: candidate.id,
                    content: """
                    The hybrid image semantic pipeline could not produce a valid typed observation for fileReferences=\(decision.fileReferences).
                    \(error.localizedDescription)
                    Do not infer image meaning from this failure. Continue with deterministic metadata/discovery or finish with review when appropriate.
                    This error is feedback only and cannot be cited as factual evidence.
                    """,
                    unavailableImageReferences: decision.fileReferences
                )
            } catch let error as ImageComparisonError {
                switch error {
                case .missingImageContentEvidence:
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        Image comparison failed because both requested G references do not yet have imageContent observations.
                        Inspect the local image with inspectImageContent and any external image with inspectGlobalImageContent, then retry compareImageContent.
                        This error is feedback only and cannot be cited as factual evidence.
                        """
                    )
                    state.executedToolCalls.remove(signature)
                case .invalidSemanticResponse:
                    observation = AgentObservation(
                        type: .error,
                        candidateID: candidate.id,
                        content: """
                        The image relationship model returned an invalid structured response.
                        You may retry compareImageContent once or finish with uncertain/review when appropriate.
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

    private static func onlyUnsupportedRevisionOrdering(_ issues: [String]) -> Bool {
        issues.count == 1
            && issues[0].contains("symmetric relationship only")
    }

    private static func canonicalizeRevisionFinding(
        _ finding: AgentFinding
    ) -> AgentFinding {
        AgentFinding(
            candidateID: finding.candidateID,
            relationship: finding.relationship,
            summary: "The candidate file and the compared document appear to be revisions of the same underlying document.",
            evidence: finding.evidence.map {
                AgentEvidenceReference(
                    observationID: $0.observationID,
                    description: "The cited document comparison classified the files as revisions of the same underlying document."
                )
            },
            proposals: finding.proposals.map { proposal in
                AgentFileProposal(
                    fileReference: proposal.fileReference,
                    disposition: proposal.disposition,
                    reason: "The files have a revision relationship, but their ordering is not established; review the evidence before taking any irreversible action."
                )
            },
            confidence: finding.confidence
        )
    }

    private static func render(_ references: [String]) -> String {
        references.isEmpty ? "none" : references.joined(separator: ", ")
    }
}
