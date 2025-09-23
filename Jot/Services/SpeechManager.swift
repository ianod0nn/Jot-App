//
//  SpeechManager.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/7/25.
//
import Foundation
import Speech
import AVFoundation
import Combine

class SpeechManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false
    @Published var errorMessage = ""
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioSession = AVAudioSession.sharedInstance()
    
    override init() {
        super.init()
        requestPermissions()
    }
    
    func requestPermissions() {
        // Request Speech Recognition permission
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                case .denied, .restricted, .notDetermined:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition not authorized"
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
        
        // Request Microphone permission - iOS 17+ compatible
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        self?.errorMessage = "Microphone access denied"
                    }
                }
            }
        } else {
            // Fallback for iOS 16 and earlier
            audioSession.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        self?.errorMessage = "Microphone access denied"
                    }
                }
            }
        }
    }
    
    func startRecording() {
        guard isAuthorized else {
            errorMessage = "Speech recognition not authorized"
            return
        }
        
        guard !audioEngine.isRunning else { return }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session for iOS 17+
        do {
            if #available(iOS 17.0, *) {
                try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            } else {
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            }
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // iOS 17+ improvements for better recognition
        if #available(iOS 16.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false // Allow cloud processing for better accuracy
        }
        
        // Get audio input node
        let inputNode = audioEngine.inputNode
        
        // Create recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.transcribedText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    // Stop recording if there's an error or if the result is final
                    self?.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self?.recognitionRequest = nil
                    self?.recognitionTask = nil
                    self?.isRecording = false
                    
                    if let error = error {
                        self?.errorMessage = "Recognition error: \(error.localizedDescription)"
                    }
                }
            }
        }
        
        // Configure audio input with better format handling for iOS 17+
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            recognitionRequest.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            transcribedText = ""
            errorMessage = ""
        } catch {
            errorMessage = "Audio engine start failed: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
        
        // Deactivate audio session with iOS 17+ compatibility
        do {
            if #available(iOS 17.0, *) {
                try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            } else {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            }
        } catch {
            print("Audio session deactivation failed: \(error)")
        }
    }
    
    func reset() {
        transcribedText = ""
        errorMessage = ""
    }
    
    // iOS 17+ specific improvements
    @available(iOS 17.0, *)
    func checkMicrophonePermission() -> Bool {
        return AVAudioApplication.shared.recordPermission == .granted
    }
}
