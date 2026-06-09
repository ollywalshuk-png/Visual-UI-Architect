import Foundation
import UIQualityEngine

/// UI-quality integration: run the assessor over the live document.
extension DocumentStore {
    func assessQuality() -> QualityReport {
        QualityAssessor().assess(document)
    }
}
