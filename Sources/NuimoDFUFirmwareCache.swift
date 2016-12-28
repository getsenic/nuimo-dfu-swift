//
//  NuimoDFUCache.swift
//  NuimoDFU
//
//  Created by Lars Blumberg on 6/27/16.
//  Copyright © 2016 senic. All rights reserved.
//

import Alamofire

public class NuimoDFUFirmwareCache {
    public static let sharedCache = NuimoDFUFirmwareCache()

    public weak var delegate:               NuimoDFUFirmwareCacheDelegate?
    public var updateStoreURL =             URL(string: "https://files.senic.com/nuimo-firmware-updates.json")!
    public private(set) var firmwareUpates: [NuimoFirmwareUpdate] = []
    public var latestFirmwareUpdate:        NuimoFirmwareUpdate? { return firmwareUpates.first }

    public func requestFirmwareUpdates() {
        var request = URLRequest(url: updateStoreURL)
        request.httpMethod  = "GET"
        request.cachePolicy = NSURLRequest.CachePolicy.reloadIgnoringCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Alamofire
            .request(request)
            .responseJSON { [weak self] response in
                guard let strongSelf = self else { return }
                switch response.result {
                case .success(let json):
                    guard let jsonUpdates = (json as? [String : [[String : String]]])?["updates"] else {
                        strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: NSError(domain: "NuimoDFUCache", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot retrieve firmware updates", NSLocalizedFailureReasonErrorKey: "The update meta file is invalid"]))
                        return
                    }
                    let updates: [NuimoFirmwareUpdate] = jsonUpdates
                        .flatMap { values in
                            guard
                                let versionString = values["version"],
                                let version       = NuimoFirmwareVersion(string: versionString),
                                let urlString     = values["url"],
                                let url           = URL(string: urlString)
                            else { return nil }
                            return NuimoFirmwareUpdate(version: version, url: url)
                        }
                        .sorted { (lhs, rhs) in
                            return lhs > rhs
                        }
                    guard updates.count > 0 else {
                        strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: NSError(domain: "NuimoDFUCache", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot retrieve firmware updates", NSLocalizedFailureReasonErrorKey: "The list of updates is empty"]))
                        return
                    }
                    strongSelf.firmwareUpates = updates
                    strongSelf.delegate?.nuimoDFUFirmwareCacheDidUpdate(strongSelf)
                    NotificationCenter.default.post(name: .NuimoDFUFirmwareCacheDidRequestFirmwareUpdates, object: self)
                case .failure(let error):
                    strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: error)
                }
        }
    }
}

public protocol NuimoDFUFirmwareCacheDelegate: class {
    func nuimoDFUFirmwareCacheDidUpdate(_ cache: NuimoDFUFirmwareCache)
    func nuimoDFUFirmwareCache(_ cache: NuimoDFUFirmwareCache, didFailRetrievingFirmwareUpdatesWithError error: Error)
}

public struct NuimoFirmwareUpdate {
    public let version: NuimoFirmwareVersion
    public let url: URL
}

public struct NuimoFirmwareVersion {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let beta: Int?

    public init?(string: String) {
        guard let match = string.matchingStrings(regex: "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:\\.beta([0-9]+))?$").first else { return nil }
        guard match.count >= 5 else { return nil }
        guard
            let major = Int(match[1]),
            let minor = Int(match[2]),
            let patch = Int(match[3])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.beta  = Int(match[4])
    }
}

public func >(lhs: NuimoFirmwareUpdate, rhs: NuimoFirmwareUpdate) -> Bool {
    return lhs.version > rhs.version
}

public func ==(lhs: NuimoFirmwareUpdate, rhs: NuimoFirmwareUpdate) -> Bool {
    return lhs.version == rhs.version
}

public func <(lhs: NuimoFirmwareUpdate, rhs: NuimoFirmwareUpdate) -> Bool {
    return lhs.version < rhs.version
}

public func >(lhs: NuimoFirmwareVersion, rhs: NuimoFirmwareVersion) -> Bool {
    if lhs.major > rhs.major {
        return true
    }
    else if lhs.major == rhs.major {
        if lhs.minor > rhs.minor {
            return true
        }
        else if lhs.minor == rhs.minor {
            if lhs.patch > rhs.patch {
                return true
            }
            else if lhs.patch == rhs.patch {
                if let lhsBeta = lhs.beta {
                    if let rhsBeta = rhs.beta {
                        return lhsBeta > rhsBeta
                    }
                }
                else if let _ = rhs.beta {
                    // `lhs` is release and `rhs` is beta of the same version, e.g. `lhs`=1.2.3, `rhs`=1.2.3.beta4, that's why `lhs` outdates `rhs`
                    return true
                }
            }
        }
    }
    return false
}

public func ==(lhs: NuimoFirmwareVersion, rhs: NuimoFirmwareVersion) -> Bool {
    return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.beta == rhs.beta
}

public func <(lhs: NuimoFirmwareVersion, rhs: NuimoFirmwareVersion) -> Bool {
    return !(lhs == rhs) && !(lhs > rhs)
}

public extension Notification.Name {
    static let NuimoDFUFirmwareCacheDidRequestFirmwareUpdates = Notification.Name(rawValue: "NuimoDFUFirmwareCacheDidRequestFirmwareUpdates")
}

private extension String {
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map { result.rangeAt($0).location != NSNotFound
                ? nsString.substring(with: result.rangeAt($0))
                : ""
            }
        }
    }
}
