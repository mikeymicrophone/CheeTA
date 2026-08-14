import Combine
import Foundation

@MainActor
final class SavedGameStore: ObservableObject {
    @Published private(set) var documents: [GameDocument] = []
    @Published var lastError: String?

    private let fileManager: FileManager
    private let directory: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    static let maxFileBytes = 1_000_000

    init(directory: URL? = nil) {
        fileManager = .default
        self.directory = directory ?? fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appending(path: "Games")
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func report(_ message: String) {
        lastError = message
    }

    func loadAll() async {
        lastError = nil
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            documents = []
            return
        }

        var loaded: [GameDocument] = []
        for url in urls where url.lastPathComponent.hasSuffix(".cheeta.json") {
            do {
                let document = try decodeFile(at: url)
                loaded.append(document)
            } catch {
                lastError = error.localizedDescription
            }
        }
        documents = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ document: GameDocument) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL(for: document.id), options: .atomic)
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
        documents.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(id: UUID) throws {
        try fileManager.removeItem(at: fileURL(for: id))
        documents.removeAll { $0.id == id }
    }

    func document(id: UUID) -> GameDocument? {
        documents.first { $0.id == id }
    }

    func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).cheeta.json")
    }

    func siblings(parentID: UUID?, forkPlyIndex: Int?) -> [GameDocument] {
        documents.filter { $0.parentID == parentID && $0.forkPlyIndex == forkPlyIndex }
    }

    private func decodeFile(at url: URL) throws -> GameDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > Self.maxFileBytes {
            throw GameDocumentError.fileTooLarge
        }
        let data = try Data(contentsOf: url)
        if data.count > Self.maxFileBytes {
            throw GameDocumentError.fileTooLarge
        }
        let document = try decoder.decode(GameDocument.self, from: data)
        guard document.schemaVersion == GameDocument.currentSchemaVersion else {
            throw GameDocumentError.unsupportedSchema(document.schemaVersion)
        }
        _ = try document.decodedMoves()
        return document
    }
}
