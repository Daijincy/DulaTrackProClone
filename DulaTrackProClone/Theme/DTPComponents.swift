//
//  DTPComponents.swift
//  DulaTrackPro Clone
//
//  一套小而完整的液态玻璃控件。
//

import UIKit

// MARK: - 玻璃卡片

final class DTPGlassCard: UIView {

    let contentView = UIView()
    private let glass: UIVisualEffectView
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DTPTheme.Metric.cardCorner, interactive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.glass = DTPGlass.makeView(cornerRadius: cornerRadius, interactive: interactive)
        super.init(frame: .zero)
        backgroundColor = .clear

        glass.isUserInteractionEnabled = interactive
        addSubview(glass)
        glass.dtpPin(to: self)

        contentView.backgroundColor = .clear
        glass.contentView.addSubview(contentView)
        contentView.dtpPin(to: glass.contentView)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.30
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 14)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }
}

// MARK: - 玻璃按钮

final class DTPGlassButton: UIControl {

    enum Style { case glass, prominent, subtle }

    var onTap: (() -> Void)?

    private let style: Style
    private let baseView: UIView
    private let gradientLayer = CAGradientLayer()
    private let highlightView = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let contentStack = UIStackView()
    private var effectView: UIVisualEffectView?

    init(title: String,
         systemImage: String? = nil,
         style: Style = .glass,
         height: CGFloat = 52,
         cornerRadius: CGFloat = DTPTheme.Metric.controlCorner) {
        self.style = style

        switch style {
        case .glass:
            let effect = DTPGlass.makeView(cornerRadius: cornerRadius, interactive: true)
            baseView = effect
            effectView = effect
        case .prominent:
            let host = UIView()
            host.clipsToBounds = true
            host.layer.cornerRadius = cornerRadius
            host.layer.cornerCurve = .continuous
            baseView = host
        case .subtle:
            let host = UIView()
            host.clipsToBounds = true
            host.layer.cornerRadius = cornerRadius
            host.layer.cornerCurve = .continuous
            host.backgroundColor = UIColor.white.withAlphaComponent(0.07)
            baseView = host
        }

        super.init(frame: .zero)
        backgroundColor = .clear

        baseView.isUserInteractionEnabled = false
        addSubview(baseView)
        baseView.dtpPin(to: self)

        if style == .prominent {
            gradientLayer.colors = [DTPTheme.Palette.accent.cgColor,
                                    DTPTheme.Palette.violet.cgColor]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.3)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.7)
            baseView.layer.addSublayer(gradientLayer)
        }

        highlightView.backgroundColor = .white
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        baseView.addSubview(highlightView)
        highlightView.dtpPin(to: baseView)

        titleLabel.text = title
        titleLabel.font = DTPTheme.rounded(16, .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(style == .subtle ? 0.82 : 0.98)
        titleLabel.numberOfLines = 1
        titleLabel.isUserInteractionEnabled = false

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.isUserInteractionEnabled = false

        if let systemImage, let image = UIImage(systemName: systemImage) {
            iconView.image = image
            iconView.tintColor = titleLabel.textColor
            iconView.contentMode = .scaleAspectFit
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            let size = iconView.widthAnchor.constraint(equalToConstant: 20)
            iconView.addConstraint(size)
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor).isActive = true
            contentStack.addArrangedSubview(iconView)
        }
        contentStack.addArrangedSubview(titleLabel)

        addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            heightAnchor.constraint(equalToConstant: height)
        ])

        addTarget(self, action: #selector(handleTouchUp), for: .touchUpInside)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if style == .prominent {
            gradientLayer.frame = bounds
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.965, y: 0.965) : .identity
                self.highlightView.alpha = self.isHighlighted ? 0.14 : 0
            }
        }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.45 }
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }

    @objc private func handleTouchUp() {
        DTPHaptics.light()
        onTap?()
    }
}

// MARK: - 圆形图标按钮

final class DTPIconButton: UIControl {

