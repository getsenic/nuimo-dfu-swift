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

    public fileprivate(set) var discoveredControllers: Set<NuimoDFUBluetoothController> = []

    private lazy var discovery: NuimoDiscoveryManager = NuimoDiscoveryManager(delegate: self)

    public init(delegate: NuimoDFUDiscoveryManagerDelegate? = nil) {
        self.delegate = delegate
    }

    public func startDiscovery() {
        discovery.startDiscovery(extraServiceUUIDs: [CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")], detectUnreachableControllers: true)
    }

    public func stopDiscovery() {
        discovery.stopDiscovery()
    }
}

extension NuimoDFUDiscoveryManager: NuimoDiscoveryDelegate {
    public func nuimoDiscoveryManager(_ discovery: NuimoDiscoveryManager, deviceForPeripheral peripheral: CBPeripheral) -> BLEDevice? {
        guard peripheral.name == "NuimoDFU" else { return nil }
        return NuimoDFUBluetoothController(discoveryManager: discovery.bleDiscovery, uuid: peripheral.identifier.uuidString, peripheral: peripheral)
    }

    public func nuimoDiscoveryManager(_ discovery: NuimoDiscoveryManager, didDiscoverNuimoController controller: NuimoController) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        controller.delegate = self
        discoveredControllers.insert(controller)
        delegate?.nuimoDFUDiscoveryManager(self, didDisoverNuimoDFUController: controller)
    }
}

extension NuimoDFUDiscoveryManager: NuimoControllerDelegate {
    public func nuimoController(_ controller: NuimoController, didChangeConnectionState state: NuimoConnectionState, withError error: NSError?) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        if state == .invalidated {
            discoveredControllers.remove(controller)
            delegate?.nuimoDFUDiscoveryManager(self, didInvalidateNuimoDFUController: controller)
        }
    }
}

public protocol NuimoDFUDiscoveryManagerDelegate: class {
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController)
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController)
}

public extension NuimoDFUDiscoveryManagerDelegate {
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {}
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didInvalidateNuimoDFUController controller: NuimoDFUBluetoothController) {}
}

#if os(macOS)
private let CBCentralManagerOptionRestoreIdentifierKey = "CBCentralManagerOptionRestoreIdentifierKey-does-not-exist-on-macOS"
#endif
