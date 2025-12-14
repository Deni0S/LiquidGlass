import UIKit

final class SwipeButtonView: UIButton {

    // MARK: - Property

    private let backgroundLiquidGlassView = BackgroundLiquidGlassView()

    // MARK: - LifeCycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLayoutFirst()
    }
}

// MARK: UI

private extension SwipeButtonView {

    func setupUI() {
        backgroundColor = .clear
        layer.cornerRadius = layer.bounds.height / 2
//        clipsToBounds = false
//        layer.masksToBounds = true

        backgroundLiquidGlassView.layer.cornerRadius = layer.cornerRadius
        backgroundLiquidGlassView.frame = bounds
        addSubview(backgroundLiquidGlassView)
    }

    func updateLayoutFirst() {
        if let superview = superview {
            backgroundLiquidGlassView.setupSwipeEffect(superview: superview)
        }
    }
}
