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
        discovery.startDiscovery(serviceUUIDs: [CBUUID(string: "00001530-1212-EFDE-1523-785FEABCD123")], updateReachability: true)
    }

    public func stopDiscovery() {
        discovery.stopDiscovery()
    }
}

extension NuimoDFUDiscoveryManager: NuimoDiscoveryDelegate {
    public func nuimoDiscoveryManager(_ discovery: NuimoDiscoveryManager, deviceForPeripheral peripheral: CBPeripheral, advertisementData: [String : Any]) -> BLEDevice? {
        guard peripheral.name == "NuimoDFU" else { return nil }
        return NuimoDFUBluetoothController(discoveryManager: discovery.bleDiscoveryManager, peripheral: peripheral)
    }

    public func nuimoDiscoveryManager(_ discovery: NuimoDiscoveryManager, didDiscoverNuimoController controller: NuimoController) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        discoveredControllers.insert(controller)
        delegate?.nuimoDFUDiscoveryManager(self, didDiscover: controller)
    }

    public func nuimoDiscoveryManager(_ discovery: NuimoDiscoveryManager, didStopAdvertising controller: NuimoController) {
        guard let controller = controller as? NuimoDFUBluetoothController else { return }
        discoveredControllers.remove(controller)
        delegate?.nuimoDFUDiscoveryManager(self, didStopAdvertising: controller)
    }
}

public protocol NuimoDFUDiscoveryManagerDelegate: class {
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didDiscover controller: NuimoDFUBluetoothController)
    func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didStopAdvertising controller: NuimoDFUBluetoothController)
}

#if os(macOS)
private let CBCentralManagerOptionRestoreIdentifierKey = "CBCentralManagerOptionRestoreIdentifierKey-does-not-exist-on-macOS"
#endif
