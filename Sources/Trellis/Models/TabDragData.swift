import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Data transferred during tab drag & drop operations.
/// Contains the tab ID and its source area ID to support inter-area moves.
public struct TabDragData: Codable, Transferable, Equatable {
    public let tabId: UUID
    public let sourceAreaId: UUID

    public init(tabId: UUID, sourceAreaId: UUID) {
        self.tabId = tabId
        self.sourceAreaId = sourceAreaId
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabDragData)
    }
}

extension UTType {
    static let tabDragData = UTType(exportedAs: "dev.trellis.tab-drag-data")
}
