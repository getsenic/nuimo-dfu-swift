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
    override public var serviceUUIDs:                    [CBUUID]            { return [] }
    override public var charactericUUIDsForServiceUUID:  [CBUUID : [CBUUID]] { return [:] }
    override public var notificationCharacteristicUUIDs: [CBUUID]            { return [] }

    override public func connect() -> Bool {
        return false
    }
}
