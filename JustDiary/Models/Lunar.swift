import Foundation

enum Lunar {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .chinese)
        c.timeZone = .current
        return c
    }()

    static let dayNames = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                           "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                           "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
    static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                             "七月", "八月", "九月", "十月", "冬月", "腊月"]
    static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let animals = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    static func components(_ date: Date) -> (year: Int, month: Int, day: Int, leap: Bool) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 1, c.month ?? 1, c.day ?? 1, c.isLeapMonth ?? false)
    }

    static func sexagenary(_ cycleYear: Int) -> String {
        stems[(cycleYear - 1) % 10] + branches[(cycleYear - 1) % 12]
    }

    static func dayLabel(_ date: Date) -> String {
        let c = components(date)
        if c.day == 1 {
            return (c.leap ? "闰" : "") + monthNames[(c.month - 1) % 12]
        }
        return dayNames[(c.day - 1) % 30]
    }

    static func fullLabel(_ date: Date) -> String {
        let c = components(date)
        return sexagenary(c.year) + "年" + (c.leap ? "闰" : "") + monthNames[(c.month - 1) % 12] + dayNames[(c.day - 1) % 30]
    }

    static func yearZodiacLabel(_ date: Date) -> String {
        let c = components(date)
        return sexagenary(c.year) + animals[(c.year - 1) % 12] + "年"
    }
}
