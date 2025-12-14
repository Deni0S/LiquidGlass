import UIKit

final class SliderView: UISlider {

    // MARK: - Property

    private var liquidGlassLensView = LensLiquidGlassView()
    private var thumbView: UIView?

    private let generator = UIImpactFeedbackGenerator(style: .light)

    private var previousTouchLocation: CGPoint?
    private var previousTouchTime: TimeInterval?
    private var velocityX: CGFloat = 0.0

    // MARK: - LifeCycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func setValue(_ value: Float, animated: Bool) {
        super.setValue(value, animated: animated)
        updateLensPosition()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLensPosition()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        liquidLens()

        previousTouchLocation = touches.first?.location(in: self)
        previousTouchTime = event?.timestamp
        velocityX = 0.0
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        liquidLens(false)

        previousTouchLocation = nil
        previousTouchTime = nil
        velocityX = 0.0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard let touch = touches.first,
              let previousLocation = previousTouchLocation,
              let previousTime = previousTouchTime,
              let event = event else { return }

        let currentLocation = touch.location(in: self)
        let currentTime = event.timestamp
        let deltaX = currentLocation.x - previousLocation.x
        let deltaTime = CGFloat(currentTime - previousTime)
        if deltaTime > 0 {
            velocityX = deltaX / deltaTime
        }

        let trackRect = self.trackRect(forBounds: bounds)
        let newValue = minimumValue + Float((currentLocation.x - trackRect.minX) / trackRect.width) * (maximumValue - minimumValue)
        let clampedValue = min(maximumValue, max(minimumValue, newValue))
        setValue(clampedValue, animated: false)

        liquidGlassLensView.animateLensSquash(with: velocityX, min: 500)

        previousTouchLocation = currentLocation
        previousTouchTime = currentTime
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        liquidLens(false)

        previousTouchLocation = nil
        previousTouchTime = nil
        velocityX = 0.0
    }
}

// MARK: - UI

private extension SliderView {

    func setupUI() {
        layer.shadowOpacity = 0

        liquidGlassLensView.frame = CGRect(x: 0, y: 0, width: 44, height: 31)
        addSubview(liquidGlassLensView)

//        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
//        addGestureRecognizer(panGesture)

        updateLensPosition()

        DispatchQueue.main.async { [weak self] in
            self?.thumbView = self?.setupThumbView()
        }
    }

    func updateLensPosition() {
        let trackRect = self.trackRect(forBounds: bounds)
        let thumbRect = self.thumbRect(forBounds: bounds, trackRect: trackRect, value: value)

        liquidGlassLensView.center = CGPoint(x: thumbRect.midX, y: bounds.midY)
    }

    func updateSliderValue(whith locationX: Double) {
        let trackRect = self.trackRect(forBounds: bounds)
        let newValue = minimumValue + Float((locationX - trackRect.minX) / trackRect.width) * (maximumValue - minimumValue)
        let clampedValue = min(maximumValue, max(minimumValue, newValue))
        setValue(clampedValue, animated: false)
        generator.impactOccurred(intensity: 1)
    }
}

// MARK: - Thumb

private extension SliderView {

    func setupThumbView() -> UIView? {
        if let thumbView = findThumbView(in: self) {
            return thumbView
        } else {
            print("Error: Can't find thumb in the slider view")
            return nil
        }
    }

    func findThumbView(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if let imageView = subview as? UIImageView,
               imageView.frame.width <= 40 && imageView.frame.height <= 40 {
                return imageView
            }
            if let found = findThumbView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - GestureRecognizer

//private extension SliderView {
//
//    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
//        switch gesture.state {
//        case .began:
//            liquidLens()
//        case .changed:
//            let location = gesture.location(in: self)
//            let trackRect = self.trackRect(forBounds: bounds)
//            let newValue = minimumValue + Float((location.x - trackRect.minX) / trackRect.width) * (maximumValue - minimumValue)
//            let clampedValue = min(maximumValue, max(minimumValue, newValue))
//            setValue(clampedValue, animated: false)
//
//            liquidGlassLensView.animateLensSquash(with: gesture.velocity(in: self).x, min: 500)
//        case .ended, .cancelled, .failed:
//            liquidLens(false)
//        default:
//            break
//        }
//    }
//}

// MARK: - LiquidGlass

private extension SliderView {

    func liquidLens(_ isShow: Bool = true) {
        if isShow {
            if thumbView == nil {
                thumbTintColor = .clear
            }
            liquidGlassLensView.showLens(animation: { [weak self] in
                self?.thumbView?.layer.opacity = 0
            })
        } else {
            liquidGlassLensView.hideLens(animation: { [weak self] in
                self?.thumbView?.layer.opacity = 1
            }) { [weak self] in
                if self?.thumbView == nil {
                    self?.thumbTintColor = .white
                }
            }
        }
    }
}
