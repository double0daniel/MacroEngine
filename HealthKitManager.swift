import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var observerQueries: [HKObserverQuery] = []
    @ObservationIgnored private var observersStarted = false

    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
    private let dietaryWaterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)!

    private var syncEnabled: Bool {
        UserDefaults.standard.object(forKey: "isHealthKitSyncEnabled") as? Bool ?? true
    }

    private init() {}

    /// Requests Health access, imports current values, and starts background updates.
    func requestAccessAndStartSync(diary: DiaryStore) async {
        guard syncEnabled, HKHealthStore.isHealthDataAvailable() else {
            stopObservers()
            diary.updateActiveEnergyBurnedToday(0)
            return
        }

        if !observersStarted {
            let readTypes: Set<HKObjectType> = [activeEnergyType, bodyMassType]
            let writeTypes: Set<HKSampleType> = [dietaryWaterType]
            do {
                try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            } catch {
                return
            }

            startObserver(for: activeEnergyType, diary: diary)
            startObserver(for: bodyMassType, diary: diary)
            observersStarted = true
        }

        await refreshActiveEnergy(diary: diary)
        await importLatestBodyMass(diary: diary)
    }

    /// Starts or pauses HealthKit integration when the user changes the Settings toggle.
    func setSyncEnabled(_ enabled: Bool, diary: DiaryStore) async {
        guard enabled else {
            stopObservers()
            diary.updateActiveEnergyBurnedToday(0)
            return
        }
        await requestAccessAndStartSync(diary: diary)
    }

    /// Rechecks the active-energy contribution after diary mutations so the
    /// dashboard target and widget snapshot stay aligned with the current day.
    func diaryDidChange(_ diary: DiaryStore) {
        guard syncEnabled, observersStarted else { return }
        Task { @MainActor [weak self, weak diary] in
            guard let self, let diary, self.syncEnabled else { return }
            await self.refreshActiveEnergy(diary: diary)
        }
    }

    /// Writes a newly logged hydration amount to HealthKit when write access is available.
    func saveWaterIntake(amountMl: Int, date: Date = .now) {
        guard syncEnabled,
              amountMl > 0,
              healthStore.authorizationStatus(for: dietaryWaterType) == .sharingAuthorized else { return }

        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: Double(amountMl))
        let sample = HKQuantitySample(type: dietaryWaterType, quantity: quantity, start: date, end: date)
        healthStore.save(sample) { _, _ in }
    }

    private func startObserver(for sampleType: HKSampleType, diary: DiaryStore) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self, weak diary] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }

            Task { @MainActor [weak self, weak diary] in
                guard let self, let diary, self.syncEnabled else {
                    completionHandler()
                    return
                }

                if sampleType.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue {
                    await self.refreshActiveEnergy(diary: diary)
                } else if sampleType.identifier == HKQuantityTypeIdentifier.bodyMass.rawValue {
                    await self.importLatestBodyMass(diary: diary)
                }
                completionHandler()
            }
        }

        observerQueries.append(query)
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
    }

    private func stopObservers() {
        observerQueries.forEach { healthStore.stop($0) }
        observerQueries.removeAll()
        observersStarted = false
        healthStore.disableBackgroundDelivery(for: activeEnergyType) { _, _ in }
        healthStore.disableBackgroundDelivery(for: bodyMassType) { _, _ in }
    }

    private func refreshActiveEnergy(diary: DiaryStore) async {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)
        let total = await activeEnergyTotal(matching: predicate)
        diary.updateActiveEnergyBurnedToday(max(0, total.isFinite ? Int(total.rounded()) : 0))
    }

    private func activeEnergyTotal(matching predicate: NSPredicate) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    private func importLatestBodyMass(diary: DiaryStore) async {
        guard let latest = await latestBodyMass() else { return }
        diary.recordWeight(latest.kilograms, date: latest.date)
    }

    private func latestBodyMass() async -> (kilograms: Double, date: Date)? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: (kilograms, sample.endDate))
            }
            healthStore.execute(query)
        }
    }
}
