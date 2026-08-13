import Foundation
import CoreGraphics

struct GeoRing {
    var pts: [Double]
}

struct GeoFeature {
    var name: String
    var adcode: String
    var level: String
    var rings: [GeoRing]
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    var cx: Double
    var cy: Double
}

struct GeoDataSet {
    var world: [GeoFeature] = []
    var china: [GeoFeature] = []
    var cities: [String: [GeoFeature]] = [:]
}

struct GeoCamera {
    var centerLng: Double = 105
    var centerLat: Double = 35
    var zoom: Double = 3.5
}

struct GeoXY {
    var wx: Double
    var wy: Double
}

enum GeoMath {
    static let world = 256.0
    static let maxLat = 85.05112878

    static func lngToX(_ lng: Double) -> Double {
        (lng + 180) / 360 * world
    }

    static func latToY(_ lat: Double) -> Double {
        let c = max(-maxLat, min(maxLat, lat)) * .pi / 180
        return (1 - log(tan(.pi / 4 + c / 2)) / .pi) / 2 * world
    }

    static func xToLng(_ x: Double) -> Double {
        var lng = x / world * 360 - 180
        while lng >= 180 { lng -= 360 }
        while lng < -180 { lng += 360 }
        return lng
    }

    static func yToLat(_ y: Double) -> Double {
        let n = .pi - 2 * .pi * y / world
        return 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }

    static func camScale(_ zoom: Double) -> Double {
        pow(2, zoom)
    }

    static func clampZoom(_ z: Double) -> Double {
        max(0.5, min(17, z))
    }

    static func screenToWorld(_ sx: Double, _ sy: Double, cam: GeoCamera, vpW: Double, vpH: Double) -> GeoXY {
        let s = camScale(cam.zoom)
        return GeoXY(wx: lngToX(cam.centerLng) + (sx - vpW / 2) / s,
                     wy: latToY(cam.centerLat) + (sy - vpH / 2) / s)
    }

    static func pointInFeature(_ wx: Double, _ wy: Double, _ f: GeoFeature) -> Bool {
        var inside = false
        for ring in f.rings {
            let pts = ring.pts
            let n = pts.count
            var i = 0
            while i < n {
                let j = (i == 0) ? n - 2 : i - 2
                let xi = pts[i], yi = pts[i + 1]
                let xj = pts[j], yj = pts[j + 1]
                if ((yi > wy) != (yj > wy)) && (wx < (xj - xi) * (wy - yi) / (yj - yi) + xi) {
                    inside.toggle()
                }
                i += 2
            }
        }
        return inside
    }

    static func nearestFeature(_ list: [GeoFeature], wx: Double, wy: Double) -> GeoFeature? {
        for f in list {
            if wx < f.minX || wx > f.maxX || wy < f.minY || wy > f.maxY { continue }
            if pointInFeature(wx, wy, f) { return f }
        }
        var best: GeoFeature?
        var bestD = Double.greatestFiniteMagnitude
        for f in list {
            let dx = f.cx - wx
            let dy = f.cy - wy
            let d = dx * dx + dy * dy
            if d < bestD {
                bestD = d
                best = f
            }
        }
        return best
    }
}

enum GeoMap {
    static func parseFeature(_ json: [String: Any], level: String) -> GeoFeature? {
        guard let props = json["properties"] as? [String: Any],
              let geom = json["geometry"] as? [String: Any] else { return nil }
        let type = geom["type"] as? String ?? ""
        let adcode = String(describing: props["adcode"] ?? "")
        var rings: [GeoRing] = []
        if type == "Polygon" {
            if let coords = geom["coordinates"] as? [[[Double]]] {
                rings = parseRings(coords)
            }
        } else if type == "MultiPolygon" {
            if let coords = geom["coordinates"] as? [[[[Double]]]] {
                for poly in coords {
                    rings += parseRings(poly)
                }
            }
        }
        guard !rings.isEmpty else { return nil }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for r in rings {
            var i = 0
            while i < r.pts.count {
                minX = min(minX, r.pts[i])
                maxX = max(maxX, r.pts[i])
                minY = min(minY, r.pts[i + 1])
                maxY = max(maxY, r.pts[i + 1])
                i += 2
            }
        }
        let name = (props["name"] as? String) ?? ""
        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        if let centroid = props["centroid"] as? [Double], centroid.count >= 2 {
            cx = GeoMath.lngToX(centroid[0])
            cy = GeoMath.latToY(centroid[1])
        }
        return GeoFeature(name: name, adcode: adcode, level: level, rings: rings,
                          minX: minX, maxX: maxX, minY: minY, maxY: maxY, cx: cx, cy: cy)
    }

    private static func parseRings(_ coords: [[[Double]]]) -> [GeoRing] {
        var rings: [GeoRing] = []
        for ring in coords {
            var pts: [Double] = []
            for pair in ring {
                pts.append(GeoMath.lngToX(pair[0]))
                pts.append(GeoMath.latToY(pair[1]))
            }
            if pts.count >= 6 {
                rings.append(GeoRing(pts: pts))
            }
        }
        return rings
    }

