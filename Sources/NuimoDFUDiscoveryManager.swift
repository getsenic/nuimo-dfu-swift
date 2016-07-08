//
//  NuimoDFUDiscoveryManager.swift
//  Pods
//
//  Created by Lars Blumberg on 7/8/16.
//
//

import CoreBluetooth
import iOSDFULibrary
import NuimoSwift
import Then

public class NuimoDFUDiscoveryManager {
    public weak var delegate: NuimoDFUDiscoveryManagerDelegate?
    public var centralManager: CBCentralManager { return discovery.centralManager }

    public private(set) var discoveredControllers: Set<NuimoDFUBluetoothController> = []

    private lazy var discovery: NuimoDiscoveryManager = NuimoDiscoveryManager(delegate: self, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true, NuimoDiscoveryManagerAdditionalDiscoverServiceUUIDsKey: [CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")]])

    public init(delegate: NuimoDFUDiscoveryManagerDelegate? = nil) {
        self.delegate = delegate
    }

    public func startDiscovery() {
        discovery.startDiscovery(true)
    }

    public func stopDiscovery() {
        discovery.stopDiscovery()
    }
}

extension NuimoDFUDiscoveryManager: NuimoDiscoveryDelegate {
    @objc public func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, deviceForPeripheral peripheral: CBPeripheral) -> BLEDevice? {
        guard peripheral.name == "NuimoDFU" else { return nil }
        return NuimoDFUBluetoothController(discoveryManager: discovery.bleDiscovery, uuid: peripheral.identifier.UUIDString, peripheral: peripheral)
    }

    @objc public func nuimoDiscoveryManager(discovery: NuimoDiscoveryManager, didDiscoverNuimoController controller: NuimoController) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        controller.delegate = self
        discoveredControllers.insert(controller)
        delegate?.nuimoDFUDiscoveryManager(self, didDisoverNuimoDFUController: controller)
    }
}

extension NuimoDFUDiscoveryManager: NuimoControllerDelegate {
    @objc public func nuimoController(controller: NuimoController, didChangeConnectionState state: NuimoConnectionState, withError error: NSError?) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        if state == .Invalidated {
            discoveredControllers.remove(controller)
            delegate?.nuimoDFUDiscoveryManager(self, didInvalidateNuimoDFUController: controller)
        }
    }
}

public protocol NuimoDFUDiscoveryManagerDelegate: class {
    func nuimoDFUDiscoveryManager(manager: NuimoDFUDiscoveryManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController)
    func nuimoDFUDiscoveryManager(manager: NuimoDFUDiscoveryManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController)
}

public extension NuimoDFUDiscoveryManagerDelegate {
    func nuimoDFUDiscoveryManager(manager: NuimoDFUDiscoveryManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {}
    func nuimoDFUDiscoveryManager(manager: NuimoDFUDiscoveryManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController) {}
}