    var onTap: (() -> Void)?
    private let glass: UIVisualEffectView
    private let iconView = UIImageView()

    init(systemImage: String, diameter: CGFloat = 44, tint: UIColor = .white) {
        glass = DTPGlass.makeView(cornerRadius: diameter / 2, interactive: true)
        super.init(frame: .zero)

        glass.isUserInteractionEnabled = false
        addSubview(glass)
        glass.dtpPin(to: self)

        iconView.image = UIImage(systemName: systemImage)
        iconView.tintColor = tint
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])

        addTarget(self, action: #selector(handleTouchUp), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String, pointSize: CGFloat = 17) {
        iconView.image = UIImage(systemName: name,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize,
                                                                                weight: .semibold))
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }

    @objc private func handleTouchUp() {
        DTPHaptics.light()
        onTap?()
    }
}

// MARK: - 可选中的胶囊开关

final class DTPChip: UIControl {

    var onToggle: ((Bool) -> Void)?
    private(set) var isOn: Bool = false

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let stack = UIStackView()
    private let accentBorder = CALayer()

    init(title: String, systemImage: String? = nil, isOn: Bool = false) {
        super.init(frame: .zero)

        layer.cornerRadius = 19
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.8
        backgroundColor = UIColor.white.withAlphaComponent(0.06)

        titleLabel.text = title
        titleLabel.font = DTPTheme.font(13.5, .semibold)
        titleLabel.textColor = DTPTheme.Palette.textSecondary

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false

        if let systemImage, let image = UIImage(systemName: systemImage) {
            iconView.image = image
            iconView.tintColor = DTPTheme.Palette.textSecondary
            iconView.contentMode = .scaleAspectFit
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(iconView)
        }
        stack.addArrangedSubview(titleLabel)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            heightAnchor.constraint(equalToConstant: 38)
        ])

        addTarget(self, action: #selector(handleTouchUp), for: .touchUpInside)
        setOn(isOn, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        let apply = {
            self.backgroundColor = on
                ? DTPTheme.Palette.accent.withAlphaComponent(0.22)
                : UIColor.white.withAlphaComponent(0.06)
            self.layer.borderColor = (on
                ? DTPTheme.Palette.accent.withAlphaComponent(0.55)
                : UIColor.white.withAlphaComponent(0.10)).cgColor
            self.titleLabel.textColor = on ? UIColor.white : DTPTheme.Palette.textSecondary
            self.iconView.tintColor = on ? DTPTheme.Palette.accent : DTPTheme.Palette.textSecondary
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                apply()
            }
        } else {
            apply()
        }
        accessibilityTraits = on ? [.button, .selected] : .button
    }

    @objc private func handleTouchUp() {
        DTPHaptics.light()
        setOn(!isOn, animated: true)
        onToggle?(isOn)
    }
}

// MARK: - 进度环

final class DTPProgressRing: UIView {

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let lineWidth: CGFloat
    private var progress: CGFloat = 0
    private var isSpinning = false

    let captionLabel = UILabel()

    init(diameter: CGFloat = 64,
         lineWidth: CGFloat = 5,
         tint: UIColor = DTPTheme.Palette.accent,
         showsCaption: Bool = true) {
        self.lineWidth = lineWidth
        super.init(frame: .zero)

        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.12).cgColor
        trackLayer.lineWidth = lineWidth
        layer.addSublayer(trackLayer)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = tint.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)

        captionLabel.font = DTPTheme.mono(13, .semibold)
        captionLabel.textColor = .white
        captionLabel.textAlignment = .center
        captionLabel.isHidden = !showsCaption
        addSubview(captionLabel)
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            captionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            captionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = UIBezierPath(ovalIn: rect).cgPath
        trackLayer.path = path
        progressLayer.path = path
        trackLayer.frame = bounds
        progressLayer.frame = bounds
    }

    func setProgress(_ value: CGFloat, animated: Bool = true) {
        progress = min(max(value, 0), 1)
        captionLabel.text = "\(Int((progress * 100).rounded()))%"
        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
            animation.toValue = progress
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressLayer.strokeEnd = progress
            progressLayer.add(animation, forKey: "strokeEnd")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = progress
            CATransaction.commit()
        }
    }

    func startSpinning() {
        guard !isSpinning else { return }
        isSpinning = true
        captionLabel.isHidden = false
        captionLabel.text = "AI"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0.22
        CATransaction.commit()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1.1
        spin.repeatCount = .greatestFiniteMagnitude
        progressLayer.add(spin, forKey: "spin")
    }

    func stopSpinning() {
        guard isSpinning else { return }
        isSpinning = false
        progressLayer.removeAnimation(forKey: "spin")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeStart = 0
        CATransaction.commit()
    }
}

