//
//  DTPEditorViewController.swift
//  DulaTrackPro Clone
//

import UIKit
import AVFoundation

final class DTPEditorViewController: UIViewController {

    private let project: DTPProject
    private var asset: AVURLAsset?
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()

    private let previewCard = DTPGlassCard(cornerRadius: 30)
    private let videoContainer = UIView()
    private let overlay = DTPTrackOverlayView()
    private let playbackBar = DTPGlassCard(cornerRadius: 20)
    private let playButton = DTPIconButton(systemImage: "play.fill", diameter: 36)
    private let timeline = UISlider()
    private let timeLabel = UILabel()
    private let totalLabel = UILabel()

    private let controlsCard = DTPGlassCard(cornerRadius: 30)
    private let statusLabel = UILabel()
    private let statusDot = UIView()
    private let zoomLabel = UILabel()
    private let zoomSlider = UISlider()
    private let exportButton = DTPGlassButton(title: "开始导出", systemImage: "sparkles", style: .prominent, height: 52)

    private let progressOverlay = DTPGlassCard(cornerRadius: 26)
    private let progressRing = DTPProgressRing(diameter: 76, lineWidth: 6)
    private let progressTitle = UILabel()
    private let progressSubtitle = UILabel()

    private var aspect: DTPAspect = DTPSettings.load().aspect
    private var autoFrame = DTPSettings.load().autoFrame
    private var stabilize = DTPSettings.load().stabilize
    private var zoom: CGFloat = 1

    private var plan: DTPTrackPlan?
    private var displaySize = CGSize(width: 1080, height: 1920)
    private var videoDuration: Double = 0
    private var timeObserver: Any?
    private var isAnalyzing = false
    private var isExporting = false
    private var isScrubbing = false
    private var didStartAnalysis = false
    private var isPlayingState = false
    private var aspectChips: [DTPAspect: DTPChip] = [:]

    private let planner = DTPTrackingPlanner()
    private let exporter = DTPVideoExporter()

