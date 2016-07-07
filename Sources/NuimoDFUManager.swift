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

public class NuimoDFUManager {
    public weak var delegate: NuimoDFUManagerDelegate?

    public private(set) var discoveredControllers: Set<NuimoDFUBluetoothController> = []

    private var peripheralIdentifier = ""
    private lazy var discovery: NuimoDiscoveryManager = NuimoDiscoveryManager(delegate: self, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true, NuimoDiscoveryManagerAdditionalDiscoverServiceUUIDsKey: [CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")]])
    private var dfuController: DFUServiceController?

    public init(delegate: NuimoDFUManagerDelegate? = nil) {
        self.delegate = delegate
    }

    public func startDiscovery() {
        discovery.startDiscovery(true)
    }

    public func stopDiscovery() {
        discovery.stopDiscovery()
    }

    public func startUpdateForNuimoController(controller: NuimoDFUBluetoothController, withUpdateURL URL: NSURL) {
        let localFirmwareFilename = String(format: "%@_%@", NSProcessInfo.processInfo().globallyUniqueString, "nf.zip")
        let localFirmwareFileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(localFirmwareFilename)

        Alamofire
            .download(.GET, URL.absoluteString, destination: { _ in return localFirmwareFileURL })
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

    public func cancelUpdate() {
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
    @objc public func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, deviceForPeripheral peripheral: CBPeripheral) -> BLEDevice? {
        guard peripheral.name == "NuimoDFU" else { return nil }
        return NuimoDFUBluetoothController(discoveryManager: discovery.bleDiscovery, uuid: peripheral.identifier.UUIDString, peripheral: peripheral)
    }

    @objc public func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, didDiscoverNuimoController controller: NuimoController) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        controller.delegate = self
        discoveredControllers.insert(controller)
        delegate?.nuimoDFUManager(self, didDisoverNuimoDFUController: controller)
    }
}

extension NuimoDFUManager: NuimoControllerDelegate {
    @objc public func nuimoController(controller: NuimoController, didChangeConnectionState state: NuimoConnectionState, withError error: NSError?) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        if state == .Invalidated {
            discoveredControllers.remove(controller)
            delegate?.nuimoDFUManager(self, didInvalidateNuimoDFUController: controller)
        }
    }
}

extension NuimoDFUManager: DFUServiceDelegate {
    @objc public func didStateChangedTo(state: State) {
        delegate?.nuimoDFUManager(self, didChangeState: NuimoDFUState(state: state))
    }

    @objc public func didErrorOccur(error: DFUError, withMessage message: String) {
        delegate?.nuimoDFUManager(self, didFailFlashingFirmwareWithError: NSError(domain: "NuimoDFUManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update aborted", NSLocalizedFailureReasonErrorKey: message]))
    }
}

extension NuimoDFUManager: DFUProgressDelegate {
    @objc public func onUploadProgress(part: Int, totalParts: Int, progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        delegate?.nuimoDFUManager(self, didUpdateProgress: Float(progress) / 100.0, forPartIndex: part - 1, ofPartsCount: totalParts)
    }
}

//TODO: http://marginalfutility.net/2015/10/11/swift-compiler-flags/
#if DEBUG
extension NuimoDFUManager: LoggerDelegate {
    @objc public func logWith(level: LogLevel, message: String) {
        print("DFU", level.rawValue, message)
    }
}
#endif

public protocol NuimoDFUManagerDelegate: class {
    func nuimoDFUManager(manager: NuimoDFUManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController)
    func nuimoDFUManager(manager: NuimoDFUManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController)
    func nuimoDFUManager(manager: NuimoDFUManager, didChangeState state: NuimoDFUState)
    func nuimoDFUManager(manager: NuimoDFUManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int)
    func nuimoDFUManager(manager: NuimoDFUManager, didFailDownloadingFirmwareWithError error: NSError)
    func nuimoDFUManagerDidFailStartingFirmwareUpload(manager: NuimoDFUManager)
    func nuimoDFUManager(manager: NuimoDFUManager, didFailFlashingFirmwareWithError error: NSError)
}

public extension NuimoDFUManagerDelegate {
    func nuimoDFUManager(manager: NuimoDFUManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didChangeState state: NuimoDFUState) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didFailDownloadingFirmwareWithError error: NSError) {}
    func nuimoDFUManagerDidFailStartingFirmwareUpload(manager: NuimoDFUManager) {}
    func nuimoDFUManager(manager: NuimoDFUManager, didFailFlashingFirmwareWithError error: NSError) {}
}

public class NuimoDFUBluetoothController: NuimoBluetoothController {
    override public var serviceUUIDs:                    [CBUUID]            { return [] }
    override public var charactericUUIDsForServiceUUID:  [CBUUID : [CBUUID]] { return [:] }
    override public var notificationCharacteristicUUIDs: [CBUUID]            { return [] }

    override public func connect() -> Bool {
        return false
    }
}

public enum NuimoDFUState {
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
