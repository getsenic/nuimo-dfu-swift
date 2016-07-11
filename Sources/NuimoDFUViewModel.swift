//
//  NuimoDFUViewModel.swift
//  NuimoDFU
//
//  Created by Lars Blumberg on 6/28/16.
//  Copyright © 2016 senic. All rights reserved.
//

import NuimoSwift

public class NuimoDFUViewModel: NSObject {
    @IBOutlet public weak var delegate: NuimoDFUViewModelDelegate?
    /// Workaround for Xcode bug that prevents you from connecting the delegate in the storyboard.
    /// Remove this extra property once Xcode gets fixed.
    @IBOutlet public var ibDelegate: AnyObject? {
        get { return delegate }
        set { delegate = newValue as? NuimoDFUViewModelDelegate }
    }

    private var step = DFUStep.Intro { didSet { didSetStep() } }
    private var dfuController:    NuimoDFUBluetoothController?
    private var discoveryManager: NuimoDFUDiscoveryManager?
    private var updateManager:    NuimoDFUUpdateManager?

    public func viewDidLoad() {
        NuimoDFUFirmwareCache.sharedCache.requestFirmwareUpdates()
        restart()
    }

    @IBAction public func dismiss(sender: AnyObject) {
        discoveryManager?.stopDiscovery()
        updateManager?.cancelUpdate()
        delegate?.nuimoDFUViewModelDidDismiss(self)
    }

    @IBAction public func performNextStep(sender: AnyObject) {
        switch step {
        case .Intro:
            if let dfuController = dfuController {
                startUpdateForNuimoController(dfuController)
            }
            else {
                step = .Discovery
            }
        case .Success: dismiss(self)
        case .Error:   restart() //TODO: When DFU was aborted (e.g. Nuimo turned off) then restarting the DFU process won't discover Nuimo in DFU, even though it can be discovered with other centrals.
        default:       break
        }
    }
}

extension NuimoDFUViewModel {
    private func restart() {
        dfuController    = nil
        step             = .Intro
        discoveryManager = NuimoDFUDiscoveryManager(delegate: self)
        updateManager    = NuimoDFUUpdateManager(centralManager: discoveryManager!.centralManager, delegate: self)
        discoveryManager!.startDiscovery()
    }

    private func didSetStep() {
        delegate?.nuimoDFUViewModel(self, didSetStep: step)
        delegate?.nuimoDFUViewModel(self, didUpdateContinueButtonTitle: step.continueButtonTitle, continueButtonEnabled: step.continueButtonEnabled, cancelButtonEnabled: step.cancelButtonEnabled)
    }

    private func startUpdateForNuimoController(controller: NuimoDFUBluetoothController) {
        //TODO: Provide proper firmware file. We probably wanna predownload it
        guard let updateURL = NuimoDFUFirmwareCache.sharedCache.latestFirmwareUpdate?.URL else {
            didFailWithError(NSError(domain: "NuimoDFU", code: 103, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware upload", NSLocalizedFailureReasonErrorKey: "Cannot access latest firmware"]))
            return
        }
        updateManager?.startUpdateForNuimoController(controller, withUpdateURL: updateURL)
        step = .Update
    }

    private func didFailWithError(error: NSError) {
        step = .Error
        delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "\(error.localizedDescription)\n\(error.localizedFailureReason ?? "")")
    }
}

@objc public protocol NuimoDFUViewModelDelegate: class {
    func nuimoDFUViewModel(model: NuimoDFUViewModel, didSetStep step: DFUStep)
    func nuimoDFUViewModel(model: NuimoDFUViewModel, didUpdateContinueButtonTitle continueButtonTitle: String, continueButtonEnabled: Bool, cancelButtonEnabled: Bool)
    func nuimoDFUViewModel(model: NuimoDFUViewModel, didUpdateStatusText text: String)
    func nuimoDFUViewModel(model: NuimoDFUViewModel, didUpdateFlashProgress progress: Double)
    func nuimoDFUViewModelDidDismiss(model: NuimoDFUViewModel)
}

extension NuimoDFUViewModel: NuimoDFUDiscoveryManagerDelegate {
    public func nuimoDFUDiscoveryManager(manager: NuimoDFUDiscoveryManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {
        discoveryManager?.stopDiscovery()
        controller.delegate = self
        dfuController = controller
        if step == .Discovery {
            startUpdateForNuimoController(controller)
        }
    }
}

extension NuimoDFUViewModel: NuimoControllerDelegate {
    public func nuimoController(controller: NuimoController, didChangeConnectionState state: NuimoConnectionState, withError error: NSError?) {
        if dfuController?.connectionState == .Invalidated {
            dfuController = nil
            if [.Intro, .Discovery].contains(step) {
                discoveryManager?.startDiscovery()
            }
        }
    }
}

extension NuimoDFUViewModel: NuimoDFUUpdateManagerDelegate {
    public func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didChangeState state: NuimoDFUUpdateState) {
        switch state {
        case .Completed: step = .Success
        case .Aborted:   didFailWithError(NSError(domain: "NuimoDFU", code: 101, userInfo: [NSLocalizedDescriptionKey: "Firmware upload aborted", NSLocalizedFailureReasonErrorKey: "Aborted by user"]))
        default:         delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "\(state.description)...")
        }
    }

    public func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {
        delegate?.nuimoDFUViewModel(self, didUpdateFlashProgress: Double(progress))
    }

    public func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailDownloadingFirmwareWithError error: NSError) {
        didFailWithError(error)
    }

    public func nuimoDFUUpdateManagerDidFailStartingFirmwareUpload(manager: NuimoDFUUpdateManager) {
        didFailWithError(NSError(domain: "NuimoDFU", code: 102, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware upload", NSLocalizedFailureReasonErrorKey: "Unknown"]))
    }

    public func nuimoDFUUpdateManager(manager: NuimoDFUUpdateManager, didFailFlashingFirmwareWithError error: NSError) {
        didFailWithError(error)
    }
}

@objc public enum DFUStep: Int {
    case Intro = 0
    case Discovery = 1
    case Update = 2
    case Success = 3
    case Error = 4

    public var segueIdentifier: String {
        switch self {
        case Intro:     return "intro"
        case Discovery: return "discovery"
        case Update:    return "update"
        case Success:   return "success"
        case Error:     return "error"
        }
    }

    public var continueButtonTitle: String {
        switch self {
        case Success:  return "Close"
        case Error(_): return "Retry"
        default:       return "Continue"
        }
    }

    public var continueButtonEnabled: Bool {
        switch self {
        case Discovery: fallthrough
        case Update:    return false
        default:        return true
        }
    }

    public var cancelButtonEnabled: Bool {
        return self != .Success
    }
}

extension DFUStep: Equatable {
}

public func ==(lhs: DFUStep, rhs: DFUStep) -> Bool {
    switch (lhs, rhs) {
    case (.Intro, .Intro):         return true
    case (.Discovery, .Discovery): return true
    case (.Update, .Update):       return true
    case (.Success, .Success):     return true
    case (.Error(_), .Error(_)):   return true
    default:                       return false
    }
}