    static func loadJson(_ name: String) -> [[String: Any]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            Log.map.error("loadJson failed: \(name, privacy: .public)")
            return []
        }
        return features
    }

    static func loadGeoData() -> GeoDataSet {
        var data = GeoDataSet()
        for f in loadJson("world") {
            if let feat = parseFeature(f, level: "country") { data.world.append(feat) }
        }
        for f in loadJson("china") {
            if let feat = parseFeature(f, level: "province") { data.china.append(feat) }
        }
        return data
    }

    static func loadCityData(_ geo: inout GeoDataSet, provinceAdcode: String) -> Bool {
        if let cached = geo.cities[provinceAdcode] {
            return !cached.isEmpty
        }
        let parsed = loadJson(provinceAdcode).compactMap { parseFeature($0, level: "city") }
        geo.cities[provinceAdcode] = parsed
        return !parsed.isEmpty
    }

    static func displayName(_ name: String, isZh: Bool, level: String) -> String {
        if isZh || name.isEmpty { return name }
        let table = level == "province" ? provinceEn : cityEn
        return table[name] ?? name
    }

    static func countryName(_ name: String, isZh: Bool) -> String {
        if isZh {
            return countryZh[name] ?? name
        }
        return name
    }

    static func countryKey(_ name: String) -> String {
        if countryZh[name] != nil { return name }
        for (en, zh) in countryZh where zh == name {
            return en
        }
        return name
    }
}

private let provinceEn: [String: String] = [
    "北京市": "Beijing", "天津市": "Tianjin", "河北省": "Hebei", "山西省": "Shanxi",
    "内蒙古自治区": "Inner Mongolia", "辽宁省": "Liaoning", "吉林省": "Jilin",
    "黑龙江省": "Heilongjiang", "上海市": "Shanghai", "江苏省": "Jiangsu",
    "浙江省": "Zhejiang", "安徽省": "Anhui", "福建省": "Fujian", "江西省": "Jiangxi",
    "山东省": "Shandong", "河南省": "Henan", "湖北省": "Hubei", "湖南省": "Hunan",
    "广东省": "Guangdong", "广西壮族自治区": "Guangxi", "海南省": "Hainan",
    "重庆市": "Chongqing", "四川省": "Sichuan", "贵州省": "Guizhou", "云南省": "Yunnan",
    "西藏自治区": "Tibet", "陕西省": "Shaanxi", "甘肃省": "Gansu", "青海省": "Qinghai",
    "宁夏回族自治区": "Ningxia", "新疆维吾尔自治区": "Xinjiang", "台湾省": "Taiwan",
    "香港特别行政区": "Hong Kong", "澳门特别行政区": "Macao"
]

private let cityEn: [String: String] = [
    "杭州市": "Hangzhou", "宁波市": "Ningbo", "温州市": "Wenzhou", "嘉兴市": "Jiaxing",
    "湖州市": "Huzhou", "绍兴市": "Shaoxing", "金华市": "Jinhua", "衢州市": "Quzhou",
    "台州市": "Taizhou", "丽水市": "Lishui", "舟山市": "Zhoushan",
    "南京市": "Nanjing", "苏州市": "Suzhou", "无锡市": "Wuxi", "常州市": "Changzhou",
    "南通市": "Nantong", "扬州市": "Yangzhou", "徐州市": "Xuzhou",
    "合肥市": "Hefei", "芜湖市": "Wuhu", "蚌埠市": "Bengbu", "黄山市": "Huangshan",
    "福州市": "Fuzhou", "厦门市": "Xiamen", "泉州市": "Quanzhou", "漳州市": "Zhangzhou",
    "济南市": "Jinan", "青岛市": "Qingdao", "烟台市": "Yantai", "威海市": "Weihai",
    "郑州市": "Zhengzhou", "洛阳市": "Luoyang", "开封市": "Kaifeng",
    "武汉市": "Wuhan", "宜昌市": "Yichang", "襄阳市": "Xiangyang",
    "长沙市": "Changsha", "株洲市": "Zhuzhou", "岳阳市": "Yueyang", "张家界市": "Zhangjiajie",
    "广州市": "Guangzhou", "深圳市": "Shenzhen", "珠海市": "Zhuhai", "佛山市": "Foshan",
    "东莞市": "Dongguan", "中山市": "Zhongshan", "惠州市": "Huizhou", "汕头市": "Shantou",
    "南宁市": "Nanning", "桂林市": "Guilin", "柳州市": "Liuzhou",
    "海口市": "Haikou", "三亚市": "Sanya",
    "成都市": "Chengdu", "绵阳市": "Mianyang", "乐山市": "Leshan",
    "贵阳市": "Guiyang", "遵义市": "Zunyi",
    "昆明市": "Kunming", "丽江市": "Lijiang",
    "兰州市": "Lanzhou", "天水市": "Tianshui", "酒泉市": "Jiuquan", "敦煌市": "Dunhuang",
    "银川市": "Yinchuan",
    "哈尔滨市": "Harbin", "齐齐哈尔市": "Qiqihar", "大庆市": "Daqing",
    "长春市": "Changchun", "吉林市": "Jilin City",
    "石家庄市": "Shijiazhuang", "唐山市": "Tangshan", "秦皇岛市": "Qinhuangdao",
    "太原市": "Taiyuan", "大同市": "Datong",
    "东城区": "Dongcheng", "西城区": "Xicheng", "朝阳区": "Chaoyang",
    "海淀区": "Haidian", "丰台区": "Fengtai", "浦东新区": "Pudong",
    "徐汇区": "Xuhui", "黄浦区": "Huangpu", "静安区": "Jingan",
    "西湖区": "Xihu", "滨江区": "Binjiang", "拱墅区": "Gongshu", "上城区": "Shangcheng",
    "余杭区": "Yuhang", "萧山区": "Xiaoshan", "南山区": "Nanshan", "福田区": "Futian",
    "罗湖区": "Luohu", "天河区": "Tianhe", "越秀区": "Yuexiu", "香洲区": "Xiangzhou"
]

