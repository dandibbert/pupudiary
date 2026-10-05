import Foundation

// MARK: - 布里斯托分类（用可爱的叫法，不用拟物描述）

enum BristolType: Int, Codable, CaseIterable, Identifiable, Hashable {
    case t1 = 1, t2, t3, t4, t5, t6, t7

    var id: Int { rawValue }

    /// Q 版名字
    var nickname: String {
        switch self {
        case .t1: return "小石子"
        case .t2: return "疙瘩瘩"
        case .t3: return "有裂纹"
        case .t4: return "软滑滑"
        case .t5: return "软团团"
        case .t6: return "糊糊状"
        case .t7: return "水水的"
        }
    }

    /// 一句话说明，帮助判断属于哪一型
    var hint: String {
        switch self {
        case .t1: return "一颗颗分开的小硬块，很难排出"
        case .t2: return "成形但表面凹凸、偏硬"
        case .t3: return "成形，表面有些裂纹"
        case .t4: return "光滑柔软、形状完整，最理想"
        case .t5: return "柔软的小团，边缘清楚，容易排出"
        case .t6: return "松散、边缘模糊的糊状"
        case .t7: return "几乎全是液体，没有固体"
        }
    }

    var status: GutStatus {
        switch self {
        case .t1, .t2: return .dry
        case .t3, .t4: return .ideal
        case .t5: return .soft
        case .t6, .t7: return .loose
        }
    }

    var label: String { "第 \(rawValue) 型" }
}

/// 一目了然的四档肠道状态，用颜色区分
enum GutStatus: Int, Codable, CaseIterable, Identifiable {
    case dry, ideal, soft, loose

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dry: return "偏干"
        case .ideal: return "理想"
        case .soft: return "偏软"
        case .loose: return "偏稀"
        }
    }

    var advice: String {
        switch self {
        case .dry: return "多喝水、多吃蔬菜水果和粗粮，适当运动～"
        case .ideal: return "状态很棒，继续保持！"
        case .soft: return "稍微偏软，留意一下最近的饮食哦"
        case .loose: return "注意补充水分和电解质，饮食清淡些"
        }
    }

    /// 快捷记录时代表该状态的典型分型
    var representative: BristolType {
        switch self {
        case .dry: return .t2
        case .ideal: return .t4
        case .soft: return .t5
        case .loose: return .t6
        }
    }
}

// MARK: - 其他细节

enum StoolColor: String, Codable, CaseIterable, Identifiable {
    case brown, darkBrown, yellow, green, black, red, pale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brown: return "棕色"
        case .darkBrown: return "深棕"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .black: return "黑色"
        case .red: return "带红"
        case .pale: return "灰白"
        }
    }

    /// 需要留意的颜色
    var needsAttention: Bool {
        switch self {
        case .black, .red, .pale: return true
        default: return false
        }
    }
}

enum Amount: Int, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .small: return "少量"
        case .medium: return "适中"
        case .large: return "大量"
        }
    }
}

enum Ease: Int, Codable, CaseIterable, Identifiable {
    case easy, normal, hard
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .easy: return "轻松"
        case .normal: return "一般"
        case .hard: return "费力"
        }
    }
    var emoji: String {
        switch self {
        case .easy: return "😌"
        case .normal: return "🙂"
        case .hard: return "😣"
        }
    }
}

enum Symptom: String, Codable, CaseIterable, Identifiable {
    case pain, bloating, blood, mucus, incomplete, urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pain: return "肚子痛"
        case .bloating: return "胀气"
        case .blood: return "有血丝"
        case .mucus: return "有黏液"
        case .incomplete: return "没排干净"
        case .urgent: return "很急"
        }
    }

    var needsAttention: Bool { self == .blood }
}

// MARK: - 记录

struct PoopRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var bristol: BristolType = .t4
    var color: StoolColor? = nil
    var amount: Amount = .medium
    var ease: Ease = .normal
    /// 0 表示未记录
    var durationMinutes: Int = 0
    var symptoms: [Symptom] = []
    var note: String = ""
    /// 一键记录产生的，细节待补充
    var isQuick: Bool = false

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         bristol: BristolType = .t4,
         color: StoolColor? = nil,
         amount: Amount = .medium,
         ease: Ease = .normal,
         durationMinutes: Int = 0,
         symptoms: [Symptom] = [],
         note: String = "",
         isQuick: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.bristol = bristol
        self.color = color
        self.amount = amount
        self.ease = ease
        self.durationMinutes = durationMinutes
        self.symptoms = symptoms
        self.note = note
        self.isQuick = isQuick
    }

    // 宽松解码：字段缺失时使用默认值，方便以后升级和导入
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        bristol = (try? c.decodeIfPresent(BristolType.self, forKey: .bristol)) ?? .t4
        color = try? c.decodeIfPresent(StoolColor.self, forKey: .color)
        amount = (try? c.decodeIfPresent(Amount.self, forKey: .amount)) ?? .medium
        ease = (try? c.decodeIfPresent(Ease.self, forKey: .ease)) ?? .normal
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes)) ?? 0
        let rawSymptoms = (try? c.decodeIfPresent([String].self, forKey: .symptoms)) ?? []
        symptoms = rawSymptoms.compactMap(Symptom.init(rawValue:))
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        isQuick = (try? c.decodeIfPresent(Bool.self, forKey: .isQuick)) ?? false
    }

    var status: GutStatus { bristol.status }

    var needsAttention: Bool {
        (color?.needsAttention ?? false) || symptoms.contains(where: \.needsAttention)
    }
}
