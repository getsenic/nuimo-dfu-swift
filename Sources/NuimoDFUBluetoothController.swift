//
//  NuimoDFUBluetoothController.swift
//  Pods
//
//  Created by Lars Blumberg on 7/8/16.
//
//

import CoreBluetooth
import NuimoSwift

public class NuimoDFUBluetoothController: NuimoBluetoothController {
    open override class var maxAdvertisingPackageInterval: TimeInterval? { return 1.0 }

    override public func connect(autoReconnect: Bool = false) {
        // NOP
    }
}
