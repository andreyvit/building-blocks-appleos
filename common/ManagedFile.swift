/**
Manages files and groups of files for internal purposes (caches, databases,
Application Support data) and user data in iOS and shoebox-style apps.

This component is part of the Building Blocks initiative. We believe that apps
should be assembled from standardized building blocks like houses, not designed
from scratch like cathedrals. Over time, we want to produce a collection of
composable self-contained building blocks that work well with a number of
standardized internal (app & model) architectures.

To install these building blocks, copy some into your project and check back
for updates regularly. Each component follows semantic versioning. This may seem
like too much work, but we believe the manual approach is appropriately hands-on.

© 2018 Andrey Tarantsov <andrey@tarantsov.com>, published under the terms of
the MIT license.

- v1.0.0 (2018-12-02): public version published
*/
import Foundation
import os.log

public class ManagedFile {

    fileprivate enum RootDirectory {
        case fromFileManager(Foundation.FileManager.SearchPathDirectory)
        case forAppGroup(String)
        case temporary

        fileprivate func resolve() throws -> URL {
            switch self {
            case let .fromFileManager(directory):
                // don't create to avoid failing when a folder cannot be created (which would cause a crash during initialization)
                return try Foundation.FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false)
            case let .forAppGroup(groupIdentifier):
                // will crash if the group identifier is invalid
                return Foundation.FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)!
            case .temporary:
                return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            }
        }
    }

    public enum Role {
        case cache(discardableOnLowSpace: Bool)
        case internalData(backupsEnabled: Bool)
        case exposedUserData(backupsEnabled: Bool)
        case appGroup(identifier: String, backupsEnabled: Bool)
        case temporary

        fileprivate var shouldBeExplicitlyExcludedFromBackup: Bool {
            switch self {
            case .cache(discardableOnLowSpace: false), .internalData(backupsEnabled: false), .exposedUserData(backupsEnabled: false), .appGroup(identifier: _, backupsEnabled: false):
                return true
            case .cache(discardableOnLowSpace: true), .internalData(backupsEnabled: true), .exposedUserData(backupsEnabled: true), .appGroup(identifier: _, backupsEnabled: true), .temporary:
                return false
            }
        }

        fileprivate var rootDirectorySpec: (root: RootDirectory, includesBundleSubfolder: Bool) {
            switch self {
            case .cache:
                return (.fromFileManager(.cachesDirectory), true)
            case .internalData:
                return (.fromFileManager(.applicationSupportDirectory), true)
            case .exposedUserData:
                return (.fromFileManager(.documentDirectory), false)
            case let .appGroup(identifier: groupIdentifier, backupsEnabled: _):
                return (.forAppGroup(groupIdentifier), false)
            case .temporary:
                return (.temporary, false)
            }
        }

        fileprivate func rootDirectoryURL() throws -> URL {
            let (root, includesBundleSubfolder) = self.rootDirectorySpec

            let rootURL = try root.resolve()
            if includesBundleSubfolder {
                return rootURL.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
            } else {
                return rootURL
            }
        }
    }

    public class NamingScheme {

        public let subfolder: String?
        public let prefix: String?
        public let suffix: String?
        private let minNameLength: Int

        public init(subfolder: String? = nil, prefix: String? = nil, suffix: String? = nil) {
            self.subfolder = nonEmptyOrNil(subfolder)
            self.prefix = nonEmptyOrNil(prefix)
            self.suffix = nonEmptyOrNil(suffix)
            minNameLength = (self.prefix?.count ?? 0) + (self.suffix?.count ?? 0)
        }

        public static let bare = NamingScheme(subfolder: nil, prefix: nil, suffix: nil)

        public func resolveDirectory(relativeTo rootURL: URL) -> URL {
            if let subfolder = subfolder {
                return rootURL.appendingPathComponent(subfolder, isDirectory: true)
            } else {
                return rootURL
            }
        }

        public func resolveFileName(bareName: String) -> String {
            switch (prefix, suffix) {
            case (.none, .none):
                return bareName
            case (let .some(pref), .none):
                return pref + bareName
            case (.none, let .some(suff)):
                return bareName + suff
            case (let .some(pref), let .some(suff)):
                return pref + bareName + suff
            }
        }

        public func parseFileName(fullName: String) -> String? {
            if minNameLength == 0 {
                return fullName
            } else if fullName.count < minNameLength {
                return nil
            }

            var startPos = fullName.startIndex
            if let prefix = prefix {
                guard let range = fullName.range(of: prefix, options: [.anchored], range: nil, locale: nil) else {
                    return nil
                }
                startPos = range.upperBound
            }

            var endPos = fullName.endIndex
            if let suffix = suffix {
                guard let range = fullName.range(of: suffix, options: [.anchored, .backwards], range: nil, locale: nil) else {
                    return nil
                }
                endPos = range.lowerBound
            }

            return String(fullName[startPos ..< endPos])
        }

        public func matches(fullName: String) -> Bool {
            if minNameLength == 0 {
                return true
            } else if fullName.count < minNameLength {
                return false
            }

            if let prefix = prefix {
                guard fullName.range(of: prefix, options: [.anchored], range: nil, locale: nil) != nil else {
                    return false
                }
            }

            if let suffix = suffix {
                guard fullName.range(of: suffix, options: [.anchored, .backwards], range: nil, locale: nil) != nil else {
                    return false
                }
            }

            return true
        }

        var spansEntireSubfolder: Bool {
            return minNameLength == 0 && subfolder != nil
        }

    }

    public let group: ManagedFileGroup
    public let url: URL

    // private to guarantee that a file cannot be created from a URL that does not match its group
    fileprivate init(group: ManagedFileGroup, url: URL) {
        self.group = group
        self.url = url
    }

    public var bareName: String {
        if let bareName = group.namingScheme.parseFileName(fullName: url.lastPathComponent) {
            return bareName
        } else {
            fatalError("ManagedFile name does not belong to its group's naming scheme: \(url.path)")
        }
    }

    public var fullName: String {
        return url.lastPathComponent
    }

    public var exists: Bool {
        return (try? url.checkResourceIsReachable()) ?? false
    }

    public var size: Int? {
        guard let attributes = try? Foundation.FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attributes[FileAttributeKey.size] as! Int)
    }

    public var creationDate: Date? {
        guard let attributes = try? Foundation.FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attributes[FileAttributeKey.creationDate] as! Date)
    }

    public func createParentDirectory() throws {
        try group.createDirectory()
    }

    public func remove() throws {
        try Foundation.FileManager.default.removeItem(at: url)
    }

    public func resetAttributes() throws {
        var url = self.url

        try Foundation.FileManager.default.setAttributes([.protectionKey: group.protectionType], ofItemAtPath: url.path)

        var values = URLResourceValues()
        values.isExcludedFromBackup = group.role.shouldBeExplicitlyExcludedFromBackup
        try url.setResourceValues(values)
    }

    public func replaceWithFile(at sourceURL: URL, keepSourceFile: Bool) throws {
        try createParentDirectory()
        try? remove()
        if keepSourceFile {
            try Foundation.FileManager.default.copyItem(at: sourceURL, to: url)
        } else {
            try Foundation.FileManager.default.moveItem(at: sourceURL, to: url)
        }
        try resetAttributes()
    }

    public func loadData(options: Data.ReadingOptions = []) throws -> Data {
        return try Data(contentsOf: url, options: options)
    }

    public func saveData(_ data: Data) throws {
        try createParentDirectory()
        try data.write(to: url, options: group.protectionType.dataProtectionOptions)
        try resetAttributes()
    }

    public func loadJSON<T>(_ type: T.Type) throws -> T where T : Decodable {
        let data = try loadData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    public func saveJSON<T>(_ value: T) throws where T : Encodable {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try saveData(data)
    }

    public func migrate(from oldURL: URL) throws {
        guard (try? oldURL.checkResourceIsReachable()) ?? false else {
            return
        }

        if exists {
            do {
                try Foundation.FileManager.default.removeItem(at: oldURL)
                os_log("[ManagedFile_migration] Deleted legacy file at %@ (no migration attempted because new file already exists at %@)", log: OSLog.default, type: .default, oldURL.path, url.path)
            } catch {
                os_log("[ManagedFile_migration] Failed to delete legacy file at %@ (no migration attempted because new file already exists at %@): %@", log: OSLog.default, type: .error, oldURL.path, url.path, String(reflecting: error))
            }
        } else {
            os_log("[ManagedFile_migration] Migrating legacy file at %@ ==> %@", log: OSLog.default, type: .info, oldURL.path, url.path)
            try replaceWithFile(at: oldURL, keepSourceFile: false)
        }
    }

    public func migrate(from oldFile: ManagedFile) throws {
        try migrate(from: oldFile.url)
    }

}

