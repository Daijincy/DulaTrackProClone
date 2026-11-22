//
//  DTPCameraRecorder.swift
//  DulaTrackPro Clone
//

import AVFoundation
import UIKit

final class DTPCameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.dula.trackpro.camera")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private(set) var isConfigured = false
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back

    var onFinish: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - 配置

    func prepare(completion: @escaping (Bool) -> Void) {
        requestPermissions { [weak self] granted in
            guard let self, granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.sessionQueue.async {
                let success = self.configureIfNeeded()
                DispatchQueue.main.async { completion(success) }
            }
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var videoGranted = false
        var audioGranted = false

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            videoGranted = granted
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            audioGranted = granted
            group.leave()
        }

        group.notify(queue: .global()) {
            completion(videoGranted || audioGranted)
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }

        session.beginConfiguration()
        session.sessionPreset = .high

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        } else {
            session.commitConfiguration()
            return false
        }

        if let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.movieFragmentInterval = .invalid
        } else {
            session.commitConfiguration()
            return false
        }

        session.commitConfiguration()

        sessionQueue.async {
            self.session.startRunning()
        }
        isConfigured = true
        return true
    }

    // MARK: - 录制

    func startRecording() {
        guard isConfigured, !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DTPCapture-\(UUID().uuidString).mov")
        isRecording = true
        sessionQueue.async {
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        DTPHaptics.medium()
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async {
            self.movieOutput.stopRecording()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        isRecording = false

        if let error {
            let nsError = error as NSError
            let finished = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            if !finished {
                DispatchQueue.main.async { self.onError?(error) }
                return
            }
        }
        DispatchQueue.main.async { self.onFinish?(outputFileURL) }
    }

    // MARK: - 摄像头控制

    func flipCamera() {
        guard isConfigured, !isRecording else { return }
        let target: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        sessionQueue.async {
            self.session.beginConfiguration()
            if let current = self.videoInput {
                self.session.removeInput(current)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                DispatchQueue.main.async { self.currentPosition = target }
            } else if let current = self.videoInput {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
        }
        DTPHaptics.light()
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}
