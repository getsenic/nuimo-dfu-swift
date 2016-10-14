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
    public var updateStoreURL               = NSURL(string: "https://files.senic.com/nuimo-firmware-updates.json")!
    public private(set) var firmwareUpates: [NuimoFirmwareUpdate] = []
    public var latestFirmwareUpdate:        NuimoFirmwareUpdate? { return firmwareUpates.first }

    public func requestFirmwareUpdates() {
        let request = NSMutableURLRequest(URL: updateStoreURL)
        request.HTTPMethod  = "GET"
        request.cachePolicy = NSURLRequestCachePolicy.ReloadIgnoringCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Alamofire
            .request(request)
            .responseJSON { [weak self] response in
                guard let strongSelf = self else { return }
                switch response.result {
                case .Success(let json):
                    guard let jsonUpdates = (json["updates"] as? Array<Dictionary<String, String>>) else {
                        strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: NSError(domain: "NuimoDFUCache", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot retrieve firmware updates", NSLocalizedFailureReasonErrorKey: "The update meta file is invalid"]))
                        return
                    }
                    let updates: [NuimoFirmwareUpdate] = jsonUpdates
                        .flatMap { values in guard let versionString = values["version"], version = NuimoFirmwareVersion(string: versionString), urlString = values["url"], url = NSURL(string: urlString) else { return nil }
                            return NuimoFirmwareUpdate(version: version, URL: url)
                        }.sort { (lhs, rhs) in
                            return lhs > rhs
                        }
                    guard updates.count > 0 else {
                        strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: NSError(domain: "NuimoDFUCache", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot retrieve firmware updates", NSLocalizedFailureReasonErrorKey: "The list of updates is empty"]))
                        return
                    }
                    strongSelf.firmwareUpates = updates
                    strongSelf.delegate?.nuimoDFUFirmwareCacheDidUpdate(strongSelf)
                    NSNotificationCenter.defaultCenter().postNotificationName(NuimoDFUFirmwareCacheDidRequestFirmwareUpdates, object: self)
                case .Failure(let error):
                    strongSelf.delegate?.nuimoDFUFirmwareCache(strongSelf, didFailRetrievingFirmwareUpdatesWithError: error)
                }
        }
    }
}

public protocol NuimoDFUFirmwareCacheDelegate: class {
    func nuimoDFUFirmwareCacheDidUpdate(cache: NuimoDFUFirmwareCache)
    func nuimoDFUFirmwareCache(cache: NuimoDFUFirmwareCache, didFailRetrievingFirmwareUpdatesWithError error: NSError)
}

public struct NuimoFirmwareUpdate {
    public let version: NuimoFirmwareVersion
    public let URL: NSURL
}

public struct NuimoFirmwareVersion {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(string: String) {
        let tokens = string.componentsSeparatedByString(".")
        guard tokens.count >= 3 else { return nil }
        guard let major = Int(tokens[0]), minor = Int(tokens[1]), patch = Int(tokens[2]) where major >= 0 && minor >= 0 && patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
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
        }
    }
    return false
}

public func ==(lhs: NuimoFirmwareVersion, rhs: NuimoFirmwareVersion) -> Bool {
    return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
}

public func <(lhs: NuimoFirmwareVersion, rhs: NuimoFirmwareVersion) -> Bool {
    return !(lhs == rhs) && !(lhs > rhs)
}

public let NuimoDFUFirmwareCacheDidRequestFirmwareUpdates = "NuimoDFUFirmwareCacheDidRequestFirmwareUpdates"
