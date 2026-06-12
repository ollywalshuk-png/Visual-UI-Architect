import Foundation
import RepositoryEngine

public struct ImportCoordinator: Sendable {
    private let detector: ImportFrameworkDetector

    public init(detector: ImportFrameworkDetector = ImportFrameworkDetector()) {
        self.detector = detector
    }

    public func summarize(root: URL) -> ImportProjectSummary {
        detector.detect(root: root)
    }

    public func swiftUICandidates(root: URL) -> [ExistingUIImport.Candidate] {
        ExistingUIImport.scanRepository(root)
    }

    public func importCandidate(_ candidate: ExistingUIImport.Candidate) -> ExistingUIImport.Imported? {
        AppleUIImport.importCandidate(candidate)
            ?? ExistingUIImport.importCandidateEnsuringAnchors(candidate)
            ?? WebUIImport.importCandidate(candidate)
    }
}
