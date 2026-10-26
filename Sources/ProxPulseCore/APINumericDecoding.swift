import Foundation

extension KeyedDecodingContainer {
    func pveDouble(_ key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let number: Double
        if let value = try? decode(Double.self, forKey: key) { number = value }
        else if let value = try? decode(String.self, forKey: key), let parsed = Double(value) { number = parsed }
        else { throw DecodingError.typeMismatch(Double.self, .init(codingPath: codingPath + [key], debugDescription: "Expected a numeric API metric")) }
        guard number.isFinite else { throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [key], debugDescription: "Non-finite API metric")) }
        return number
    }
    func pveInt(_ key: Key) throws -> Int? {
        guard let number = try pveDouble(key) else { return nil }
        guard let value = Int(exactly: number) else { throw DecodingError.typeMismatch(Int.self, .init(codingPath: codingPath + [key], debugDescription: "Expected an integer API metric")) }
        return value
    }
    func pveFlag(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        return try pveInt(key)
    }
    func pveBool(_ key: Key) throws -> Bool? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key), [0, 1].contains(value) { return value == 1 }
        throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath + [key], debugDescription: "Expected a boolean API flag"))
    }
}
