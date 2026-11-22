//
//  DTPCameraViewController.swift
//  DulaTrackPro Clone
//

import UIKit
import AVFoundation

final class DTPCameraViewController: UIViewController {

    var onFinishRecording: ((DTPProject) -> Void)?

    private let recorder = DTPCameraRecorder()
    private let previewHost = UIView()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let recordButton = DTPRecordButton()
    private let flipButton = DTPIconButton(systemImage: "arrow.triangle.2.circlepath.camera", diameter: 48)
    private let durationLabel = UILabel()
    private let hintLabel = UILabel()
    private let topCard = DTPGlassCard(cornerRadius: 22)
    private let recordDot = UIView()

    private var recordingTimer: Timer?
    private var elapsed: TimeInterval = 0
    private var isPreparing = false
    private var didConfigure = false
    private var permissionCard: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildInterface()
        bindRecorder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        prepareCameraIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if recorder.isRecording {
            recorder.stopRecording()
            stopTimer()
            recordButton.setRecording(false, animated: false)
        }
        recorder.stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewHost.bounds
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - 界面

    private func buildInterface() {
        previewHost.backgroundColor = .black
        view.addSubview(previewHost)
        previewHost.dtpPin(to: view)

        let title = UILabel()
        title.text = "拍摄"
        title.font = DTPTheme.rounded(18, .bold)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = "AI 主体跟踪 · 防抖"
        subtitle.font = DTPTheme.font(11, .medium)
        subtitle.textColor = DTPTheme.Palette.textSecondary

        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        recordDot.backgroundColor = DTPTheme.Palette.danger
        recordDot.layer.cornerRadius = 4
        recordDot.translatesAutoresizingMaskIntoConstraints = false
        recordDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        recordDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let row = UIStackView(arrangedSubviews: [titleStack, UIView(), recordDot])
        row.axis = .horizontal
        row.alignment = .center
        topCard.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(topCard)
        topCard.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = DTPTheme.mono(15, .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.text = "00:00"
        durationLabel.alpha = 0

        hintLabel.text = "对准主体，开始录制"
        hintLabel.font = DTPTheme.font(12, .medium)
        hintLabel.textColor = DTPTheme.Palette.textSecondary
        hintLabel.textAlignment = .center

        view.addSubview(hintLabel)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        recordButton.addTarget(self, action: #selector(toggleRecord), for: .touchUpInside)
        view.addSubview(recordButton)
        recordButton.translatesAutoresizingMaskIntoConstraints = false

        flipButton.onTap = { [weak self] in self?.recorder.flipCamera() }
        view.addSubview(flipButton)
        flipButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            topCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),

            row.leadingAnchor.constraint(equalTo: topCard.contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: topCard.contentView.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: topCard.contentView.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: topCard.contentView.bottomAnchor, constant: -14),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            flipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            flipButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),

            durationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            durationLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -12),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: durationLabel.topAnchor, constant: -10)
        ])
    }

    private func bindRecorder() {
        recorder.onFinish = { [weak self] url in
            self?.handleRecordingFinished(url)
        }
        recorder.onError = { [weak self] error in
            guard let self else { return }
            self.recordButton.setRecording(false, animated: true)
            self.stopTimer()
            DTPToast.show(error.localizedDescription, symbol: "exclamationmark.triangle", in: self.view)
        }
    }

    private func prepareCameraIfNeeded() {
        guard !isPreparing else { return }
        isPreparing = true

        recorder.prepare { [weak self] granted in
            guard let self else { return }
            self.isPreparing = false
            if granted {
                self.didConfigure = true
                self.installPreviewIfNeeded()
                self.permissionCard?.removeFromSuperview()
                self.permissionCard = nil
            } else {
                self.showPermissionCard()
            }
        }
    }

    private func installPreviewIfNeeded() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: recorder.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewHost.bounds
        previewHost.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func showPermissionCard() {
        guard permissionCard == nil else { return }
        let card = DTPGlassCard(cornerRadius: 28)

        let icon = UIImageView(image: UIImage(systemName: "camera.metering.unknown"))
        icon.tintColor = DTPTheme.Palette.warm
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)

        let title = UILabel()
        title.text = "需要相机权限"
        title.font = DTPTheme.rounded(17, .bold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "开启相机与麦克风权限后，就可以直接拍摄素材。"
        subtitle.font = DTPTheme.font(12.5, .regular)
        subtitle.textColor = DTPTheme.Palette.textSecondary
        subtitle.numberOfLines = 3
        subtitle.textAlignment = .center

        let button = DTPGlassButton(title: "前往设置", systemImage: "gearshape", style: .prominent, height: 46)
        button.onTap = {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, button])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.setCustomSpacing(18, after: subtitle)
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -24),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300)
        ])
        permissionCard = card
        DTPToast.show("相机权限未开启", symbol: "camera", in: view)
    }

    // MARK: - 录制

    @objc private func toggleRecord() {
        if recorder.isRecording {
            recorder.stopRecording()
            stopTimer()
            recordButton.setRecording(false, animated: true)
            hintLabel.text = "正在保存…"
            return
        }

        guard didConfigure else {
            prepareCameraIfNeeded()
            DTPToast.show("相机还在准备中", symbol: "hourglass", in: view)
            return
        }

        elapsed = 0
        durationLabel.text = "00:00"
        hintLabel.text = "录制中，点击停止"
        recorder.startRecording()
        recordButton.setRecording(true, animated: true)
        UIView.animate(withDuration: 0.2) { self.durationLabel.alpha = 1 }

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed += 0.5
            let seconds = Int(self.elapsed)
            self.durationLabel.text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        UIView.animate(withDuration: 0.2) { self.durationLabel.alpha = 0 }
    }

    private func handleRecordingFinished(_ url: URL) {
        stopTimer()
        recordButton.setRecording(false, animated: true)
        hintLabel.text = "正在导入…"

        Task {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? self.elapsed
            var size = CGSize(width: 1080, height: 1920)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let natural = (try? await track.load(.naturalSize)) ?? size
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            let thumbnail = await DTPMediaImporter.makeThumbnail(asset: asset, duration: duration)
            let name = "拍摄 \(Self.timeFormatter.string(from: Date()))"

            let project = DTPProjectStore.shared.importVideo(from: url,
                                                             name: name,
                                                             duration: duration,
                                                             size: size,
                                                             thumbnail: thumbnail)
            try? FileManager.default.removeItem(at: url)

            await MainActor.run {
                self.hintLabel.text = "对准主体，开始录制"
                guard let project else {
                    DTPToast.show("视频保存失败", symbol: "exclamationmark.triangle", in: self.view)
                    return
                }
                DTPHaptics.success()
                self.onFinishRecording?(project)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - 录制按钮

private final class DTPRecordButton: UIControl {

    private let glass = DTPGlass.makeView(cornerRadius: 44)
    private let ring = UIView()
    private let core = UIView()
    private var isRecordingMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        glass.isUserInteractionEnabled = false
        addSubview(glass)
        glass.dtpPin(to: self)

        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        ring.layer.borderWidth = 3
        ring.layer.cornerRadius = 38
        ring.isUserInteractionEnabled = false
        addSubview(ring)
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 76),
            ring.heightAnchor.constraint(equalToConstant: 76),
            widthAnchor.constraint(equalToConstant: 88),
            heightAnchor.constraint(equalToConstant: 88)
        ])

        core.backgroundColor = DTPTheme.Palette.danger
        core.layer.cornerRadius = 28
        core.isUserInteractionEnabled = false
        addSubview(core)
        core.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            core.centerXAnchor.constraint(equalTo: centerXAnchor),
            core.centerYAnchor.constraint(equalTo: centerYAnchor),
            core.widthAnchor.constraint(equalToConstant: 56),
            core.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRecording(_ recording: Bool, animated: Bool) {
        guard recording != isRecordingMode else { return }
        isRecordingMode = recording
        let apply = {
            self.core.transform = recording ? CGAffineTransform(scaleX: 0.52, y: 0.52) : .identity
            self.core.layer.cornerRadius = recording ? 18 : 28
            self.ring.layer.borderColor = recording
                ? DTPTheme.Palette.danger.withAlphaComponent(0.9).cgColor
                : UIColor.white.withAlphaComponent(0.9).cgColor
        }
        if animated {
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: apply)
        } else {
            apply()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
}
