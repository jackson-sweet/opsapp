//
//  WelcomeScreen.swift
//  OPS
//
//  Hero landing screen with video/slideshow background.
//  First screen users see when downloading the app.
//

import SwiftUI
import AVKit

struct WelcomeScreen: View {
    @ObservedObject var manager: OnboardingManager
    @State private var currentSlide = 0
    @State private var slideTimer: Timer?

    // Slideshow images - add your hero images to Assets
    private let heroImages = ["hero_1", "hero_2", "hero_3"]
    private let slideDuration: Double = 4.0

    var body: some View {
        ZStack {
            // Background slideshow/video layer
            backgroundLayer

            // Dark overlay gradient
            LinearGradient(
                colors: [
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.9),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // Top logo
                HStack(alignment: .bottom) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .padding(.bottom, 8)

                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle.weight(.bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.top, 60)

                Spacer()

                // Brand message
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BUILT BY TRADES.")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("FOR TRADES.")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Text("Job management your crew will actually use.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    // GET STARTED - Primary
                    Button {
                        manager.goToScreen(.signup)
                    } label: {
                        HStack {
                            Text("GET STARTED")
                                .font(OPSStyle.Typography.bodyBold)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }

                    // SIGN IN - Secondary
                    Button {
                        manager.goToScreen(.login)
                    } label: {
                        HStack {
                            Text("SIGN IN")
                                .font(OPSStyle.Typography.bodyBold)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            startSlideshow()
        }
        .onDisappear {
            stopSlideshow()
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        // Try to load hero images, fallback to solid color
        GeometryReader { geometry in
            ZStack {
                // Solid background fallback
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                // Slideshow images (if available)
                ForEach(0..<heroImages.count, id: \.self) { index in
                    Image(heroImages[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(currentSlide == index ? 1 : 0)
                        .animation(.easeInOut(duration: 1.0), value: currentSlide)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Slideshow Control

    private func startSlideshow() {
        slideTimer = Timer.scheduledTimer(withTimeInterval: slideDuration, repeats: true) { _ in
            withAnimation {
                currentSlide = (currentSlide + 1) % max(heroImages.count, 1)
            }
        }
    }

    private func stopSlideshow() {
        slideTimer?.invalidate()
        slideTimer = nil
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    WelcomeScreen(manager: manager)
        .environmentObject(dataController)
}
