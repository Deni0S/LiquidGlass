import UIKit

final class BackgroundLiquidGlassView: UIView {

    // MARK: - Public Property

    public let blurContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    public let highlightLayer = CAGradientLayer()

    // MARK: - Property

    private var backgroundContainer = UIView()
    private var innerDistortedView = UIImageView()
    private var outerDistortedView = UIImageView()

    private let extraBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

    private let borderGradientLayer = CAGradientLayer()
    private let borderShape = CAShapeLayer()
    private let borderShapeMask = CAShapeLayer()
    private let tintLayer = CALayer()

    private let innerMaskLayer = CAShapeLayer()
    private let outerMaskLayer = CAShapeLayer()

    private var currentSuperview: UIView = .init()
    private var currentDragLocation: CGPoint = .zero

    private var shiftAnimator: UIViewPropertyAnimator?
    private var shiftCentrPositionX: CGFloat = 0.0

    private var backgroundDisplayLink: CADisplayLink?
    private var borderDisplayLink: CADisplayLink?

    private var ciContext: CIContext?
    private let chromaticAberrationFilter = ChromaticAberrationFilter()
    private let liquidDistortionFilter = LiquidDistortionFilter()
    private let waveDistortionFilter = WaveDistortionFilter()

    private var isPressed = false
    private var isDragging = false
    private let scale = 1.388

    // MARK: - LifeCycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupCiContext()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupCiContext()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateForCurrentInterfaceStyle()
    }

    deinit {
        tearDownBackgroundDisplayLink()
        tearDownBorderDisplayLink()
    }

    @MainActor
    public func setupSwipeEffect(superview: UIView) {
        currentSuperview = superview

        let longPressGesture = UILongPressGestureRecognizer()
        longPressGesture.minimumPressDuration = 0
        longPressGesture.addTarget(self, action: #selector(handleLongPress(_:)))
        longPressGesture.delegate = self
        addGestureRecognizer(longPressGesture)

        let panGesture = UIPanGestureRecognizer()
        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }
}

// MARK: - UI

private extension BackgroundLiquidGlassView {

    func setupUI() {
        layer.shouldRasterize = false
        backgroundContainer.layer.shouldRasterize = false
        innerDistortedView.layer.shouldRasterize = false
        outerDistortedView.layer.shouldRasterize = false

//        translatesAutoresizingMaskIntoConstraints = false
//        clipsToBounds = false
//        layer.masksToBounds = false
//        backgroundColor = .systemGray.withAlphaComponent(0.1)
//        layer.borderColor = UIColor.systemGray.withAlphaComponent(0.1).cgColor

        backgroundContainer.backgroundColor = .clear
        backgroundContainer.isUserInteractionEnabled = false
        backgroundContainer.layer.cornerRadius = layer.cornerRadius
        backgroundContainer.clipsToBounds = true
        backgroundContainer.layer.masksToBounds = false
        addSubview(backgroundContainer)
        sendSubviewToBack(backgroundContainer)

        outerDistortedView.contentMode = .scaleAspectFill
        outerDistortedView.layer.cornerRadius = layer.cornerRadius
        outerDistortedView.clipsToBounds = true
        outerDistortedView.layer.masksToBounds = false
//        backgroundContainer.addSubview(outerDistortedView)

        innerDistortedView.contentMode = .scaleAspectFill
        innerDistortedView.layer.cornerRadius = layer.cornerRadius
        innerDistortedView.clipsToBounds = true
//        backgroundContainer.addSubview(innerDistortedView)

        blurContainer.frame = bounds
        blurContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurContainer.alpha = 0.8
        blurContainer.layer.opacity = 0.4
        blurContainer.layer.masksToBounds = true
        addSubview(blurContainer)

        extraBlur.frame = blurContainer.bounds
        extraBlur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        extraBlur.alpha = 0.3
        blurContainer.contentView.addSubview(extraBlur)

        tintLayer.compositingFilter = "overlayBlendMode"
        tintLayer.backgroundColor = UIColor.clear.cgColor
        blurContainer.contentView.layer.addSublayer(tintLayer)

        highlightLayer.opacity = 0.2
        layer.addSublayer(highlightLayer)

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
        layer.addSublayer(borderGradientLayer)

        borderShape.lineWidth = 2
        borderShape.fillColor = UIColor.clear.cgColor
        borderShape.strokeColor = UIColor.label.withAlphaComponent(0.3).cgColor
        borderGradientLayer.mask = borderShape

//        borderShapeMask.lineCap = .butt
//        borderShapeMask.lineJoin = .miter
//        borderShapeMask.fillRule = .evenOdd
//        borderShapeMask.lineWidth = 1

        updateForCurrentInterfaceStyle()
//        showBackgroundLiquidGlass()
    }

