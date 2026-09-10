import Foundation

extension OrderlyAgent {
    /// Production/image-enabled agents opt into bounded deterministic fast paths by
    /// default. The full designated initializer keeps `deterministicFastPaths=false`
    /// for existing scripted unit tests and specialized callers that need to exercise
    /// every model-planning turn explicitly.
    convenience init(
        llm: any LLMService,
        visionLanguageService: any VisionLanguageService
    ) {
        self.init(
            llm: llm,
            visionLanguageService: Optional(visionLanguageService),
            toolRouter: nil,
            deterministicFastPaths: true
        )
    }
}
