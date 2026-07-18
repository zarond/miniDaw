//
//  audioEffects.swift
//  miniDaw
//
//  Created by Artur Makoev on 11.07.2026.
//

import AVFoundation
import AudioToolbox
import AppKit
import CoreAudioKit

@Observable
final class AudioEffectsManager {
    // Core engine and nodes
    let model : AudioEngineModel
    let engine : AVAudioEngine

    // Effects
    //let timePitch = AVAudioUnitTimePitch() // doesn't work well with monitoring
    let eq: AVAudioUnitEQ
    let distortion = AVAudioUnitDistortion()
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    
    static let pluginsManager = AudioPluginsManager()
    var customPlugin: AVAudioUnit? = nil
    var customPluginWindow: NSWindowController?
    var cachedViewController: NSViewController?
    var windowDelegate: WindowDelegate?

    init(model: AudioEngineModel, engine: AVAudioEngine, eqBands: Int = 4) {
        self.eq = AVAudioUnitEQ(numberOfBands: max(1, eqBands))
        self.model = model
        self.engine = engine
        
        // Attach nodes
        //engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(distortion)
        engine.attach(delay)
        engine.attach(reverb)

        configureDefaults()
        connectChain()
    }
    
    deinit {
        removeCustomPlugin()
    }

    private func configureDefaults() {
        // TimePitch: 0 cents, default overlap for quality
        //timePitch.pitch = 0
        //timePitch.overlap = 8.0

        eq.globalGain = 0

        // EQ band defaults for 4 bands: high pass, parametric, parametric, low pass
        if eq.bands.count >= 4 {
            // High-pass band
            let band0 = eq.bands[0]
            band0.filterType = .highPass
            band0.frequency = 80
            band0.bandwidth = 1.0
            band0.gain = 0.0
            band0.bypass = false

            // Low-mid parametric
            let band1 = eq.bands[1]
            band1.filterType = .parametric
            band1.frequency = 500
            band1.bandwidth = 1.0
            band1.gain = 0.0
            band1.bypass = false

            // High-mid parametric
            let band2 = eq.bands[2]
            band2.filterType = .parametric
            band2.frequency = 4000
            band2.bandwidth = 1.0
            band2.gain = 0.0
            band2.bypass = false

            // Low-pass band
            let band3 = eq.bands[3]
            band3.filterType = .lowPass
            band3.frequency = 12000
            band3.bandwidth = 1.0
            band3.gain = 0.0
            band3.bypass = false
        }

        // Distortion
        distortion.loadFactoryPreset(.multiDistortedCubed)
        distortion.wetDryMix = 25

        // Delay
        delay.delayTime = 0.25
        delay.feedback = 25
        delay.lowPassCutoff = 15000
        delay.wetDryMix = 20

        // Reverb
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 30
        
        // Bypass all
        eq.bypass = true
        distortion.bypass = true
        delay.bypass = true
        reverb.bypass = true
    }

    private func connectChain() {
        let mainMixer = engine.mainMixerNode
        let outputFormat = model.outputFormat

        // EQ → Distortion → Delay → Reverb
        //engine.connect(timePitch, to: eq, format: outputFormat)
        engine.connect(eq, to: distortion, format: outputFormat)
        engine.connect(distortion, to: delay, format: outputFormat)
        engine.connect(delay, to: reverb, format: outputFormat)
        engine.connect(reverb, to: mainMixer, format: outputFormat)
    }
    
    func loadCustomPlugin(id: UUID, outOfProcess: Bool) {
        AudioEffectsManager.pluginsManager.loadPlugin(id: id, outOfProcess: outOfProcess) { unit in
            guard let unit else { print("Failed to load plugin"); return }
            self.customPlugin = unit
            self.connectCustomPlugin()
        }
    }
    
    func removeCustomPlugin() {
        guard let customPlugin else { return }
        if let customPluginWindow {
            customPluginWindow.close()
        }
        engine.disconnectNodeOutput(customPlugin)
        engine.disconnectNodeOutput(distortion)
        engine.detach(customPlugin)
        engine.connect(distortion, to: delay, format: model.outputFormat)
        self.customPlugin = nil
        self.customPluginWindow = nil
        self.cachedViewController = nil
    }
    
    func connectCustomPlugin() {
        guard let customPlugin else { return }
        let outputFormat = model.outputFormat
        engine.attach(customPlugin)
        engine.disconnectNodeOutput(distortion)
        engine.connect(distortion, to: customPlugin, format: outputFormat)
        engine.connect(customPlugin, to: delay, format: outputFormat)
    }
    
