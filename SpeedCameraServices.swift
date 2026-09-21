import Foundation
import CoreLocation
import CloudKit

final class OfficialCameraStore {
    static let shared = OfficialCameraStore()

    private let cacheKey = "official-speed-cameras-v1"
    private let cacheDateKey = "official-speed-cameras-date-v1"
    private let sourceURL = URL(string: "https://data.gov.tw/dataset/7320")!

    func load(completion: @escaping ([SpeedCamera]) -> Void) {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([SpeedCamera].self, from: data) {
            completion(cached)

            if let date = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
               Date().timeIntervalSince(date) < 6 * 60 * 60 {
                return
            }
        }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data else { return }

            let cameras = Self.parse(data)
            guard !cameras.isEmpty else { return }

            if let encoded = try? JSONEncoder().encode(cameras) {
                UserDefaults.standard.set(encoded, forKey: self.cacheKey)
                UserDefaults.standard.set(Date(), forKey: self.cacheDateKey)
            }

            DispatchQueue.main.async {
                completion(cameras)
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> [SpeedCamera] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let rows = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)

        guard rows.count > 1 else { return [] }

        return rows.dropFirst().compactMap { row in
            let fields: [String] = row
                .split(separator: ",", omittingEmptySubsequences: false)
                .map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }

            guard fields.count >= 3,
                  let lat = Double(fields.first {
                      $0.contains("25.") || $0.contains("24.")
                  } ?? ""),
                  let lon = Array(fields.dropFirst())
                      .compactMap({ Double($0) })
                      .first,
                  (-90...90).contains(lat),
                  (-180...180).contains(lon) else {
                return nil
            }

            let limit = fields
                .compactMap(Double.init)
                .first(where: { (10...140).contains($0) }) ?? 50

            return SpeedCamera(
                latitude: lat,
                longitude: lon,
                speedLimit: limit,
                description: "警政署測速點"
            )
        }
    }
}

final class CloudKitCameraReports {
    static let shared = CloudKitCameraReports()

    private let database = CKContainer.default().publicCloudDatabase

    func fetch(
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 50_000,
        completion: @escaping ([SpeedCamera]) -> Void
    ) {
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        let predicate = NSPredicate(
            format: "distanceToLocation:fromLocation:(location, %@) < %f",
            location,
            radius
        )

        let query = CKQuery(
            recordType: "SpeedCameraReport",
            predicate: predicate
        )

        query.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        database.perform(query, inZoneWith: nil) { records, _ in
            let cameras = (records ?? []).compactMap { record -> SpeedCamera? in
                guard let value = record["location"] as? CLLocation,
                      let limitNumber = record["speedLimit"] as? NSNumber else {
                    return nil
                }

                return SpeedCamera(
                    latitude: value.coordinate.latitude,
                    longitude: value.coordinate.longitude,
                    speedLimit: limitNumber.doubleValue,
                    description: (record["note"] as? String) ?? "使用者回報",
                    isTemporary: true
                )
            }

            DispatchQueue.main.async {
                completion(cameras)
            }
        }
    }

    func submit(
        coordinate: CLLocationCoordinate2D,
        speedLimit: Double,
        note: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let record = CKRecord(recordType: "SpeedCameraReport")

        record["location"] = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        record["speedLimit"] = NSNumber(value: speedLimit)
        record["note"] = note as NSString
        record["createdAt"] = NSDate()
        record["expiresAt"] = NSDate(
            timeIntervalSinceNow: 3 * 60 * 60
        )

        database.save(record) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}