public class ManagedFileGroup: Sequence {

    public let role: ManagedFile.Role
    public let namingScheme: ManagedFile.NamingScheme
    public let protectionType: FileProtectionType

    public let directoryURL: URL

    public init(role: ManagedFile.Role, namingScheme: ManagedFile.NamingScheme, protectionType: FileProtectionType) {
        self.role = role
        self.namingScheme = namingScheme
        self.protectionType = protectionType

        // this will crash if the directory cannot be found
        directoryURL = namingScheme.resolveDirectory(relativeTo: try! role.rootDirectoryURL())
    }

    public func file(bareName: String) -> ManagedFile {
        let fullName = namingScheme.resolveFileName(bareName: bareName)
        let url = directoryURL.appendingPathComponent(fullName, isDirectory: false)
        return ManagedFile(group: self, url: url)
    }

    public func file(fullName: String) -> ManagedFile {
        guard namingScheme.matches(fullName: fullName) else {
            fatalError("ManagedFileGroup.file(fullName:) called with a name that does not match the naming scheme: '\(fullName)'")
        }
        let url = directoryURL.appendingPathComponent(fullName, isDirectory: false)
        return ManagedFile(group: self, url: url)
    }

    public var directoryExists: Bool {
        return (try? directoryURL.checkResourceIsReachable()) ?? false
    }

