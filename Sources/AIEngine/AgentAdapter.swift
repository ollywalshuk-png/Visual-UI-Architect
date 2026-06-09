import Foundation
import VUACore

/// A non-destructive suggestion produced by an AI provider. Suggestions are
/// *proposals only* — applying them is gated behind explicit user approval and
/// performed by the app, never by the adapter. AI never touches files directly.
public struct Suggestion: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case layout, accessibility, responsive, alignment, naming
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    public var detail: String
    /// Optional concrete change the app can apply on approval.
    public var proposedChange: ProposedChange?

    public init(id: UUID = UUID(), kind: Kind, title: String, detail: String, proposedChange: ProposedChange? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.proposedChange = proposedChange
    }
}

/// A structured, reviewable change. The app validates and applies it; the
/// adapter only describes it.
public enum ProposedChange: Sendable {
    case rename(layerID: UUID, newName: String)
    case reframe(layerID: UUID, newFrame: VRect)
    case restyle(layerID: UUID, newStyle: LayerStyle)
}

public struct SuggestionRequest: Sendable {
    public var document: Document
    public var focusedLayerIDs: [UUID]
    public var kinds: Set<Suggestion.Kind>

    public init(document: Document, focusedLayerIDs: [UUID] = [], kinds: Set<Suggestion.Kind> = [.layout, .accessibility, .responsive, .alignment, .naming]) {
        self.document = document
        self.focusedLayerIDs = focusedLayerIDs
        self.kinds = kinds
    }
}

/// Provider abstraction. Implementations: local LLM, Claude, Codex, etc.
/// No vendor lock-in: the app depends only on this protocol.
public protocol AgentAdapter: Sendable {
    var providerName: String { get }
    var isAvailable: Bool { get }
    func suggest(_ request: SuggestionRequest) async throws -> [Suggestion]
}

/// Registry the app uses to enumerate and select providers at runtime.
public final class AgentRegistry: @unchecked Sendable {
    private var adapters: [any AgentAdapter]
    public private(set) var selected: (any AgentAdapter)?

    public init(adapters: [any AgentAdapter] = [HeuristicAdapter()]) {
        self.adapters = adapters
        self.selected = adapters.first(where: { $0.isAvailable })
    }

    public var available: [any AgentAdapter] { adapters.filter { $0.isAvailable } }

    public func register(_ adapter: any AgentAdapter) {
        adapters.append(adapter)
        if selected == nil, adapter.isAvailable { selected = adapter }
    }

    public func select(named name: String) {
        selected = adapters.first { $0.providerName == name && $0.isAvailable }
    }
}
