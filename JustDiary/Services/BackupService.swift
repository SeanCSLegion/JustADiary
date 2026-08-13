import Foundation
import SQLite3

struct BackupManifest: Codable {
    var formatVersion: Int
    var appVersion: String
    var exportedAt: Int64
    var includeSettings: Bool
    var diaryCount: Int
    var blockCount: Int
    var imageCount: Int
    var images: [BackupImageRef]
    var settingsJson: String
}

struct BackupImageRef: Codable {
    var src: String
    var file: String
}

struct BackupStats {
    var importedDays: Int
    var skippedDays: Int
    var overwrittenDays: Int
    var importedBlocks: Int
    var importedImages: Int
    var settingsRestored: Bool
}

enum BackupService {
    static func exportBackup(includeSettings: Bool) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let repo = DiaryRepository.shared
            await repo.ensureSearchIndex()
            let stamp = Int64(Date().timeIntervalSince1970 * 1000)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("jdiary_export_\(stamp)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            let dbDir = tempDir.appendingPathComponent("db")
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let imagesDir = tempDir.appendingPathComponent("images")
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

            try snapshotDatabase(to: dbDir.appendingPathComponent("just_diary.db").path)

            let blockRows = await repo.rawBlocksForBackup()
            var imageRefs: [BackupImageRef] = []
            var usedNames = Set<String>()
            for (_, json) in blockRows {
                for src in ImagePathUtil.collectImageSrcs(json) {
                    let key = ImagePathUtil.normalizeSrcKey(src)
                    let sourcePath = ImagePathUtil.resolveImagePath(key)
                    guard FileManager.default.fileExists(atPath: sourcePath) else { continue }
                    var fileName = (key as NSString).lastPathComponent
                    var target = imagesDir.appendingPathComponent(fileName)
                    var counter = 1
                    while usedNames.contains(target.lastPathComponent) {
                        fileName = "\(((key as NSString).lastPathComponent as NSString).deletingPathExtension)_\(counter).\((key as NSString).pathExtension)"
                        target = imagesDir.appendingPathComponent(fileName)
                        counter += 1
                    }
                    usedNames.insert(target.lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: target)
                        imageRefs.append(BackupImageRef(src: key, file: "images/\(target.lastPathComponent)"))
                    } catch {
                        Log.backup.error("copy image failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }

            let settings = SettingsStore.load()
            let diaryCount = await repo.countDiaries()
            let blockCount = await repo.countBlocks()
            let manifest = BackupManifest(
                formatVersion: 1,
                appVersion: SettingsStore.appVersion,
                exportedAt: stamp,
                includeSettings: includeSettings,
                diaryCount: diaryCount,
                blockCount: blockCount,
                imageCount: imageRefs.count,
                images: imageRefs,
                settingsJson: includeSettings ? settingsJsonString(settings) : "")

            var entries: [ZipEntry] = []
            entries.append(ZipEntry(path: "manifest.json", data: try JSONEncoder().encode(manifest)))
            let dbData = try Data(contentsOf: dbDir.appendingPathComponent("just_diary.db"))
            entries.append(ZipEntry(path: "db/just_diary.db", data: dbData))
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) {
                for file in files {
                    if let data = try? Data(contentsOf: file) {
                        entries.append(ZipEntry(path: "images/\(file.lastPathComponent)", data: data))
                    }
                }
            }
            let zipData = try ZipArchive.create(entries: entries)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let outName = "JustDiary_\(formatter.string(from: Date())).jdiary"
            let keepURL = FileManager.default.temporaryDirectory.appendingPathComponent(outName)
            try? FileManager.default.removeItem(at: keepURL)
            try zipData.write(to: keepURL)
            Log.backup.info("export done: \(diaryCount) diaries, \(imageRefs.count) images")
            return keepURL
        }.value
    }

    /// UI 测试自动化导入入口（通过启动参数 -ui-test-import <path> 触发）。
    static func runAutoImport() async {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui-test-import"), args.count > idx + 1 else { return }
        var path = args[idx + 1]
        let mode = args.contains("-ui-test-import-overwrite") ? "overwrite" : "skip"
        if !FileManager.default.fileExists(atPath: path) {
            let candidate = NSHomeDirectory() + "/Documents/" + (path as NSString).lastPathComponent
            if FileManager.default.fileExists(atPath: candidate) { path = candidate }
        }
        Log.backup.info("auto import start: \(path, privacy: .public) mode=\(mode, privacy: .public)")
        let resultLog = NSHomeDirectory() + "/Documents/import-result.log"
        try? "start import \(path) mode=\(mode)\n".write(toFile: resultLog, atomically: true, encoding: .utf8)
        do {
            let stats = try await importBackup(fileURL: URL(fileURLWithPath: path), mode: mode)
            let msg = """
            OK importedDays=\(stats.importedDays) skippedDays=\(stats.skippedDays) overwrittenDays=\(stats.overwrittenDays) blocks=\(stats.importedBlocks) images=\(stats.importedImages) settings=\(stats.settingsRestored)
            """
            Log.backup.info("auto import done: \(msg, privacy: .public)")
            try? msg.appendToFile2(resultLog)
            try? msg.write(toFile: NSHomeDirectory() + "/Documents/import-ok.log", atomically: true, encoding: .utf8)
        } catch {
            Log.backup.error("auto import failed: \(String(describing: error), privacy: .public)")
            try? "FAIL \(error)\n".write(toFile: NSHomeDirectory() + "/Documents/import-fail.log", atomically: true, encoding: .utf8)
            try? "FAIL \(error)\n".appendToFile2(resultLog)
        }
    }

    static func importBackup(fileURL: URL, mode: String) async throws -> BackupStats {
        try await Task.detached(priority: .userInitiated) {
            let stamp = Int64(Date().timeIntervalSince1970 * 1000)
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("jdiary_import_\(stamp)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            let data = try Data(contentsOf: fileURL)
            let entries = try ZipArchive.extract(data)
            let manifestData: Data
            if let m = entries["manifest.json"] {
                manifestData = m
            } else if let m = entries["jdiary_export/manifest.json"] {
                manifestData = m
            } else {
                throw BackupError.invalidManifest
            }
            let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
            guard manifest.formatVersion == 1 else { throw BackupError.invalidVersion }

            let imagesDir = tempDir.appendingPathComponent("images")
            let dbDir = tempDir.appendingPathComponent("db")
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            var imageFiles: [String: Data] = [:]
            for (path, d) in entries where path.hasPrefix("images/") {
                imageFiles[path] = d
            }
            var backupDbData = entries["db/just_diary.db"]
            if backupDbData == nil { backupDbData = entries["jdiary_export/db/just_diary.db"] }
            guard let dbData = backupDbData else { throw BackupError.invalidManifest }
            let dbPath = dbDir.appendingPathComponent("backup.db").path
            try dbData.write(to: URL(fileURLWithPath: dbPath))

            let srcMap = Dictionary(uniqueKeysWithValues: manifest.images.map { ($0.src, $0.file) })
            var copiedMap: [String: String] = [:]
            var importedImages = 0

            func copyImage(_ src: String) -> String {
                let key = ImagePathUtil.normalizeSrcKey(src)
                if let existing = copiedMap[key] { return existing }
                guard let file = srcMap[key], let imgData = imageFiles[file] else { return key }
                let ext = (file as NSString).pathExtension.isEmpty ? "jpg" : (file as NSString).pathExtension
                let newName = "imp_\(stamp)_\(importedImages + 1).\(ext)"
                importedImages += 1
                let target = DiaryRepository.imagesDir().appendingPathComponent(newName)
                do {
                    try FileManager.default.createDirectory(at: DiaryRepository.imagesDir(), withIntermediateDirectories: true)
                    try imgData.write(to: target)
                    let newKey = "images/\(newName)"
                    copiedMap[key] = newKey
                    return newKey
                } catch {
                    Log.backup.error("write image failed: \(String(describing: error), privacy: .public)")
                    return key
                }
            }

            let repo = DiaryRepository.shared
            var stats = BackupStats(importedDays: 0, skippedDays: 0, overwrittenDays: 0,
                                    importedBlocks: 0, importedImages: 0, settingsRestored: false)
            try await repo.mergeBackupDatabase(path: dbPath, mode: mode, copyImage: copyImage, stats: &stats)
            stats.importedImages = importedImages

            if !manifest.settingsJson.isEmpty, let s = try? JSONDecoder().decode(AppSettings.self,
                                                                                from: Data(manifest.settingsJson.utf8)) {
                SettingsStore.save(s)
                stats.settingsRestored = true
            }
            Log.backup.info("import done: +\(stats.importedDays) -\(stats.overwrittenDays) ~\(stats.skippedDays)")
            return stats
        }.value
    }

    private static func snapshotDatabase(to path: String) throws {
        let srcPath = DiaryRepository.dbPath()
        var srcDb: OpaquePointer?
        var dstDb: OpaquePointer?
        guard sqlite3_open_v2(srcPath, &srcDb, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BackupError.dbError
        }
        defer { if let s = srcDb { sqlite3_close(s) } }
        guard sqlite3_open_v2(path, &dstDb, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw BackupError.dbError
        }
        defer { if let d = dstDb { sqlite3_close(d) } }
        let backup = sqlite3_backup_init(dstDb, "main", srcDb, "main")
        guard backup != nil else { throw BackupError.dbError }
        defer { sqlite3_backup_finish(backup) }
        let rc = sqlite3_backup_step(backup, -1)
        guard rc == SQLITE_DONE else { throw BackupError.dbError }
    }

    private static func settingsJsonString(_ s: AppSettings) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}

enum BackupError: Error {
    case invalidManifest
    case invalidVersion
    case dbError
}
