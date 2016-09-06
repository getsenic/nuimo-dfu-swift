//
//  NuimoDFUUpdateManager.swift
//  NuimoDFU
//
//  Created by Lars Blumberg on 6/22/16.
//  Copyright © 2016 senic. All rights reserved.
//

import Alamofire
import CoreBluetooth
import iOSDFULibrary
import NuimoSwift
import Then

public class NuimoDFUUpdateManager {
    public weak var delegate: NuimoDFUUpdateManagerDelegate?

    public private(set) var discoveredControllers: Set<NuimoDFUBluetoothController> = []

    private var centralManager: CBCentralManager
    private var dfuController: DFUServiceController?

    public init(centralManager: CBCentralManager, delegate: NuimoDFUUpdateManagerDelegate? = nil) {
        self.centralManager = centralManager
        self.delegate = delegate
    }

    public func startUpdateForNuimoController(controller: NuimoDFUBluetoothController, withLocalOrRemoteFirmwareURL URL: NSURL) {
        guard URL.scheme != "file" else {
            updateNuimoController(controller, withLocalFirmwareURL: URL)
            return
        }

        let localFirmwareFilename = String(format: "%@_%@", NSProcessInfo.processInfo().globallyUniqueString, "nf.zip")
        let localFirmwareFileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(localFirmwareFilename)

        Alamofire
            .download(.GET, URL.absoluteString, destination: { _ in return localFirmwareFileURL })
            .response{ [weak self] (_, _, _, error) in
                guard let strongSelf = self else { return }
                if let error = error {
                    strongSelf.delegate?.nuimoDFUUpdateManager(strongSelf, didFailDownloadingFirmwareWithError: error)
                    return
                }
                strongSelf.updateNuimoController(controller, withLocalFirmwareURL: localFirmwareFileURL)
            }
    }

    public func cancelUpdate() {
        dfuController?.abort()
    }

    func updateNuimoController(controller: NuimoDFUBluetoothController, withLocalFirmwareURL firmwareURL: NSURL) {
        cancelUpdate()
        guard let firmware = DFUFirmware(urlToZipFile: firmwareURL) else {
            delegate?.nuimoDFUUpdateManager(self, didFailStartingFirmwareUploadWithError: NSError(domain: "NuimoDFUUpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open firmware file", NSLocalizedFailureReasonErrorKey: "Unknown"]))
            return
        }
        let dfuInitiator = DFUServiceInitiator(centralManager: centralManager, target: controller.peripheral).then {
            #if DEBUG
            $0.logger           = self
            #endif
            $0.delegate         = self
            $0.progressDelegate = self
        }.withFirmwareFile(firmware)
        guard let dfuController = dfuInitiator.start() else {
            delegate?.nuimoDFUUpdateManager(self, didFailStartingFirmwareUploadWithError: NSError(domain: "NuimoDFUUpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware update", NSLocalizedFailureReasonErrorKey: "Unexpected error"]))
            return
        }
        self.dfuController = dfuController
    }
}

extension NuimoDFUUpdateManager: DFUServiceDelegate {
    @objc public func didStateChangedTo(state: State) {
        delegate?.nuimoDFUUpdateManager(self, didChangeState: NuimoDFUUpdateState(state: state))
    }

    @objc public func didErrorOccur(error: DFUError, withMessage message: String) {
        delegate?.nuimoDFUUpdateManager(self, didFailFlashingFirmwareWithError: NSError(domain: "NuimoDFUUpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update aborted", NSLocalizedFailureReasonErrorKey: message]))
    }
}

extension NuimoDFUUpdateManager: DFUProgressDelegate {
    @objc public func onUploadProgress(part: Int, totalParts: Int, progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        delegate?.nuimoDFUUpdateManager(self, didUpdateProgress: Float(progress) / 100.0, forPartIndex: part - 1, ofPartsCount: totalParts)
    }
}

//TODO: http://marginalfutility.net/2015/10/11/swift-compiler-flags/
#if DEBUG
extension NuimoDFUUpdateManager: LoggerDelegate {
    @objc public func logWith(level: LogLevel, message: String) {
        print("DFU", level.rawValue, message)
    }
}
#endif

public protocol NuimoDFUUpdateManagerDelegate: class {
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState)
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int)
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: NSError)
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailStartingFirmwareUploadWithError error: NSError)
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: NSError)
}

public extension NuimoDFUUpdateManagerDelegate {
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState) {}
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {}
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: NSError) {}
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailStartingFirmwareUploadWithError error: NSError) {}
    func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: NSError) {}
}

public enum NuimoDFUUpdateState {
    case Connecting
    case Starting
    case EnablingDfuMode
    case Uploading
    case Validating
    case Disconnecting
    case Completed
    case Aborted
    case SignatureMismatch
    case OperationNotPermitted
    case Failed

    var description: String {
        switch self {
        case Connecting:            return "Connecting"
        case Starting:              return "Starting"
        case EnablingDfuMode:       return "Enabling DFU mode"
        case Uploading:             return "Uploading"
        case Validating:            return "Validating"
        case Disconnecting:         return "Disconnecting"
        case Completed:             return "Completing"
        case Aborted:               return "Aborted"
        case SignatureMismatch:     return "Signature mismatch"
        case OperationNotPermitted: return "Operation not permitted"
        case Failed:                return "Failed"
        }
    }

    init(state: State) {
        switch state {
        case .Connecting:            self = .Connecting
        case .Starting:              self = .Starting
        case .EnablingDfuMode:       self = .EnablingDfuMode
        case .Uploading:             self = .Uploading
        case .Validating:            self = .Validating
        case .Disconnecting:         self = .Disconnecting
        case .Completed:             self = .Completed
        case .Aborted:               self = .Aborted
        //TODO: Need to be added when nordic DFU library is updated from 1.0.12 which crashes, see https://github.com/NordicSemiconductor/IOS-Pods-DFU-Library/issues/14
        /*
        case .SignatureMismatch:     self = .SignatureMismatch
        case .OperationNotPermitted: self = .OperationNotPermitted
        case .Failed:                self = .Failed
        */
        }
    }
}
