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

/// Holds the state for a single custom plugin slot + window delegate
class CustomPluginSlot: NSObject, NSWindowDelegate {
    var customPlugin: AVAudioUnit?
    var customPluginWindow: NSWindowController?
    var cachedViewController: NSViewController?
    
    init(customPlugin: AVAudioUnit) {
        self.customPlugin = customPlugin
    }
    
    func showWindow() {
        guard let customPlugin else { return }
        if (isWindowOpen) {
            customPluginWindow?.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        if cachedViewController != nil {
            CreateWindow()
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

                // Cache view controller in slot
                cachedViewController = viewController
                CreateWindow()
            }
        }
    }
    
    /// Create and show a window for the given view controller and plugin slot
    private func CreateWindow() {
        guard let viewController = cachedViewController else { return }
        // Check if window already exists for this slot
        if let existingWindowController = customPluginWindow {
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
        window.delegate = self
        
        // 4. Wrap it in a Window Controller and show it
        let windowController = NSWindowController(window: window)
        customPluginWindow = windowController
        windowController.showWindow(nil)
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
        // Clear references from the slot to avoid memory leaks
        customPluginWindow = nil
    }
    
    var isWindowOpen: Bool {
        // 1. Is there a window controller?
        // 2. Is its window loaded?
        // 3. Is that window currently visible on screen?
        return customPluginWindow?.window?.isVisible ?? false
    }
}

@Observable
final class AudioEffectsManager {
    // Core engine and nodes
    let model: AudioEngineModel
    let engine: AVAudioEngine

    // Effects
    //let timePitch = AVAudioUnitTimePitch() // doesn't work well with monitoring
    let eq: AVAudioUnitEQ
    let distortion = AVAudioUnitDistortion()
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    
    static let pluginsManager = AudioPluginsManager()
    
    /// Array of custom plugin slots, supporting multiple plugins in the chain
    var customPlugins: [CustomPluginSlot] = []

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
        // Remove all plugins safely
        for index in customPlugins.indices.reversed() {
            removeCustomPlugin(at: index)
        }
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

    /// Connect the audio chain:
    /// EQ → Distortion → [Custom Plugins in sequence] → Delay → Reverb → Main Mixer
    private func connectChain() {
        let mainMixer = engine.mainMixerNode
        let outputFormat = model.outputFormat

        // Disconnect everything first
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(distortion)
        engine.disconnectNodeOutput(delay)
        engine.disconnectNodeOutput(reverb)
        for slot in customPlugins {
            if let plugin = slot.customPlugin {
                engine.disconnectNodeOutput(plugin)
            }
        }
        
        // Connect EQ to Distortion
        engine.connect(eq, to: distortion, format: outputFormat)
        
        // Connect Distortion to first custom plugin or Delay if none
        var previousNode: AVAudioNode = distortion
        
        for slot in customPlugins {
            guard let plugin = slot.customPlugin else { continue }
            // Attach if not attached
            if !engine.attachedNodes.contains(plugin) {
                engine.attach(plugin)
            }
            engine.connect(previousNode, to: plugin, format: outputFormat)
            previousNode = plugin
        }
        
        // Connect last custom plugin (or distortion if none) to Delay
        engine.connect(previousNode, to: delay, format: outputFormat)
        engine.connect(delay, to: reverb, format: outputFormat)
        engine.connect(reverb, to: mainMixer, format: outputFormat)
    }
    
    /// Load a new custom plugin and insert it at the end of the custom plugins chain
    func loadCustomPlugin(id: UUID, outOfProcess: Bool) {
        AudioEffectsManager.pluginsManager.loadPlugin(id: id, outOfProcess: outOfProcess) { unit in
            guard let unit else {
                print("Failed to load plugin")
                return
            }
            
            // Create new slot and append
            let slot = CustomPluginSlot(customPlugin: unit)
            self.customPlugins.append(slot)
            
            // Attach node to engine
            self.engine.attach(unit)
            
            // Reconnect chain to include new plugin
            self.connectChain()
        }
    }
    
    /// Remove the custom plugin at a specified index from the chain
    func removeCustomPlugin(at index: Int) {
        guard customPlugins.indices.contains(index) else { return }
        let slot = customPlugins[index]
        
        if let customPlugin = slot.customPlugin {
            if let window = slot.customPluginWindow {
                window.close()
            }
            engine.disconnectNodeOutput(customPlugin)
            engine.detach(customPlugin)
        }
        
        customPlugins.remove(at: index)
        connectChain()
    }
    
    /// Swap the positions of two custom plugins in the chain, reconnecting afterwards
    func swapPlugins(at indexA: Int, with indexB: Int) {
        guard customPlugins.indices.contains(indexA) && customPlugins.indices.contains(indexB) else { return }
        guard indexA != indexB else { return }
        
        customPlugins.swapAt(indexA, indexB)
        connectChain()
    }
    
    /// Show the audio unit UI in a new window for the plugin at the specified index
    func showAudioUnitInNewWindow(at index: Int) {
        guard customPlugins.indices.contains(index) else { return }
        let slot = customPlugins[index]
        slot.showWindow()
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
