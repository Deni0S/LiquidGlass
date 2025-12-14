import UIKit

final class LensLiquidGlassView: UIView {

    // MARK: - Property

    private var backgroundContainer = UIView()
    private var innerDistortedView = UIImageView()
    private var outerDistortedView = UIImageView()

    private var displayLink: CADisplayLink?
    private var ciContext: CIContext?

    private let chromaticAberrationFilter = ChromaticAberrationFilter()
    private let liquidDistortionFilter = LiquidDistortionFilter()
    private let waveDistortionFilter = WaveDistortionFilter()

    private let innerMaskLayer = CAShapeLayer()
    private let outerMaskLayer = CAShapeLayer()
    private let borderGradientLayer = CAGradientLayer()
    private let borderShape = CAShapeLayer()

    private var showLensAnimator: UIViewPropertyAnimator?

    public let lensScale = 1.388
    private let borderWidth: CGFloat = 1.0
    private let borderShapeWidth: CGFloat = 1.0
    private var isLensSquashAnimation = false

    // MARK: - LifeCycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        configure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLayoutFirst()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    deinit {
        tearDownDisplayLink()
        showLensAnimator?.stopAnimation(true)
        showLensAnimator = nil
    }
}

// MARK: - Public Interface

extension LensLiquidGlassView {

    @MainActor
    public func showLens(
        animation: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        isHidden = false
        setupDisplayLink()
        if determineEnergySavingMode() {
            enableRasterizationForStaticMode()
            alpha = 1
            transform = CGAffineTransform(scaleX: self.lensScale, y: self.lensScale)
            animation?()
            completion?()
        } else {
            disableRasterizationForAnimation()
            showLensAnimator?.stopAnimation(false)
            showLensAnimator?.finishAnimation(at: .current)
            let lensScale = lensScale
            showLensAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .easeIn)
            showLensAnimator?.addAnimations { [weak self] in
                self?.transform = CGAffineTransform(scaleX: lensScale, y: lensScale)
                self?.alpha = 1
                animation?()
            }
            showLensAnimator?.addCompletion { _ in
                completion?()
            }
            showLensAnimator?.startAnimation()
        }
    }

    @MainActor
    public func hideLens(
        animation: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) {
        innerDistortedView.image = nil
        outerDistortedView.image = nil

        if determineEnergySavingMode() {
            tearDownDisplayLink()
            enableRasterizationForStaticMode()
            alpha = 0
            transform = .identity
            isHidden = true
            animation?()
            completion?()
        } else {
            disableRasterizationForAnimation()
            showLensAnimator?.stopAnimation(false)
            showLensAnimator?.finishAnimation(at: .current)
            showLensAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .easeIn)
            showLensAnimator?.addAnimations { [weak self] in
                self?.alpha = 0
                self?.transform = .identity
                animation?()

            }
            showLensAnimator?.addCompletion { [weak self]_ in
                completion?()
                self?.tearDownDisplayLink()
            }
            showLensAnimator?.startAnimation()
        }
    }

    @MainActor
    public func animateLensSquash(with velocityX: CGFloat, min velocityMin: CGFloat, layers: [String: CALayer] = [:]) {
        guard abs(velocityX) > velocityMin, !determineEnergySavingMode(), !isLensSquashAnimation else { return }

        isLensSquashAnimation = true

        let animation = CAKeyframeAnimation(keyPath: "transform")

        let normalizedX = abs(velocityX)/velocityMin - 1

        if velocityX < 0 {
            let squash = min(max(0.1 + 0.2 * normalizedX, 0.1), 0.3)
            animation.values = [
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale, lensScale, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale - squash, lensScale + 0.3, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale, lensScale - 0.1, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale, lensScale, 1.0))
            ]
            animation.keyTimes = [0, 0.35, 0.7, 1.0]
        } else {
            let squash = min(max(0.1 + 0.3 * normalizedX, 0.3), 0.4)
            animation.values = [
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale, lensScale, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale + 0.4, lensScale - squash, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale - 0.1, lensScale + 0.2, 1.0)),
                NSValue(caTransform3D: CATransform3DMakeScale(lensScale, lensScale, 1.0))
            ]
            animation.keyTimes = [0, 0.2, 0.7, 1.0]
        }

        animation.duration = 0.5
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeIn)
        ]

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isLensSquashAnimation = false
        }
        layer.add(animation, forKey: "liquidLensDropAnimation")
        for layer in layers {
            layer.value.add(animation, forKey: layer.key)
        }
        CATransaction.commit()
    }

    @MainActor
    public func correctLensEffect() {
        updateLensEffectImmediately()
    }
}

