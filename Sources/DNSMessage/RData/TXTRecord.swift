import NIOCore

/// A text record. This is used for storing arbitrary text.
public struct TXTRecord: DNSResource {
    /// The values of the text record. This is a dictionary of key-value pairs.
    public let values: [String: String]
    public let rawValues: [String]

    init(values: [String: String], rawValues: [String]) {
        self.values = values
        self.rawValues = rawValues
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> TXTRecord? {
        var currentIndex = 0
        var components: [String: String] = [:]
        var rawValues: [String] = []

        while currentIndex < length {
            guard let componentLenght = buffer.readInteger(endianness: .big, as: UInt8.self) else {
                return nil
            }

            currentIndex += (Int(componentLenght) + 1)

            guard let componentString = buffer.readString(length: Int(componentLenght)) else {
                return nil
            }

            rawValues.append(componentString)

            let parts = componentString.split(separator: "=")

            if parts.count != 2 {
                continue
            }

            components[String(parts[0])] = String(parts[1])
        }

        return TXTRecord(values: components, rawValues: rawValues)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        fatalError()
    }
}
