//
//  DTPHomeViewController.swift
//  DulaTrackPro Clone
//

import UIKit

final class DTPHomeViewController: UIViewController {

    var onOpenCamera: (() -> Void)?
    var onOpenEditor: ((DTPProject) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let projectsStack = UIStackView()
    private let projectCountLabel = UILabel()
    private let totalDurationLabel = UILabel()
    private let sectionCountLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildInterface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshProjects()
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

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makeHeroCard())
        contentStack.addArrangedSubview(makeStatsRow())
        contentStack.addArrangedSubview(makeSectionHeader())
        contentStack.addArrangedSubview(makeProjectsContainer())
    }

    private func makeHeader() -> UIView {
        let container = UIView()

        let orb = DTPOrbView()
        orb.translatesAutoresizingMaskIntoConstraints = false
        orb.widthAnchor.constraint(equalToConstant: 56).isActive = true
        orb.heightAnchor.constraint(equalToConstant: 56).isActive = true
        orb.startAnimating()

        let title = UILabel()
        title.text = "毒辣剪辑"
        title.font = DTPTheme.rounded(27, .bold)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = "DulaTrackPro AI X · 本地版"
        subtitle.font = DTPTheme.font(12, .medium)
        subtitle.textColor = DTPTheme.Palette.textSecondary

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 3

        let badge = makePill(text: "AI 已就绪", symbol: "sparkles", tint: DTPTheme.Palette.mint)

        let row = UIStackView(arrangedSubviews: [orb, textStack, UIView(), badge])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        container.addSubview(row)
        row.dtpPin(to: container)
        return container
    }

    private func makeHeroCard() -> UIView {
        let card = DTPGlassCard(cornerRadius: 30)
        let content = card.contentView

        let orb = DTPOrbView()
        orb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            orb.widthAnchor.constraint(equalToConstant: 72),
            orb.heightAnchor.constraint(equalToConstant: 72)
        ])
        orb.startAnimating()

        let title = UILabel()
        title.text = "让主体永远在画面中央"
        title.font = DTPTheme.rounded(19, .bold)
        title.textColor = .white
        title.numberOfLines = 2

        let subtitle = UILabel()
        subtitle.text = "AI 识别主体、平滑运镜、自动重构构图，导出保留原画质。"
        subtitle.font = DTPTheme.font(13, .regular)
        subtitle.textColor = DTPTheme.Palette.textSecondary
        subtitle.numberOfLines = 3

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 6

        let topRow = UIStackView(arrangedSubviews: [orb, textStack])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 16

        let pills = UIStackView(arrangedSubviews: [
            makePill(text: "主体跟踪", symbol: "scope"),
            makePill(text: "防抖", symbol: "waveform.path.badge.minus"),
            makePill(text: "自动构图", symbol: "rectangle.dashed")
        ])
        pills.axis = .horizontal
        pills.spacing = 8
        pills.distribution = .fillEqually

        let importButton = DTPGlassButton(title: "导入视频", systemImage: "square.and.arrow.down", style: .prominent, height: 50)
        importButton.onTap = { [weak self] in self?.startImport() }

        let cameraButton = DTPGlassButton(title: "拍摄", systemImage: "video.fill", style: .glass, height: 50)
        cameraButton.onTap = { [weak self] in self?.onOpenCamera?() }

        let buttons = UIStackView(arrangedSubviews: [importButton, cameraButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [topRow, pills, buttons])
        stack.axis = .vertical
        stack.spacing = 16
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        return card
    }

    private func makeStatsRow() -> UIView {
        let countCard = makeStatCard(valueLabel: projectCountLabel, caption: "素材")
        let durationCard = makeStatCard(valueLabel: totalDurationLabel, caption: "素材总时长")
        let row = UIStackView(arrangedSubviews: [countCard, durationCard])
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        return row
    }

    private func makeStatCard(valueLabel: UILabel, caption: String) -> UIView {
        let card = DTPGlassCard(cornerRadius: 24)

        valueLabel.font = DTPTheme.rounded(24, .bold)
        valueLabel.textColor = .white
        valueLabel.text = "0"

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = DTPTheme.font(12, .medium)
        captionLabel.textColor = DTPTheme.Palette.textTertiary

        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 2
        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeSectionHeader() -> UIView {
        let title = UILabel()
        title.text = "最近项目"
        title.font = DTPTheme.rounded(18, .bold)
        title.textColor = .white

        sectionCountLabel.font = DTPTheme.font(12, .medium)
        sectionCountLabel.textColor = DTPTheme.Palette.textTertiary
        sectionCountLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [title, UIView(), sectionCountLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        return row
    }

    private func makeProjectsContainer() -> UIView {
        projectsStack.axis = .vertical
        projectsStack.spacing = 12
        return projectsStack
    }

    // MARK: - 刷新

    private func refreshProjects() {
        projectsStack.arrangedSubviews.forEach {
            projectsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let projects = DTPProjectStore.shared.projects
        projectCountLabel.text = "\(projects.count)"
        totalDurationLabel.text = formatDuration(projects.reduce(0) { $0 + $1.duration })
        sectionCountLabel.text = projects.isEmpty ? "" : "共 \(projects.count) 个"

        if projects.isEmpty {
            projectsStack.addArrangedSubview(makeEmptyState())
            return
        }

        for project in projects {
            let image = DTPProjectStore.shared.thumbnailURL(for: project)
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { UIImage(data: $0) }
            let row = DTPProjectRowView(project: project, thumbnail: image)
            row.onTap = { [weak self] in self?.onOpenEditor?(project) }
            row.onDelete = { [weak self] in self?.confirmDelete(project) }
            projectsStack.addArrangedSubview(row)
        }
    }

    private func makeEmptyState() -> UIView {
        let card = DTPGlassCard(cornerRadius: 26)
        let icon = UIImageView(image: UIImage(systemName: "film.stack"))
        icon.tintColor = DTPTheme.Palette.textTertiary
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)

        let title = UILabel()
        title.text = "还没有素材"
        title.font = DTPTheme.font(15, .semibold)
        title.textColor = UIColor.white.withAlphaComponent(0.82)

        let subtitle = UILabel()
        subtitle.text = "从相册导入视频，或直接拍摄一段试试。"
        subtitle.font = DTPTheme.font(12.5, .regular)
        subtitle.textColor = DTPTheme.Palette.textTertiary
        subtitle.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center

        card.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 20),
            row.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -20),
            icon.widthAnchor.constraint(equalToConstant: 26)
        ])
        return card
    }

    // MARK: - 操作

    private func startImport() {
        DTPMediaImporter.shared.present(from: self) { [weak self] projects in
            guard let self else { return }
            self.refreshProjects()
            guard !projects.isEmpty else { return }
            if projects.count == 1, let project = projects.first {
                self.onOpenEditor?(project)
            } else {
                DTPToast.show("已导入 \(projects.count) 段素材", symbol: "checkmark.circle", in: self.view)
            }
        }
    }

    private func confirmDelete(_ project: DTPProject) {
        let alert = UIAlertController(title: "删除素材？",
                                      message: "「\(project.name)」将从本地移除。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            DTPProjectStore.shared.delete(project)
            self?.refreshProjects()
            DTPHaptics.warning()
        })
        present(alert, animated: true)
    }

    // MARK: - 小工具

    private func makePill(text: String, symbol: String? = nil, tint: UIColor = DTPTheme.Palette.textSecondary) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous

        let label = UILabel()
        label.text = text
        label.font = DTPTheme.font(11.5, .semibold)
        label.textColor = tint

        let stack = UIStackView(arrangedSubviews: [])
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center

        if let symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = tint
            icon.contentMode = .scaleAspectFit
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            icon.widthAnchor.constraint(equalToConstant: 13).isActive = true
            stack.addArrangedSubview(icon)
        }
        stack.addArrangedSubview(label)
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 素材行

private final class DTPProjectRowView: DTPGlassCard, UIContextMenuInteractionDelegate {

    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    private let project: DTPProject

    init(project: DTPProject, thumbnail: UIImage?) {
        self.project = project
        super.init(cornerRadius: 24)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        let thumb = UIImageView(image: thumbnail)
        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 16
        thumb.layer.cornerCurve = .continuous
        thumb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: 62),
            thumb.heightAnchor.constraint(equalToConstant: 62)
        ])

        let title = UILabel()
        title.text = project.name
        title.font = DTPTheme.font(15, .semibold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail

        let meta = UILabel()
        meta.text = "\(project.durationText)   \(project.resolutionText)"
        meta.font = DTPTheme.mono(11.5, .medium)
        meta.textColor = DTPTheme.Palette.textTertiary

        let textStack = UIStackView(arrangedSubviews: [title, meta])
        textStack.axis = .vertical
        textStack.spacing = 4

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DTPTheme.Palette.textTertiary
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)

        let row = UIStackView(arrangedSubviews: [thumb, textStack, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 13
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11)
        ])

        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() {
        DTPHaptics.light()
        onTap?()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(title: self.project.name, children: [
                UIAction(title: "删除素材", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self.onDelete?()
                }
            ])
        }
    }
}
