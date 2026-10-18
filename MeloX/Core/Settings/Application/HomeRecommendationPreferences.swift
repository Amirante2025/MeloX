import Foundation
import Observation

@MainActor
@Observable
final class HomeRecommendationPreferences {
    private enum Key {
        static let quickActionOrder = "melox.home.quickActionOrder"
        static let sectionOrder = "melox.home.recommendationSectionOrder"
    }

    private(set) var quickActionOrder: [HomeQuickAction] {
        didSet {
            defaults.set(quickActionOrder.map(\.rawValue), forKey: Key.quickActionOrder)
        }
    }

    private(set) var sectionOrder: [HomeRecommendationSlot] {
        didSet {
            defaults.set(sectionOrder.map(\.rawValue), forKey: Key.sectionOrder)
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quickActionOrder = Self.normalized(
            (defaults.stringArray(forKey: Key.quickActionOrder) ?? [])
                .compactMap(HomeQuickAction.init(rawValue:)),
            all: HomeQuickAction.allCases
        )
        sectionOrder = Self.normalized(
            (defaults.array(forKey: Key.sectionOrder) as? [Int] ?? [])
                .compactMap(HomeRecommendationSlot.init(rawValue:)),
            all: HomeRecommendationSlot.allCases
        )
    }

    func setQuickActionOrder(_ order: [HomeQuickAction]) {
        quickActionOrder = Self.normalized(order, all: HomeQuickAction.allCases)
    }

    func setSectionOrder(_ order: [HomeRecommendationSlot]) {
        sectionOrder = Self.normalized(order, all: HomeRecommendationSlot.allCases)
    }

    func reset() {
        quickActionOrder = HomeQuickAction.allCases
        sectionOrder = HomeRecommendationSlot.allCases
    }

    private static func normalized<Item: Hashable>(
        _ order: [Item],
        all: [Item]
    ) -> [Item] {
        let available = Set(all)
        var seen = Set<Item>()
        return (order + all).filter {
            available.contains($0) && seen.insert($0).inserted
        }
    }
}
