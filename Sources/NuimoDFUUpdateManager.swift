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

    private var centralManager: CBCentralManager

    private var dfuInitiator: DFUServiceInitiator?
    private var dfuController: DFUServiceController?

    public init(centralManager: CBCentralManager, delegate: NuimoDFUUpdateManagerDelegate? = nil) {
        self.centralManager = centralManager
        self.delegate = delegate
    }

    public func startUpdateForNuimoController(_ controller: NuimoDFUBluetoothController, withLocalOrRemoteFirmwareURL url: URL) {
        guard url.scheme != "file" else {
            updateNuimoController(controller, withLocalFirmwareURL: url)
            return
        }

        let localFirmwareFilename = String(format: "%@_%@", ProcessInfo.processInfo.globallyUniqueString, "nf.zip")
        let localFirmwareFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(localFirmwareFilename)

        Alamofire
            .download(url) { _ in
                return (localFirmwareFileURL, [DownloadRequest.DownloadOptions.removePreviousFile])
            }
            .response{ [weak self] response in
                guard let strongSelf = self else { return }
                if let error = response.error {
                    strongSelf.delegate?.nuimoDFUUpdateManager(strongSelf, didFailDownloadingFirmwareWithError: error)
                    return
                }
                strongSelf.updateNuimoController(controller, withLocalFirmwareURL: localFirmwareFileURL)
            }
    }

    public func cancelUpdate() {
        dfuController?.abort()
    }

    func updateNuimoController(_ controller: NuimoDFUBluetoothController, withLocalFirmwareURL firmwareURL: URL) {
        cancelUpdate()
        guard let firmware = DFUFirmware(urlToZipFile: firmwareURL) else {
            delegate?.nuimoDFUUpdateManager(self, didFailStartingFirmwareUploadWithError: NSError(domain: "NuimoDFUUpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open firmware file", NSLocalizedFailureReasonErrorKey: "Unknown"]))
            return
        }
        guard let peripheral = controller.peripheral else {
            delegate?.nuimoDFUUpdateManager(self, didFailStartingFirmwareUploadWithError: NSError(domain: "NuimoDFUUpdateManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot update Nuimo", NSLocalizedFailureReasonErrorKey: "Nuimo is not connected"]))
            return
        }
        dfuInitiator = DFUServiceInitiator(centralManager: centralManager, target: peripheral).then {
            $0.logger           = self // Fixes https://github.com/NordicSemiconductor/IOS-Pods-DFU-Library/issues/14
            $0.delegate         = self
            $0.progressDelegate = self
        }.with(firmware: firmware)

        startUpdate()
    }

    fileprivate func startUpdate() {
        guard let dfuInitiator = dfuInitiator else { return }

        guard let dfuController = dfuInitiator.start() else {
            delegate?.nuimoDFUUpdateManager(self, didFailStartingFirmwareUploadWithError: NSError(domain: "NuimoDFUUpdateManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware update", NSLocalizedFailureReasonErrorKey: "Unexpected error"]))
            return
        }
        self.dfuController = dfuController
    }
}

extension NuimoDFUUpdateManager: DFUServiceDelegate {
    @objc public func dfuStateDidChange(to state: DFUState) {
        delegate?.nuimoDFUUpdateManager(self, didChangeState: NuimoDFUUpdateState(state: state))
    }

    @objc public func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        if error == .deviceDisconnected {
            // For some reason Nuimo/DFU library disconnects very often during first connection attempt, simply restart DFU
            cancelUpdate()
            startUpdate()
            return
        }

        delegate?.nuimoDFUUpdateManager(self, didFailFlashingFirmwareWithError: NSError(domain: "NuimoDFUUpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update aborted with error code \(error.rawValue)", NSLocalizedFailureReasonErrorKey: message]))
    }
}

extension NuimoDFUUpdateManager: DFUProgressDelegate {
    @objc public func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        delegate?.nuimoDFUUpdateManager(self, didUpdateProgress: Float(progress) / 100.0, forPartIndex: part - 1, ofPartsCount: totalParts)
    }
}

extension NuimoDFUUpdateManager: LoggerDelegate {
    @objc public func logWith(_ level: LogLevel, message: String) {
        #if DEBUG
        print("DFU", level.rawValue, message)
        #endif
    }
}

public protocol NuimoDFUUpdateManagerDelegate: class {
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState)
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int)
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: Error)
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailStartingFirmwareUploadWithError error: Error)
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: Error)
}

public extension NuimoDFUUpdateManagerDelegate {
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState) {}
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {}
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: Error) {}
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailStartingFirmwareUploadWithError error: Error) {}
    func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: Error) {}
}

public enum NuimoDFUUpdateState {
    case connecting
    case starting
    case enablingDfuMode
    case uploading
    case validating
    case disconnecting
    case completed
    case aborted

    var description: String {
        switch self {
        case .connecting:            return "Connecting"
        case .starting:              return "Starting"
        case .enablingDfuMode:       return "Enabling DFU mode"
        case .uploading:             return "Uploading"
        case .validating:            return "Validating"
        case .disconnecting:         return "Disconnecting"
        case .completed:             return "Completing"
        case .aborted:               return "Aborted"
        }
    }

    init(state: DFUState) {
        switch state {
        case .connecting:            self = .connecting
        case .starting:              self = .starting
        case .enablingDfuMode:       self = .enablingDfuMode
        case .uploading:             self = .uploading
        case .validating:            self = .validating
        case .disconnecting:         self = .disconnecting
        case .completed:             self = .completed
        case .aborted:               self = .aborted
        }
    }
}
