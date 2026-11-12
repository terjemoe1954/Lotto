#if DEBUG
import Foundation
import CoreData
import CloudKit
import CryptoKit
import SwiftData

/// Explicit developer-only checks. Never executed by a normal launch or Release build.
@MainActor enum LottoCloudDevelopment {
    static var observer: NSObjectProtocol?
    static var events: [String: String] = [:]
    static func monitor() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let name = event.type == .setup ? "setup" : event.type == .import ? "import" : "export"
            let state = event.endDate == nil ? "running" : event.succeeded ? "success" : "failed: \(event.error?.localizedDescription ?? "unknown")"
            Task { @MainActor in events[name] = state; print("LOTTO_CLOUD_EVENT \(name): \(state)") }
        }
    }
    static let testID = "codex-icloud-ledger-check-2026-11-12"
    static let containerID = "iCloud.iCloude.com.terjemoe.Lottery"
    static func initialize(configuration: ModelConfiguration) throws {
        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self]) else {
                throw CocoaError(.persistentStoreInvalidType)
            }
            let description = NSPersistentStoreDescription(url: configuration.url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "Lotto", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var failure: Error?
            container.loadPersistentStores { _, error in failure = error }
            if let failure { throw failure }
            defer {
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
            try container.initializeCloudKitSchema()
            print("LOTTO_CLOUD_SCHEMA_INITIALIZED")
        }
    }
    static func run(context: ModelContext) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--lotto-cloud-check"), arguments.indices.contains(index + 1) else {
            // Remove only this developer-created status file after returning to a normal launch.
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("lotto-cloud-check.json"))
            return
        }
        let action = arguments[index + 1]
        guard ["seed", "observe", "update", "cleanup"].contains(action) else { return }
        do {
            let entries = try context.fetch(FetchDescriptor<LotteryLedgerEntry>()).filter { $0.entryID == testID }
            switch action {
            case "seed":
                if entries.isEmpty {
                    context.insert(LotteryLedgerEntry(record: LotteryLedgerRecord(id: testID, gameID: "lotto", date: .now, stakeOre: 10000, prizeOre: 4500, note: "TEST – midlertidig iCloud-kontroll")))
                }
            case "update":
                guard let entry = entries.first else { throw CocoaError(.fileNoSuchFile) }
                entry.prizeOre = 5000
            case "cleanup": entries.forEach { context.delete($0) }
            default: break
            }
            try context.save()
            let cloud = CKContainer(identifier: containerID)
            var identity = "unavailable"
            do {
                let user = try await cloud.userRecordID()
                identity = SHA256.hash(data: Data(user.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
            } catch { print("LOTTO_CLOUD_ACCOUNT_ERROR: \(error.localizedDescription)") }
            // Export only the explicitly-created test record state, never personal ledger content.
            for _ in 0..<180 {
                let records = try context.fetch(FetchDescriptor<LotteryLedgerEntry>()).filter { $0.entryID == testID }
                let status: [String: Any] = ["accountHash": identity, "events": events, "action": action, "testID": testID, "count": records.count,
                                           "prizeOre": records.first?.prizeOre ?? -1,
                                           "observedAt": ISO8601DateFormatter().string(from: .now)]
                let url = URL.documentsDirectory.appendingPathComponent("lotto-cloud-check.json")
                try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]).write(to: url, options: .atomic)
                try await Task.sleep(for: .seconds(2))
            }
        } catch { print("LOTTO_CLOUD_CHECK_ERROR: \(error)") }
    }
}
#endif