// MARK: - UI

private extension LensLiquidGlassView {

    func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isHidden = true
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        backgroundContainer.frame = bounds
        backgroundContainer.backgroundColor = .clear
        backgroundContainer.isUserInteractionEnabled = false
        backgroundContainer.layer.cornerRadius = layer.cornerRadius
        backgroundContainer.clipsToBounds = true
        backgroundContainer.layer.masksToBounds = false
        addSubview(backgroundContainer)
        sendSubviewToBack(backgroundContainer)

        outerDistortedView.frame = bounds
        outerDistortedView.contentMode = .scaleAspectFill
        outerDistortedView.layer.cornerRadius = layer.cornerRadius
        outerDistortedView.clipsToBounds = true
        outerDistortedView.layer.masksToBounds = false
        backgroundContainer.addSubview(outerDistortedView)

        innerDistortedView.frame = bounds
        innerDistortedView.contentMode = .scaleAspectFill
        innerDistortedView.layer.cornerRadius = layer.cornerRadius
        innerDistortedView.clipsToBounds = true
        backgroundContainer.addSubview(innerDistortedView)

        borderGradientLayer.colors = [
            UIColor.label.withAlphaComponent(0.0).cgColor,
            UIColor.label.withAlphaComponent(0.15).cgColor,
            UIColor.label.withAlphaComponent(0.5).cgColor,
            UIColor.label.withAlphaComponent(0.8).cgColor,
            UIColor.label.withAlphaComponent(0.5).cgColor,
            UIColor.label.withAlphaComponent(0.15).cgColor,
            UIColor.label.withAlphaComponent(0.0).cgColor
        ]
        borderGradientLayer.locations = [0, 0.1, 0.4, 0.5, 0.6, 0.9, 1]
        borderGradientLayer.startPoint = CGPoint(x: 0, y: 1)
        borderGradientLayer.endPoint = CGPoint(x: 1, y: 0)
        backgroundContainer.layer.addSublayer(borderGradientLayer)

