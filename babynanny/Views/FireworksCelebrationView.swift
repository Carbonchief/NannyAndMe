import SwiftUI
import QuartzCore
import UIKit

/// A full-screen celebration view that renders animated fireworks.
struct FireworksCelebrationView: UIViewRepresentable {
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterShape = .point
        emitterLayer.emitterMode = .outline
        emitterLayer.renderMode = .additive
        emitterLayer.emitterPosition = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        emitterLayer.emitterSize = view.bounds.size
        emitterLayer.emitterCells = context.coordinator.makeEmitterCells()

        view.layer.addSublayer(emitterLayer)
        context.coordinator.emitterLayer = emitterLayer
        context.coordinator.startCelebration()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onFinished = onFinished
        context.coordinator.emitterLayer?.frame = uiView.bounds
        context.coordinator.emitterLayer?.emitterPosition = CGPoint(x: uiView.bounds.midX, y: uiView.bounds.midY)
        context.coordinator.emitterLayer?.emitterSize = uiView.bounds.size
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
}

extension FireworksCelebrationView {
    final class Coordinator {
        var emitterLayer: CAEmitterLayer?
        var onFinished: () -> Void
        private var hasScheduledStop = false

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func makeEmitterCells() -> [CAEmitterCell] {
            let colors: [UIColor] = [
                UIColor(red: 0.98, green: 0.38, blue: 0.35, alpha: 1.0),
                UIColor(red: 0.99, green: 0.76, blue: 0.27, alpha: 1.0),
                UIColor(red: 0.44, green: 0.85, blue: 0.52, alpha: 1.0),
                UIColor(red: 0.36, green: 0.64, blue: 0.99, alpha: 1.0),
                UIColor(red: 0.79, green: 0.49, blue: 0.96, alpha: 1.0)
            ]

            return colors.map { color in
                let cell = CAEmitterCell()
                cell.birthRate = 4
                cell.lifetime = 3
                cell.lifetimeRange = 1.5
                cell.velocity = 160
                cell.velocityRange = 120
                cell.scale = 0.04
                cell.scaleRange = 0.02
                cell.emissionRange = .pi * 2
                cell.alphaSpeed = -0.4
                cell.yAcceleration = 50
                cell.color = color.cgColor
                if let sparkle = UIImage(systemName: "sparkle")?
                    .withTintColor(color, renderingMode: .alwaysOriginal)
                    .cgImage {
                    cell.contents = sparkle
                }
                return cell
            }
        }

        func startCelebration() {
            guard let emitterLayer else { return }
            emitterLayer.birthRate = 1
            scheduleStopIfNeeded()
        }

        private func scheduleStopIfNeeded() {
            guard hasScheduledStop == false else { return }
            hasScheduledStop = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let emitterLayer = self.emitterLayer else { return }
                emitterLayer.birthRate = 0

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self else { return }
                    self.onFinished()
                    self.hasScheduledStop = false
                }
            }
        }

        func invalidate() {
            emitterLayer?.birthRate = 0
            emitterLayer = nil
            hasScheduledStop = false
        }
    }
}

#Preview {
    FireworksCelebrationView {}
        .ignoresSafeArea()
}
