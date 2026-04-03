import Foundation

enum Persistence {

    static func documentsURL(_ filename: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(filename)
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        do {
            let url = documentsURL(filename)

            // Ensure directory exists
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let data = try JSONEncoder.pretty.encode(value)
            try data.write(to: url, options: [.atomic])

        } catch {
            print("❌ Save failed (\(filename)): \(error)")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        do {
            let url = documentsURL(filename)

            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            let data = try Data(contentsOf: url)
            return try JSONDecoder.iso.decode(type, from: data)

        } catch {
            print("❌ Load failed (\(filename)): \(error)")
            return nil
        }
    }
}

// MARK: - Encoder

private extension JSONEncoder {

    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

// MARK: - Decoder

private extension JSONDecoder {

    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
