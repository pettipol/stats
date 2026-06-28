//
//  readers.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 06/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class UsageReader: Reader<Battery_Usage> {
    private var service: io_connect_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    
    private var usage: Battery_Usage = Battery_Usage()
    
    deinit {
        self.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if self.service != 0 {
            IOObjectRelease(self.service)
            self.service = 0
        }
    }
    
    public override func start() {
        self.active = true
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        self.source = IOPSNotificationCreateRunLoopSource({ (context) in
            guard let ctx = context else {
                return
            }
            
            let watcher = Unmanaged<UsageReader>.fromOpaque(ctx).takeUnretainedValue()
            if watcher.active {
                watcher.read()
            }
        }, context).takeRetainedValue()
        
        self.loop = RunLoop.current.getCFRunLoop()
        CFRunLoopAddSource(self.loop, source, .defaultMode)
        
        self.read()
    }
    
    public override func stop() {
        guard let source = self.source else {
            return
        }
        
        self.active = false
        CFRunLoopSourceInvalidate(source)
        if let runLoop = self.loop {
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        }
        self.source = nil
        self.loop = nil
    }
    
    public override func setup() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(self.wakeListener),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    @objc private func wakeListener() {
        self.read()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.read()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.read()
        }
    }
    
    public override func read() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.read()
            }
            return
        }
        
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        
        if psList.isEmpty {
            return
        }
        
        for ps in psList {
            if let list = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {
                self.usage.powerSource = list[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
                self.usage.isBatteryPowered = self.usage.powerSource == "Battery Power"
                self.usage.isCharged = list[kIOPSIsChargedKey] as? Bool ?? false
                self.usage.isCharging = self.getBoolValue("IsCharging" as CFString) ?? false
                self.usage.optimizedChargingEngaged = list["Optimized Battery Charging Engaged"] as? Int == 1
                self.usage.level = Double(list[kIOPSCurrentCapacityKey] as? Int ?? 0) / 100
                
                if let time = list[kIOPSTimeToEmptyKey] as? Int {
                    self.usage.timeToEmpty = Int(time)
                }
                if let time = list[kIOPSTimeToFullChargeKey] as? Int {
                    self.usage.timeToCharge = Int(time)
                }
                
                if self.usage.powerSource == "AC Power" {
                    self.usage.timeOnACPower = Date()
                }
                
                self.usage.cycles = self.getIntValue("CycleCount" as CFString) ?? 0
                
                self.usage.currentCapacity = self.getIntValue("AppleRawCurrentCapacity" as CFString) ?? 0
                self.usage.designedCapacity = self.getIntValue("DesignCapacity" as CFString) ?? 1
                if self.usage.designedCapacity == 0 {
                    self.usage.designedCapacity = 1
                }
                self.usage.maxCapacity = self.getIntValue((isARM ? "AppleRawMaxCapacity" : "MaxCapacity") as CFString) ?? 1
                if !isARM {
                    self.usage.state = list[kIOPSBatteryHealthKey] as? String
                }
                self.usage.health = Int((Double(100 * self.usage.maxCapacity) / Double(self.usage.designedCapacity)).rounded(.toNearestOrEven))
                
                self.usage.current = self.getIntValue("Amperage" as CFString) ?? 0
                self.usage.voltage = self.getVoltage() ?? 0
                self.usage.temperature = self.getTemperature() ?? 0
                
                var ACwatts: Int = 0
                if let ACDetails = IOPSCopyExternalPowerAdapterDetails() {
                    if let ACList = ACDetails.takeRetainedValue() as? [String: Any] {
                        if let watts = (ACList[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue {
                            ACwatts = watts
                        }
                    }
                }
                self.usage.ACwatts = ACwatts
                
                self.usage.batteryPower = SMC.shared.getValue("PPBR") ?? (self.usage.voltage * (Double(self.usage.current) / 1000))
                self.usage.adapterPower = SMC.shared.getValue("PDTR") ?? 0
                if let adapterDetails = self.getAdapterDetails() {
                    self.usage.adapterVoltage = Double(adapterDetails["AdapterVoltage"] as? Int ?? 0) / 1000
                }
                
                if let chargerData = self.getChargerData() {
                    self.usage.chargingCurrent = chargerData["ChargingCurrent"] as? Int ?? 0
                    self.usage.chargingVoltage = chargerData["ChargingVoltage"] as? Int ?? 0
                    
                    if !self.usage.optimizedChargingEngaged && !self.usage.isBatteryPowered && !self.usage.isCharging && self.usage.level < 1,
                       let notChargingReason = chargerData["NotChargingReason"] as? Int, notChargingReason != 0 {
                        self.usage.optimizedChargingEngaged = true
                    }
                }
                
                var usage = self.usage
                DispatchQueue.global(qos: .background).async { [weak self] in
                    guard let self = self else { return }
                    let usbDevices = self.readUSBDevices()
                    DispatchQueue.main.async {
                        usage.usbDevices = usbDevices
                        self.usage = usage
                        self.callback(self.usage)
                    }
                }
            }
        }
    }
    
    private func getBoolValue(_ forIdentifier: CFString) -> Bool? {
        if let value = IORegistryEntryCreateCFProperty(self.service, forIdentifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Bool
        }
        return nil
    }
    
    private func getIntValue(_ identifier: CFString) -> Int? {
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Int
        }
        return nil
    }
    
    private func getDoubleValue(_ identifier: CFString) -> Double? {
        if let value = IORegistryEntryCreateCFProperty(self.service, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Double
        }
        return nil
    }
    
    private func getVoltage() -> Double? {
        if let value = self.getDoubleValue("Voltage" as CFString) {
            return value / 1000.0
        }
        return nil
    }
    
    private func getTemperature() -> Double? {
        let sensors = ["TB1T", "TB2T"].compactMap { SMC.shared.getValue($0) }.filter { $0 > 0 }
        if !sensors.isEmpty {
            return sensors.reduce(0, +) / Double(sensors.count)
        }
        if let value = IORegistryEntryCreateCFProperty(self.service, "Temperature" as CFString, kCFAllocatorDefault, 0),
           let temperature = value.takeRetainedValue() as? Double {
            return temperature / 100.0
        }
        return nil
    }
    
    private func getChargerData() -> [String: Any]? {
        if let chargerData = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0) {
            return chargerData.takeRetainedValue() as? [String: Any]
        }
        return nil
    }

    private func getAdapterDetails() -> [String: Any]? {
        if let adapterDetails = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0) {
            return adapterDetails.takeRetainedValue() as? [String: Any]
        }
        return nil
    }
    
    private func readUSBDevices() -> [USBDevice_t] {
        var devices: [USBDevice_t] = []
        let matchingDict = IOServiceMatching("IOUSBHostDevice")
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return []
        }
        
        var service = IOIteratorNext(iterator)
        var seenKeys = Set<String>()
        
        while service != 0 {
            var serviceProperties: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(service, &serviceProperties, kCFAllocatorDefault, 0)
            if kr == KERN_SUCCESS, let props = serviceProperties?.takeRetainedValue() as NSDictionary? {
                let name = props["kUSBProductString"] as? String ?? props["USB Product Name"] as? String ?? "USB Device"
                let vendor = props["kUSBVendorString"] as? String ?? props["USB Vendor Name"] as? String ?? "Unknown"
                let serial = props["kUSBSerialNumberString"] as? String ?? props["USB Serial Number"] as? String ?? ""
                
                var speed: UInt64 = 0
                if let linkSpeed = (props["UsbLinkSpeed"] as? NSNumber)?.uint64Value {
                    speed = linkSpeed
                } else if let usbSpeed = (props["USBSpeed"] as? NSNumber)?.intValue {
                    switch usbSpeed {
                    case 0: speed = 1_500_000      // Low Speed (1.5 Mbps)
                    case 1: speed = 12_000_000     // Full Speed (12 Mbps)
                    case 2: speed = 480_000_000    // High Speed (480 Mbps)
                    case 3: speed = 5_000_000_000  // SuperSpeed (5 Gbps)
                    case 4: speed = 10_000_000_000 // SuperSpeed+ (10 Gbps)
                    default: speed = 0
                    }
                }
                
                let alloc = (props["UsbPowerSinkAllocation"] as? NSNumber)?.intValue
                            ?? (props["kUSBConfigurationCurrentOverride"] as? NSNumber)?.intValue ?? 0
                
                let uniqueKey = "\(name)-\(vendor)-\(serial)"
                if !seenKeys.contains(uniqueKey) {
                    seenKeys.insert(uniqueKey)
                    devices.append(USBDevice_t(name: name, vendor: vendor, speed: speed, alloc: alloc))
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return devices
    }
}

public class ProcessReader: Reader<[TopProcess]> {
    private var numberOfProcesses: Int {
        get {
            return Store.shared.int(key: "Battery_processes", defaultValue: 8)
        }
    }
    
    public override func setup() {
        self.popup = true
    }
    
    public override func read() {
        if self.numberOfProcesses == 0 {
            return
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/top"
        task.arguments = ["-o", "power", "-l", "2", "-n", "\(self.numberOfProcesses)", "-stats", "pid,command,power"]
        
        let outputPipe = Pipe()
        defer {
            outputPipe.fileHandleForReading.closeFile()
        }
        task.standardOutput = outputPipe
        
        do {
            try task.run()
        } catch let err {
            error("error read ps: \(err.localizedDescription)", log: self.log)
            return
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if outputData.isEmpty {
            return
        }
        
        let output = String(data: outputData.advanced(by: outputData.count/2), encoding: .utf8)
        guard let output, !output.isEmpty else { return }
        
        var processes: [TopProcess] = []
        output.enumerateLines { (line, _) in
            if line.matches("^\\d+ *[^(\\d)]*\\d+\\.*\\d* *$") {
                let str = line.trimmingCharacters(in: .whitespaces)
                let pidFind = str.findAndCrop(pattern: "^\\d+")
                let usageFind = pidFind.remain.findAndCrop(pattern: " +[0-9]+.*[0-9]*$")
                let command = usageFind.remain.trimmingCharacters(in: .whitespaces)
                let pid = Int(pidFind.cropped) ?? 0
                guard let usage = Double(usageFind.cropped.filter("01234567890.".contains)) else {
                    return
                }
                
                var name: String = command
                if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let n = app.localizedName {
                    name = n
                }
                
                processes.append(TopProcess(pid: pid, name: name, usage: usage))
            }
        }
        
        self.callback(processes.suffix(self.numberOfProcesses).sorted(by: { $0.usage > $1.usage }))
    }
}
