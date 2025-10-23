import SwiftUI
import UIKit

private struct TwoFingerProfileSwipeModifier: ViewModifier {
    let label: String
    let onSwipe: (ProfileNavigationDirection) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                TwoFingerSwipeRecognizerView(onSwipe: onSwipe)
                    .postHogLabel(label)
            )
    }
}

private struct TwoFingerSwipeRecognizerView: UIViewRepresentable {
    let onSwipe: (ProfileNavigationDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let leftSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        leftSwipe.direction = .left
        leftSwipe.numberOfTouchesRequired = 2
        leftSwipe.cancelsTouchesInView = false
        leftSwipe.delegate = context.coordinator
        view.addGestureRecognizer(leftSwipe)

        let rightSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        rightSwipe.direction = .right
        rightSwipe.numberOfTouchesRequired = 2
        rightSwipe.cancelsTouchesInView = false
        rightSwipe.delegate = context.coordinator
        view.addGestureRecognizer(rightSwipe)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onSwipe: (ProfileNavigationDirection) -> Void

        init(onSwipe: @escaping (ProfileNavigationDirection) -> Void) {
            self.onSwipe = onSwipe
        }

        @objc
        func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended else { return }

            switch recognizer.direction {
            case .left:
                onSwipe(.next)
            case .right:
                onSwipe(.previous)
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            true
        }
    }
}

extension View {
    func twoFingerProfileSwitchGesture(label: String,
                                       onSwipe: @escaping (ProfileNavigationDirection) -> Void) -> some View
    {
        modifier(TwoFingerProfileSwipeModifier(label: label, onSwipe: onSwipe))
    }
}
