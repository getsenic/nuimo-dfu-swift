//
//  NuimoDFUViewModel.swift
//  NuimoDFU
//
//  Created by Lars Blumberg on 6/28/16.
//  Copyright © 2016 senic. All rights reserved.
//

import NuimoSwift

open class NuimoDFUViewModel: NSObject {
    @IBOutlet open weak var delegate: NuimoDFUViewModelDelegate?
    /// Workaround for Xcode bug that prevents you from connecting the delegate in the storyboard.
    /// Remove this extra property once Xcode gets fixed.
    @IBOutlet open var ibDelegate: AnyObject? {
        get { return delegate }
        set { delegate = newValue as? NuimoDFUViewModelDelegate }
    }
    /// If specified, this controller will be automatically put into DFU mode (if possible)
    open var nuimoBluetoothController: NuimoBluetoothController?
    /// If specified, it will take this firmware file, otherwise it will ask NuimoDFUFirmwareCache for the latest firmware that is stored remotely
    open var firmwareFileURL: URL?

    fileprivate var step = DFUStep.intro { didSet { didSetStep() } }
    fileprivate var dfuController:    NuimoDFUBluetoothController?
    fileprivate var discoveryManager: NuimoDFUDiscoveryManager?
    fileprivate var updateManager:    NuimoDFUUpdateManager?

    open func viewDidLoad() {
        NuimoDFUFirmwareCache.sharedCache.requestFirmwareUpdates()
        restart()
    }

    @IBAction open func dismiss(_ sender: AnyObject) {
        discoveryManager?.stopDiscovery()
        updateManager?.cancelUpdate()
        delegate?.nuimoDFUViewModelDidDismiss(self)
    }

    @IBAction open func performNextStep(_ sender: AnyObject) {
        switch step {
        case .intro:
            if let dfuController = dfuController {
                startUpdateForNuimoController(dfuController)
            }
            else if let nuimoBluetoothController = nuimoBluetoothController, nuimoBluetoothController.supportsRebootToDFUMode {
                guard nuimoBluetoothController.rebootToDFUMode() else {
                    didFailWithError(NSError(domain: "NuimoDFU", code: 104, userInfo: [NSLocalizedDescriptionKey: "Cannot reboot Nuimo into firmware update mode", NSLocalizedFailureReasonErrorKey: "Nuimo is not ready"]))
                    return
                }
                //TODO: Make sure that controller is discovered within X msecs, otherwise fail. Also reset the timeout in restart().
                step = .autoRebootToDFUMode
                delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "Preparing update...")
            }
            else {
                step = .manualRebootToDFUMode
            }
        case .success: dismiss(self)
        case .error:   restart() //TODO: When DFU was aborted (e.g. Nuimo turned off) then restarting the DFU process won't discover Nuimo in DFU, even though it can be discovered with other centrals.
        default:       break
        }
    }
}

extension NuimoDFUViewModel {
    fileprivate func restart() {
        dfuController    = nil
        step             = .intro
        discoveryManager = NuimoDFUDiscoveryManager(delegate: self)
        updateManager    = NuimoDFUUpdateManager(centralManager: discoveryManager!.centralManager, delegate: self)
        discoveryManager!.startDiscovery()
    }

    fileprivate func didSetStep() {
        delegate?.nuimoDFUViewModel(self, didSetStep: step)
        delegate?.nuimoDFUViewModel(self, didUpdateContinueButtonTitle: step.continueButtonTitle, continueButtonEnabled: step.continueButtonEnabled, cancelButtonEnabled: step.cancelButtonEnabled)
    }