    func showAudioUnitInNewWindow() {
        guard let customPlugin else { return }
        if (windowDelegate?.isWindowOpen ?? false) {
            customPluginWindow?.window?.makeKeyAndOrderFront(nil)
            return
        }
        if let cachedViewController {
            CreateWindow(viewController: cachedViewController)
        } else {
            loadAudioUnitViewController(unit: customPlugin) { [weak self] viewController in
                guard let self else { return }
                var viewController = viewController
                if viewController == nil { // Fallback: obtain a generic view if the plugin does not provide a custom view
                    // We generate a generic view mapping its parameters to generic sliders.
                    let genericViewController = NSViewController()
                    
                    // AUGenericView is a native Apple class that automatically parses
                    // the plugin's parameters and creates sliders for them.
                    let genericView = AUGenericView(audioUnit: customPlugin.audioUnit)
                    genericView.showsExpertParameters = true
                    
                    genericViewController.view = genericView
                    viewController = genericViewController
                }
                guard let viewController else {
                    print("Could not load Audio Unit View Controller")  // Generic View also failed
                    return
                }
                // Advice for UI performance
                // Force the View Controller's root view to be layer-backed
                let pluginView = viewController.view
                pluginView.wantsLayer = true
                // Tell the layer to update only when explicitly needed, preventing layout thrashing
                pluginView.layerContentsRedrawPolicy = .onSetNeedsDisplay
                // Optional: Force a performance-focused layout mode
                pluginView.canDrawConcurrently = true
                // Advice for UI performance

                self.cachedViewController = viewController
                self.CreateWindow(viewController: viewController)
            }
        }
    }
    
    private func CreateWindow(viewController: NSViewController) {
        if let existingWindowController = self.customPluginWindow {
            existingWindowController.showWindow(nil)
            existingWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // 1. Create a standard macOS Window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), // Default size, AU will usually auto-resize it
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = customPlugin?.name ?? "Audio Unit Interface"
        window.center() // Center it on the screen
        
        // 2. Assign the AU view controller as the window's content view controller
        window.contentViewController = viewController
        
        window.level = .floating
        window.hidesOnDeactivate = true
        
        // 3. Set the window's delegate to SELF so we can hear when it closes
        let delegate = WindowDelegate(manager: self)
        window.delegate = delegate
        windowDelegate = delegate // Save it to memory
        
        // 4. Wrap it in a Window Controller and show it
        customPluginWindow = NSWindowController(window: window)
        customPluginWindow?.showWindow(nil)
    }
    
    //func firstEffect() -> AVAudio​Node? {
    //    return nil
    //}
}

class WindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: AudioEffectsManager?
    
    init(manager: AudioEffectsManager) {
        self.manager = manager
        super.init()
    }
    
    // Intercept the close command
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window visually from the screen instead of destroying it
        sender.orderOut(nil)
        // Return false so macOS doesn't actually close/deallocate the window
        return false
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            // Sever the view hierarchy connection completely
            window.contentViewController = nil
            window.contentView = nil
        }
        manager?.customPluginWindow = nil
        manager?.windowDelegate = nil
    }
    
    var isWindowOpen: Bool {
        // 1. Is there a window controller?
        // 2. Is its window loaded?
        // 3. Is that window currently visible on screen?
        return manager?.customPluginWindow?.window?.isVisible ?? false
    }
}

@Observable
final class AudioPluginsManager {
    let Manager = AVAudioUnitComponentManager.shared()
        
    struct PluginDescription: Identifiable {
        let id: UUID
        let name: String
        let manufacturer: String
        let description: AudioComponentDescription
    }
    
    var AllPluginsInfoList: [PluginDescription] = []
    
    init() {
        // search for available effects on the system
        let effectDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        let effectComponents = Manager.components(matching: effectDescription)
        
        for component in effectComponents {
            print("Found plugin: \(component.name), manufacturer: \(component.manufacturerName)")
            AllPluginsInfoList.append(
                PluginDescription(
                    id: UUID(),
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    description: component.audioComponentDescription
                )
            )
        }
    }
    
    func loadPlugin(id: UUID, outOfProcess: Bool, completion: @escaping (AVAudioUnit?) -> Void) {
        let pluginInfo = AllPluginsInfoList.first(where: { $0.id == id })
        guard let pluginInfo else { return }
        let componentDescription = pluginInfo.description
        let options : AudioComponentInstantiationOptions = outOfProcess ? [.loadOutOfProcess] : [.loadInProcess]
        
        AVAudioUnit.instantiate(with: componentDescription, options: options) { audioUnit, error in
            if let audioUnit {
                completion(audioUnit)
            } else if let error = error {
                print("Failed to instantiate plugin: \(error)")
                completion(nil)
            }
        }
    }
}

private func loadAudioUnitViewController(unit: AVAudioUnit?, completion: @escaping (NSViewController?) -> Void) {
    if let unit {
        // Call our AVAudioUnit extension to request the ViewController
        unit.auAudioUnit.requestViewController(completionHandler: completion)
    } else {
        completion(nil)
    }
}