        borderShape.lineWidth = borderShapeWidth
        borderShape.fillColor = UIColor.clear.cgColor
        borderShape.strokeColor = UIColor.label.withAlphaComponent(0.3).cgColor
        borderGradientLayer.mask = borderShape
    }

    func configure() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    func updateLayoutFirst() {

    }

    func updateLayout() {
        layer.cornerRadius = round(bounds.height / 3)

        borderGradientLayer.frame = bounds
        borderGradientLayer.cornerRadius = layer.cornerRadius
        borderShape.path = UIBezierPath(roundedRect: CGRect(x: bounds.minX + borderWidth, y: bounds.minY + borderWidth, width: bounds.width - 2 * borderWidth, height: bounds.height - 2 * borderWidth), cornerRadius: round((bounds.height - 2 * borderWidth) / 3)).cgPath

        backgroundContainer.frame = bounds
        backgroundContainer.layer.cornerRadius = layer.cornerRadius

        innerDistortedView.frame = bounds
        innerDistortedView.layer.cornerRadius = layer.cornerRadius

        outerDistortedView.frame = bounds
        outerDistortedView.layer.cornerRadius = layer.cornerRadius

        updateLensMasks()
        updateLensEffect()
    }

    func updateLensMasks() {
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let outerPath = CGMutablePath()
        outerPath.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath)
        let radiusRatio: CGFloat = 0.7
        let innerWidth = bounds.width * radiusRatio
        let innerHigh = bounds.height * radiusRatio
        let innerRect = CGRect(x: bounds.midX - innerWidth / 2, y: bounds.midY - innerHigh / 2, width: innerWidth, height: innerHigh)
        let innerCornerRadius = min(innerWidth, innerHigh) / layer.cornerRadius * min(bounds.width, bounds.height)
        outerPath.addPath(UIBezierPath(roundedRect: innerRect, cornerRadius: innerCornerRadius).cgPath)

        outerMaskLayer.path = outerPath
        outerMaskLayer.fillRule = .evenOdd
        outerDistortedView.layer.mask = outerMaskLayer

        innerMaskLayer.path = UIBezierPath(roundedRect: innerRect, cornerRadius: layer.cornerRadius).cgPath
        innerDistortedView.layer.mask = innerMaskLayer
    }

    func updateLensEffect() {
        guard let window = window else { return }

        innerDistortedView.isHidden = true
        outerDistortedView.isHidden = true

        let lensFrameInWindow = convert(bounds, to: window)
        guard lensFrameInWindow.size.width > 0 && lensFrameInWindow.size.height > 0 else { return }

        UIGraphicsBeginImageContextWithOptions(lensFrameInWindow.size, false, UIScreen.main.scale)

        if let context = UIGraphicsGetCurrentContext() {
            context.translateBy(x: -lensFrameInWindow.origin.x, y: -lensFrameInWindow.origin.y)

            window.layer.render(in: context)

            if let snapshot = UIGraphicsGetImageFromCurrentImageContext(),
               let ciImage = CIImage(image: snapshot) {

                innerDistortedView.image = applyInnerLensEffect(to: ciImage)
                outerDistortedView.image = applyOuterLensEffect(to: ciImage)
            }
        }

        UIGraphicsEndImageContext()

        innerDistortedView.isHidden = false
        outerDistortedView.isHidden = false
    }

    func enableRasterizationForStaticMode() {
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        backgroundContainer.layer.shouldRasterize = true
        backgroundContainer.layer.rasterizationScale = UIScreen.main.scale
        innerDistortedView.layer.shouldRasterize = true
        innerDistortedView.layer.rasterizationScale = UIScreen.main.scale
        outerDistortedView.layer.shouldRasterize = true
        outerDistortedView.layer.rasterizationScale = UIScreen.main.scale
    }

    func disableRasterizationForAnimation() {
        layer.shouldRasterize = false
        backgroundContainer.layer.shouldRasterize = false
        innerDistortedView.layer.shouldRasterize = false
        outerDistortedView.layer.shouldRasterize = false
    }
}

// MARK: - DisplayLink

private extension LensLiquidGlassView {

    func setupDisplayLink() {
        tearDownDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        displayLink?.add(to: .main, forMode: .common)

        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            displayLink?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func handleDisplayLink() {
        updateLensEffect()
    }

    func tearDownDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func updateLensEffectImmediately() {
        displayLink?.isPaused = true
        updateLensEffect()
        displayLink?.isPaused = false
    }
}

// MARK: - LensEffect

private extension LensLiquidGlassView {

    func applyInnerLensEffect(to image: CIImage) -> UIImage? {
        var processedImage = image

        processedImage = processedImage.applyingFilter(
            "CIGaussianBlur",
            parameters: [
                kCIInputRadiusKey: 0.05
            ])

        guard let cgImage = ciContext?.createCGImage(
            processedImage,
            from: processedImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    func applyOuterLensEffect(to image: CIImage) -> UIImage? {
        var processedImage = image

        chromaticAberrationFilter.applyFilter(
            to: &processedImage)

        liquidDistortionFilter.applyFilter(
            to: &processedImage)

        //        let radius = max(processedImage.extent.width, processedImage.extent.height) / 2
        //        waveDistortionFilter.applyFilter(
        //            to: &processedImage,
        //            radius: radius * 1.2,
        //            intensity: -10,
        //            frequency: 10)

        processedImage = processedImage.applyingFilter(
            "CIGaussianBlur",
            parameters: [
                kCIInputRadiusKey: 1
            ])

        guard let cgImage = ciContext?.createCGImage(
            processedImage,
            from: processedImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
