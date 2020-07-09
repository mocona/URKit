//
//  URDecoder.swift
//
//  Copyright © 2020 by Blockchain Commons, LLC
//  Licensed under the "BSD-2-Clause Plus Patent License"
//

import Foundation

public final class URDecoder {
    public enum Error: Swift.Error {
        case invalidScheme
        case invalidType
        case invalidPathLength
        case invalidSequenceComponent
        case invalidFragment
    }

    /// Decode a single-part UR.
    public static func decode(_ string: String) throws -> UR {
        let (type, components) = try parse(string)

        guard let body = components.first else {
            throw Error.invalidPathLength
        }

        return try decode(type: type, body: body)
    }

    static func decode(type: String, body: String) throws -> UR {
        let cbor = try Bytewords.decode(body, style: .minimal)
        return try UR(type: type, cbor: cbor)
    }

    let fountainDecoder: FountainDecoder

    public var expectedType: String?
    public var expectedPartCount: Int! { fountainDecoder.expectedPartCount }
    public var receivedPartIndexes: PartIndexes { fountainDecoder.receivedPartIndexes }
    public var lastPartIndexes: PartIndexes! { fountainDecoder.lastPartIndexes }
    public var processedPartsCount: Int { fountainDecoder.processedPartsCount }
    public var estimatedPercentComplete: Double { fountainDecoder.estimatedPercentComplete }
    public var result: Result<UR, Swift.Error>?

    /// Start decoding a (possibly) multi-part UR.
    public init() {
        fountainDecoder = FountainDecoder()
    }

    @discardableResult public func receivePart(_ string: String) -> Bool {
        do {
            // Don't process the part if we're already done
            guard result == nil else { return false }

            // Don't continue if this part doesn't validate
            let (type, components) = try Self.parse(string)
            guard validatePart(type: type) else { return false }

            // If this is a single-part UR then we're done
            if components.count == 1 {
                let body = components[0]
                result = try .success(Self.decode(type: type, body: body))
                return true
            }

            // Multi-part URs must have two path components: seq/fragment
            guard components.count == 2 else { throw Error.invalidPathLength }
            let seq = components[0]
            let fragment = components[1]

            // Parse the sequence component and the fragment, and
            // make sure they agree.
            let (seqNum, seqLen) = try Self.parseSequenceComponent(seq)
            let cbor = try Bytewords.decode(fragment, style: .minimal)
            let part = try FountainEncoder.Part(cbor: cbor)
            guard seqNum == part.seqNum, seqLen == part.seqLen else {
                return false
            }

            // Process the part
            guard fountainDecoder.receivePart(part) else {
                return false
            }

            switch fountainDecoder.result {
            case .success(let cbor)?:
                result = try! .success(UR(type: type, cbor: cbor))
            case .failure(let error)?:
                result = .failure(error)
            case nil:
                break
            }

            return true
        } catch {
            return false
        }
    }

    func validatePart(type: String) -> Bool {
        if expectedType == nil {
            guard type.isURType else { return false }
            expectedType = type
        } else {
            return type == expectedType
        }
        return true
    }

    static func parse(_ string: String) throws -> (type: String, components: [String]) {
        // Don't consider case
        let lowered = string.lowercased()

        // Validate URI scheme
        guard lowered.hasPrefix("ur:") else { throw Error.invalidScheme }
        let path = lowered.dropFirst(3)

        // Split the remainder into path components
        let components = path.split(separator: "/").map { String($0) }

        // Make sure there are at least two path components
        guard components.count > 1 else {
            throw Error.invalidPathLength
        }

        // Validate the type
        let type = components[0]
        guard type.isURType else { throw Error.invalidType }

        return (type, Array(components[1...]))
    }

    static func parseSequenceComponent(_ s: String) throws -> (seqNum: Int, seqLen: Int) {
        let scanner = Scanner(string: s)
        guard let seqNum = scanner.scanInt() else { throw Error.invalidSequenceComponent }
        guard scanner.scanString("-") != nil else { throw Error.invalidSequenceComponent }
        guard let seqLen = scanner.scanInt() else { throw Error.invalidSequenceComponent }
        guard scanner.isAtEnd else { throw Error.invalidSequenceComponent }
        guard seqNum >= 1, seqLen >= 1 else { throw Error.invalidSequenceComponent }
        return (seqNum, seqLen)
    }
}
