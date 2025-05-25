//
//  SimplePINEntryView.swift
//  OPS
//
//  Simple PIN entry view for app access
//

import SwiftUI
import UIKit

struct SimplePINEntryView: View {
    @ObservedObject var pinManager: SimplePINManager
    @State private var enteredPIN = ""
    @State private var showError = false
    @State private var pinState: PINValidationState = .neutral
    @State private var shakeOffset: CGFloat = 0
    
    enum PINValidationState {
        case neutral
        case success
        case error
        
        var borderColor: Color {
            switch self {
            case .neutral:
                return Color.white.opacity(0.3)
            case .success:
                return OPSStyle.Colors.successStatus
            case .error:
                return OPSStyle.Colors.errorStatus
            }
        }
    }
    
    init(pinManager: SimplePINManager) {
        self.pinManager = pinManager
        print("SimplePINEntryView: Initialized with isAuthenticated=\(pinManager.isAuthenticated), requiresPIN=\(pinManager.requiresPIN)")
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 32) {
                Spacer()
                
                // App Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                HStack {
                    
                    Text(Image(systemName: "lock"))
                        .font(.system(size: 24))
                    Spacer()
                    Text("ENTER PIN")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                
                
                // PIN input with individual boxes
                PINDigitBoxes(pin: $enteredPIN, validationState: pinState)
                    .offset(x: shakeOffset)
                    .onChange(of: enteredPIN) { _, newValue in
                        // Reset state when user starts typing again
                        if pinState != .neutral && newValue.count < 4 {
                            pinState = .neutral
                        }
                        
                        if newValue.count > 4 {
                            enteredPIN = String(newValue.prefix(4))
                        } else if newValue.count == 4 {
                            validatePIN()
                        }
                    }
                
                if showError {
                    Text("Incorrect PIN")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                } else if enteredPIN.isEmpty {
                    Text("ENTER YOUR PIN")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func validatePIN() {
        print("SimplePINEntryView: validatePIN called with PIN: \(enteredPIN)")
        print("SimplePINEntryView: Current isAuthenticated: \(pinManager.isAuthenticated)")
        print("SimplePINEntryView: Current requiresPIN: \(pinManager.requiresPIN)")
        
        if pinManager.validatePIN(enteredPIN) {
            print("SimplePINEntryView: PIN validation successful")
            
            // Success feedback
            pinState = .success
            showError = false
            
            // Haptic feedback for success
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
            
            // Don't clear the PIN - keep all digits visible during success animation
            // The view will be dismissed anyway, so no need to clear
            
            // Check state after validation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("SimplePINEntryView: After validation - isAuthenticated: \(self.pinManager.isAuthenticated)")
                print("SimplePINEntryView: After validation - requiresPIN: \(self.pinManager.requiresPIN)")
            }
        } else {
            print("SimplePINEntryView: PIN validation failed")
            
            // Error feedback
            pinState = .error
            showError = true
            
            // Haptic feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
            
            // Shake animation
            withAnimation(.default) {
                shakeOffset = -10
            }
            withAnimation(.default.delay(0.1)) {
                shakeOffset = 10
            }
            withAnimation(.default.delay(0.2)) {
                shakeOffset = -5
            }
            withAnimation(.default.delay(0.3)) {
                shakeOffset = 5
            }
            withAnimation(.default.delay(0.4)) {
                shakeOffset = 0
            }
            
            // Clear PIN and reset state after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.enteredPIN = ""
                self.pinState = .neutral
            }
            
            // Hide error message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showError = false
            }
        }
    }
}

// PIN input with 4 individual digit boxes
struct PINDigitBoxes: View {
    @Binding var pin: String
    let validationState: SimplePINEntryView.PINValidationState
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Hidden TextField to capture keyboard input
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .focused($isFieldFocused)
                .frame(width: 1, height: 1)
                .opacity(0)
            
            // Visual digit boxes
            HStack(spacing: 16) {
                ForEach(0..<4) { index in
                    PINDigitBox(
                        digit: getDigit(at: index),
                        isFilled: index < pin.count,
                        validationState: validationState,
                        isActive: isFieldFocused
                    )
                }
            }
            .onTapGesture {
                isFieldFocused = true
            }
        }
        // Don't auto-focus on appear - let user tap to activate
    }
    
    private func getDigit(at index: Int) -> String {
        if index < pin.count {
            let pinIndex = pin.index(pin.startIndex, offsetBy: index)
            return String(pin[pinIndex])
        }
        return ""
    }
}

struct PINDigitBox: View {
    let digit: String
    let isFilled: Bool
    let validationState: SimplePINEntryView.PINValidationState
    let isActive: Bool
    
    private var borderColor: Color {
        if validationState != .neutral {
            return validationState.borderColor
        }
        // Show active state with brighter border when field is focused
        if isActive {
            return isFilled ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.8)
        }
        return isFilled ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.3)
    }
    
    private var borderWidth: CGFloat {
        // Thicker border when active
        return isActive ? 2 : 1
    }
    
    private var fillColor: Color {
        switch validationState {
        case .neutral:
            return OPSStyle.Colors.primaryAccent
        case .success:
            return OPSStyle.Colors.successStatus
        case .error:
            return OPSStyle.Colors.errorStatus
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
                .frame(width: 56, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OPSStyle.Colors.cardBackgroundDark.opacity(isActive ? 0.5 : 0.3))
                )
                .animation(.easeInOut(duration: 0.2), value: validationState)
                .animation(.easeInOut(duration: 0.2), value: isActive)
            
            if isFilled {
                Circle()
                    .fill(fillColor)
                    .frame(width: 16, height: 16)
                    .animation(.easeInOut(duration: 0.2), value: validationState)
            }
        }
    }
}