    init(project: DTPProject) {
        self.project = project
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DTPTheme.Palette.background
        buildInterface()
        loadAsset()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didStartAnalysis {
            didStartAnalysis = true
            analyze()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreview()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - 界面搭建

    private func buildInterface() {
        let backdrop = DTPBackdropView()
        view.addSubview(backdrop)
        backdrop.dtpPin(to: view)
        backdrop.startAnimating()

        let closeButton = DTPIconButton(systemImage: "xmark", diameter: 44)
        closeButton.onTap = { [weak self] in
            self?.player.pause()
            self?.exporter.cancel()
            self?.dismiss(animated: true)
        }

        let title = UILabel()
        title.text = project.name
        title.font = DTPTheme.rounded(16, .bold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail

        let subtitle = UILabel()
        subtitle.text = "AI 主体跟踪 · 自动构图"
        subtitle.font = DTPTheme.font(11, .medium)
        subtitle.textColor = DTPTheme.Palette.textTertiary

        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let exportTop = DTPGlassButton(title: "导出",
                                       systemImage: "square.and.arrow.up",
                                       style: .prominent,
                                       height: 42)
        exportTop.onTap = { [weak self] in self?.startExport() }

        let topBar = UIStackView(arrangedSubviews: [closeButton, titleStack, UIView(), exportTop])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 12
        view.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        exportTop.translatesAutoresizingMaskIntoConstraints = false
        exportTop.widthAnchor.constraint(equalToConstant: 92).isActive = true

        // 预览
        previewCard.contentView.backgroundColor = .black
        previewCard.contentView.clipsToBounds = true
        view.addSubview(previewCard)

        videoContainer.backgroundColor = .black
        videoContainer.clipsToBounds = true
        previewCard.contentView.addSubview(videoContainer)
        videoContainer.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resize

        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        videoContainer.addSubview(overlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        previewCard.addGestureRecognizer(tap)

        buildPlaybackBar()
        buildProgressOverlay()
        buildControls()

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topBar.heightAnchor.constraint(equalToConstant: 46),

            previewCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewCard.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            previewCard.bottomAnchor.constraint(equalTo: controlsCard.topAnchor, constant: -14),

            controlsCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlsCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            controlsCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    private func buildPlaybackBar() {
        playButton.onTap = { [weak self] in self?.togglePlayback() }

        timeLabel.font = DTPTheme.mono(11, .medium)
        timeLabel.textColor = .white
        timeLabel.text = "0:00"

        totalLabel.font = DTPTheme.mono(11, .medium)
        totalLabel.textColor = DTPTheme.Palette.textTertiary
        totalLabel.text = "0:00"

        timeline.minimumTrackTintColor = DTPTheme.Palette.accent
        timeline.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
        timeline.thumbTintColor = .white
        timeline.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        timeline.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        timeline.addTarget(self, action: #selector(sliderTouchUp),
                           for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let row = UIStackView(arrangedSubviews: [playButton, timeLabel, timeline, totalLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        playbackBar.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false

        previewCard.contentView.addSubview(playbackBar)
        playbackBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playbackBar.leadingAnchor.constraint(equalTo: previewCard.contentView.leadingAnchor, constant: 12),
            playbackBar.trailingAnchor.constraint(equalTo: previewCard.contentView.trailingAnchor, constant: -12),
            playbackBar.bottomAnchor.constraint(equalTo: previewCard.contentView.bottomAnchor, constant: -12),
            playbackBar.heightAnchor.constraint(equalToConstant: 54),

            row.leadingAnchor.constraint(equalTo: playbackBar.contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: playbackBar.contentView.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: playbackBar.contentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: playbackBar.contentView.bottomAnchor, constant: -8),
            timeLabel.widthAnchor.constraint(equalToConstant: 34),
            totalLabel.widthAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func buildProgressOverlay() {
        progressTitle.font = DTPTheme.rounded(16, .bold)
        progressTitle.textColor = .white
        progressTitle.textAlignment = .center

        progressSubtitle.font = DTPTheme.font(12, .regular)
        progressSubtitle.textColor = DTPTheme.Palette.textSecondary
        progressSubtitle.textAlignment = .center
        progressSubtitle.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [progressRing, progressTitle, progressSubtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        progressOverlay.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        previewCard.contentView.addSubview(progressOverlay)
        progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: progressOverlay.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: progressOverlay.contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: progressOverlay.contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: progressOverlay.contentView.bottomAnchor, constant: -22),

            progressOverlay.centerXAnchor.constraint(equalTo: previewCard.contentView.centerXAnchor),
            progressOverlay.centerYAnchor.constraint(equalTo: previewCard.contentView.centerYAnchor),
            progressOverlay.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        progressOverlay.isHidden = true
    }

    private func buildControls() {
        view.addSubview(controlsCard)

        let aspectTitle = makeControlTitle("输出画幅")
        let aspectRow = UIStackView()
        aspectRow.axis = .horizontal
        aspectRow.spacing = 8
        aspectRow.distribution = .fillEqually

        for value in DTPAspect.allCases {
            let chip = DTPChip(title: value.title, isOn: value == aspect)
            chip.onToggle = { [weak self] _ in self?.select(aspect: value) }
            aspectChips[value] = chip
            aspectRow.addArrangedSubview(chip)
        }

        let toggleRow = UIStackView()
        toggleRow.axis = .horizontal
        toggleRow.spacing = 8
        toggleRow.distribution = .fillEqually

        let trackChip = DTPChip(title: "主体跟踪", systemImage: "scope", isOn: autoFrame)
        trackChip.onToggle = { [weak self] isOn in
            self?.autoFrame = isOn
            self?.updatePlayerFrame()
        }
        let stabilizeChip = DTPChip(title: "防抖", systemImage: "waveform.path.ecg", isOn: stabilize)
        stabilizeChip.onToggle = { [weak self] isOn in self?.stabilize = isOn }

        toggleRow.addArrangedSubview(trackChip)
        toggleRow.addArrangedSubview(stabilizeChip)

        zoomLabel.font = DTPTheme.mono(12, .semibold)
        zoomLabel.textColor = DTPTheme.Palette.textSecondary
        zoomLabel.text = "1.0×"

        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 2.5
        zoomSlider.value = 1
        zoomSlider.minimumTrackTintColor = DTPTheme.Palette.accent
        zoomSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
        zoomSlider.thumbTintColor = .white
        zoomSlider.addTarget(self, action: #selector(zoomChanged), for: .valueChanged)

        let zoomIcon = UIImageView(image: UIImage(systemName: "plus.magnifyingglass"))
        zoomIcon.tintColor = DTPTheme.Palette.textSecondary
        zoomIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        let zoomRow = UIStackView(arrangedSubviews: [zoomIcon, zoomSlider, zoomLabel])
        zoomRow.axis = .horizontal
        zoomRow.alignment = .center
        zoomRow.spacing = 10

        statusDot.backgroundColor = DTPTheme.Palette.accent
        statusDot.layer.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        statusLabel.font = DTPTheme.font(12, .medium)
        statusLabel.textColor = DTPTheme.Palette.textSecondary
        statusLabel.text = "准备分析…"
        statusLabel.numberOfLines = 2

        let reanalyzeButton = UIButton(type: .system)
        reanalyzeButton.setTitle("重新分析", for: .normal)
        reanalyzeButton.titleLabel?.font = DTPTheme.font(12, .semibold)
        reanalyzeButton.tintColor = DTPTheme.Palette.accent
        reanalyzeButton.addTarget(self, action: #selector(reanalyzeTapped), for: .touchUpInside)

        let statusRow = UIStackView(arrangedSubviews: [statusDot, statusLabel, UIView(), reanalyzeButton])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 8

        exportButton.onTap = { [weak self] in self?.startExport() }

        let stack = UIStackView(arrangedSubviews: [
            aspectTitle, aspectRow,
            makeControlTitle("处理"),
            toggleRow,
            makeControlTitle("缩放"),
            zoomRow,
            statusRow,
            exportButton
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(14, after: aspectRow)
        stack.setCustomSpacing(14, after: toggleRow)
        stack.setCustomSpacing(14, after: zoomRow)

        controlsCard.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlsCard.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: controlsCard.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: controlsCard.contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: controlsCard.contentView.bottomAnchor, constant: -16)
        ])
    }

    private func makeControlTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = DTPTheme.font(11, .semibold)
        label.textColor = DTPTheme.Palette.textTertiary
        return label
    }

    // MARK: - 资源加载

    private func loadAsset() {
        let url = DTPProjectStore.shared.mediaURL(for: project)
        let asset = AVURLAsset(url: url)
        self.asset = asset

        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        playerLayer.player = player

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30),
                                                      queue: .main) { [weak self] time in
            self?.handlePlaybackTick(seconds: time.seconds)
        }

        Task {
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            var size = CGSize(width: 1080, height: 1920)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let natural = (try? await track.load(.naturalSize)) ?? size
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            await MainActor.run {
                self.videoDuration = duration
                self.displaySize = size
                self.totalLabel.text = self.format(duration)
                self.timeline.value = 0
                self.layoutPreview()
                self.updatePlayerFrame()
            }
        }
    }

    // MARK: - 分析

    @objc private func reanalyzeTapped() {
        plan = nil
        analyze()
    }

    private func analyze() {
        guard let asset, !isAnalyzing, !isExporting else { return }
        isAnalyzing = true
        overlay.subjectRect = .zero
        overlay.label = nil
        statusLabel.text = "AI 正在识别画面主体…"
        statusDot.backgroundColor = DTPTheme.Palette.warm

        progressOverlay.isHidden = false
        progressOverlay.alpha = 1
        progressRing.stopSpinning()
        progressRing.setProgress(0, animated: false)
        progressTitle.text = "AI 主体分析"
        progressSubtitle.text = "正在逐帧识别并生成平滑轨迹"

        var options = DTPTrackingPlanner.Options()
        options.preferredLabels = DTPSettings.load().preferredLabels

        planner.buildPlan(for: asset, options: options, progress: { [weak self] value in
            self?.progressRing.setProgress(CGFloat(value))
        }, completion: { [weak self] result in
            guard let self else { return }
            self.isAnalyzing = false

            UIView.animate(withDuration: 0.25) {
                self.progressOverlay.alpha = 0
            } completion: { _ in
                self.progressOverlay.isHidden = true
            }

            switch result {
            case .success(let plan):
                self.plan = plan
                let label = plan.subjectLabel ?? "自动构图"
                if DTPSubjectDetector.shared.isReady, label != "自动构图" {
                    self.statusLabel.text = "已锁定主体：\(label)"
                    self.statusDot.backgroundColor = DTPTheme.Palette.mint
                } else {
                    self.statusLabel.text = "未识别到主体，已使用居中构图"
                    self.statusDot.backgroundColor = DTPTheme.Palette.warm
                }
            case .failure(let error):
                self.statusLabel.text = error.localizedDescription
                self.statusDot.backgroundColor = DTPTheme.Palette.danger
            }
            self.updatePlayerFrame()
        })
    }

    // MARK: - 播放

    @objc private func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if player.currentTime().seconds >= videoDuration - 0.05 {
                player.seek(to: .zero)
            }
            player.play()
        }
        updatePlayButton()
    }

    private func handlePlaybackTick(seconds: Double) {
        guard !isScrubbing else { return }
        timeLabel.text = format(seconds)
        if videoDuration > 0 {
            timeline.value = Float(min(max(seconds / videoDuration, 0), 1))
        }
        updatePlayerFrame()
        updatePlayButton()
    }

    private func updatePlayButton() {
        let playing = player.timeControlStatus == .playing
        guard playing != isPlayingState else { return }
        isPlayingState = playing
        playButton.setSymbol(playing ? "pause.fill" : "play.fill", pointSize: 15)
    }

    @objc private func sliderTouchDown() {
        isScrubbing = true
        player.pause()
        updatePlayButton()
    }

    @objc private func sliderChanged() {
        guard videoDuration > 0 else { return }
        let time = CMTime(seconds: Double(timeline.value) * videoDuration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        timeLabel.text = format(time.seconds)
        updatePlayerFrame()
    }

    @objc private func sliderTouchUp() {
        isScrubbing = false
    }

    @objc private func zoomChanged() {
        zoom = CGFloat(zoomSlider.value)
        zoomLabel.text = String(format: "%.1f×", zoom)
        updatePlayerFrame()
    }

    private func select(aspect newValue: DTPAspect) {
        if aspect != newValue {
            aspect = newValue
            layoutPreview()
            updatePlayerFrame()
        }
        for (value, chip) in aspectChips {
            chip.setOn(value == aspect, animated: true)
        }
    }

    // MARK: - 预览布局

    private var previewRatio: CGFloat {
        if let ratio = aspect.ratio { return ratio }
        guard displaySize.height > 0 else { return 9.0 / 16.0 }
        return displaySize.width / displaySize.height
    }

    private func layoutPreview() {
        guard previewCard.bounds.width > 1, previewCard.bounds.height > 1 else { return }
        let available = previewCard.contentView.bounds.insetBy(dx: 8, dy: 8)
        guard available.width > 1, available.height > 1 else { return }

        let ratio = previewRatio
        var size = CGSize(width: available.width, height: available.width / ratio)
        if size.height > available.height {
            size.height = available.height
            size.width = available.height * ratio
        }
        let origin = CGPoint(x: available.midX - size.width / 2,
                             y: available.midY - size.height / 2)
        videoContainer.frame = CGRect(origin: origin, size: size)
        overlay.frame = videoContainer.bounds
        updatePlayerFrame()
    }

    private func currentCenter(at seconds: Double) -> CGPoint {
        guard autoFrame, let plan, let sample = plan.sample(at: seconds) else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return sample.center
    }

    private func updatePlayerFrame() {
        guard videoContainer.bounds.width > 1, displaySize.width > 0 else { return }
        let seconds = player.currentTime().seconds
        let center = currentCenter(at: seconds)

        let crop = DTPVideoExporter.cropSize(for: aspect, displaySize: displaySize, zoom: zoom)
        let origin = DTPVideoExporter.cropOrigin(center: center, cropSize: crop, displaySize: displaySize)
        let scale = videoContainer.bounds.width / max(crop.width, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = CGRect(x: -origin.x * scale,
                                   y: -origin.y * scale,
                                   width: displaySize.width * scale,
                                   height: displaySize.height * scale)
        CATransaction.commit()

        if autoFrame, let plan, let sample = plan.sample(at: seconds) {
            overlay.subjectRect = CGRect(x: sample.box.minX * displaySize.width * scale - origin.x * scale,
                                         y: sample.box.minY * displaySize.height * scale - origin.y * scale,
                                         width: sample.box.width * displaySize.width * scale,
                                         height: sample.box.height * displaySize.height * scale)
            overlay.label = sample.label
            overlay.isHidden = false
        } else {
            overlay.subjectRect = .zero
            overlay.label = nil
            overlay.isHidden = true
        }
    }

    // MARK: - 导出

    private func startExport() {
        guard !isExporting, let asset else { return }
        guard !isAnalyzing else {
            DTPToast.show("AI 正在分析主体，稍等一下再导出", symbol: "hourglass", in: view)
            return
        }
        isExporting = true
        player.pause()
        updatePlayButton()

        let outputURL = DTPProjectStore.shared.makeExportURL(basedOn: project.name)

        progressOverlay.isHidden = false
        progressOverlay.alpha = 1
        progressRing.setProgress(0, animated: false)
        progressTitle.text = "正在导出"
        progressSubtitle.text = "保留原始音轨，按当前构图重新渲染"

        let settings = DTPSettings.load()
        let options = DTPExportOptions(aspect: aspect,
                                       zoom: zoom,
                                       autoFrame: autoFrame,
                                       stabilize: stabilize,
                                       saveToPhotos: settings.saveToPhotos)

        exporter.export(asset: asset,
                        plan: plan,
                        options: options,
                        outputURL: outputURL,
                        progress: { [weak self] value in
                            self?.progressRing.setProgress(CGFloat(value))
                        },
                        completion: { [weak self] result in
                            guard let self else { return }
                            self.isExporting = false
                            UIView.animate(withDuration: 0.25) {
                                self.progressOverlay.alpha = 0
                            } completion: { _ in
                                self.progressOverlay.isHidden = true
                            }

                            switch result {
                            case .success(let url):
                                if settings.saveToPhotos {
                                    DTPVideoExporter.saveToPhotos(url) { saveResult in
                                        switch saveResult {
                                        case .success:
                                            self.presentExportDone(url: url, message: "已保存到相册，也保留了本地文件。")
                                        case .failure(let error):
                                            self.presentExportDone(url: url, message: error.localizedDescription)
                                        }
                                    }
                                } else {
                                    self.presentExportDone(url: url, message: "文件已生成。")
                                }
                            case .failure(let error):
                                self.statusLabel.text = error.localizedDescription
                                self.statusDot.backgroundColor = DTPTheme.Palette.danger
                                DTPToast.show(error.localizedDescription, symbol: "exclamationmark.triangle", in: self.view)
                            }
                        })
    }

    private func presentExportDone(url: URL, message: String) {
        DTPHaptics.success()
        statusLabel.text = "导出完成"
        statusDot.backgroundColor = DTPTheme.Palette.mint

        let alert = UIAlertController(title: "导出完成", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
            self?.presentShare(url: url)
        })
        alert.addAction(UIAlertAction(title: "完成", style: .cancel))
        present(alert, animated: true)
    }

    private func presentShare(url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(activity, animated: true)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 主体跟踪框

private final class DTPTrackOverlayView: UIView {

    var subjectRect: CGRect = .zero {
        didSet { setNeedsDisplay() }
    }
    var label: String? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard subjectRect.width > 2, subjectRect.height > 2,
              let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        let path = UIBezierPath(roundedRect: subjectRect, cornerRadius: 12)
        DTPTheme.Palette.accent.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2
        path.stroke()

        // 四角强调
        let cornerLength: CGFloat = 14
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: subjectRect.minX, y: subjectRect.minY + cornerLength),
             CGPoint(x: subjectRect.minX, y: subjectRect.minY),
             CGPoint(x: subjectRect.minX + cornerLength, y: subjectRect.minY)),
            (CGPoint(x: subjectRect.maxX - cornerLength, y: subjectRect.minY),
             CGPoint(x: subjectRect.maxX, y: subjectRect.minY),
             CGPoint(x: subjectRect.maxX, y: subjectRect.minY + cornerLength)),
            (CGPoint(x: subjectRect.minX, y: subjectRect.maxY - cornerLength),
             CGPoint(x: subjectRect.minX, y: subjectRect.maxY),
             CGPoint(x: subjectRect.minX + cornerLength, y: subjectRect.maxY)),
            (CGPoint(x: subjectRect.maxX - cornerLength, y: subjectRect.maxY),
             CGPoint(x: subjectRect.maxX, y: subjectRect.maxY),
             CGPoint(x: subjectRect.maxX, y: subjectRect.maxY - cornerLength))
        ]
        UIColor.white.withAlphaComponent(0.92).setStroke()
        for (start, middle, end) in corners {
            let corner = UIBezierPath()
            corner.move(to: start)
            corner.addLine(to: middle)
            corner.addLine(to: end)
            corner.lineWidth = 3
            corner.lineCapStyle = .round
            corner.stroke()
        }

        if let label, !label.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: DTPTheme.font(11, .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = (label as NSString).size(withAttributes: attributes)
            let padding = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            var origin = CGPoint(x: subjectRect.minX,
                                 y: subjectRect.minY - textSize.height - padding.top - padding.bottom - 6)
            if origin.y < 4 {
                origin.y = subjectRect.minY + 6
            }
            let badgeRect = CGRect(x: origin.x,
                                   y: origin.y,
                                   width: textSize.width + padding.left + padding.right,
                                   height: textSize.height + padding.top + padding.bottom)
            let badge = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height / 2)
            DTPTheme.Palette.accent.withAlphaComponent(0.92).setFill()
            badge.fill()
            (label as NSString).draw(at: CGPoint(x: badgeRect.minX + padding.left,
                                                 y: badgeRect.minY + padding.top),
                                     withAttributes: attributes)
        }
        context.restoreGState()
    }
}
