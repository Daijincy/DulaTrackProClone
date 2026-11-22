//
//  DTPRootController.swift
//  DulaTrackPro Clone
//
//  自定义根容器：内容区 + 悬浮液态玻璃标签栏。
//

import UIKit

final class DTPRootController: UIViewController {

    private let contentView = UIView()
    private let tabBar: DTPTabBar

    private lazy var homeController = DTPHomeViewController()
    private lazy var cameraController = DTPCameraViewController()
    private lazy var batchController = DTPBatchViewController()
    private lazy var settingsController = DTPSettingsViewController()
    private lazy var tabControllers: [UIViewController] = [homeController,
                                                            cameraController,
                                                            batchController,
                                                            settingsController]

    private var selectedIndex = -1

    init() {
        tabBar = DTPTabBar(items: [
            DTPTabBar.Item(title: "首页", symbol: "house.fill"),
            DTPTabBar.Item(title: "拍摄", symbol: "video.fill"),
            DTPTabBar.Item(title: "批量", symbol: "square.stack.3d.up.fill"),
            DTPTabBar.Item(title: "设置", symbol: "gearshape.fill")
        ])
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DTPTheme.Palette.background

        let backdrop = DTPBackdropView()
        view.addSubview(backdrop)
        backdrop.dtpPin(to: view)

        contentView.backgroundColor = .clear
        view.dtpAddSubviews(contentView, tabBar)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                            constant: DTPTheme.Metric.tabBarInset),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                             constant: -DTPTheme.Metric.tabBarInset),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            tabBar.heightAnchor.constraint(equalToConstant: DTPTheme.Metric.tabBarHeight)
        ])

        tabBar.onSelect = { [weak self] index in
            self?.select(index: index)
        }

        homeController.onOpenCamera = { [weak self] in
            self?.select(index: 1)
        }
        homeController.onOpenEditor = { [weak self] project in
            self?.presentEditor(for: project)
        }
        cameraController.onFinishRecording = { [weak self] project in
            self?.presentEditor(for: project)
        }
        batchController.onOpenEditor = { [weak self] project in
            self?.presentEditor(for: project)
        }

        select(index: 0)
        backdrop.startAnimating()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - 切换

    private func select(index: Int) {
        guard index >= 0, index < tabControllers.count, index != selectedIndex else { return }
        let hadSelection = selectedIndex >= 0

        if selectedIndex >= 0 {
            let old = tabControllers[selectedIndex]
            old.willMove(toParent: nil)
            old.beginAppearanceTransition(false, animated: false)
            old.view.removeFromSuperview()
            old.endAppearanceTransition()
            old.removeFromParent()
        }

        let new = tabControllers[index]
        addChild(new)
        new.beginAppearanceTransition(true, animated: false)
        new.view.frame = contentView.bounds
        new.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        new.view.alpha = 0
        contentView.addSubview(new.view)
        new.endAppearanceTransition()
        new.didMove(toParent: self)

        UIView.animate(withDuration: 0.22) {
            new.view.alpha = 1
        }

        selectedIndex = index
        tabBar.setSelected(index: index, animated: hadSelection)
    }

    func presentEditor(for project: DTPProject) {
        let editor = DTPEditorViewController(project: project)
        editor.modalPresentationStyle = .fullScreen
        present(editor, animated: true)
    }
}

// MARK: - 悬浮玻璃标签栏

final class DTPTabBar: UIView {

    struct Item {
        let title: String
        let symbol: String
    }

    var onSelect: ((Int) -> Void)?

    private let items: [Item]
    private let glass = DTPGlass.makeView(cornerRadius: DTPTheme.Metric.tabBarHeight / 2)
    private let stack = UIStackView()
    private let selectionView = UIView()
    private var buttons: [UIButton] = []
    private var selectedIndex = 0

    init(items: [Item]) {
        self.items = items
        super.init(frame: .zero)
        backgroundColor = .clear

        glass.isUserInteractionEnabled = false
        addSubview(glass)
        glass.dtpPin(to: self)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 12)

        selectionView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        selectionView.layer.cornerRadius = 20
        selectionView.layer.cornerCurve = .continuous
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        for (index, item) in items.enumerated() {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: item.symbol)
            config.title = item.title
            config.imagePlacement = .top
            config.imagePadding = 3
            config.baseForegroundColor = DTPTheme.Palette.textSecondary
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = DTPTheme.font(10, .semibold)
                return outgoing
            }
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)

            let button = UIButton(configuration: config)
            button.tag = index
            button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        updateSelectionColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(index: Int, animated: Bool) {
        guard index >= 0, index < buttons.count else { return }
        selectedIndex = index
        updateSelectionColors()
        layoutSelection(animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds,
                                        cornerRadius: bounds.height / 2).cgPath
        layoutSelection(animated: false)
    }

    private func layoutSelection(animated: Bool) {
        guard selectedIndex < buttons.count else { return }
        let button = buttons[selectedIndex]
        guard button.bounds.width > 0 else { return }
        let target = button.convert(button.bounds, to: self).insetBy(dx: 4, dy: 2)
        if animated {
            UIView.animate(withDuration: 0.28,
                           delay: 0,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.6,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.selectionView.frame = target
            }
        } else {
            selectionView.frame = target
        }
    }

    private func updateSelectionColors() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.configuration?.baseForegroundColor = selected ? .white : DTPTheme.Palette.textSecondary
            button.configuration?.image = UIImage(systemName: items[index].symbol,
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 17,
                                                                                                 weight: selected ? .semibold : .regular))
        }
    }

    @objc private func handleTap(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        DTPHaptics.light()
        onSelect?(sender.tag)
    }
}