    func setupCiContext() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    func updateLayout() {
        borderGradientLayer.frame = bounds
        borderGradientLayer.cornerRadius = layer.cornerRadius

//        layer.borderWidth = 2
//        layer.borderColor = UIColor.green.cgColor
        let borderShapeRoundedRect = CGRect(x: bounds.minX + layer.borderWidth, y: bounds.minY + layer.borderWidth, width: bounds.width - 2 * layer.borderWidth, height: bounds.height - 2 * layer.borderWidth)
        let borderShapeMinDistance = min(bounds.height, bounds.width)
        let borderShapeCornerRadius = layer.cornerRadius / borderShapeMinDistance * (borderShapeMinDistance - 2 * layer.borderWidth)
        borderShape.path = UIBezierPath(roundedRect: borderShapeRoundedRect, cornerRadius: borderShapeCornerRadius).cgPath

        tintLayer.frame = bounds
        tintLayer.cornerRadius = layer.frame.height / 2

        backgroundContainer.frame = bounds
        backgroundContainer.layer.cornerRadius = layer.cornerRadius

        innerDistortedView.frame = bounds
        innerDistortedView.layer.cornerRadius = layer.cornerRadius

        outerDistortedView.frame = bounds
        outerDistortedView.layer.cornerRadius = layer.cornerRadius

        shiftCentrPositionX = frame.midX
        blurContainer.layer.cornerRadius = layer.cornerRadius
        highlightLayer.frame = bounds
        highlightLayer.cornerRadius = layer.cornerRadius
        borderGradientLayer.frame = bounds
        borderGradientLayer.cornerRadius = layer.cornerRadius
        borderShape.path = UIBezierPath(roundedRect: bounds.insetBy(dx: layer.borderWidth/2, dy: layer.borderWidth/2), cornerRadius: layer.cornerRadius).cgPath

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

    func updateForCurrentInterfaceStyle() {
        if traitCollection.userInterfaceStyle == .dark {
            highlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.15).cgColor,
                UIColor.white.withAlphaComponent(0.05).cgColor,
                UIColor.clear.cgColor
            ]
        } else {
            highlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.3).cgColor,
                UIColor.white.withAlphaComponent(0.1).cgColor,
                UIColor.clear.cgColor
            ]
        }
    }
}

// MARK: - GestureRecognizer

private extension BackgroundLiquidGlassView {

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPressed = true
            let scale = scale
            UIView.animate(withDuration: 0.2) { [weak self] in
                self?.transform = CGAffineTransform(scaleX: scale, y: scale)
                self?.blurContainer.layer.opacity = 0.8
            }
            showBorderAnimation()
            if let otherView = findOtherView() {
                otherView.updateBorderMask()
            }
        case .ended, .cancelled:
            isPressed = false
            resetStretchEffect()
            tearDownBorderDisplayLink()
            if let otherView = findOtherView() {
                otherView.tearDownBorderDisplayLink()
                otherView.updateBorderMask()
            }
        default:
            break
        }
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDragging = true
            currentDragLocation = gesture.location(in: self)
            showBorderAnimation()
            if let otherView = findOtherView() {
                otherView.showBorderAnimation()
                otherView.updateBorderMask()
            }
            updateAllBackgroundLiquidGlassViewMasks()
        case .changed:
            currentDragLocation = gesture.location(in: self)
            if !bounds.contains(currentDragLocation) {
                applyStretchEffect(to: currentDragLocation)
                updateBorderMask()
            }
        case .ended, .cancelled:
            isDragging = false
            resetStretchEffect()
            tearDownBorderDisplayLink()
            updateAllBackgroundLiquidGlassViewMasks()
        default:
            break
        }
    }
}