    fileprivate func startUpdateForNuimoController(_ controller: NuimoDFUBluetoothController) {
        //TODO: Provide proper firmware file. We probably wanna predownload it
        guard let firmwareFileURL = firmwareFileURL ?? NuimoDFUFirmwareCache.sharedCache.latestFirmwareUpdate?.url else {
            didFailWithError(NSError(domain: "NuimoDFU", code: 103, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware upload", NSLocalizedFailureReasonErrorKey: "Cannot access latest firmware"]))
            return
        }
        updateManager?.startUpdateForNuimoController(controller, withLocalOrRemoteFirmwareURL: firmwareFileURL)
        step = .update
    }

    fileprivate func didFailWithError(_ error: Error) {
        step = .error
        delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "\(error.localizedDescription)\n\((error as? LocalizedError)?.failureReason ?? "")")
    }
}

@objc public protocol NuimoDFUViewModelDelegate: class {
    func nuimoDFUViewModel(_ model: NuimoDFUViewModel, didSetStep step: DFUStep)
    func nuimoDFUViewModel(_ model: NuimoDFUViewModel, didUpdateContinueButtonTitle continueButtonTitle: String, continueButtonEnabled: Bool, cancelButtonEnabled: Bool)
    func nuimoDFUViewModel(_ model: NuimoDFUViewModel, didUpdateStatusText text: String)
    func nuimoDFUViewModel(_ model: NuimoDFUViewModel, didUpdateFlashProgress progress: Double)
    func nuimoDFUViewModelDidDismiss(_ model: NuimoDFUViewModel)
}

extension NuimoDFUViewModel: NuimoDFUDiscoveryManagerDelegate {
    public func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didDiscover controller: NuimoDFUBluetoothController) {
        discoveryManager?.stopDiscovery()
        dfuController = controller
        if [.autoRebootToDFUMode, .manualRebootToDFUMode].contains(step) {
            startUpdateForNuimoController(controller)
        }
    }

    public func nuimoDFUDiscoveryManager(_ manager: NuimoDFUDiscoveryManager, didStopAdvertising controller: NuimoDFUBluetoothController) {
        dfuController = nil
        if [.intro, .autoRebootToDFUMode, .manualRebootToDFUMode].contains(step) {
            discoveryManager?.startDiscovery()
        }
    }
}

extension NuimoDFUViewModel: NuimoDFUUpdateManagerDelegate {
    public func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState) {
        switch state {
        case .completed:             step = .success
        case .connecting:            fallthrough
        case .starting:              fallthrough
        case .enablingDfuMode:       fallthrough
        case .uploading:             fallthrough
        case .validating:            fallthrough
        case .disconnecting:         delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "\(state.description)...")
        case .aborted:               didFailWithError(NSError(domain: "NuimoDFU", code: 101, userInfo: [NSLocalizedDescriptionKey: "Firmware update failed", NSLocalizedFailureReasonErrorKey: state.description]))
        }
    }

    public func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {
        delegate?.nuimoDFUViewModel(self, didUpdateFlashProgress: Double(progress))
    }

    public func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: Error) {
        didFailWithError(error)
    }

    public func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailStartingFirmwareUploadWithError error: Error) {
        didFailWithError(NSError(domain: "NuimoDFU", code: 102, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware update", NSLocalizedFailureReasonErrorKey: error.localizedDescription]))
    }

    public func nuimoDFUUpdateManager(_ manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: Error) {
        didFailWithError(error)
    }
}

@objc public enum DFUStep: Int {
    case intro                 = 0
    case autoRebootToDFUMode   = 1
    case manualRebootToDFUMode = 2
    case update                = 3
    case success               = 4
    case error                 = 5

    public var continueButtonTitle: String {
        switch self {
        case .success:  return "Close"
        case .error(_): return "Retry"
        default:       return "Continue"
        }
    }

    public var continueButtonEnabled: Bool {
        switch self {
        case .autoRebootToDFUMode:   fallthrough
        case .manualRebootToDFUMode: fallthrough
        case .update:                return false
        default:                    return true
        }
    }

    public var cancelButtonEnabled: Bool {
        return self != .success
    }
}

extension DFUStep: Equatable {
}

public func ==(lhs: DFUStep, rhs: DFUStep) -> Bool {
    return lhs.rawValue == rhs.rawValue
}
