// OPS/OPS/DeckBuilder/Views/VoiceDimensionInput.swift

import Foundation
import Speech
import AVFoundation

@MainActor
class VoiceDimensionInput: ObservableObject {

    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""
    @Published var parsedDimensions: [Double?] = []
    @Published var error: String?
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let expectedCount: Int
    private var measurementSystem: MeasurementSystem

    init(expectedDimensionCount: Int, measurementSystem: MeasurementSystem = .imperial) {
        self.expectedCount = expectedDimensionCount
        self.measurementSystem = measurementSystem
        self.parsedDimensions = Array(repeating: nil, count: expectedDimensionCount)
    }

    func setMeasurementSystem(_ measurementSystem: MeasurementSystem) {
        self.measurementSystem = measurementSystem
        if !recognizedText.isEmpty {
            parsedDimensions = parseDimensionsFromText(recognizedText)
        }
    }

    // MARK: - Authorization

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Start/Stop Listening

    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            error = "Speech recognition not available"
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.parsedDimensions = self.parseDimensionsFromText(self.recognizedText)

                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if let error = error {
                    self.error = error.localizedDescription
                    self.stopListening()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            error = nil
        } catch {
            self.error = "Audio engine error: \(error.localizedDescription)"
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Parsing

    func parseDimensionsFromText(_ text: String) -> [Double?] {
        var results: [Double?] = Array(repeating: nil, count: expectedCount)
        let normalized = normalizeText(text)

        // Strategy 1: Split on letter labels (A, B, C, D)
        let letterPattern = #"(?i)\b([a-d])\b[,.\s]*(.+?)(?=\b[a-d]\b|$)"#
        if let regex = try? NSRegularExpression(pattern: letterPattern) {
            let nsText = normalized as NSString
            let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                if match.numberOfRanges >= 3 {
                    let letter = nsText.substring(with: match.range(at: 1)).uppercased()
                    let value = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)

                    if let index = letterToIndex(letter),
                       let inches = parseDimensionValue(value) {
                        if index < results.count {
                            results[index] = inches
                        }
                    }
                }
            }

            if results.compactMap({ $0 }).count > 0 { return results }
        }

        // Strategy 2: Split on "by" / "and" / commas
        let segments = normalized
            .replacingOccurrences(of: " by ", with: "|")
            .replacingOccurrences(of: " and ", with: "|")
            .replacingOccurrences(of: ",", with: "|")
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        for (i, segment) in segments.enumerated() where i < expectedCount {
            results[i] = parseDimensionValue(segment)
        }

        return results
    }

    private func normalizeText(_ text: String) -> String {
        var result = text.lowercased()

        // Number words to digits — ordered so compounds resolve first
        let wordMap: [(String, String)] = [
            ("twenty", "20"), ("thirty", "30"), ("forty", "40"), ("fifty", "50"),
            ("sixty", "60"), ("seventy", "70"), ("eighty", "80"), ("ninety", "90"),
            ("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"), ("five", "5"),
            ("six", "6"), ("seven", "7"), ("eight", "8"), ("nine", "9"), ("ten", "10"),
            ("eleven", "11"), ("twelve", "12"), ("thirteen", "13"), ("fourteen", "14"),
            ("fifteen", "15"), ("sixteen", "16"), ("seventeen", "17"), ("eighteen", "18"),
            ("nineteen", "19"),
        ]

        // Handle compound numbers: "twenty four" → "24"
        let compoundPattern = #"(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[\s-]*(one|two|three|four|five|six|seven|eight|nine)"#
        if let regex = try? NSRegularExpression(pattern: compoundPattern) {
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                let tens = nsResult.substring(with: match.range(at: 1))
                let ones = nsResult.substring(with: match.range(at: 2))
                let tensVal = wordMap.first(where: { $0.0 == tens })?.1 ?? "0"
                let onesVal = wordMap.first(where: { $0.0 == ones })?.1 ?? "0"
                let combined = String((Int(tensVal) ?? 0) + (Int(onesVal) ?? 0))
                result = (result as NSString).replacingCharacters(in: match.range, with: combined)
            }
        }

        // Single word numbers
        for (word, digit) in wordMap {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: digit, options: .regularExpression)
        }

        // Handle "hundred" multiplier: "2 hundred" → "200", bare "hundred" → "100"
        let hundredCompoundPattern = #"(\d+)\s*hundred"#
        if let hundredRegex = try? NSRegularExpression(pattern: hundredCompoundPattern) {
            let nsResult = result as NSString
            let hundredMatches = hundredRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in hundredMatches.reversed() {
                let numStr = nsResult.substring(with: match.range(at: 1))
                let multiplied = String((Int(numStr) ?? 1) * 100)
                result = (result as NSString).replacingCharacters(in: match.range, with: multiplied)
            }
        }
        result = result.replacingOccurrences(of: "\\bhundred\\b", with: "100", options: .regularExpression)

        // Unit words to symbols
        result = result.replacingOccurrences(of: "feet", with: "'")
        result = result.replacingOccurrences(of: "foot", with: "'")
        result = result.replacingOccurrences(of: "inches", with: "\"")
        result = result.replacingOccurrences(of: "inch", with: "\"")
        result = result.replacingOccurrences(of: "and a half", with: ".5")
        result = result.replacingOccurrences(of: "half", with: ".5")
        result = result.replacingOccurrences(of: "point ", with: ".")

        return result
    }

    private func parseDimensionValue(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return DimensionEngine.parseToInches(cleaned, system: measurementSystem)
    }

    private func letterToIndex(_ letter: String) -> Int? {
        switch letter {
        case "A": return 0
        case "B": return 1
        case "C": return 2
        case "D": return 3
        default: return nil
        }
    }
}