// MARK: - 线性进度条

final class DTPProgressBar: UIView {

    private let track = UIView()
    private let fill = UIView()
    private let fillLayer = CAGradientLayer()
    private var fillWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        track.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        addSubview(track)
        track.dtpPin(to: self)

        fill.clipsToBounds = true
        fillLayer.colors = [DTPTheme.Palette.accent.cgColor, DTPTheme.Palette.mint.cgColor]
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fill.layer.addSublayer(fillLayer)
        addSubview(fill)
        fill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let width = fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.001)
        width.isActive = true
        fillWidthConstraint = width
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        track.layer.cornerRadius = bounds.height / 2
        fill.layer.cornerRadius = bounds.height / 2
        fillLayer.frame = fill.bounds
    }

    /// 0...1
    func setProgress(_ value: CGFloat, animated: Bool) {
        let clamped = min(max(value, 0.001), 1)
        fillWidthConstraint?.isActive = false
        let newConstraint = fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: clamped)
        newConstraint.isActive = true
        fillWidthConstraint = newConstraint
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState]) {
                self.layoutIfNeeded()
            }
        }
    }
}

// MARK: - 渐变光球（首页视觉）

final class DTPOrbView: UIView {

    private let gradient = CAGradientLayer()
    private let innerCircle = UIView()
    private let iconView = UIImageView()
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        gradient.type = .conic
        gradient.colors = [DTPTheme.Palette.accent.cgColor,
                           DTPTheme.Palette.violet.cgColor,
                           DTPTheme.Palette.mint.cgColor,
                           DTPTheme.Palette.accent.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)

        innerCircle.backgroundColor = DTPTheme.Palette.background.withAlphaComponent(0.82)
        innerCircle.layer.borderWidth = 1
        innerCircle.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        addSubview(innerCircle)

        iconView.image = UIImage(systemName: "viewfinder")
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = bounds.width / 2
        let inset = bounds.width * 0.14
        innerCircle.frame = bounds.insetBy(dx: inset, dy: inset)
        innerCircle.layer.cornerRadius = innerCircle.bounds.width / 2
        iconView.frame = bounds.insetBy(dx: bounds.width * 0.34, dy: bounds.height * 0.34)
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 9
        spin.repeatCount = .greatestFiniteMagnitude
        gradient.add(spin, forKey: "spin")
    }
}

// MARK: - Toast / 触感

enum DTPToast {
    static func show(_ message: String,
                     symbol: String = "sparkles",
                     in view: UIView,
                     duration: TimeInterval = 2.2) {
        view.viewWithTag(0xD7A9)?.removeFromSuperview()

        let card = DTPGlassCard(cornerRadius: 20)
        card.tag = 0xD7A9
        card.isUserInteractionEnabled = false

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = DTPTheme.Palette.accent
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        let label = UILabel()
        label.text = message
        label.font = DTPTheme.font(14, .medium)
        label.textColor = .white
        label.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 18)
        ])

        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -116),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
        ])

        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut]) {
            card.alpha = 1
            card.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: duration, options: [.curveEaseIn]) {
                card.alpha = 0
                card.transform = CGAffineTransform(translationX: 0, y: 8)
            } completion: { _ in
                card.removeFromSuperview()
            }
        }
    }
}

enum DTPHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
