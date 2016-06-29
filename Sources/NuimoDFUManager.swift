//
//  NuimoDFUBManager.swift
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

class NuimoDFUManager {
    weak var delegate: NuimoDFUManagerDelegate?

    private var peripheralIdentifier = ""
    private lazy var discovery: NuimoDiscoveryManager = NuimoDiscoveryManager(delegate: self, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true, NuimoDiscoveryManagerAdditionalDiscoverServiceUUIDsKey: [CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")]])
    private var dfuController: DFUServiceController?

    func startDiscovery() {
        discovery.startDiscovery()
    }

    func stopDiscovery() {
        discovery.stopDiscovery()
    }

    func startUpdateForNuimoController(controller: NuimoDFUBluetoothController) {
        let localFirmwareFilename = String(format: "%@_%@", NSProcessInfo.processInfo().globallyUniqueString, "nf.zip")
        let localFirmwareFileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(localFirmwareFilename)

        Alamofire
            .download(.GET, "https://www.senic.com/files/nuimo-firmware-2-1-0.zip", destination: { _ in return localFirmwareFileURL })
            .response{ [weak self] (_, _, _, error) in
                guard let strongSelf = self else { return }
                if let error = error {
                    strongSelf.delegate?.nuimoDFUManager(strongSelf, didFailDownloadingFirmwareWithError: error)
                    return
                }
                let updateStarted = strongSelf.updateNuimoController(controller, withFirmwareZIPFileURL: localFirmwareFileURL)
                if !updateStarted {
                    strongSelf.delegate?.nuimoDFUManagerDidFailStartingFirmwareUpload(strongSelf)
                }
            }
    }

    func cancelUpdate() {
        dfuController?.abort()
    }

    private func updateNuimoController(controller: NuimoDFUBluetoothController, withFirmwareZIPFileURL firmwareURL: NSURL) -> Bool {
        cancelUpdate()
        guard let firmware = DFUFirmware(urlToZipFile: firmwareURL) else { return false }
        let dfuInitiator = DFUServiceInitiator(centralManager: discovery.centralManager, target: controller.peripheral).then {
            #if DEBUG
            $0.logger           = self
            #endif
            $0.delegate         = self
            $0.progressDelegate = self
        }.withFirmwareFile(firmware)
        guard let dfuController = dfuInitiator.start() else { return false }
        self.dfuController = dfuController
        return true
    }
}

extension NuimoDFUManager: NuimoDiscoveryDelegate {
    @objc func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, deviceForPeripheral peripheral: CBPeripheral) -> BLEDevice? {
        guard peripheral.name == "NuimoDFU" else { return nil }
        return NuimoDFUBluetoothController(centralManager: discovery.centralManager, uuid: peripheral.identifier.UUIDString, peripheral: peripheral)
    }

    @objc func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, didDiscoverNuimoController controller: NuimoController) {
        print("Found DFU \(controller.uuid)")
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        delegate?.nuimoDFUManager(self, didDisoverNuimoDFUController: controller)
    }
}

extension NuimoDFUManager: DFUServiceDelegate {
    @objc func didStateChangedTo(state: State) {
        delegate?.nuimoDFUManager(self, didChangeState: NuimoDFUState(state: state))
    }

    @objc func didErrorOccur(error: DFUError, withMessage message: String) {
        delegate?.nuimoDFUManager(self, didFailFlashingFirmwareWithError: NSError(domain: "NuimoDFUManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update aborted", NSLocalizedFailureReasonErrorKey: message]))
    }
}

extension NuimoDFUManager: DFUProgressDelegate {
    @objc func onUploadProgress(part: Int, totalParts: Int, progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        //TODO: Notify delegate
        print("DFU Progress", part, totalParts, progress)
        delegate?.nuimoDFUManager(self, didUpdateProgress: Float(progress) / 100.0, forPartIndex: part - 1, ofPartsCount: totalParts)
    }
}

#if DEBUG
extension NuimoDFUManager: LoggerDelegate {
    @objc func logWith(level: LogLevel, message: String) {
        print("DFU", level.rawValue, message)
    }
}
#endif

protocol NuimoDFUManagerDelegate: class {
    func nuimoDFUManager(manager: NuimoDFUManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController)
    func nuimoDFUManager(manager: NuimoDFUManager, didChangeState state: NuimoDFUState)
    func nuimoDFUManager(manager: NuimoDFUManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int)
    func nuimoDFUManager(manager: NuimoDFUManager, didFailDownloadingFirmwareWithError error: NSError)
    func nuimoDFUManagerDidFailStartingFirmwareUpload(manager: NuimoDFUManager)
    func nuimoDFUManager(manager: NuimoDFUManager, didFailFlashingFirmwareWithError error: NSError)
}

extension NuimoDFUManagerDelegate {
    func nuimoDFUManager(manager: NuimoDFUManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didChangeState state: NuimoDFUState) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didFailDownloadingFirmwareWithError error: NSError) {}
    func nuimoDFUManagerDidFailStartingFirmwareUpload(manager: NuimoDFUManager) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didFailFlashingFirmwareWithError error: NSError) {}
}

class NuimoDFUBluetoothController: NuimoBluetoothController {
    override var serviceUUIDs:                    [CBUUID]            { return [] }
    override var charactericUUIDsForServiceUUID:  [CBUUID : [CBUUID]] { return [:] }
    override var notificationCharacteristicUUIDs: [CBUUID]            { return [] }

    override func connect() -> Bool {
        return false
    }
}

enum NuimoDFUState {
    case Connecting
    case Starting
    case EnablingDfuMode
    case Uploading
    case Validating
    case Disconnecting
    case Completed
    case Aborted

    var description: String {
        switch self {
        case Connecting      : return "Connecting"
        case Starting        : return "Starting"
        case EnablingDfuMode : return "Enabling DFU mode"
        case Uploading       : return "Uploading"
        case Validating      : return "Validating"
        case Disconnecting   : return "Disconnecting"
        case Completed       : return "Completing"
        case Aborted         : return "Aborted"
        }
    }

    init(state: State) {
        switch state {
        case .Connecting:      self = .Connecting
        case .Starting:        self = .Starting
        case .EnablingDfuMode: self = .EnablingDfuMode
        case .Uploading:       self = .Uploading
        case .Validating:      self = .Validating
        case .Disconnecting:   self = .Disconnecting
        case .Completed:       self = .Completed
        case .Aborted:         self = .Aborted
        }
    }
}
