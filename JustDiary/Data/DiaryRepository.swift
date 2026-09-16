import Foundation
import CoreLocation
import MapKit
import os

nonisolated extension Notification.Name {
    static let diaryVersionChanged = Notification.Name("diaryVersionChanged")
    static let uiTickChanged = Notification.Name("uiTickChanged")
}

nonisolated final class DiaryRepository {
    static let shared = DiaryRepository()
    static let searchLimit = 200
    static let searchIndexVersion = 3

    private var db: SQLite?
    private let queue = DispatchQueue(label: "com.cov.justdiary.db")
    private var ftsSupported = false

    private init() {}

    private static let noLocSql = """
    NOT EXISTS (SELECT 1 FROM edit_block b WHERE b.diary_id = d.id
      AND (b.loc_quality <> 'none' OR b.loc_text <> '' OR b.country <> '' OR b.region1 <> ''
           OR b.region2 <> '' OR b.region3 <> '' OR b.latitude != 0 OR b.longitude != 0))
    """

    static var dbPathOverride: String?
    static var imagesDirOverride: URL?

    private var isSearchIndexReady: Bool {
        SettingsStore.searchIndexVersion >= Self.searchIndexVersion
    }

    private var isFtsTableExists: Bool {
        db?.query("SELECT name FROM sqlite_master WHERE type='table' AND name='diary_fts';").count ?? 0 > 0
    }

    static func dbPath() -> String {
        if let override = dbPathOverride { return override }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("just_diary.db").path
    }

    static func imagesDir() -> URL {
        if let override = imagesDirOverride { return override }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("images")
    }

    func prepare() async {
        await runOnQueue { [self] in
            guard db == nil else { return }
            let path = Self.dbPath()
            do {
                try FileManager.default.createDirectory(at: Self.imagesDir(), withIntermediateDirectories: true)
                let sqlite = try SQLite(path: path)
                db = sqlite
                do {
                    try migrateSchema()
                    try ensureFtsTable()
                    try migrateContentFormat()
                    try backfillIndexIfNeeded()
                } catch {
                    Log.db.error("migrate/index failed: \(String(describing: error), privacy: .public)")
                }
            } catch {
                Log.db.error("open failed: \(String(describing: error), privacy: .public)")
            }
        }
        await scheduleBackgroundMaintenance()
    }

    func bumpDiaryVersion() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .diaryVersionChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .diaryVersionChanged, object: nil)
            }
        }
    }

    func bumpUiTick() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .uiTickChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .uiTickChanged, object: nil)
            }
        }
    }

    private func migrateSchema() throws {
        guard let db else { return }
        let v = db.userVersion
        if v < 1 {            try db.execute("""
            CREATE TABLE IF NOT EXISTS diary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              day_key TEXT NOT NULL UNIQUE,
              summary TEXT NOT NULL DEFAULT '',
              search_text TEXT NOT NULL DEFAULT '',
              created_utc INTEGER NOT NULL,
              updated_utc INTEGER NOT NULL
            );
            """)
            try db.execute("""
            CREATE TABLE IF NOT EXISTS edit_block (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              diary_id INTEGER NOT NULL,
              start_time_utc INTEGER NOT NULL,
              loc_text TEXT NOT NULL DEFAULT '',
              latitude REAL NOT NULL DEFAULT 0,
              longitude REAL NOT NULL DEFAULT 0,
              content_json TEXT NOT NULL DEFAULT '[]',
              search_text TEXT NOT NULL DEFAULT '',
              loc_precision TEXT NOT NULL DEFAULT 'none',
              loc_quality TEXT NOT NULL DEFAULT 'none',
              country TEXT NOT NULL DEFAULT '',
              country_code TEXT NOT NULL DEFAULT '',
              region1 TEXT NOT NULL DEFAULT '',
              region2 TEXT NOT NULL DEFAULT '',
              region3 TEXT NOT NULL DEFAULT '',
              created_utc INTEGER NOT NULL,
              updated_utc INTEGER NOT NULL
            );
            """)
            try db.execute("CREATE TABLE IF NOT EXISTS diary_flag (day_key TEXT PRIMARY KEY);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_diary ON edit_block(diary_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_start ON edit_block(start_time_utc);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_country_region ON edit_block(country, region1, diary_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_diary_quality ON edit_block(diary_id, loc_quality);")
            db.userVersion = 1
        }
        if v < 3 {
            try migrateLocationMeta()
            db.userVersion = 3
        }
    }

    private func migrateLocationMeta() throws {
        guard let db else { return }
        let cols = db.query("PRAGMA table_info(edit_block);").compactMap { $0["name"] as? String }
        let needsRebuild = !cols.contains("region1")
        if needsRebuild {
            try db.execute("DROP TABLE IF EXISTS edit_block_new;")
            try db.execute("""
            CREATE TABLE edit_block_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              diary_id INTEGER NOT NULL,
              start_time_utc INTEGER NOT NULL,
              loc_text TEXT NOT NULL DEFAULT '',
              latitude REAL NOT NULL DEFAULT 0,
              longitude REAL NOT NULL DEFAULT 0,
              content_json TEXT NOT NULL DEFAULT '[]',
              search_text TEXT NOT NULL DEFAULT '',
              loc_precision TEXT NOT NULL DEFAULT 'none',
              loc_quality TEXT NOT NULL DEFAULT 'none',
              country TEXT NOT NULL DEFAULT '',
              country_code TEXT NOT NULL DEFAULT '',
              region1 TEXT NOT NULL DEFAULT '',
              region2 TEXT NOT NULL DEFAULT '',
              region3 TEXT NOT NULL DEFAULT '',
              created_utc INTEGER NOT NULL,
              updated_utc INTEGER NOT NULL
            );
            """)
            let oldCols = cols
            func col(_ c: String) -> String { oldCols.contains(c) ? c : "''" }
            try db.execute("""
            INSERT INTO edit_block_new (id, diary_id, start_time_utc, loc_text, latitude, longitude,
              content_json, search_text, loc_precision, loc_quality, country, country_code,
              region1, region2, region3, created_utc, updated_utc)
            SELECT id, diary_id, start_time_utc, loc_text, latitude, longitude,
              \(col("content_json")), \(col("search_text")), \(col("loc_precision")), \(col("loc_quality")),
              \(col("country")), \(col("country_code")),
              \(col("province")), \(col("city")), \(col("district")), created_utc, updated_utc
            FROM edit_block;
            """)
            try db.execute("DROP TABLE edit_block;")
            try db.execute("ALTER TABLE edit_block_new RENAME TO edit_block;")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_diary ON edit_block(diary_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_start ON edit_block(start_time_utc);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_country_region ON edit_block(country, region1, diary_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_block_diary_quality ON edit_block(diary_id, loc_quality);")
        }
        if !needsRebuild, !cols.contains("loc_quality") {
            try db.execute("ALTER TABLE edit_block ADD COLUMN loc_quality TEXT NOT NULL DEFAULT 'none';")
        }
        try db.execute("""
        UPDATE edit_block SET
          loc_precision = CASE
            WHEN region3 <> '' THEN 'district'
            WHEN region2 <> '' THEN 'city'
            WHEN region1 <> '' THEN 'province'
            WHEN loc_text <> '' THEN 'province'
            ELSE 'none' END
          WHERE loc_precision = 'none' OR loc_precision = '';
        """)
        try db.execute("""
        UPDATE edit_block SET
          loc_quality = CASE WHEN latitude <> 0 OR longitude <> 0 THEN 'precise' ELSE 'coarse' END
          WHERE loc_quality = 'none' OR loc_quality = '';
        """)
        try db.execute("""
        UPDATE edit_block SET region1 = region2 WHERE region1 = '' AND region2 <> '';
        """)
    }

    private func ensureFtsTable() throws {
        guard let db else { return }
        ftsSupported = true
        do {
            try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS diary_fts USING fts5(diary_id UNINDEXED, text, tokenize='unicode61');")
        } catch {
            ftsSupported = false
        }
    }

    /// Rewrites `edit_block.content_json` in the current storage format when it
    /// is still v1 — a bare part array whose runs carried a font size and whose
    /// block style names came from HTML (`h1`/`h2`/`p`/`ul`/`img`).
    ///
    /// This is a tidiness pass, not a correctness requirement: `parseContent`
    /// decodes v1 on the fly, and the import path already re-encodes through
    /// `ImagePathUtil.normalizeContent`. Doing it once keeps the database (and
    /// therefore the backups exported from it) uniform.
    private func migrateContentFormat() throws {
        guard SettingsStore.contentFormatVersion < ContentDocument.currentVersion else { return }
        guard let db else { return }
        let rows = db.query("SELECT id, content_json FROM edit_block ORDER BY id;")
        for chunk in rows.chunked(by: 500) {
            try db.inTransaction {
                for row in chunk {
                    let id = row["id"] as! Int64
                    let json = (row["content_json"] as? String) ?? "[]"
                    let normalized = ImagePathUtil.normalizeContent(json)
                    if normalized != json {
                        // The text is unchanged, so `search_text` and the FTS
                        // index stay valid.
                        try db.execute("UPDATE edit_block SET content_json = ? WHERE id = ?;", [normalized, id])
                    }
                }
            }
        }
        SettingsStore.contentFormatVersion = ContentDocument.currentVersion
    }

    private func backfillIndexIfNeeded() throws {
        if isSearchIndexReady {
            if ftsSupported && isFtsTableExists { return }
            if !ftsSupported { return }
        }
        try rebuildSearchIndex()
    }

    private func rebuildSearchIndex() throws {
        guard let db else { return }
        let blockRows = db.query("SELECT id, content_json FROM edit_block ORDER BY id;")
        for chunk in blockRows.chunked(by: 500) {
            try db.inTransaction {
                for row in chunk {
                    let id = row["id"] as! Int64
                    let json = (row["content_json"] as? String) ?? "[]"
                    let normalized = ImagePathUtil.normalizeContent(json)
                    let text = ContentFlatten.flattenContent(normalized)
                    try db.execute("UPDATE edit_block SET content_json = ?, search_text = ? WHERE id = ?;", [normalized, text, id])
                }
            }
        }
        try db.execute("""
        UPDATE diary SET
          summary = substr(IFNULL((SELECT group_concat(search_text, ' ') FROM edit_block WHERE diary_id = diary.id), ''), 1, 40),
          search_text = IFNULL((SELECT group_concat(search_text, ' ') FROM edit_block WHERE diary_id = diary.id), '');
        """)
        if ftsSupported {
            try db.execute("DELETE FROM diary_fts;")
            let ftsRows = db.query("SELECT id, search_text FROM diary WHERE search_text <> '';")
            for row in ftsRows {
                try upsertFtsEntry(db: db, diaryId: (row["id"] as? Int64) ?? 0,
                                   searchText: (row["search_text"] as? String) ?? "")
            }
        }
        SettingsStore.searchIndexVersion = Self.searchIndexVersion
    }

    func ensureSearchIndex() async {
        await runOnQueue { [self] in
            if isSearchIndexReady {
                if ftsSupported && isFtsTableExists { return }
                if !ftsSupported { return }
            }
            try? rebuildSearchIndex()
        }
    }

    func scheduleBackgroundMaintenance() async {
        await ensureSearchIndex()
        await backfillBlockRegions()
        await cleanupOrphanImages()
    }

    func searchIndexReady() -> Bool {
        SettingsStore.searchIndexVersion >= Self.searchIndexVersion
    }

    // MARK: - Reads

    func getDiaryByDay(_ dayKey: String) async -> DiaryRecord? {
        await runOnQueue { [self] in
            guard let db else { return nil }
            guard let row = db.queryFirst("SELECT * FROM diary WHERE day_key = ?;", [dayKey]) else { return nil }
            return Self.diaryFromRow(row)
        }
    }

    func getDiaryFlagsRange(fromKey: String, toKey: String) async -> [String] {        await runOnQueue { [self] in
            db?.query("SELECT day_key FROM diary_flag WHERE day_key >= ? AND day_key <= ?;", [fromKey, toKey])
                .compactMap { $0["day_key"] as? String } ?? []
        }
    }

    func getBlocks(diaryId: Int64) async -> [EditBlock] {
        await runOnQueue { [self] in
            db?.query("SELECT * FROM edit_block WHERE diary_id = ? ORDER BY start_time_utc ASC;", [diaryId])
                .map(Self.blockFromRow) ?? []
        }
    }

    func allFootprintRows() async -> [FootprintRow] {
        await runOnQueue { [self] in
            guard let db else { return [] }
            return db.query("""
            SELECT b.id AS id, d.day_key AS day_key, b.start_time_utc AS start_time_utc,
                   b.latitude AS latitude, b.longitude AS longitude, b.loc_text AS loc_text,
                   b.loc_quality AS loc_quality, b.loc_precision AS loc_precision,
                   b.country AS country, b.country_code AS country_code,
                   b.region1 AS region1, b.region2 AS region2, b.region3 AS region3,
                   d.summary AS summary
            FROM edit_block b JOIN diary d ON d.id = b.diary_id
            ORDER BY b.start_time_utc ASC;
            """).map { row in
                FootprintRow(id: (row["id"] as? Int64) ?? 0,
                            dayKey: (row["day_key"] as? String) ?? "",
                            startTimeUtc: (row["start_time_utc"] as? Int64) ?? 0,
                            latitude: (row["latitude"] as? Double) ?? 0,
                            longitude: (row["longitude"] as? Double) ?? 0,
                            locText: (row["loc_text"] as? String) ?? "",
                            locQuality: (row["loc_quality"] as? String) ?? "none",
                            locPrecision: (row["loc_precision"] as? String) ?? "none",
                            country: (row["country"] as? String) ?? "",
                            countryCode: (row["country_code"] as? String) ?? "",
                            region1: (row["region1"] as? String) ?? "",
                            region2: (row["region2"] as? String) ?? "",
                            region3: (row["region3"] as? String) ?? "",
                            summary: (row["summary"] as? String) ?? "")
            }
        }
    }

    func getLocationOptions(keyword: String, fromKey: String, toKey: String) async -> (options: [LocOption], noLocCount: Int) {
        await runOnQueue { [self] in
            guard let db else { return ([], 0) }
            let from = fromKey, to = toKey
            let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let kwLike = "%\(kw)%"
            var optionMap: [String: LocOption] = [:]
            var order: [String] = []
            func merge(_ key: String, _ option: LocOption) {
                if optionMap[key] == nil {
                    optionMap[key] = option
                    order.append(key)
                } else {
                    var o = optionMap[key]!
                    o.count += option.count
                    optionMap[key] = o
                }
            }
            let rows1 = db.query("""
            SELECT b.country AS country, b.region1 AS region1, COUNT(DISTINCT d.id) AS cnt
            FROM edit_block b JOIN diary d ON d.id = b.diary_id
            WHERE d.day_key >= ? AND d.day_key <= ? AND b.region1 <> '' AND b.country <> ''
            AND (b.country LIKE ? OR b.region1 LIKE ?)
            GROUP BY b.country, b.region1;
            """, [from, to, kwLike, kwLike])
            for r in rows1 {
                let key = "\(r["country"] ?? "")\u{1}\(r["region1"] ?? "")"
                merge(key, LocOption(country: (r["country"] as? String) ?? "",
                                     region1: (r["region1"] as? String) ?? "",
                                     count: Int((r["cnt"] as? Int64) ?? 0)))
            }
            let rows2 = db.query("""
            SELECT b.country AS country, COUNT(DISTINCT d.id) AS cnt
            FROM edit_block b JOIN diary d ON d.id = b.diary_id
            WHERE d.day_key >= ? AND d.day_key <= ? AND b.region1 = '' AND b.country <> ''
            AND b.country LIKE ?
            GROUP BY b.country;
            """, [from, to, kwLike])
            for r in rows2 {
                let country = (r["country"] as? String) ?? ""
                let key = "\(country)\u{1}"
                merge(key, LocOption(country: country, region1: "", count: Int((r["cnt"] as? Int64) ?? 0)))
            }
            let options = order
                .compactMap { optionMap[$0] }
                .sorted { $0.count > $1.count || ($0.count == $1.count && ($0.country + $0.region1) < ($1.country + $1.region1)) }
                .prefix(20)
                .map { $0 }
            let noLocRow = db.queryFirst("""
            SELECT COUNT(*) AS cnt FROM diary d
            WHERE d.day_key >= ? AND d.day_key <= ?
            AND \(Self.noLocSql);
            """, [from, to])
            let noLoc = Int((noLocRow?["cnt"] as? Int64) ?? 0)
            return (options, noLoc)
        }
    }

    // MARK: - Writes

    func addBlock(startTimeUtc: Int64, locText: String, latitude: Double, longitude: Double,
                  locPrecision: String, region: LocRegion, contentJson: String, dayStartHour: Int) async throws -> Int64 {
        try await runOnQueue { [self] in
            guard let db else { throw DBError.notReady }
            let dayKey = DateUtil.dayKeyForUtc(startTimeUtc, dayStartHour: dayStartHour)
            return try db.inTransaction {
                var diaryId: Int64 = 0
                try db.execute("INSERT OR IGNORE INTO diary(day_key, created_utc, updated_utc) VALUES (?, ?, ?);", [dayKey, startTimeUtc, startTimeUtc])
                if let row = db.queryFirst("SELECT id FROM diary WHERE day_key = ?;", [dayKey]) {
                    diaryId = (row["id"] as? Int64) ?? 0
                }
                try db.execute("INSERT OR IGNORE INTO diary_flag(day_key) VALUES (?);", [dayKey])
                try db.execute("""
                INSERT INTO edit_block(diary_id, start_time_utc, loc_text, latitude, longitude,
                  content_json, search_text, loc_precision, loc_quality, country, country_code,
                  region1, region2, region3, created_utc, updated_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [diaryId, startTimeUtc, locText, latitude, longitude, contentJson,
                      ContentFlatten.flattenContent(contentJson), locPrecision, region.locQuality,
                      region.country, region.countryCode, region.region1, region.region2, region.region3,
                      startTimeUtc, startTimeUtc])
                let blockId = db.lastInsertId()
                try touchDiaryTx(diaryId: diaryId, updatedUtc: startTimeUtc)
                return blockId
            }
        }
    }

    func addBlockToDiary(diaryId: Int64, startTimeUtc: Int64, locText: String, latitude: Double,                         longitude: Double, locPrecision: String, region: LocRegion,
                         contentJson: String) async throws -> Int64 {
        try await runOnQueue { [self] in
            guard let db else { throw DBError.notReady }
            return try db.inTransaction {
                try db.execute("""
                INSERT INTO edit_block(diary_id, start_time_utc, loc_text, latitude, longitude,
                  content_json, search_text, loc_precision, loc_quality, country, country_code,
                  region1, region2, region3, created_utc, updated_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [diaryId, startTimeUtc, locText, latitude, longitude, contentJson,
                      ContentFlatten.flattenContent(contentJson), locPrecision, region.locQuality,
                      region.country, region.countryCode, region.region1, region.region2, region.region3,
                      startTimeUtc, startTimeUtc])
                let blockId = db.lastInsertId()
                try touchDiaryTx(diaryId: diaryId, updatedUtc: startTimeUtc)
                return blockId
            }
        }
    }

    /// Saves a block's content, and optionally the location it is displayed
    /// with.
    ///
    /// Only the precision and its text can change after a block exists — the
    /// coordinates and the reverse-geocoded region belong to the moment it was
    /// written — so those are the only location columns this touches. Pass the
    /// location columns as `nil` to leave them alone.
    func updateBlockContent(blockId: Int64, contentJson: String,
                            locText: String? = nil, locPrecision: String? = nil) async throws {
        try await runOnQueue { [self] in
            guard let db else { throw DBError.notReady }
            let oldRow = db.queryFirst("SELECT content_json, diary_id FROM edit_block WHERE id = ?;", [blockId])
            let oldJson = (oldRow?["content_json"] as? String) ?? "[]"
            let diaryId = (oldRow?["diary_id"] as? Int64) ?? 0
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let newJson = ImagePathUtil.normalizeContent(contentJson)
            let text = ContentFlatten.flattenContent(newJson)
            try db.inTransaction {
                if let locText, let locPrecision {
                    try db.execute("""
                    UPDATE edit_block SET content_json = ?, search_text = ?, updated_utc = ?,
                      loc_text = ?, loc_precision = ? WHERE id = ?;
                    """, [newJson, text, now, locText, locPrecision, blockId])
                } else {
                    try db.execute("UPDATE edit_block SET content_json = ?, search_text = ?, updated_utc = ? WHERE id = ?;",
                                   [newJson, text, now, blockId])
                }
                if diaryId > 0 { try touchDiaryTx(diaryId: diaryId, updatedUtc: now) }
            }
            cleanupImages(from: oldJson, to: newJson)
        }
    }

    func deleteBlocks(_ ids: [Int64]) async throws {
        guard !ids.isEmpty else { return }
        try await runOnQueue { [self] in
            guard let db else { throw DBError.notReady }
            var removedJsons: [String] = []
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let rows = db.query("SELECT content_json FROM edit_block WHERE id IN (\(placeholders));", ids.map { $0 as Any? })
            removedJsons = rows.compactMap { $0["content_json"] as? String }
            let diaryRows = db.query("SELECT DISTINCT diary_id FROM edit_block WHERE id IN (\(placeholders));", ids.map { $0 as Any? })
            try db.inTransaction {
                try db.execute("DELETE FROM edit_block WHERE id IN (\(placeholders));", ids.map { $0 as Any? })
                for r in diaryRows {
                    let diaryId = (r["diary_id"] as? Int64) ?? 0
                    let remain = db.queryFirst("SELECT COUNT(*) AS cnt FROM edit_block WHERE diary_id = ?;", [diaryId])
                    let cnt = (remain?["cnt"] as? Int64) ?? 0
                    if cnt == 0 {
                        if let d = db.queryFirst("SELECT day_key FROM diary WHERE id = ?;", [diaryId]) {
                            let dayKey = (d["day_key"] as? String) ?? ""
                            try db.execute("DELETE FROM diary WHERE id = ?;", [diaryId])
                            try db.execute("DELETE FROM diary_flag WHERE day_key = ?;", [dayKey])
                            if ftsSupported {
                                try db.execute("DELETE FROM diary_fts WHERE diary_id = ?;", [diaryId])
                            }
                        }
                    } else {
                        let now = Int64(Date().timeIntervalSince1970 * 1000)
                        try touchDiaryTx(diaryId: diaryId, updatedUtc: now)
                    }
                }
            }
            for json in removedJsons {
                removeUnreferencedImages(in: json)
            }
        }
    }

    /// Erases the entry for one day, cleaning up its blocks, index rows and any
    /// images it no longer references.
    ///
    /// Used by the editor round-trip UI tests (`-ui-test-reset-data`) so a run
    /// starts from a clean day without wiping the sample data that the home,
    /// footprint and search screens' tests rely on.
    func deleteDiaryByDay(_ dayKey: String) async {
        guard let diary = await getDiaryByDay(dayKey) else { return }
        let ids = await getBlocks(diaryId: diary.id).map(\.id)
        try? await deleteBlocks(ids)
    }

    private func touchDiaryTx(diaryId: Int64, updatedUtc: Int64) throws {
        guard let db else { return }
        try db.execute("""
        UPDATE diary SET
          summary = substr(IFNULL((SELECT group_concat(search_text, ' ') FROM edit_block WHERE diary_id = ?), ''), 1, 40),
          search_text = IFNULL((SELECT group_concat(search_text, ' ') FROM edit_block WHERE diary_id = ?), ''),
          updated_utc = ?
        WHERE id = ?;
        """, [diaryId, diaryId, updatedUtc, diaryId])
        if ftsSupported {
            if let row = db.queryFirst("SELECT id, search_text FROM diary WHERE id = ? AND search_text <> '';", [diaryId]) {
                try upsertFtsEntry(db: db, diaryId: (row["id"] as? Int64) ?? 0,
                                   searchText: (row["search_text"] as? String) ?? "")
            }
        }
    }

    private func upsertFtsEntry(db: SQLite, diaryId: Int64, searchText: String) throws {
        try db.execute("DELETE FROM diary_fts WHERE diary_id = ?;", [diaryId])
        if !searchText.isEmpty {
            try db.execute("INSERT INTO diary_fts(diary_id, text) VALUES (?, ?);",
                           [diaryId, FtsSegment.segment(searchText)])
        }
    }

    private func cleanupImages(from oldJson: String, to newJson: String) {
        let oldSrcs = Set(ImagePathUtil.collectImageSrcs(oldJson))
        let newSrcs = Set(ImagePathUtil.collectImageSrcs(newJson))
        let removed = oldSrcs.subtracting(newSrcs)
        for src in removed {
            let path = ImagePathUtil.resolveImagePath(src)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func removeUnreferencedImages(in json: String) {
        let srcs = ImagePathUtil.collectImageSrcs(json)
        guard !srcs.isEmpty else { return }
        for src in srcs {
            let path = ImagePathUtil.resolveImagePath(src)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func cleanupOrphanImages() async {
        await runOnQueue { [self] in
            guard let db else { return }
            let fm = FileManager.default
            let dir = Self.imagesDir()
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            let rows = db.query("SELECT content_json FROM edit_block;")
            var referenced = Set<String>()
            for row in rows {
                for src in ImagePathUtil.collectImageSrcs((row["content_json"] as? String) ?? "[]") {
                    referenced.insert(src)
                }
            }
            for file in files {
                let src = "images/\(file.lastPathComponent)"
                if !referenced.contains(src) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - Backup support

    func rawBlocksForBackup() async -> [(Int64, String)] {
        await runOnQueue { [self] in
            db?.query("SELECT id, content_json FROM edit_block;")
                .map { ((($0["id"] as? Int64) ?? 0), (($0["content_json"] as? String) ?? "[]")) } ?? []
        }
    }

    func countDiaries() async -> Int {
        await runOnQueue { [self] in
            let row = db?.queryFirst("SELECT COUNT(*) AS cnt FROM diary;")
            return Int((row?["cnt"] as? Int64) ?? 0)
        }
    }

    func countBlocks() async -> Int {
        await runOnQueue { [self] in
            let row = db?.queryFirst("SELECT COUNT(*) AS cnt FROM edit_block;")
            return Int((row?["cnt"] as? Int64) ?? 0)
        }
    }

    func mergeBackupDatabase(path: String, mode: String, copyImage: @escaping (String) -> String,
                             stats: inout BackupStats) async throws {
        var working = stats
        try await runOnQueue { [self] in
            guard let backupDb = try? SQLite(path: path) else {
                Log.db.error("mergeBackup: open backup db failed")
                throw DBError.notReady
            }
            defer { backupDb.closeQuietly() }
            guard let mainDb = db else { throw DBError.notReady }
            let cols = Set(backupDb.query("PRAGMA table_info(edit_block);").compactMap { $0["name"] as? String })
            let hasRegion = cols.contains("region1")
            let hasQuality = cols.contains("loc_quality")
            let hasCountryCode = cols.contains("country_code")
            let diaryRows = backupDb.query("SELECT * FROM diary ORDER BY day_key ASC;")
            for dRow in diaryRows {
                let dayKey = (dRow["day_key"] as? String) ?? ""
                let existing = mainDb.queryFirst("SELECT id FROM diary WHERE day_key = ?;", [dayKey])
                if mode == "skip", existing != nil {
                    working.skippedDays += 1
                    continue
                }
                let backupDiaryId = (dRow["id"] as? Int64) ?? 0
                let blocks = backupDb.query("SELECT * FROM edit_block WHERE diary_id = ? ORDER BY start_time_utc ASC;", [backupDiaryId])
                var newDiaryId: Int64 = 0
                try mainDb.inTransaction {
                    if let existing {
                        let eid = (existing["id"] as? Int64) ?? 0
                        try mainDb.execute("DELETE FROM edit_block WHERE diary_id = ?;", [eid])
                        try mainDb.execute("DELETE FROM diary WHERE id = ?;", [eid])
                        try mainDb.execute("DELETE FROM diary_flag WHERE day_key = ?;", [dayKey])
                        if ftsSupported {
                            try mainDb.execute("DELETE FROM diary_fts WHERE diary_id = ?;", [eid])
                        }
                        working.overwrittenDays += 1
                    } else {
                        working.importedDays += 1
                    }
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    try mainDb.execute("INSERT INTO diary(day_key, created_utc, updated_utc) VALUES (?, ?, ?);",
                                       [dayKey, (dRow["created_utc"] as? Int64) ?? now, (dRow["updated_utc"] as? Int64) ?? now])
                    newDiaryId = mainDb.lastInsertId()
                    try mainDb.execute("INSERT OR IGNORE INTO diary_flag(day_key) VALUES (?);", [dayKey])
                    var dayText = ""
                    for b in blocks {
                        let json = ImagePathUtil.normalizeContent((b["content_json"] as? String) ?? "[]")
                        let parts = ContentFlatten.parseContent(json)
                        var rewritten = parts
                        for i in rewritten.indices {
                            if let src = rewritten[i].src {
                                rewritten[i].src = copyImage(src)
                            }
                        }
                        let newJson = ContentFlatten.serializeContent(rewritten)
                        let text = ContentFlatten.flattenContent(newJson)
                        let locQuality: String
                        if hasQuality {
                            locQuality = (b["loc_quality"] as? String) ?? ""
                        } else {
                            let lat = (b["latitude"] as? Double) ?? 0
                            let lng = (b["longitude"] as? Double) ?? 0
                            locQuality = (lat != 0 || lng != 0) ? LocQuality.precise : LocQuality.coarse
                        }
                        try mainDb.execute("""
                        INSERT INTO edit_block(diary_id, start_time_utc, loc_text, latitude, longitude,
                          content_json, search_text, loc_precision, loc_quality, country, country_code,
                          region1, region2, region3, created_utc, updated_utc)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """, [newDiaryId,
                              (b["start_time_utc"] as? Int64) ?? now,
                              (b["loc_text"] as? String) ?? "",
                              (b["latitude"] as? Double) ?? 0,
                              (b["longitude"] as? Double) ?? 0,
                              newJson,
                              text,
                              (b["loc_precision"] as? String) ?? "none",
                              locQuality,
                              (b["country"] as? String) ?? "",
                              hasCountryCode ? ((b["country_code"] as? String) ?? "") : "",
                              hasRegion ? ((b["region1"] as? String) ?? "") : ((b["province"] as? String) ?? ""),
                              hasRegion ? ((b["region2"] as? String) ?? "") : ((b["city"] as? String) ?? ""),
                              hasRegion ? ((b["region3"] as? String) ?? "") : ((b["district"] as? String) ?? ""),
                              (b["created_utc"] as? Int64) ?? now,
                              (b["updated_utc"] as? Int64) ?? now])
                        working.importedBlocks += 1
                        dayText += text + " "
                    }
                    if !dayText.isEmpty {
                        dayText = dayText.trimmingCharacters(in: .whitespacesAndNewlines)
                        try mainDb.execute("UPDATE diary SET summary = ?, search_text = ? WHERE id = ?;",
                                           [String(dayText.prefix(40)), dayText, newDiaryId])
                    }
                    if ftsSupported {
                        if let ftsRow = mainDb.queryFirst("SELECT id, search_text FROM diary WHERE id = ? AND search_text <> '';", [newDiaryId]) {
                            try upsertFtsEntry(db: mainDb, diaryId: (ftsRow["id"] as? Int64) ?? 0,
                                               searchText: (ftsRow["search_text"] as? String) ?? "")
                        }
                    }
                }
            }
            try mainDb.execute("DELETE FROM diary_flag;")
            try mainDb.execute("INSERT OR IGNORE INTO diary_flag(day_key) SELECT day_key FROM diary;")
            try rebuildSearchIndex()
        }
        stats = working
    }

    // MARK: - Day key recompute

    func recomputeDayKeys(dayStartHour: Int) async -> Int {
        (try? await runOnQueue { [self] in
            guard let db else { return 0 }
            let rows = db.query("""
            SELECT d.id AS id, d.day_key AS day_key, d.created_utc AS created_utc,
                   COALESCE(MIN(b.start_time_utc), 0) AS first_utc
            FROM diary d LEFT JOIN edit_block b ON b.diary_id = d.id
            GROUP BY d.id;
            """)
            var newKeys: [Int64: String] = [:]
            var holderOf: [String: Int64] = [:]
            for r in rows {
                let id = (r["id"] as? Int64) ?? 0
                let firstUtc = (r["first_utc"] as? Int64) ?? 0
                var key = (r["day_key"] as? String) ?? ""
                if firstUtc > 0 {
                    key = DateUtil.dayKeyForUtc(firstUtc, dayStartHour: dayStartHour)
                }
                newKeys[id] = key
                holderOf[key] = id
            }
            var conflicts = 0
            var moverIds: [Int64] = []
            var finalKeys: [Int64: String] = [:]
            for r in rows {
                let id = (r["id"] as? Int64) ?? 0
                let oldKey = (r["day_key"] as? String) ?? ""
                let newKey = newKeys[id] ?? oldKey
                if newKey == oldKey { continue }
                let currentHolder = holderOf[oldKey]
                if currentHolder == nil || currentHolder != id {
                    if currentHolder != nil, let ch = currentHolder, !moverIds.contains(ch) {
                        if newKeys[ch] != oldKey {
                            conflicts += 1
                            continue
                        }
                    }
                }
                moverIds.append(id)
                finalKeys[id] = newKey
            }
            for id in moverIds {
                try db.execute("UPDATE diary SET day_key = ? WHERE id = ?;", ["tmp#\(id)", id])
            }
            for (id, key) in finalKeys {
                try db.execute("UPDATE diary SET day_key = ? WHERE id = ?;", [key, id])
            }
            try db.execute("DELETE FROM diary_flag;")
            try db.execute("INSERT OR IGNORE INTO diary_flag(day_key) SELECT day_key FROM diary;")
            return conflicts
        }) ?? 0
    }

    // MARK: - Region backfill

    func blocksNeedingRegionBackfill(limit: Int) async -> [(id: Int64, latitude: Double, longitude: Double)] {
        await runOnQueue { [self] in
            guard let db else { return [] }
            let skip = regionGeocodeSkip()
            var result: [(Int64, Double, Double)] = []
            let rows = db.query("""
            SELECT id, latitude, longitude FROM edit_block
            WHERE (latitude <> 0 OR longitude <> 0) AND region1 = ''
            ORDER BY id ASC LIMIT \(max(limit, 1));
            """)
            for r in rows {
                let id = (r["id"] as? Int64) ?? 0
                if skip.contains(id) { continue }
                result.append((id, (r["latitude"] as? Double) ?? 0, (r["longitude"] as? Double) ?? 0))
            }
            return result
        }
    }

    func updateBlockRegions(id: Int64, country: String, countryCode: String,
                            region1: String, region2: String, region3: String, locQuality: String) async {
        try? await runOnQueue { [self] in
            guard let db else { return }
            try db.execute("""
            UPDATE edit_block SET country = ?, country_code = ?, region1 = ?, region2 = ?, region3 = ?, loc_quality = ?
            WHERE id = ? AND region1 = '';
            """, [country, countryCode, region1, region2, region3, locQuality, id])
        }
    }

    func markRegionGeocodeSkipped(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        var skip = regionGeocodeSkip()
        skip.formUnion(ids)
        let list = Array(skip.suffix(2000))
        SettingsStore.defaults.set(list, forKey: "region_geocode_skip_v2")
    }

    private func regionGeocodeSkip() -> Set<Int64> {
        let list = SettingsStore.defaults.array(forKey: "region_geocode_skip_v2") as? [Int64] ?? []
        return Set(list)
    }

    func backfillBlockRegions() async {
        let pending = await blocksNeedingRegionBackfill(limit: 30)
        guard !pending.isEmpty else { return }
        var updated: [(Int64, String, String, String, String, String, String)] = []
        var failed: [Int64] = []
        for item in pending {
            let coordinate = CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
            if let placemark = await ReverseGeocoder.reverse(coordinate) {
                updated.append((item.id, placemark.country, placemark.countryCode, placemark.region1,
                                placemark.region2, placemark.region3, "precise"))
            } else {
                failed.append(item.id)
            }
        }
        for u in updated {
            await updateBlockRegions(id: u.0, country: u.1, countryCode: u.2, region1: u.3, region2: u.4, region3: u.5, locQuality: u.6)
        }
        if !failed.isEmpty {
            markRegionGeocodeSkipped(failed)
        }
    }

    // MARK: - Search

    func search(keyword: String, fromKey: String, toKey: String, filter: LocFilter, offset: Int) async -> SearchPageResult {
        await runOnQueue { [self] in
            let ftsEnabled = ftsSupported
            return Self.runSearch(db: db, keyword: keyword, fromKey: fromKey, toKey: toKey,
                                  filter: filter, offset: offset, ftsEnabled: ftsEnabled)
        }
    }

    private static func runSearch(db: SQLite?, keyword: String, fromKey: String, toKey: String,
                                  filter: LocFilter, offset: Int, ftsEnabled: Bool) -> SearchPageResult {
        guard let db else { return SearchPageResult(items: [], hasMore: false, total: -1) }
        let terms = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        var whereParts: [String] = ["d.day_key >= ?", "d.day_key <= ?"]
        var args: [Any?] = [fromKey, toKey]
        var ftsQuery = ""
        if !terms.isEmpty {
            ftsQuery = terms.map { "\"\(FtsSegment.segment($0.replacingOccurrences(of: "\"", with: "")))\"" }.joined(separator: " ")
            let likeParts = terms.map { _ in "d.search_text LIKE ? ESCAPE '\\'" }
            let likeArgs = terms.map { "%\(SearchUtil.escapeLikeTerm($0))%" }
            let matchSql = ftsEnabled
                ? "EXISTS (SELECT 1 FROM diary_fts WHERE diary_fts.diary_id = d.id AND diary_fts MATCH ?)"
                : "1=0"
            whereParts.append("(\(matchSql) OR (\(likeParts.joined(separator: " AND "))))")
            args.append(ftsQuery)
            args.append(contentsOf: likeArgs)
        }
        if !filter.noLoc, !filter.country.isEmpty {
            whereParts.append("EXISTS (SELECT 1 FROM edit_block b WHERE b.diary_id = d.id AND b.country = ? AND b.region1 = ?)")
            args.append(filter.country)
            args.append(filter.region1)
        }
        if filter.noLoc {
            whereParts.append(Self.noLocSql)
        }
        let whereSql = whereParts.joined(separator: " AND ")
        let total = db.queryFirst("SELECT COUNT(*) AS cnt FROM diary d WHERE \(whereSql);", args)
            .flatMap { $0["cnt"] as? Int64 }.map { Int($0) } ?? 0
        let snipSql = (ftsEnabled && !terms.isEmpty)
            ? "(SELECT snippet(diary_fts, 1, '<hl>', '</hl>', '…', 24) FROM diary_fts WHERE diary_fts.diary_id = d.id AND diary_fts MATCH ? LIMIT 1)"
            : "''"
        var listArgs: [Any?] = []
        if ftsEnabled && !terms.isEmpty { listArgs.append(ftsQuery) }
        listArgs.append(contentsOf: args)
        listArgs.append(Self.searchLimit + 1)
        listArgs.append(offset)
        let rows = db.query("""
        SELECT d.id AS id, d.day_key AS day_key, d.summary AS summary, d.updated_utc AS updated_utc,
               \(snipSql) AS snip
        FROM diary d
        WHERE \(whereSql)
        ORDER BY d.day_key DESC LIMIT ? OFFSET ?;
        """, listArgs)
        var items: [SearchResultItem] = []
        for r in rows {
            var snippet = (r["snip"] as? String) ?? ""
            if !snippet.isEmpty {
                snippet = FtsSegment.desegment(snippet)
            }
            if snippet.isEmpty, !terms.isEmpty {
                let searchText = (r["summary"] as? String) ?? ""
                snippet = SearchUtil.buildFallbackSnippet(searchText, keyword: keyword)
            }
            items.append(SearchResultItem(id: (r["id"] as? Int64) ?? 0,
                                          dayKey: (r["day_key"] as? String) ?? "",
                                          summary: (r["summary"] as? String) ?? "",
                                          snippet: snippet,
                                          updatedUtc: (r["updated_utc"] as? Int64) ?? 0))
        }
        let hasMore = items.count > Self.searchLimit
        if hasMore { items = Array(items.prefix(Self.searchLimit)) }
        return SearchPageResult(items: items, hasMore: hasMore, total: total)
    }

    // MARK: - Row mapping

    private static func diaryFromRow(_ row: [String: Any]) -> DiaryRecord {
        DiaryRecord(id: (row["id"] as? Int64) ?? 0,
                    dayKey: (row["day_key"] as? String) ?? "",
                    summary: (row["summary"] as? String) ?? "",
                    searchText: (row["search_text"] as? String) ?? "",
                    createdUtc: (row["created_utc"] as? Int64) ?? 0,
                    updatedUtc: (row["updated_utc"] as? Int64) ?? 0)
    }

    private static func blockFromRow(_ row: [String: Any]) -> EditBlock {
        EditBlock(id: (row["id"] as? Int64) ?? 0,
                  diaryId: (row["diary_id"] as? Int64) ?? 0,
                  startTimeUtc: (row["start_time_utc"] as? Int64) ?? 0,
                  locText: (row["loc_text"] as? String) ?? "",
                  latitude: (row["latitude"] as? Double) ?? 0,
                  longitude: (row["longitude"] as? Double) ?? 0,
                  contentJson: (row["content_json"] as? String) ?? "[]",
                  searchText: (row["search_text"] as? String) ?? "",
                  locPrecision: (row["loc_precision"] as? String) ?? "none",
                  locQuality: (row["loc_quality"] as? String) ?? "none",
                  country: (row["country"] as? String) ?? "",
                  countryCode: (row["country_code"] as? String) ?? "",
                  region1: (row["region1"] as? String) ?? "",
                  region2: (row["region2"] as? String) ?? "",
                  region3: (row["region3"] as? String) ?? "",
                  createdUtc: (row["created_utc"] as? Int64) ?? 0,
                  updatedUtc: (row["updated_utc"] as? Int64) ?? 0)
    }

    // MARK: - Queue helpers

    private func runOnQueue<T>(_ block: @escaping () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: block())
            }
        }
    }

    private func runOnQueue<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do {
                    cont.resume(returning: try block())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

enum DBError: Error {
    case notReady
}

struct ReversePlacemark {
    var country: String
    var countryCode: String
    var region1: String
    var region2: String
    var region3: String
}

enum ReverseGeocoder {
    static func reverse(_ coordinate: CLLocationCoordinate2D) async -> ReversePlacemark? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItems = try? await request.mapItems,
              let pm = mapItems.first?.diaryPlacemark else {
            Log.location.error("reverse geocode failed for \(coordinate.latitude),\(coordinate.longitude)")
            return nil
        }
        let countryCode = pm.isoCountryCode ?? ""
        let region1 = pm.administrativeArea ?? pm.subAdministrativeArea ?? ""
        let region2 = pm.subAdministrativeArea ?? pm.locality ?? ""
        let region3 = pm.locality != nil && pm.subAdministrativeArea != nil ? pm.subLocality ?? "" : ""
        return ReversePlacemark(
            country: pm.country ?? "",
            countryCode: countryCode,
            region1: region1,
            region2: region2,
            region3: region3)
    }
}

nonisolated extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
