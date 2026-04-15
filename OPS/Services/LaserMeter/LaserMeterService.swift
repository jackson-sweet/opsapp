// OPS/OPS/Services/LaserMeter/LaserMeterService.swift

import Foundation
import CoreBluetooth
import Combine

class LaserMeterService: NSObject, ObservableObject {

    static let shared = LaserMeterService()

    // MARK: - Published State

    @Published var connectionState: LaserConnectionState = .disconnected
    @Published var connectedDevice: DiscoveredLaserDevice?
    @Published var discoveredDevices: [DiscoveredLaserDevice] = []
    @Published var latestMeasurement: LaserMeasurement?
    @Published var measurementError: String?
    @Published var bluetoothState: CBManagerState = .unknown

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var connectedBrand: LaserMeterBrand = .generic
    private var scanTimer: Timer?

    // UserDefaults keys
    private static let savedDeviceKey = "laserMeter.savedDevice"

    // MARK: - Init

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        guard connectionState != .connected else { return }

        discoveredDevices.removeAll()
        connectionState = .scanning

        // Scan for known service UUIDs + nil (catches generic devices by name)
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // 10-second scan timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self, self.connectionState == .scanning else { return }
            self.stopScanning()
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    func connect(_ device: DiscoveredLaserDevice) {
        stopScanning()
        connectionState = .connecting
        connectedBrand = device.brand

        // Save for auto-reconnect
        let saved = SavedLaserDevice(
            peripheralId: device.peripheral.identifier.uuidString,
            name: device.name,
            brand: device.brand
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedDeviceKey)
        }

        device.peripheral.delegate = self
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
    }

    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: Self.savedDeviceKey)
        latestMeasurement = nil
    }

    // MARK: - Auto-Reconnect

    private func attemptAutoReconnect() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedDeviceKey),
              let saved = try? JSONDecoder().decode(SavedLaserDevice.self, from: data),
              let uuid = UUID(uuidString: saved.peripheralId) else { return }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = peripherals.first {
            connectionState = .reconnecting
            connectedBrand = saved.brand
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }

    // MARK: - Brand Detection

    private func detectBrand(for peripheral: CBPeripheral) -> LaserMeterBrand {
        let name = peripheral.name
        if BoschProtocol.isBoschDevice(name: name) {
            return .bosch
        } else if LeicaProtocol.isLeicaDevice(name: name) {
            return .leica
        }
        return .generic
    }
}

// MARK: - CBCentralManagerDelegate

extension LaserMeterService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        switch central.state {
        case .poweredOn:
            attemptAutoReconnect()
        case .poweredOff, .unauthorized, .unsupported:
            connectionState = .disconnected
            connectedPeripheral = nil
            connectedDevice = nil
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        // Only show devices that look like laser meters
        let brand = detectBrand(for: peripheral)
        let isKnownLaser = BoschProtocol.isBoschDevice(name: name) || LeicaProtocol.isLeicaDevice(name: name)

        // Also check advertised service UUIDs
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasKnownService = advertisedServices.contains(BoschProtocol.serviceUUID)
            || advertisedServices.contains(LeicaProtocol.serviceUUID)

        guard isKnownLaser || hasKnownService else { return }
        guard name != nil else { return }

        // Avoid duplicates
        if discoveredDevices.contains(where: { $0.id == peripheral.identifier }) { return }

        let device = DiscoveredLaserDevice(
            id: peripheral.identifier,
            name: name ?? "Unknown Laser",
            brand: brand,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        discoveredDevices.append(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connected

        let brand = connectedBrand
        let device = DiscoveredLaserDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Laser Meter",
            brand: brand,
            rssi: 0,
            peripheral: peripheral
        )
        connectedDevice = device

        // Discover services
        let serviceUUIDs = [BoschProtocol.serviceUUID, LeicaProtocol.serviceUUID]
        peripheral.discoverServices(serviceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == connectedPeripheral?.identifier else { return }

        // If we have a saved device, attempt reconnect
        if UserDefaults.standard.data(forKey: Self.savedDeviceKey) != nil {
            connectionState = .reconnecting
            centralManager.connect(peripheral, options: nil)
        } else {
            connectionState = .disconnected
            connectedPeripheral = nil
            connectedDevice = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
        connectedDevice = nil
        print("[LaserMeter] Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - CBPeripheralDelegate

extension LaserMeterService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == BoschProtocol.serviceUUID {
                connectedBrand = .bosch
                peripheral.discoverCharacteristics(
                    [BoschProtocol.measurementCharUUID, BoschProtocol.commandCharUUID],
                    for: service
                )
            } else if service.uuid == LeicaProtocol.serviceUUID {
                connectedBrand = .leica
                peripheral.discoverCharacteristics(
                    [LeicaProtocol.measurementCharUUID],
                    for: service
                )
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            // Subscribe to measurement notifications
            if characteristic.uuid == BoschProtocol.measurementCharUUID
                || characteristic.uuid == LeicaProtocol.measurementCharUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        var meters: Double?

        switch connectedBrand {
        case .bosch:
            // Full-length Bosch messages (≥20 bytes) include a checksum — enforce it
            if data.count >= 20 {
                guard BoschProtocol.validateChecksum(data) else {
                    print("[LaserMeter] Bosch checksum failed — discarding measurement")
                    return
                }
            }
            meters = BoschProtocol.parseMeasurement(data)

            // Detect Bosch error byte (valid header but nil parse = measurement error)
            if meters == nil && data.count >= 7 {
                let bytes = [UInt8](data)
                if bytes[0] == 0xC0 && bytes[1] == 0x55 && bytes[6] != 0x00 {
                    DispatchQueue.main.async { [weak self] in
                        self?.measurementError = "Measurement error — try again"
                    }
                    return
                }
            }
        case .leica:
            meters = LeicaProtocol.parseMeasurement(data)
        case .generic:
            // Try Leica format first (simpler), then Bosch
            meters = LeicaProtocol.parseMeasurement(data) ?? BoschProtocol.parseMeasurement(data)
        }

        if let meters = meters {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.latestMeasurement = LaserMeasurement(meters: meters, brand: self.connectedBrand)
            }
        }
    }
}