    public func createDirectory() throws {
        try Foundation.FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        try resetAttributes()
    }

    public func resetAttributes() throws {
        guard namingScheme.spansEntireSubfolder else {
            return
        }

        var url = self.directoryURL

        try Foundation.FileManager.default.setAttributes([.protectionKey: protectionType], ofItemAtPath: url.path)

        var values = URLResourceValues()
        values.isExcludedFromBackup = role.shouldBeExplicitlyExcludedFromBackup
        try url.setResourceValues(values)
    }

    public func resetAttributesOnAllFiles() throws {
        try createDirectory()

        for file in self {
            try file.resetAttributes()
        }
    }

    public func removeAll() throws {
        if namingScheme.spansEntireSubfolder {
            try Foundation.FileManager.default.removeItem(at: directoryURL)
        } else {
            for file in self {
                try file.remove()
            }
        }
    }

    public func allFiles() -> [ManagedFile] {
        var files: [ManagedFile] = []
        for file in self {
            files.append(file)
        }
        return files
    }

    public func makeIterator() -> FileIterator {
        let enumerator = Foundation.FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants], errorHandler: { (url, error) -> Bool in
            return true
        })

        return FileIterator(group: self, enumerator: enumerator)
    }

    public struct FileIterator: IteratorProtocol {

        private let group: ManagedFileGroup
        private let enumerator: Foundation.FileManager.DirectoryEnumerator?

        fileprivate init(group: ManagedFileGroup, enumerator: Foundation.FileManager.DirectoryEnumerator?) {
            self.group = group
            self.enumerator = enumerator
        }

        public mutating func next() -> ManagedFile? {
            guard let enumerator = enumerator else {
                return nil
            }

            while let itemURL = enumerator.nextObject().map({ $0 as! URL }) {
                guard group.namingScheme.matches(fullName: itemURL.lastPathComponent) else {
                    continue
                }
                return ManagedFile(group: group, url: itemURL)
            }

            return nil
        }

    }

    public func migrate(from oldGroup: ManagedFileGroup) throws {
        guard oldGroup.directoryExists else {
            return
        }

        if oldGroup.namingScheme.spansEntireSubfolder && self.namingScheme.spansEntireSubfolder {
            if !self.directoryExists {
                os_log("[ManagedFile_migration] Migrating legacy directory at %@ ==> %@", log: OSLog.default, type: .info, oldGroup.directoryURL.path, self.directoryURL.path)
                try Foundation.FileManager.default.moveItem(at: oldGroup.directoryURL, to: self.directoryURL)
                try resetAttributesOnAllFiles()
                return
            }
        }

        var firstError: Error?
        for oldFile in oldGroup {
            let newFile = file(bareName: oldFile.bareName)
            do {
                try newFile.migrate(from: oldFile)
            } catch {
                os_log("[ManagedFile_migration] Failed to migrate %@ ==> %@: %@", log: OSLog.default, type: .error, oldFile.url.path, newFile.url.path, String(reflecting: error))
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError = firstError {
            throw firstError
        }

        if oldGroup.namingScheme.spansEntireSubfolder {
            os_log("[ManagedFile_migration] Deleting legacy directory after migration: %@", log: OSLog.default, type: .info, oldGroup.directoryURL.path)
            try Foundation.FileManager.default.removeItem(at: oldGroup.directoryURL)
        }
    }

}

private func nonEmptyOrNil(_ value: String?) -> String? {
    if let value = value, !value.isEmpty {
        return value
    } else {
        return nil
    }
}

fileprivate extension FileProtectionType {

    var dataProtectionOptions: Data.WritingOptions {
        switch self {
        case .none:
            return []
        case .complete:
            return .completeFileProtection
        case .completeUnlessOpen:
            return .completeFileProtectionUnlessOpen
        case .completeUntilFirstUserAuthentication:
            return .completeFileProtectionUntilFirstUserAuthentication
        default:
            fatalError("unknown protection class")
        }
    }

}
