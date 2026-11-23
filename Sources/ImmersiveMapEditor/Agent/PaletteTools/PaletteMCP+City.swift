import Foundation

/// The palette agent's look at a city: Mapillary's street photos around a
/// point, the newest of a sample, panoramas left out, spread over the
/// sample's dates' newest third and drawn nine on a sheet with their dates
/// (`ContactSheet`). What a city's facades and roofs look like decides its
/// palette, more than what is known of it (the landmarks' agent's lesson,
/// 2026-10-26: what it sees helps more than what it is told).
extension PaletteMCP {
    static func cityPhotos(_ args: [String: Any], work: URL) throws -> [[String: Any]] {
        guard let lat = (args["lat"] as? NSNumber)?.doubleValue, let lon = (args["lon"] as? NSNumber)?.doubleValue,
              abs(lat) < 85, abs(lon) <= 180 else { throw MCPChannel.Failure("give lat and lon, the point in degrees") }
        let radius = min(1500, max(100, (args["radius"] as? NSNumber)?.doubleValue ?? 500))
        let dLat = radius / 111_320, dLon = radius / (111_320 * cos(lat * .pi / 180))
        // Mapillary's Graph API with the token of the editor's keychain
        // (App puts it in the environment); a landmark's server's request,
        // which uses nothing of its landmark.
        let mapillary = LandmarkMCP.Server(folder: work)
        let json = try mapillary.mapillary("images", [
            "bbox": String(format: "%.6f,%.6f,%.6f,%.6f", lon - dLon, lat - dLat, lon + dLon, lat + dLat),
            "fields": "id,captured_at,thumb_1024_url,is_pano", "limit": "500"])
        let found = (json["data"] as? [[String: Any]] ?? []).filter { ($0["is_pano"] as? Bool) != true && $0["thumb_1024_url"] is String }
        guard !found.isEmpty else { return [MCPChannel.text("No street photo within \(Int(radius)) m of \(lat), \(lon): try another point or a larger radius.")] }
        // The newest third of the sample, nine spread over it, so one car's
        // pass does not fill the sheet.
        let newest = found.sorted { ($0["captured_at"] as? Double ?? 0) > ($1["captured_at"] as? Double ?? 0) }
        let pool = Array(newest.prefix(max(9, newest.count / 3)))
        let step = max(1, pool.count / 9)
        let picked = stride(from: 0, to: pool.count, by: step).prefix(9).map { pool[$0] }
        let folder = work.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var cells: [ContactSheet.Cell] = []
        for photo in picked {
            let id = "\(photo["id"] ?? "")"
            let file = folder.appendingPathComponent(id + ".jpg")
            if !FileManager.default.fileExists(atPath: file.path) {
                guard Download.file(photo["thumb_1024_url"] as! String, to: file).status == 0 else { continue }
            }
            let date = (photo["captured_at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000).formatted(.iso8601.year().month().day()) } ?? "?"
            cells.append(ContactSheet.Cell(image: file, box: nil, cut: false, label: date))
        }
        guard !cells.isEmpty else { throw MCPChannel.Failure("Mapillary listed photos but none came down: try again") }
        let sheet = work.appendingPathComponent("photos-\(String(format: "%.4f_%.4f", lat, lon)).jpg")
        try ContactSheet.draw(cells, to: sheet)
        return [MCPChannel.text("\(cells.count) of \(found.count) street photos within \(Int(radius)) m (Mapillary, CC BY-SA 4.0), the newest spread over their dates."),
                ["type": "image", "data": try Data(contentsOf: sheet).base64EncodedString(), "mimeType": "image/jpeg"]]
    }
}