// MARK: - LiquidGlassEffect

private extension BackgroundLiquidGlassView {

    func showBackgroundLiquidGlass() {
        tearDownBackgroundDisplayLink()
        setupBackgroundDisplayLink()
    }

    func setupBackgroundDisplayLink() {
        tearDownBackgroundDisplayLink()
        backgroundDisplayLink = CADisplayLink(target: self, selector: #selector(backgroundLiquidGlass))
        backgroundDisplayLink?.add(to: .main, forMode: .common)

        if #available(iOS 15.0, *) {
            backgroundDisplayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            backgroundDisplayLink?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func backgroundLiquidGlass() {
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

                innerDistortedView.image = applyInnerBackground(to: ciImage)
                outerDistortedView.image = applyOuterBackground(to: ciImage)
            }
        }

        UIGraphicsEndImageContext()

        innerDistortedView.isHidden = false
        outerDistortedView.isHidden = false
    }

    func applyInnerBackground(to image: CIImage) -> UIImage? {
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

    func applyOuterBackground(to image: CIImage) -> UIImage? {
        var processedImage = image

        chromaticAberrationFilter.applyFilter(
            to: &processedImage)

        liquidDistortionFilter.applyFilter(
            to: &processedImage)

        guard let cgImage = ciContext?.createCGImage(
            processedImage,
            from: processedImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    func tearDownBackgroundDisplayLink() {
        backgroundDisplayLink?.invalidate()
        backgroundDisplayLink = nil
    }
}

// MARK: - ShiftEffect

extension BackgroundLiquidGlassView {

    func updateShift(for progress: CGFloat) {
        let clampedProgress = max(-1.0, min(1.0, progress))
        let shift = clampedProgress * abs(clampedProgress) * 4

        if determineEnergySavingMode() {
            layer.position.x = shiftCentrPositionX + shift
        } else {
            let tabBarCentrPositionX = shiftCentrPositionX + shift
            shiftAnimator?.stopAnimation(false)
            shiftAnimator?.finishAnimation(at: .current)
            shiftAnimator = UIViewPropertyAnimator(duration: 0.15, curve: .linear)
            shiftAnimator?.addAnimations { [weak self] in
                self?.layer.position.x = tabBarCentrPositionX
            }
            shiftAnimator?.startAnimation()
        }
    }

    func resetShift() {
        if determineEnergySavingMode() {
            layer.position.x = shiftCentrPositionX
        } else {
            let centrPositionX = shiftCentrPositionX
            shiftAnimator?.stopAnimation(false)
            shiftAnimator?.finishAnimation(at: .current)
            shiftAnimator =  UIViewPropertyAnimator(duration: 0.3, curve: .linear)
            shiftAnimator?.addAnimations { [weak self] in
                self?.layer.position.x = centrPositionX
            }
            shiftAnimator?.startAnimation()
        }
    }
}

// MARK: - BorderEfect

extension BackgroundLiquidGlassView {

    func showBorderAnimation() {
        tearDownBorderDisplayLink()
        setupBorderDisplayLink()
    }

    func setupBorderDisplayLink() {
        borderDisplayLink = CADisplayLink(target: self, selector: #selector(updateBorderAnimation))
        borderDisplayLink?.add(to: .main, forMode: .common)

        if #available(iOS 15.0, *) {
            borderDisplayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            borderDisplayLink?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func updateBorderAnimation() {
        updateBorderMask()
        if let otherView = findOtherView() {
            otherView.updateBorderMask()
        }
    }

    func updateBorderMask() {
        let intersectingButtons = getAllBackgroundLiquidGlassView().filter {
            $0 != self && framesIntersect(frame, $0.frame)
        }

        if intersectingButtons.isEmpty {
            borderShapeMask.path = nil
            borderShape.mask = nil
            return
        }

        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)

        for button in intersectingButtons {
            let intersection = frame.intersection(button.frame)
            if !intersection.isEmpty {
                maskPath.addPath(UIBezierPath(roundedRect: convert(intersection, from: superview), cornerRadius: min(layer.cornerRadius, intersection.height / 2)).cgPath)
            }
        }

        borderShapeMask.path = maskPath
        borderShape.mask = borderShapeMask
    }

    func findOtherView() -> BackgroundLiquidGlassView? {
        let allButtons = getAllBackgroundLiquidGlassView()
        for button in allButtons {
            if button != self && framesIntersect(frame, button.frame) {
                return button
            }
        }
        return nil
    }

    func getAllBackgroundLiquidGlassView() -> [BackgroundLiquidGlassView] {
        func findButtons(in view: UIView) -> [BackgroundLiquidGlassView] {
            var buttons: [BackgroundLiquidGlassView] = []
            if let swipeButton = view as? BackgroundLiquidGlassView {
                buttons.append(swipeButton)
            }
            for subview in view.subviews {
                buttons.append(contentsOf: findButtons(in: subview))
            }
            return buttons
        }

        return findButtons(in: currentSuperview)
    }

    func updateAllBackgroundLiquidGlassViewMasks() {
        for view in getAllBackgroundLiquidGlassView() {
            view.updateBorderMask()
            if view != self && view.isPressed {
                view.tearDownBorderDisplayLink()
            }
        }
    }

    func framesIntersect(_ frame1: CGRect, _ frame2: CGRect) -> Bool {
        let frame1InSuperview = currentSuperview.convert(frame1, from: currentSuperview)
        let frame2InSuperview = currentSuperview.convert(frame2, from: currentSuperview)
        let intersection = frame1InSuperview.intersection(frame2InSuperview)
        return intersection.width > 0.1 && intersection.height > 0.1
    }

    func tearDownBorderDisplayLink() {
        borderDisplayLink?.invalidate()
        borderDisplayLink = nil
    }
}

// MARK: - StretchEffect

private extension BackgroundLiquidGlassView {

    func applyStretchEffect(to touchPoint: CGPoint) {
        // Конвертируем координаты в систему superview
        let touchInSuperview = convert(touchPoint, to: currentSuperview)
        let centerInSuperview = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: currentSuperview)

        // Вычисляем вектор направления
        let directionVector = CGVector(dx: touchInSuperview.x - centerInSuperview.x, dy: touchInSuperview.y - centerInSuperview.y)

        let angle = atan2(directionVector.dy, directionVector.dx)
        let distance = sqrt(directionVector.dx * directionVector.dx + directionVector.dy * directionVector.dy)

        // Определяем близость к основным направлениям
        let proximity = calculateDirectionProximity(angle: angle)

        // Вычисляем коэффициент растяжения
        let stretchCoefficient = smoothStep(1 - proximity.diagonal)

        let safeAreaFrame = currentSuperview.bounds.inset(by: currentSuperview.safeAreaInsets)
        let stretchLimits = calculateStretchLimits(center: centerInSuperview, angle: angle, safeAreaFrame: safeAreaFrame)
        let distanceRatio = stretchLimits.maxStretchDistance > 0 ? min(distance / stretchLimits.maxStretchDistance, 1.0) : 0
        let effectiveFactor = stretchCoefficient * smoothStep(distanceRatio)

        // Вычисляем растяжение по осям
        let stretchAmounts = calculateStretchAmounts(proximity: proximity, stretchCoefficient: stretchCoefficient, effectiveFactor: effectiveFactor)

        // Применяем трансформацию
        let scaleX = scale + stretchAmounts.x * 0.5
        let scaleY = scale + stretchAmounts.y * 0.5
        let translationFactor = 0.04

        transform = CGAffineTransform(translationX: directionVector.dx * translationFactor, y: directionVector.dy * translationFactor).scaledBy(x: scaleX, y: scaleY)
        highlightLayer.setAffineTransform(CGAffineTransform(scaleX: 1/scaleX, y: 1/scaleY))
    }

    struct StretchLimits {
        let maxLength: CGFloat
        let maxStretchDistance: CGFloat
    }

    func calculateStretchLimits(
        center: CGPoint,
        angle: CGFloat,
        safeAreaFrame: CGRect
    ) -> StretchLimits {
        // Вычисляем максимальную длину экрана (диагональ)
        let screenDiagonal = sqrt(pow(safeAreaFrame.width, 2) + pow(safeAreaFrame.height, 2))
        // Вычисляем максимальное расстояние от центра до границы в данном направлении
        let maxDistanceToEdge = distanceToSafeAreaEdge(from: center, angle: angle, safeAreaFrame: safeAreaFrame)
        // Определяем эталонное максимальное расстояние как наибольшее
        let referenceMaxDistance = max(maxDistanceToEdge, screenDiagonal * 0.5)
        return StretchLimits(
            maxLength: screenDiagonal,
            maxStretchDistance: referenceMaxDistance
        )
    }

    struct DirectionProximity {
        let horizontal: CGFloat
        let vertical: CGFloat
        let diagonal: CGFloat
    }

    func calculateDirectionProximity(angle: CGFloat) -> DirectionProximity {
        let absAngle = abs(angle)
        let diagonalAngle: CGFloat = .pi / 4

        // Вычисляем угловое расстояние до каждого направления
        let toHorizontal = min(absAngle, abs(absAngle - .pi))
        let toVertical = abs(absAngle - .pi / 2)
        let toDiagonal = min(abs(absAngle - diagonalAngle), abs(absAngle - (.pi - diagonalAngle)))

        // Вычисляем близость (1 = идеальное совпадение, 0 = нет совпадения)
        let horizontalProximity = max(0, 1 - (toHorizontal / diagonalAngle))
        let verticalProximity = max(0, 1 - (toVertical / diagonalAngle))
        let diagonalProximity = max(0, 1 - (toDiagonal / diagonalAngle))

        let total = horizontalProximity + verticalProximity + diagonalProximity
        guard total > 0 else { return DirectionProximity(horizontal: 0, vertical: 0, diagonal: 0) }

        return DirectionProximity(horizontal: horizontalProximity / total, vertical: verticalProximity / total, diagonal: diagonalProximity / total)
    }

    func calculateStretchAmounts(
        proximity: DirectionProximity,
        stretchCoefficient: CGFloat,
        effectiveFactor: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        // Веса для разных направлений
        let horizontalWeight = proximity.horizontal * stretchCoefficient
        let verticalWeight = proximity.vertical * stretchCoefficient
        let diagonalWeight = proximity.diagonal * (1 - stretchCoefficient)

        // Растяжение по осям
        let stretchX = effectiveFactor * (
            horizontalWeight * 1.0 +    // Горизонтальное направление
            verticalWeight * -0.3 +      // Вертикальное направление
            diagonalWeight * 0.6        // Диагональное направление
        )

        let stretchY = effectiveFactor * (
            horizontalWeight * -0.3 +    // Горизонтальное направление
            verticalWeight * 1.0 +      // Вертикальное направление
            diagonalWeight * 0.6        // Диагональное направление
        )

        return (stretchX, stretchY)
    }

    func smoothStep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    func distanceToSafeAreaEdge(from point: CGPoint, angle: CGFloat, safeAreaFrame: CGRect) -> CGFloat {
        let dx = cos(angle)
        let dy = sin(angle)

        var distances: [CGFloat] = []

        if dx > 0 {
            distances.append((safeAreaFrame.maxX - point.x) / dx)
        } else if dx < 0 {
            distances.append((safeAreaFrame.minX - point.x) / dx)
        }

        if dy > 0 {
            distances.append((safeAreaFrame.maxY - point.y) / dy)
        } else if dy < 0 {
            distances.append((safeAreaFrame.minY - point.y) / dy)
        }

        let positiveDistances = distances.filter { $0 > 0 }
        return positiveDistances.min() ?? .greatestFiniteMagnitude
    }

    func resetStretchEffect() {
        UIView.animate(
            withDuration: 0.8,
            delay: 0,
            usingSpringWithDamping: 0.4,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) { [weak self] in
            self?.transform = .identity
            self?.highlightLayer.setAffineTransform(.identity)
            self?.blurContainer.layer.opacity = 0.4
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension BackgroundLiquidGlassView: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
