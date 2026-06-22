//
//  SpeechRecognitionManager.swift
//  OPS
//
//  Wraps SFSpeechRecognizer for live transcription with contextual string boosting.
//

import Foundation
import Speech
import AVFoundation

enum SpeechRecognitionState: Equatable {
    case idle
    case recording
    case stopping
    case error(String)
}

@MainActor
class SpeechRecognitionManager: ObservableObject {
    @Published var transcription: String = ""
    @Published var state: SpeechRecognitionState = .idle

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Contextual strings to boost recognition of names and domain terms
    var contextualStrings: [String] = []

    /// Force on-device transcription so the dictated audio never leaves the
    /// phone. Used by the around-call voice note (feature 154cb8a3) — the
    /// operator's own dictation about a call stays private. Falls back to the
    /// default (server-when-online) when the device/locale can't do on-device.
    var preferOnDeviceRecognition: Bool = false

    /// Silence timer — auto-stop after 3 seconds of no new speech
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 3.0

    // MARK: - Authorization

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    // MARK: - Start / Stop

    func startRecording() throws {
        // Cancel any in-flight task
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [
            .defaultToSpeaker,
            .allowBluetooth
        ])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Default: server-based when online. Voice-note callers can force
        // on-device so call audio never leaves the phone (when supported).
        request.requiresOnDeviceRecognition =
            preferOnDeviceRecognition && (speechRecognizer?.supportsOnDeviceRecognition ?? false)

        if !contextualStrings.isEmpty {
            request.contextualStrings = Array(contextualStrings.prefix(100))
        }

        self.recognitionRequest = request

        guard let recognizer = speechRecognizer else {
            state = .error("Speech recognizer not available")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcription = result.bestTranscription.formattedString
                    self.resetSilenceTimer()

                    if result.isFinal {
                        self.cleanupRecording()
                    }
                }

                if let error, self.state == .recording {
                    // Ignore cancellation errors from manual stop
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // User cancelled — not an error
                    } else if nsError.code == 1110 {
                        // No speech detected — normal for silence auto-stop
                    } else {
                        self.state = .error(error.localizedDescription)
                    }
                    self.cleanupRecording()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        transcription = ""
        resetSilenceTimer()
    }

    func stopRecording() {
        guard state == .recording || state == .stopping else { return }
        state = .stopping
        cleanupRecording()
    }

    func toggleRecording() throws {
        if state == .recording {
            stopRecording()
        } else {
            try startRecording()
        }
    }

    // MARK: - Private

    private func cleanupRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if case .error = state {
            // Preserve the error state
        } else {
            state = .idle
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }
}
