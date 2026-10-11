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

    @MainActor
    func testDailyTrackersContributeToNetCaloriesAndPersistState() {
        let store = DiaryStore(persist: false)
        let food = FoodItem(id: "test", name: "Test food", brand: nil,
                            per100g: Macros(calories: 500, protein: 20, carbs: 50, fat: 10),
                            servingGrams: nil, imageURL: nil)
        store.add(food, grams: 100)
        store.addWorkout(type: "Run", durationMinutes: 30, notes: "Easy pace", caloriesBurned: 300)
        store.addWater(250)
        store.addWater(500)
        store.toggleSupplement("creatine")

        XCTAssertEqual(store.caloriesBurnedToday, 300)
        XCTAssertEqual(store.netCaloriesToday, 200)
        XCTAssertEqual(store.waterConsumedTodayMl, 750)
        XCTAssertTrue(store.todaysSupplementIDs.contains("creatine"))

        store.toggleSupplement("creatine")
        XCTAssertFalse(store.todaysSupplementIDs.contains("creatine"))
    }

    func testOpenFoodFactsUsesUKProductAndSearchEndpoints() throws {
        let service = OpenFoodFactsService.shared
        let productURL = try XCTUnwrap(service.ukProductURL("5000159484695"))
        let searchURL = try XCTUnwrap(service.ukSearchURL("rolled oats"))

        XCTAssertEqual(productURL.host, "uk.openfoodfacts.org")
        XCTAssertEqual(productURL.path, "/api/v2/product/5000159484695.json")
        XCTAssertEqual(searchURL.host, "uk.openfoodfacts.org")
        XCTAssertEqual(searchURL.path, "/cgi/search.pl")
        let queryItems = try XCTUnwrap(URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(queryItems.first(where: { $0.name == "countries_tags_en" })?.value, "united-kingdom")
    }
}
