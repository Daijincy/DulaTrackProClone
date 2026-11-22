//
//  DTPSettingsViewController.swift
//  DulaTrackPro Clone
//

import UIKit

@MainActor
final class DTPSettingsViewController: UIViewController {

    private var settings = DTPSettings.load()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var aspectChips: [DTPAspect: DTPChip] = [:]

    private let primaryLabels = ["人物", "汽车", "汽车内部前排", "车牌", "方向盘", "多媒体屏幕"]
    private var labelChecks: [String: UIImageView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildInterface()
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
        contentStack.spacing = 16
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
        title.text = "设置"
        title.font = DTPTheme.rounded(27, .bold)
        title.textColor = .white

        let subtitle = UILabel()
        subtitle.text = "导出偏好与 AI 识别策略，只保存在本机。"
        subtitle.font = DTPTheme.font(13, .regular)
        subtitle.textColor = DTPTheme.Palette.textSecondary

        let header = UIStackView(arrangedSubviews: [title, subtitle])
        header.axis = .vertical
        header.spacing = 4

        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(makeSectionTitle("导出默认"))
        contentStack.addArrangedSubview(makeExportCard())
        contentStack.addArrangedSubview(makeSectionTitle("AI 主体优先"))
        contentStack.addArrangedSubview(makeLabelCard())
        contentStack.addArrangedSubview(makeSectionTitle("关于"))
        contentStack.addArrangedSubview(makeAboutCard())
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = DTPTheme.rounded(17, .bold)
        label.textColor = .white
        return label
    }

    private func makeExportCard() -> UIView {
        let card = DTPGlassCard(cornerRadius: 28)

        let aspectTitle = UILabel()
        aspectTitle.text = "默认输出画幅"
        aspectTitle.font = DTPTheme.font(12.5, .medium)
        aspectTitle.textColor = DTPTheme.Palette.textSecondary

        let aspectRow = UIStackView()
        aspectRow.axis = .horizontal
        aspectRow.spacing = 8
        aspectRow.distribution = .fillEqually

        for value in DTPAspect.allCases {
            let chip = DTPChip(title: value.title, isOn: settings.aspect == value)
            chip.onToggle = { [weak self] _ in
                guard let self else { return }
                self.settings.aspect = value
                self.settings.save()
                for (key, item) in self.aspectChips {
                    item.setOn(key == self.settings.aspect, animated: true)
                }
            }
            aspectChips[value] = chip
            aspectRow.addArrangedSubview(chip)
        }

        let photoSwitch = makeSwitch(isOn: settings.saveToPhotos) { [weak self] value in
            self?.settings.saveToPhotos = value
            self?.settings.save()
        }
        let stabilizeSwitch = makeSwitch(isOn: settings.stabilize) { [weak self] value in
            self?.settings.stabilize = value
            self?.settings.save()
        }
        let trackSwitch = makeSwitch(isOn: settings.autoFrame) { [weak self] value in
            self?.settings.autoFrame = value
            self?.settings.save()
        }

        let stack = UIStackView(arrangedSubviews: [
            aspectTitle,
            aspectRow,
            makeSwitchRow(title: "导出后保存到相册",
                          subtitle: "关闭时只保留本地文件，可手动分享。",
                          control: photoSwitch),
            makeSeparator(),
            makeSwitchRow(title: "默认开启防抖",
                          subtitle: "对轨迹做平滑处理，减少手持抖动。",
                          control: stabilizeSwitch),
            makeSeparator(),
            makeSwitchRow(title: "默认开启主体跟踪",
                          subtitle: "自动把识别到的主体放在画面中心。",
                          control: trackSwitch)
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(16, after: aspectRow)

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

    private func makeLabelCard() -> UIView {
        let card = DTPGlassCard(cornerRadius: 28)

        let hint = UILabel()
        hint.text = "检测到多个候选时，优先锁定这些类别。"
        hint.font = DTPTheme.font(12, .regular)
        hint.textColor = DTPTheme.Palette.textTertiary
        hint.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [hint])
        stack.axis = .vertical
        stack.spacing = 6

        for (index, name) in primaryLabels.enumerated() {
            let row = makeLabelRow(name: name, tag: index)
            stack.addArrangedSubview(row)
            if index < primaryLabels.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }

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

    private func makeLabelRow(name: String, tag: Int) -> UIControl {
        let control = UIControl()

        let label = UILabel()
        label.text = name
        label.font = DTPTheme.font(14, .medium)
        label.textColor = .white

        let check = UIImageView()
        check.tintColor = DTPTheme.Palette.accent
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        check.contentMode = .scaleAspectFit
        labelChecks[name] = check

        let row = UIStackView(arrangedSubviews: [label, UIView(), check])
        row.axis = .horizontal
        row.alignment = .center
        row.isUserInteractionEnabled = false

        control.tag = tag
        control.addTarget(self, action: #selector(labelRowTapped(_:)), for: .touchUpInside)
        control.addSubview(row)
        row.dtpPin(to: control, insets: UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0))

        updateLabelCheck(name)
        return control
    }

    private func updateLabelCheck(_ name: String) {
        let active = settings.preferredLabels.contains(name)
        labelChecks[name]?.image = UIImage(systemName: active ? "checkmark.circle.fill" : "circle")
        labelChecks[name]?.tintColor = active ? DTPTheme.Palette.accent : DTPTheme.Palette.textTertiary
    }

    private func makeAboutCard() -> UIView {
        let card = DTPGlassCard(cornerRadius: 28)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.8"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let glassState = DTPGlass.isLiquidGlassAvailable ? "液态玻璃已启用" : "兼容毛玻璃模式"

        let rows = [
            ("版本", "\(version) (\(build)) · 克隆版"),
            ("授权", "无订阅 · 全部功能可用"),
            ("处理方式", "100% 本地，不上传素材"),
            ("AI 模型", "DulaAI 内容检测 v1 · 20 类"),
            ("界面材质", glassState)
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        for (index, item) in rows.enumerated() {
            let key = UILabel()
            key.text = item.0
            key.font = DTPTheme.font(12.5, .medium)
            key.textColor = DTPTheme.Palette.textTertiary

            let value = UILabel()
            value.text = item.1
            value.font = DTPTheme.font(12.5, .medium)
            value.textColor = DTPTheme.Palette.textSecondary
            value.textAlignment = .right
            value.numberOfLines = 2

            let row = UIStackView(arrangedSubviews: [key, UIView(), value])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 12
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }

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

    // MARK: - 控件

    private func makeSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = DTPTheme.Palette.accentDeep
        toggle.addAction(UIAction { _ in
            DTPHaptics.light()
            onChange(toggle.isOn)
        }, for: .valueChanged)
        return toggle
    }

    private func makeSwitchRow(title: String, subtitle: String, control: UISwitch) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = DTPTheme.font(14, .semibold)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = DTPTheme.font(11.5, .regular)
        subtitleLabel.textColor = DTPTheme.Palette.textTertiary
        subtitleLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let row = UIStackView(arrangedSubviews: [textStack, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    @objc private func labelRowTapped(_ sender: UIControl) {
        guard sender.tag >= 0, sender.tag < primaryLabels.count else { return }
        let name = primaryLabels[sender.tag]

        if let index = settings.preferredLabels.firstIndex(of: name) {
            settings.preferredLabels.remove(at: index)
        } else {
            settings.preferredLabels.append(name)
        }
        settings.save()
        updateLabelCheck(name)
        DTPHaptics.light()
    }
}