private let countryZh: [String: String] = [
    "China": "中国", "United States of America": "美国", "Japan": "日本",
    "South Korea": "韩国", "North Korea": "朝鲜", "United Kingdom": "英国",
    "France": "法国", "Germany": "德国", "Russia": "俄罗斯", "Italy": "意大利",
    "Spain": "西班牙", "Canada": "加拿大", "Australia": "澳大利亚",
    "Thailand": "泰国", "Singapore": "新加坡", "Malaysia": "马来西亚",
    "Vietnam": "越南", "Philippines": "菲律宾", "Indonesia": "印度尼西亚",
    "India": "印度", "Turkey": "土耳其", "Egypt": "埃及", "Switzerland": "瑞士",
    "Netherlands": "荷兰", "Sweden": "瑞典", "Norway": "挪威", "Finland": "芬兰",
    "Belgium": "比利时", "Austria": "奥地利", "Portugal": "葡萄牙",
    "Greece": "希腊", "Poland": "波兰", "Ukraine": "乌克兰", "Czechia": "捷克",
    "New Zealand": "新西兰", "Ireland": "爱尔兰", "Denmark": "丹麦",
    "Brazil": "巴西", "Argentina": "阿根廷", "Mexico": "墨西哥", "Chile": "智利",
    "Peru": "秘鲁", "Colombia": "哥伦比亚", "Saudi Arabia": "沙特阿拉伯",
    "United Arab Emirates": "阿联酋", "Qatar": "卡塔尔", "Israel": "以色列",
    "Iran": "伊朗", "Iraq": "伊拉克", "Pakistan": "巴基斯坦", "Bangladesh": "孟加拉国",
    "Myanmar": "缅甸", "Cambodia": "柬埔寨", "Laos": "老挝", "Nepal": "尼泊尔",
    "Mongolia": "蒙古国", "Kazakhstan": "哈萨克斯坦", "Uzbekistan": "乌兹别克斯坦",
    "South Africa": "南非", "Kenya": "肯尼亚", "Ethiopia": "埃塞俄比亚",
    "Morocco": "摩洛哥", "Tunisia": "突尼斯", "Cuba": "古巴", "Venezuela": "委内瑞拉",
    "Ecuador": "厄瓜多尔", "Bolivia": "玻利维亚", "Paraguay": "巴拉圭",
    "Uruguay": "乌拉圭", "Croatia": "克罗地亚", "Serbia": "塞尔维亚",
    "Romania": "罗马尼亚", "Hungary": "匈牙利", "Bulgaria": "保加利亚",
    "Slovakia": "斯洛伐克", "Slovenia": "斯洛文尼亚", "Lithuania": "立陶宛",
    "Latvia": "拉脱维亚", "Estonia": "爱沙尼亚", "Belarus": "白俄罗斯",
    "Georgia": "格鲁吉亚", "Armenia": "亚美尼亚", "Azerbaijan": "阿塞拜疆",
    "Afghanistan": "阿富汗", "Sri Lanka": "斯里兰卡", "Fiji": "斐济",
    "Iceland": "冰岛", "Luxembourg": "卢森堡", "Monaco": "摩纳哥", "Malta": "马耳他",
    "Cyprus": "塞浦路斯", "Jordan": "约旦", "Syria": "叙利亚", "Lebanon": "黎巴嫩",
    "Kuwait": "科威特", "Bahrain": "巴林", "Oman": "阿曼", "Yemen": "也门",
    "Libya": "利比亚", "Algeria": "阿尔及利亚", "Sudan": "苏丹", "Nigeria": "尼日利亚",
    "Ghana": "加纳", "Angola": "安哥拉", "Tanzania": "坦桑尼亚", "Uganda": "乌干达",
    "Cameroon": "喀麦隆", "Mozambique": "莫桑比克", "Zimbabwe": "津巴布韦",
    "Zambia": "赞比亚", "Madagascar": "马达加斯加", "Somalia": "索马里"
]
