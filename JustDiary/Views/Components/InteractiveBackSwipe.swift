import SwiftUI
import UIKit

/// 让**导航栏被隐藏**的页面照样能「右滑返回」。
///
/// 为什么需要它：SwiftUI 的 `NavigationStack` 底下是 `UINavigationController`，
/// 而 UIKit 只在导航栏可见时才让 `interactivePopGestureRecognizer` 起手 —— 关掉它的
/// 不是 `isEnabled`，是它内部 delegate 的 `gestureRecognizerShouldBegin` 在导航栏
/// 隐藏时返回 false。日记页的顶栏是页面自己画的（`DiaryPageView.topBarOverlay`），
/// 导航栏必须藏起来，于是系统手势也一起没了：隐藏导航栏时右滑**完全不响应**
/// （实测见 `DiaryPageTransitionUITests`，加了这个 helper 之后同一个手势才返回日历）。
///
/// 做法：找到宿主 `UINavigationController`，把内部 delegate 换成我们自己的 ——
/// 判断条件只留两条：栈里不止一页，且调用方说现在可以走。自己**不画**任何东西
/// （探针视图关掉了交互），也不接管动画：推进 / 返回仍然是系统的。
struct InteractiveBackSwipe: UIViewControllerRepresentable {
    /// 现在允许右滑返回吗。
    ///
    /// 日记页按阅读 / 编辑态给：编辑态正文还没落库，右滑直接弹回会把这半篇日记丢掉
    /// （`DiaryViewModel.handleBack` 的规则是「先退出编辑，再退出页面」，有内容时
    /// 还要先问一句「放弃修改」）。
    var canGoBack: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let probe = ProbeViewController()
        probe.onNavigationController = { [weak coordinator = context.coordinator] controller in
            coordinator?.attach(controller)
        }
        return probe
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.canGoBack = { canGoBack }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canGoBack: () -> Bool = { true }
        private weak var navigationController: UINavigationController?

        func attach(_ controller: UINavigationController?) {
            guard let controller, controller !== navigationController else { return }
            navigationController = controller
            controller.interactivePopGestureRecognizer?.isEnabled = true
            controller.interactivePopGestureRecognizer?.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController, navigationController.viewControllers.count > 1 else {
                return false
            }
            return canGoBack()
        }
    }

    /// 只为拿到宿主导航控制器而存在；不画东西、不吃手势。
    final class ProbeViewController: UIViewController {
        var onNavigationController: ((UINavigationController?) -> Void)?

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            report()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            report()
        }

        private func report() {
            guard let onNavigationController else { return }
            // `navigationController` 会沿 parent 链往上找，SwiftUI 的
            // `NavigationStack` 把内容挂在它自己的 `UINavigationController` 里；
            // 找不到就什么都不做（退化成系统默认行为：没有右滑返回）。
            onNavigationController(navigationController)
        }
    }
}

extension View {
    /// 给一个隐藏了导航栏的推进页面恢复「右滑返回」。
    func interactiveBackSwipe(canGoBack: Bool) -> some View {
        background(InteractiveBackSwipe(canGoBack: canGoBack))
    }
}
