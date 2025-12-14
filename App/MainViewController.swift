import UIKit

final class MainViewController: UIViewController {

    private let liquidLens = LensLiquidGlassView()

    override func viewDidLoad() {
        super.viewDidLoad()

        // MARK: - SwipeButton

        let swipeButtonViewTop = SwipeButtonView(frame: CGRect(x: 50, y: 555, width: 40, height: 40))
        view.addSubview(swipeButtonViewTop)

        let swipeButtonViewLeft = SwipeButtonView(frame: CGRect(x: 50, y: 600, width: 40, height: 40))
        view.addSubview(swipeButtonViewLeft)

        let swipeButtonViewRigth = SwipeButtonView(frame: CGRect(x: 95, y: 600, width: 40, height: 40))
        view.addSubview(swipeButtonViewRigth)

        // MARK: - Switch

        let switchViewLeft = SwitchView(frame: CGRect(x: 50, y: 310, width:  200, height: 140))
        view.addSubview(switchViewLeft)

        let switchViewRight = UISwitch(frame: CGRect(x: 150, y: 310, width:  200, height: 140))
        view.addSubview(switchViewRight)

        // MARK: - Slider

        let sliderViewLeft = SliderView(frame: CGRect(x: 10, y: 110, width:  200, height: 140))
        view.addSubview(sliderViewLeft)

        let sliderViewRight = UISlider(frame: CGRect(x: 210, y: 110, width:  200, height: 140))
        view.addSubview(sliderViewRight)

        // MARK: - Lens

        let superView = UIView(frame: CGRect(x: 100, y: 370, width: 250, height: 110))
        superView.backgroundColor = .darkGray
        superView.layer.cornerRadius = 20
        view.addSubview(superView)

        let image = UIImageView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        image.image = UIImage(systemName: "arrow.2.circlepath.circle")
        superView.addSubview(image)

        let label = UILabel(frame: CGRect(x: 20, y: 70, width: 100, height: 20))
        label.font = UIFont.systemFont(ofSize: 20)
        label.text = "Чат"
        superView.addSubview(label)

        let image2 = UIImageView(frame: CGRect(x: 160, y: 10, width: 50, height: 50))
        image2.image = UIImage(systemName: "arrow.2.circlepath.circle")
        superView.addSubview(image2)

        let label2 = UILabel(frame: CGRect(x: 140, y: 70, width: 100, height: 20))
        label2.font = UIFont.systemFont(ofSize: 20)
        label2.textColor = .systemBlue
        label2.text = "Настройки"
        superView.addSubview(label2)

        liquidLens.frame = CGRect(x: 0, y: 0, width: superView.bounds.height * 1.388, height: superView.bounds.height)
        liquidLens.isUserInteractionEnabled = true
        superView.addSubview(liquidLens)
        liquidLens.showLens()

        let longPressGesture = UILongPressGestureRecognizer()
        longPressGesture.minimumPressDuration = 0
        longPressGesture.addTarget(self, action: #selector(handleLongPress(_:)))
        superView.addGestureRecognizer(longPressGesture)
        longPressGesture.delegate = self

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanLens(_:)))
        liquidLens.addGestureRecognizer(panGesture)
        panGesture.delegate = self

        // MARK: - TabBar

        let tabBarView = TabBarView()
        tabBarView.frame = CGRect(x: 10, y: 700, width: 380, height: 64)
        view.addSubview(tabBarView)
    }
}

// MARK: - Logic

private extension MainViewController {

    @objc func handlePanLens(_ gesture: UIPanGestureRecognizer) {
        guard let lensView = gesture.view else { return }

        let translation = gesture.translation(in: self.view)
        lensView.center = CGPoint(x: lensView.center.x + translation.x,
                                  y: lensView.center.y + translation.y)
        gesture.setTranslation(.zero, in: self.view)
    }

    @objc func handleLongPress(
        _ gesture: UILongPressGestureRecognizer
    ) {
        switch gesture.state {
        case .began:
            liquidLens.showLens()
        case .ended, .cancelled:
            liquidLens.hideLens()
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MainViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
