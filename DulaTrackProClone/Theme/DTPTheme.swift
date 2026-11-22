//
//  DTPTheme.swift
//  DulaTrackPro Clone
//
//  视觉基调：深色底 + 高饱和光晕，给液态玻璃提供折射内容。
//

import UIKit

enum DTPTheme {

    enum Palette {
        static let background = UIColor(red: 0.035, green: 0.039, blue: 0.055, alpha: 1)
        static let backgroundLift = UIColor(red: 0.075, green: 0.090, blue: 0.135, alpha: 1)
        static let accent = UIColor(red: 0.420, green: 0.760, blue: 1.000, alpha: 1)
        static let accentDeep = UIColor(red: 0.180, green: 0.440, blue: 0.980, alpha: 1)
        static let violet = UIColor(red: 0.635, green: 0.455, blue: 1.000, alpha: 1)
        static let mint = UIColor(red: 0.400, green: 0.930, blue: 0.780, alpha: 1)
        static let warm = UIColor(red: 1.000, green: 0.620, blue: 0.360, alpha: 1)
        static let danger = UIColor(red: 1.000, green: 0.360, blue: 0.400, alpha: 1)
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor.white.withAlphaComponent(0.64)
        static let textTertiary = UIColor.white.withAlphaComponent(0.38)
        static let hairline = UIColor.white.withAlphaComponent(0.12)
        static let glassBorder = UIColor.white.withAlphaComponent(0.16)
    }

    enum Metric {
        static let screenInset: CGFloat = 20
        static let cardCorner: CGFloat = 28
        static let controlCorner: CGFloat = 22
        static let pillCorner: CGFloat = 18
        static let tabBarInset: CGFloat = 18
        static let tabBarHeight: CGFloat = 64
        static let contentBottomInset: CGFloat = 118
    }

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - 布局小工具

extension UIView {
    func dtpAddSubviews(_ views: UIView...) {
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
    }

    @discardableResult
    func dtpPin(to other: UIView, insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
}

// MARK: - 背景

/// 深色渐变 + 缓慢漂移的彩色光晕。液态玻璃需要有内容可以折射，否则会像一块灰膜。
final class DTPBackdropView: UIView {

    private let baseGradient = CAGradientLayer()
    private let blobs: [CAGradientLayer] = [CAGradientLayer(), CAGradientLayer(), CAGradientLayer()]
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = DTPTheme.Palette.background
        clipsToBounds = true

        baseGradient.colors = [
            UIColor(red: 0.075, green: 0.090, blue: 0.135, alpha: 1).cgColor,
            DTPTheme.Palette.background.cgColor,
            UIColor(red: 0.020, green: 0.022, blue: 0.035, alpha: 1).cgColor
        ]
        baseGradient.startPoint = CGPoint(x: 0.1, y: 0)
        baseGradient.endPoint = CGPoint(x: 0.9, y: 1)
        layer.addSublayer(baseGradient)

        configureBlob(blobs[0], color: DTPTheme.Palette.accentDeep)
        configureBlob(blobs[1], color: DTPTheme.Palette.violet)
        configureBlob(blobs[2], color: DTPTheme.Palette.mint)
        blobs.forEach { layer.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureBlob(_ blob: CAGradientLayer, color: UIColor) {
        blob.type = .radial
        blob.colors = [color.withAlphaComponent(0.42).cgColor,
                       color.withAlphaComponent(0.12).cgColor,
                       color.withAlphaComponent(0).cgColor]
        blob.locations = [0, 0.45, 1]
        blob.startPoint = CGPoint(x: 0.5, y: 0.5)
        blob.endPoint = CGPoint(x: 1.05, y: 1.05)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseGradient.frame = bounds
        let w = max(bounds.width, 320)
        let h = max(bounds.height, 320)
        blobs[0].frame = CGRect(x: -w * 0.42, y: -h * 0.08, width: w * 0.95, height: w * 0.95)
        blobs[1].frame = CGRect(x: w * 0.42, y: h * 0.10, width: w * 0.9, height: w * 0.9)
        blobs[2].frame = CGRect(x: -w * 0.10, y: h * 0.52, width: w * 0.75, height: w * 0.75)
        CATransaction.commit()
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        animateBlob(blobs[0], dx: 28, dy: 46, duration: 13)
        animateBlob(blobs[1], dx: -34, dy: -30, duration: 17)
        animateBlob(blobs[2], dx: 20, dy: -44, duration: 15)
    }

    func stopAnimating() {
        isAnimating = false
        blobs.forEach { $0.removeAllAnimations() }
    }

    private func animateBlob(_ layer: CAGradientLayer, dx: CGFloat, dy: CGFloat, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(cgPoint: layer.position)
        animation.toValue = NSValue(cgPoint: CGPoint(x: layer.position.x + dx, y: layer.position.y + dy))
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .greatestFiniteMagnitude
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "drift")
    }
}
