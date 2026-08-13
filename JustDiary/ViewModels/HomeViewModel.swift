import Foundation
import Observation

@Observable
final class HomeViewModel {
    var selectedDate = Date()
    var monthPage = DateUtil.monthFirst(Date())
    var yearPage = DateUtil.calendar.component(.year, from: Date())
    var flags: Set<String> = []
    var dayBlocks: [EditBlock]?
    var settings = SettingsStore.load()

    var weekStart: String { settings.weekStart }

    func refreshSettings() {
        settings = SettingsStore.load()
    }

    func loadInitial() async {
        let thisYear = DateUtil.calendar.component(.year, from: Date())
        let pageYear = DateUtil.calendar.component(.year, from: monthPage)
        let from = "\(min(thisYear, pageYear) - 1)-01-01"
        let to = "\(max(thisYear, pageYear) + 1)-12-31"
        flags = Set(await DiaryRepository.shared.getDiaryFlagsRange(fromKey: from, toKey: to))
        await reloadDayBlocks()
    }

    func reloadDayBlocks() async {
        let key = DateUtil.dayKeyOf(selectedDate)
        if let diary = await DiaryRepository.shared.getDiaryByDay(key) {
            dayBlocks = await DiaryRepository.shared.getBlocks(diaryId: diary.id)
        } else {
            dayBlocks = nil
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-morph-log") {
            MorphProgressLog.shared.append("reload")
        }
        #endif
    }

    func select(_ day: Date) {
        selectedDate = day
        monthPage = DateUtil.monthFirst(day)
    }

    func selectMonth(_ monthDate: Date) {
        monthPage = monthDate
    }

    func resetToToday() {
        selectedDate = Date()
        monthPage = DateUtil.monthFirst(selectedDate)
        yearPage = DateUtil.calendar.component(.year, from: selectedDate)
    }
}
