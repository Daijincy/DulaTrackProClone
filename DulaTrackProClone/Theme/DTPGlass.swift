//
//  DTPGlass.swift
//  DulaTrackPro Clone
//
//  液态玻璃（Liquid Glass）统一入口：
//  - iOS 26+ 使用 UIGlassEffect（可交互玻璃）
//  - iOS 16~25 回退到 ultraThinMaterial 毛玻璃，保证同一套界面可用
//

import UIKit

enum DTPGlass {

    /// 当前系统是否支持真正的液态玻璃。
    static var isLiquidGlassAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func makeEffect(interactive: Bool = false) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect()
            // 可交互玻璃：按压时会产生液态形变
            effect.isInteractive = interactive
            return effect
        }
        return UIBlurEffect(style: .systemUltraThinMaterialDark)
    }

    /// 一块圆角玻璃。
    static func makeView(cornerRadius: CGFloat,
                         interactive: Bool = false,
                         borderAlpha: CGFloat = 0.16) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: makeEffect(interactive: interactive))
        view.clipsToBounds = true
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.8
        view.layer.borderColor = UIColor.white.withAlphaComponent(borderAlpha).cgColor
        return view
    }
}
