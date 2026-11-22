//
//  DTPBatchViewController.swift
//  DulaTrackPro Clone
//

import UIKit
import AVFoundation

@MainActor
final class DTPBatchViewController: UIViewController {

    var onOpenEditor: ((DTPProject) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let listStack = UIStackView()
    private let summaryLabel = UILabel()
    private let startButton = DTPGlassButton(title: "开始全部处理",
                                             systemImage: "bolt.fill",
                                             style: .prominent,
                                             height: 52)
    private let countLabel = UILabel()

    private var rows: [UUID: DTPBatchRowView] = [:]
    private let planner = DTPTrackingPlanner()
    private let exporter = DTPVideoExporter()
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildInterface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: - 界面

    private func buildInterface() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scrollView.contentInset.bottom = DTPTheme.Metric.contentBottomInset

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 24, right: 20)
        scrollView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let title = UILabel()
        title.text = "批量处理"
        title.font = DTPTheme.rounded(27, .bold)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = "一次排队处理多段素材，全部使用 AI 主体跟踪与防抖。"
        subtitle.font = DTPTheme.font(13, .regular)
        subtitle.textColor = DTPTheme.Palette.textSecondary
        subtitle.numberOfLines = 2

        let header = UIStackView(arrangedSubviews: [title, subtitle])
        header.axis = .vertical
        header.spacing = 4

        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(makeRunCard())
        contentStack.addArrangedSubview(makeSectionHeader())
        contentStack.addArrangedSubview(makeListContainer())
    }

    private func makeRunCard() -> UIView {
        let card = DTPGlassCard(cornerRadius: 28)

        summaryLabel.font = DTPTheme.font(12.5, .medium)
        summaryLabel.textColor = DTPTheme.Palette.textSecondary
        summaryLabel.numberOfLines = 2

        let icon = UIImageView(image: UIImage(systemName: "wand.and.stars"))
        icon.tintColor = DTPTheme.Palette.accent
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let row = UIStackView(arrangedSubviews: [icon, summaryLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10

        startButton.onTap = { [weak self] in self?.startAll() }

        let stack = UIStackView(arrangedSubviews: [row, startButton])
        stack.axis = .vertical
        stack.spacing = 14
        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeSectionHeader() -> UIView {
        let title = UILabel()
        title.text = "处理队列"
        title.font = DTPTheme.rounded(18, .bold)
        title.textColor = .white

        countLabel.font = DTPTheme.font(12, .medium)
        countLabel.textColor = DTPTheme.Palette.textTertiary
        countLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [title, UIView(), countLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        return row
    }

    private func makeListContainer() -> UIView {
        listStack.axis = .vertical
        listStack.spacing = 12
        return listStack
    }

    // MARK: - 刷新

    private func refresh() {
        let settings = DTPSettings.load()
        var summaryParts = [settings.aspect.title, "主体跟踪"]
        if settings.stabilize { summaryParts.append("防抖") }
        if settings.saveToPhotos { summaryParts.append("保存到相册") }
        summaryLabel.text = "默认流程 · " + summaryParts.joined(separator: " · ")

        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()

        let projects = DTPProjectStore.shared.projects
        countLabel.text = projects.isEmpty ? "" : "\(projects.count) 段素材"

        guard !projects.isEmpty else {
            let empty = UILabel()
            empty.text = "还没有可处理的素材，先去首页导入吧。"
            empty.font = DTPTheme.font(13, .regular)
            empty.textColor = DTPTheme.Palette.textTertiary
            empty.numberOfLines = 2
            empty.textAlignment = .center
            listStack.addArrangedSubview(empty)
            return
        }

        for project in projects {
            let image = DTPProjectStore.shared.thumbnailURL(for: project)
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { UIImage(data: $0) }
            let row = DTPBatchRowView(project: project, thumbnail: image)
            row.onTap = { [weak self] in
                self?.onOpenEditor?(project)
            }
            rows[project.id] = row
            listStack.addArrangedSubview(row)
        }
    }

    // MARK: - 队列

    private func startAll() {
        guard !isRunning else { return }
        let projects = DTPProjectStore.shared.projects
        guard !projects.isEmpty else {
            DTPToast.show("先导入素材再批量处理", symbol: "tray", in: view)
            return
        }

        isRunning = true
        updateStartButton(total: projects.count, current: 0)
        let settings = DTPSettings.load()

        Task { @MainActor in
            for (index, project) in projects.enumerated() {
                guard let row = rows[project.id] else { continue }
                updateStartButton(total: projects.count, current: index + 1)

                let asset = AVURLAsset(url: DTPProjectStore.shared.mediaURL(for: project))
                row.setStatus("分析中", color: DTPTheme.Palette.accent, progress: 0)
                let plan = await buildPlan(for: asset, row: row)

                row.setStatus("导出中", color: DTPTheme.Palette.mint, progress: 0)
                let outputURL = DTPProjectStore.shared.makeExportURL(basedOn: project.name)
                let options = DTPExportOptions(aspect: settings.aspect,
                                               zoom: 1,
                                               autoFrame: true,
                                               stabilize: settings.stabilize,
                                               saveToPhotos: settings.saveToPhotos)
                let result = await runExport(asset: asset, plan: plan, options: options, outputURL: outputURL, row: row)

                switch result {
                case .success(let url):
                    if settings.saveToPhotos {
                        _ = await saveToPhotos(url)
                    }
                    row.setStatus("完成", color: DTPTheme.Palette.mint, progress: 1)
                case .failure(let error):
                    row.setStatus("失败", color: DTPTheme.Palette.danger, progress: 0)
                    row.setDetail(error.localizedDescription)
                }
            }

            isRunning = false
            startButton.isEnabled = true
            startButton.setTitle("开始全部处理")
            DTPHaptics.success()
            DTPToast.show("批量处理完成", symbol: "checkmark.circle", in: view)
        }
    }

    private func updateStartButton(total: Int, current: Int) {
        if isRunning {
            startButton.isEnabled = false
            startButton.setTitle("处理中 \(current)/\(total)")
        }
    }

    private func buildPlan(for asset: AVAsset, row: DTPBatchRowView) async -> DTPTrackPlan? {
        let settings = DTPSettings.load()
        var options = DTPTrackingPlanner.Options()
        options.preferredLabels = settings.preferredLabels
        return await withCheckedContinuation { continuation in
            planner.buildPlan(for: asset, options: options, progress: { value in
                row.setProgress(CGFloat(value))
            }, completion: { result in
                continuation.resume(returning: try? result.get())
            })
        }
    }

    private func runExport(asset: AVAsset,
                           plan: DTPTrackPlan?,
                           options: DTPExportOptions,
                           outputURL: URL,
                           row: DTPBatchRowView) async -> Result<URL, Error> {
        await withCheckedContinuation { continuation in
            exporter.export(asset: asset,
                            plan: plan,
                            options: options,
                            outputURL: outputURL,
                            progress: { value in
                                row.setProgress(CGFloat(value))
                            },
                            completion: { result in
                                continuation.resume(returning: result)
                            })
        }
    }

    private func saveToPhotos(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DTPVideoExporter.saveToPhotos(url) { result in
                if case .success = result {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - 队列行

private final class DTPBatchRowView: DTPGlassCard {

    var onTap: (() -> Void)?

    private let project: DTPProject
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressBar = DTPProgressBar()
    private let thumb = UIImageView()

    init(project: DTPProject, thumbnail: UIImage?) {
        self.project = project
        super.init(cornerRadius: 24)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        thumb.image = thumbnail
        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 14
        thumb.layer.cornerCurve = .continuous
        thumb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: 52),
            thumb.heightAnchor.constraint(equalToConstant: 52)
        ])

        let title = UILabel()
        title.text = project.name
        title.font = DTPTheme.font(14.5, .semibold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail

        detailLabel.font = DTPTheme.mono(11, .medium)
        detailLabel.textColor = DTPTheme.Palette.textTertiary
        detailLabel.text = "\(project.durationText)  \(project.resolutionText)"
        detailLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [title, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        statusLabel.font = DTPTheme.font(11.5, .semibold)
        statusLabel.textColor = DTPTheme.Palette.textTertiary
        statusLabel.text = "待处理"
        statusLabel.textAlignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [thumb, textStack, statusLabel])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 12

        progressBar.isHidden = true
        progressBar.setProgress(0, animated: false)

        let stack = UIStackView(arrangedSubviews: [topRow, progressBar])
        stack.axis = .vertical
        stack.spacing = 10
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStatus(_ text: String, color: UIColor, progress: CGFloat) {
        statusLabel.text = text
        statusLabel.textColor = color
        progressBar.isHidden = progress <= 0 || text == "完成"
        if progress > 0 {
            setProgress(progress)
        }
    }

    func setProgress(_ value: CGFloat) {
        if progressBar.isHidden, value > 0 {
            progressBar.isHidden = false
        }
        progressBar.setProgress(value, animated: true)
    }

    func setDetail(_ text: String) {
        detailLabel.text = text
    }

    @objc private func handleTap() {
        DTPHaptics.light()
        onTap?()
    }
}
