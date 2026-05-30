// OPS/OPS/Views/Settings/LaserMeterSettingsView.swift

import SwiftUI

struct LaserMeterSettingsView: View {
    @ObservedObject private var laserService = LaserMeterService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showForgetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Bluetooth off warning
                    if laserService.bluetoothState != .poweredOn {
                        bluetoothOffBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // Connected device section
                    if laserService.connectionState == .connected, let device = laserService.connectedDevice {
                        connectedDeviceSection(device: device)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // Reconnecting state
                    if laserService.connectionState == .reconnecting {
                        reconnectingSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // Scanning / discovered devices
                    if laserService.connectionState == .scanning {
                        scanningSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // Idle state — scan button
                    if laserService.connectionState == .disconnected && laserService.bluetoothState == .poweredOn {
                        idleSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(OPSStyle.Colors.background)
        .alert("Forget Device", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Forget", role: .destructive) {
                laserService.forgetDevice()
            }
        } message: {
            Text("This will disconnect and remove the saved laser meter. You'll need to scan and pair again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text("LASER METER")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Spacer for symmetry
            Color.clear
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Bluetooth Off

    private var bluetoothOffBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.warningStatus)

                Text("Bluetooth is turned off")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()
            }

            Text("Enable Bluetooth in Settings to connect a laser distance meter.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("OPEN SETTINGS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Connected Device

    private func connectedDeviceSection(device: DiscoveredLaserDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTED DEVICE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                // Device info
                HStack(spacing: 14) {
                    Image(systemName: device.brand.iconName)
                        .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .frame(width: 32, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(OPSStyle.Colors.successStatus)
                                .frame(width: 8, height: 8)

                            Text("Connected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.successStatus)

                            Text("·")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(device.brand.displayName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                // Last measurement
                if let measurement = laserService.latestMeasurement {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.leading, 62)

                    HStack(spacing: 14) {
                        Image(systemName: "ruler")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 32, alignment: .center)

                        Text("Last: \(formatMeasurement(measurement))")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }

                // Forget device
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)
                    .padding(.leading, 62)

                Button {
                    showForgetConfirmation = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(width: 32, alignment: .center)

                        Text("Forget Device")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Reconnecting

    private var reconnectingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LASER METER")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: 14) {
                ProgressView()
                    .tint(OPSStyle.Colors.warningStatus)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reconnecting...")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Attempting to reconnect to your laser meter")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Scanning

    private var scanningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AVAILABLE DEVICES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                ProgressView()
                    .tint(OPSStyle.Colors.primaryAccent)
                    .scaleEffect(0.8)

                Text("Scanning...")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            VStack(spacing: 0) {
                if laserService.discoveredDevices.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("Searching for laser meters...")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("Make sure your device is powered on and in pairing mode.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    ForEach(Array(laserService.discoveredDevices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorder)
                                .frame(height: 1)
                                .padding(.leading, 62)
                        }

                        Button {
                            laserService.connect(device)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: device.brand.iconName)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 32, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text(device.brand.displayName)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Spacer()

                                // Signal strength indicator
                                signalBars(rssi: device.rssi)

                                Image(OPSStyle.Icons.chevronRight)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            // Stop scanning button
            Button {
                laserService.stopScanning()
            } label: {
                Text("STOP SCANNING")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text("No Laser Meter Connected")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Connect a Bluetooth laser distance meter (Bosch GLM, Leica DISTO) for precision measurements in the deck builder.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            Button {
                laserService.startScanning()
            } label: {
                Text("SCAN FOR DEVICES")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func formatMeasurement(_ measurement: LaserMeasurement) -> String {
        let totalInches = measurement.inches
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        let fraction = totalInches - Double(Int(totalInches))

        if fraction > 0.0625 {
            return "\(feet)' \(inches) \(fractionString(fraction))\""
        }
        return "\(feet)' \(inches)\""
    }

    private func fractionString(_ fraction: Double) -> String {
        // Round to nearest 1/16"
        let sixteenths = Int(round(fraction * 16))
        switch sixteenths {
        case 0: return ""
        case 8: return "1/2"
        case 4: return "1/4"
        case 12: return "3/4"
        case 2: return "1/8"
        case 6: return "3/8"
        case 10: return "5/8"
        case 14: return "7/8"
        default: return "\(sixteenths)/16"
        }
    }

    @ViewBuilder
    private func signalBars(rssi: Int) -> some View {
        let strength: Int = {
            if rssi > -50 { return 4 }
            if rssi > -60 { return 3 }
            if rssi > -70 { return 2 }
            return 1
        }()

        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= strength ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + bar * 3))
            }
        }
    }
}
