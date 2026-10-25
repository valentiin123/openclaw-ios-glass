import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Tap on the transcript dismisses the keyboard without ever competing with scrolling.
///
/// The previous SwiftUI `simultaneousGesture(TapGesture())` sat on the whole scroll container and
/// took part in SwiftUI's gesture arbitration for every touch. This UIKit recognizer never cancels or
/// delays touches (`cancelsTouchesInView = false`, `delaysTouchesBegan = false`) and recognizes
/// simultaneously with every other recognizer, so the scroll view starts on the first drag.
extension View {
    @ViewBuilder
    func chatTapToDismissKeyboard(_ onTap: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.gesture(ChatPassiveTapGesture(onTap: onTap))
        #else
        self
        #endif
    }
}

#if os(iOS)
struct ChatPassiveTapGesture: UIGestureRecognizerRepresentable {
    let onTap: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        self.onTap()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool
        {
            true
        }
    }
}
#endif
