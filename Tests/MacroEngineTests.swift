import XCTest
@testable import MacroEngine

final class MacroEngineTests: XCTestCase {
    func testMifflinStJeorAndFatLossTarget() {
        let profile = UserProfile(
            age: 30,
            sex: .male,
            heightCm: 175,
            weightKg: 80,
            activityLevel: .moderatelyActive,
            goal: .fatLoss
        )

        let estimate = MacroTargetCalculator.estimate(for: profile)
        XCTAssertEqual(estimate.bmr, 1748.75, accuracy: 0.01)
        XCTAssertEqual(estimate.tdee, 2710.5625, accuracy: 0.01)
        XCTAssertEqual(estimate.targetCalories, 2300, accuracy: 0.01)
        XCTAssertEqual(estimate.macros.energyFromMacros, estimate.targetCalories, accuracy: 1)
    }

    func testLegacyDiaryEntryWithoutCategoryDefaultsToSnacks() throws {
        let json = #"""
        {
          "id":"F9BC74C7-4C7F-4D24-80E3-25F4C06F1E09",
          "food":{
            "id":"5000159484695",
            "name":"Oats",
            "brand":null,
            "per100g":{"calories":370,"protein":13,"carbs":60,"fat":7},
            "servingGrams":null,
            "imageURL":null
          },
          "grams":100,
          "date":0
        }
        """#.data(using: .utf8)!

        let entry = try JSONDecoder().decode(DiaryEntry.self, from: json)
        XCTAssertEqual(entry.category, .snacks)
        XCTAssertEqual(entry.grams, 100)
    }
}
