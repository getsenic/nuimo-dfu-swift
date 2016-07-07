//
//  NuimoDFUViewModel.swift
//  NuimoDFU
//
//  Created by Lars Blumberg on 6/28/16.
//  Copyright © 2016 senic. All rights reserved.
//

import Foundation

public class NuimoDFUViewModel: NSObject {
    @IBOutlet public weak var delegate: NuimoDFUViewModelDelegate?
    /// Workaround for Xcode bug that prevents you from connecting the delegate in the storyboard.
    /// Remove this extra property once Xcode gets fixed.
    @IBOutlet public var ibDelegate: AnyObject? {
        get { return delegate }
        set { delegate = newValue as? NuimoDFUViewModelDelegate }
    }

    private var step = DFUStep.Intro { didSet { didSetStep() } }
    private lazy var nuimoDFUManager: NuimoDFUManager = {
        let manager = NuimoDFUManager()
        manager.delegate = self
        return manager
    }()

    public func viewDidLoad() {
        NuimoDFUCache.sharedCache.requestFirmwareUpdates()
        step = .Intro
        didSetStep()
    }

    @IBAction public func dismiss(sender: AnyObject) {
        nuimoDFUManager.stopDiscovery()
        nuimoDFUManager.cancelUpdate()
        delegate?.nuimoDFUViewModelDidDismiss(self)
    }

    @IBAction public func performNextStep(sender: AnyObject) {
        switch step {
        case .Intro:   step = .Discovery
        case .Success: dismiss(self)
        case .Error:   step = .Intro //TODO: When DFU was aborted (e.g. Nuimo turned off) then restarting the DFU process won't discover Nuimo in DFU, even though it can be discovered with other centrals.
        default:       break
        }
    }

    private func didSetStep() {
        if step == .Discovery {
            nuimoDFUManager.startDiscovery()
        }

        delegate?.nuimoDFUViewModel(self, didSetStep: step)
        delegate?.nuimoDFUViewModel(self, didUpdateContinueButtonTitle: step.continueButtonTitle, continueButtonEnabled: step.continueButtonEnabled, cancelButtonEnabled: step.cancelButtonEnabled)
    }

    private func startUpdateForNuimoController(controller: NuimoDFUBluetoothController) {
        //TODO: Provide proper firmware file. We probably wanna predownload it
        guard let updateURL = NuimoDFUCache.sharedCache.latestFirmwareUpdate?.URL else {
            didFailWithError(NSError(domain: "Nuimo", code: 103, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware upload", NSLocalizedFailureReasonErrorKey: "Cannot access latest firmware"]))
            return
        }
        nuimoDFUManager.startUpdateForNuimoController(controller, withUpdateURL: updateURL)
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

extension NuimoDFUViewModel: NuimoDFUManagerDelegate {
    public func nuimoDFUManager(manager: NuimoDFUManager, didDisoverNuimoDFUController controller: NuimoDFUBluetoothController) {
        manager.stopDiscovery()
        startUpdateForNuimoController(controller)
    }

    public func nuimoDFUManager(manager: NuimoDFUManager, didChangeState state: NuimoDFUState) {
        switch state {
        case .Completed: step = .Success
        case .Aborted:   didFailWithError(NSError(domain: "Nuimo", code: 101, userInfo: [NSLocalizedDescriptionKey: "Firmware upload aborted", NSLocalizedFailureReasonErrorKey: "Aborted by user"]))
        default:         delegate?.nuimoDFUViewModel(self, didUpdateStatusText: "\(state.description)...")
        }
    }

    public func nuimoDFUManager(manager: NuimoDFUManager, didUpdateProgress progress: Float, forPartIndex partIndex: Int, ofPartsCount partsCount: Int) {
        delegate?.nuimoDFUViewModel(self, didUpdateFlashProgress: Double(progress))
    }

    public func nuimoDFUManager(manager: NuimoDFUManager, didFailDownloadingFirmwareWithError error: NSError) {
        didFailWithError(error)
    }

    public func nuimoDFUManagerDidFailStartingFirmwareUpload(manager: NuimoDFUManager) {
        didFailWithError(NSError(domain: "Nuimo", code: 102, userInfo: [NSLocalizedDescriptionKey: "Cannot start firmware upload", NSLocalizedFailureReasonErrorKey: "Unknown"]))
    }

    public func nuimoDFUManager(manager: NuimoDFUManager, didFailFlashingFirmwareWithError error: NSError) {
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
