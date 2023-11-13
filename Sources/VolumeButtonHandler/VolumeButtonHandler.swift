// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import MediaPlayer
import AVFoundation
import AVFAudio

public typealias VolumeButtonBlock = () -> Void

public class VolumeButtonHandler: NSObject {
    static let sessionVolumeKeyPath = "outputVolume"
    
    static let maxVolume: CGFloat = 0.95
    static let minVolume: CGFloat = 0.05
    
    private let tag = "VolumeButtonHandler"
    
    private var initialVolume: CGFloat = 0.0
    private var session: AVAudioSession?
    private var volumeView: MPVolumeView?
    
    private var appIsActive = false
    private var isStarted = false
    private var disableSystemVolumeHandler = false
    private var isAdjustingVolume = false
    private var exactJumpsOnly: Bool = false
    
    private var sessionOptions: AVAudioSession.CategoryOptions?
    private var sessionCategory: String = ""
    
    public var upBlock: VolumeButtonBlock?
    public var downBlock: VolumeButtonBlock?
    public var currentVolume: Float = 0.0
    
    override public init() {
        appIsActive = true
        sessionCategory = AVAudioSession.Category.playback.rawValue
        sessionOptions = AVAudioSession.CategoryOptions.mixWithOthers
        
        volumeView = MPVolumeView(
            frame: CGRect(
                x: CGFloat.infinity,
                y: CGFloat.infinity,
                width: 0,
                height: 0
            )
        )
        
        if let window = UIApplication.shared.windows.first, let view = volumeView {
            debugPrint("\(tag) add MPVolumeView")
            window.insertSubview(view, at: 0)
        }
        
        volumeView?.isHidden = true
        exactJumpsOnly = false
    }
    
    deinit {
        stopHandler()
        
        let volumeView = volumeView
        DispatchQueue.main.async {
            volumeView?.removeFromSuperview()
        }
    }
    
    public func startHandler(disableSystemVolumeHandler: Bool) {
        self.setupSession()
        volumeView?.isHidden = false
        self.disableSystemVolumeHandler = disableSystemVolumeHandler
        debugPrint("\(tag) startHandler")
    }
    
    public func stopHandler() {
        guard isStarted else { return }
        isStarted = false
        volumeView?.isHidden = true
        self.observation = nil
        NotificationCenter.default.removeObserver(self)
        
        debugPrint("\(tag) stopHandler")
    }
    
    private var observation: NSKeyValueObservation? = nil
    
    @objc func setupSession() {
        guard !isStarted else { return }
        isStarted = true
        
        self.session = AVAudioSession.sharedInstance()
        
        setInitialVolume()
        
        do {
            try session?.setCategory(AVAudioSession.Category(rawValue: sessionCategory), options: sessionOptions!)
            try session?.setActive(true)
        } catch {
            print("Error setupSession: \(error)")
        }
        
        debugPrint("\(tag) setupSession")
        
        observation = session?.observe(\.outputVolume, options: [.new, .old, .initial]) { [weak self] session, change in
            guard let newVolume = change.newValue,
                  let oldVolume = change.oldValue,
                  let self = self else {
                return
            }
            
            if !appIsActive {
                // Probably control center, skip blocks
                debugPrint("app not active, skip")
                return
            }
            
            let difference = abs(newVolume - oldVolume)
            
            debugPrint("\(tag) Old Vol:\(oldVolume) New Vol:\(newVolume) Difference = \(difference)")
            
            if isAdjustingVolume {
                debugPrint("\(tag) isAdjustingVolume, skip")
                isAdjustingVolume = false
                return
            }
            
            if exactJumpsOnly && difference < 0.062 && (newVolume == 1.0 || newVolume == 0.0) {
                debugPrint("\(tag) Using a non-standard Jump of %f (%f-%f) which is less than the .0625 because a press of the volume button resulted in hitting min or max volume", difference, oldVolume, newVolume)
            } else if exactJumpsOnly && (difference > 0.063 || difference < 0.062) {
                debugPrint("\(tag) Ignoring non-standard Jump of %f (%f-%f), which is not the .0625 a press of the actually volume button would have resulted in.", difference, oldVolume, newVolume)
                setInitialVolume()
                return
            }
            
            if newVolume > oldVolume {
                upBlock?()
            } else {
                downBlock?()
            }
            currentVolume = newVolume
            
            if !disableSystemVolumeHandler {
                // Don't reset volume if default handling is enabled
                return
            }
            
            // Reset volume
            setSystemVolume(initialVolume)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(
                audioSessionInterruped(notification:)
            ),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(
                applicationDidChangeActive(notification:)
            ),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(
                applicationDidChangeActive(notification:)
            ),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        volumeView?.isHidden = !disableSystemVolumeHandler
    }
    
    func useExactJumpsOnly(enabled: Bool) {
        exactJumpsOnly = enabled
    }
    
    @objc func audioSessionInterruped(notification: NSNotification) {
        guard let interruptionDict = notification.userInfo,
              let interruptionType = interruptionDict[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return
        }
        switch AVAudioSession.InterruptionType(rawValue: interruptionType) {
        case .began:
            debugPrint("Audio Session Interruption case started")
        case .ended:
            print("Audio Session interruption case ended")
            do {
                try self.session?.setActive(true)
            } catch {
                print("Error: \(error)")
            }
        default:
            print("Audio Session Interruption Notification case default")
        }
    }
    
    public func setInitialVolume() {
        guard let session = session else { return }
        initialVolume = CGFloat(session.outputVolume)
        
        debugPrint("\(tag) session output volume is \(initialVolume)")
        
        if initialVolume > VolumeButtonHandler.maxVolume {
            initialVolume = VolumeButtonHandler.maxVolume
            debugPrint("\(tag) setInitialVolume to \(initialVolume)")
            setSystemVolume(initialVolume)
        } else if initialVolume < VolumeButtonHandler.minVolume {
            initialVolume = VolumeButtonHandler.minVolume
            debugPrint("\(tag) setInitialVolume to \(initialVolume)")
            setSystemVolume(initialVolume)
        }
        currentVolume = Float(initialVolume)
    }
    
    @objc func applicationDidChangeActive(notification: NSNotification) {
        self.appIsActive = notification.name.rawValue == UIApplication.didBecomeActiveNotification.rawValue
        
        if appIsActive, isStarted {
            setInitialVolume()
        }
    }
    
    public static func volumeButtonHandler(upBlock: VolumeButtonBlock?, downBlock: VolumeButtonBlock?) -> VolumeButtonHandler {
        let instance = VolumeButtonHandler()
        instance.upBlock = upBlock
        instance.downBlock = downBlock
        return instance
    }
    
    func setSystemVolume(_ volume: CGFloat) {
        debugPrint("\(self.tag) about to setSystemVolume to \(volume)")
        
        if let volumeView = self.volumeView,
           let volumeSlider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                debugPrint("\(self.tag) setSystemVolume to \(volume)")
                self.isAdjustingVolume = true
                volumeSlider.value = Float(volume)
            }
        }
    }
}
