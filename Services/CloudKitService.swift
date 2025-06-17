import Foundation
import CloudKit
import Combine

/// Manages all interactions with the CloudKit private database.
class CloudKitService {
    
    // MARK: - Properties
    
    let errorPublisher = PassthroughSubject<Error, Never>()
    let recordsChangedPublisher = PassthroughSubject<[CKRecord], Never>()
    let deletedRecordIDsPublisher = PassthroughSubject<[CKRecord.ID], Never>()

    private let container = CKContainer(identifier: "iCloud.com.scalegj.DronePal")
    private var database: CKDatabase { container.privateCloudDatabase }
    
    static let customZoneID = CKRecordZone.ID(zoneName: "DronePalZone", ownerName: CKCurrentUserDefaultName)
    private let customZone = CKRecordZone(zoneID: customZoneID)

    // MARK: - Change Token Handling
    
    private let changeTokenKey = "cloudKitPrivateCustomZoneChangeToken"
    
    private var databaseChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
            do {
                return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
            } catch {
                AppLogger.persistence.error("Failed to unarchive CKServerChangeToken: \(error)")
                return nil
            }
        }
        set {
            guard let token = newValue, let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
                UserDefaults.standard.removeObject(forKey: changeTokenKey)
                return
            }
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        }
    }

    // MARK: - Zone Management
    
    func createZoneIfNeeded() async {
        do {
            _ = try await database.recordZone(for: Self.customZoneID)
            AppLogger.general.info("Custom zone already exists.")
        } catch {
            AppLogger.general.info("Custom zone not found, attempting to create it.")
            do {
                _ = try await database.save(customZone)
                AppLogger.general.info("Successfully created custom zone.")
            } catch {
                AppLogger.general.error("Failed to create custom zone: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Public API
    
    func fetchRecord(withID recordID: CKRecord.ID) async -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch {
            if let ckError = error as? CKError, ckError.code != .unknownItem {
                 AppLogger.network.error("CloudKit fetch failed for \(recordID.recordName): \(error.localizedDescription)")
                 errorPublisher.send(error)
            }
            return nil
        }
    }
    
    func fetchRecords(recordType: String) async -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        do {
            let (results, _) = try await database.records(matching: query, inZoneWith: Self.customZoneID)
            return results.compactMap { try? $0.1.get() }
        } catch {
            AppLogger.network.error("CloudKit fetch failed for \(recordType): \(error.localizedDescription)")
            errorPublisher.send(error)
            return []
        }
    }

    // ** THE FIX IS HERE **
    // This corrected function uses the `.changedKeys` save policy, which is the
    // modern and correct way to handle creating and updating records without
    // causing version conflicts or needing to fetch before saving.
    func save<T: CloudKitSyncable>(_ item: T) async {
        let recordToSave = item.ckRecord
        
        do {
            // The `savePolicy: .changedKeys` parameter is the key. It tells CloudKit
            // to intelligently merge our changes. If the record is new, it's created.
            // If it exists, only the fields we provide are updated, preventing data loss
            // from other devices and resolving the "record to insert already exists" error.
            _ = try await database.modifyRecords(saving: [recordToSave], deleting: [], savePolicy: .changedKeys)
            AppLogger.network.info("Successfully saved record with changedKeys policy: \(recordToSave.recordID.recordName)")
        } catch let error as CKError {
            // With .changedKeys, a .serverRecordChanged error is less likely, but we can still log it.
            // This error means a conflict occurred that couldn't be automatically merged.
            // Our app's sync mechanism will eventually receive the server version and update the UI.
            if error.code == .serverRecordChanged {
                AppLogger.network.warning("Save failed for \(recordToSave.recordID.recordName) due to a server change. The conflict should be resolved by a down-sync. Error: \(error.localizedDescription)")
            } else {
                AppLogger.network.error("CloudKit save failed for \(recordToSave.recordID.recordName): \(error.localizedDescription)")
                errorPublisher.send(error)
            }
        } catch {
            AppLogger.network.error("An unexpected error occurred during save for \(recordToSave.recordID.recordName): \(error.localizedDescription)")
            errorPublisher.send(error)
        }
    }
    
    func delete(recordID: CKRecord.ID) async {
        do {
            _ = try await database.deleteRecord(withID: recordID)
            AppLogger.network.info("Successfully deleted record: \(recordID.recordName)")
        } catch {
            AppLogger.network.error("CloudKit delete failed for \(recordID.recordName): \(error.localizedDescription)")
            errorPublisher.send(error)
        }
    }
    
    // MARK: - Subscription Handling
    
    func subscribeToChanges(for recordType: String) async {
        let subscriptionID = "\(Self.customZoneID.zoneName)-\(recordType)-changes"
        
        do {
            let existingSubscriptions = try await database.allSubscriptions()
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                AppLogger.network.info("Subscription already exists for \(recordType).")
                return
            }
        } catch {
             AppLogger.network.error("Failed to check for existing subscription for \(recordType): \(error)")
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        subscription.recordType = recordType
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await database.save(subscription)
            AppLogger.network.info("Successfully subscribed to changes for \(recordType).")
        } catch {
            AppLogger.network.error("Failed to subscribe to changes for \(recordType): \(error)")
            errorPublisher.send(error)
        }
    }

    func handleNotification(from userInfo: [AnyHashable: Any]) async {
        if let _ = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            await fetchDatabaseChanges()
        }
    }

    func fetchDatabaseChanges() async {
        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []

        do {
            let zoneChanges = try await database.recordZoneChanges(inZoneWith: Self.customZoneID, since: databaseChangeToken)
            
            for change in zoneChanges.modificationResultsByID.values {
                if case .success(let modification) = change {
                    changedRecords.append(modification.record)
                }
            }
            
            for deletion in zoneChanges.deletions {
                deletedRecordIDs.append(deletion.recordID)
            }

            self.databaseChangeToken = zoneChanges.changeToken
            
        } catch {
            AppLogger.network.error("Failed to fetch database changes: \(error.localizedDescription)")
            if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                self.databaseChangeToken = nil
                AppLogger.network.warning("CloudKit change token expired. A full refetch is needed.")
            }
            return
        }
        
        if !changedRecords.isEmpty {
            AppLogger.network.info("Fetched and publishing \(changedRecords.count) remote changes.")
            recordsChangedPublisher.send(changedRecords)
        }
        
        if !deletedRecordIDs.isEmpty {
            AppLogger.network.info("Fetched and publishing \(deletedRecordIDs.count) remote deletions.")
            deletedRecordIDsPublisher.send(deletedRecordIDs)
        }
    }
}
