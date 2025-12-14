import UIKit

final class TabBarView: UIView {

    // MARK: - Properties

    private let tabBarView = BackgroundLiquidGlassView()
    private let controlView = UIView()
    private let liquidGlassLensView = LensLiquidGlassView()

    private var displayLinkIconScale: CADisplayLink?
    private var startTimeIconScale: CFTimeInterval = 0
    private var startXIconScale: CGFloat = .zero
    private var startYIconScale: CGFloat = .zero
    private var conteinerIconScale: UIView = .init()

    private var displayLinkIndicatorPosition: CADisplayLink?
    private var startTimeIndicatorPosition: CFTimeInterval = 0
    private var startFrameIndicatorPosition: CGRect = .zero
    private var startCenterIndicatorPosition: CGPoint = .zero
    private var targetFrameIndicatorPosition: CGRect = .zero
    private var targetCenterIndicatorPosition: CGPoint = .zero
    private var indicatorPositionAnimator: UIViewPropertyAnimator?

    private var displayLinkMaskIconsVisibility: CADisplayLink?
    private var startTimeMaskIconsVisibility: CFTimeInterval = 0
    private var animationMaskIconsVisibility: [() -> Void] = []
    private var maskIconsVisibilityAnimator: UIViewPropertyAnimator?

    private var outerIcons: [UIImageView] = []
    private var innerIcons: [UIImageView] = []
    private var maskIconContainers: [UIView] = []
    private var outerIconMaskLayers: [CAShapeLayer] = []
    private let tabIcons = ["message.fill", "phone.fill", "person.2.fill", "gear"]

    private var isDragging = false
    private var isLongTapping = false
    private var buttonWidth = 0.0
    private var indicatorStartX = 0.0
    private var dragStartX = 0.0
    private var currentIndex = 0

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLayoutFirst()
    }

    deinit {
        tearDownIconScaleDisplayLink()
        tearDownIndicatorPositionDisplayLink()
        tearDownMaskIconsVisibilityDisplayLink()
    }
}

// MARK: - UI

private extension TabBarView {

    func setupUI() {
        backgroundColor = .clear
//        tabBarView.backgroundColor = .systemGray.withAlphaComponent(0.1)
//        tabBarView.layer.cornerRadius = 32
//        tabBarView.layer.borderWidth = 1
//        tabBarView.layer.borderColor = UIColor.systemGray.withAlphaComponent(0.1).cgColor
//        tabBarView.clipsToBounds = false
        addSubview(tabBarView)

        controlView.backgroundColor = .systemGray.withAlphaComponent(0.5)
        tabBarView.addSubview(controlView)

        tabBarView.addSubview(liquidGlassLensView)

        for (index, iconName) in tabIcons.enumerated() {
            setupTabElement(at: index, iconName: iconName)
        }
        setSelectedTab(at: 0)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        tabBarView.addGestureRecognizer(panGesture)
        panGesture.delegate = self
        let longPressGesture = UILongPressGestureRecognizer()
        longPressGesture.minimumPressDuration = 0
        longPressGesture.addTarget(self, action: #selector(handleLongTap(_:)))
        tabBarView.addGestureRecognizer(longPressGesture)
        longPressGesture.delegate = self
    }

    func updateLayoutFirst() {
        let tabBarHeight: CGFloat = 64
        tabBarView.frame = CGRect(x: 16, y: bounds.height - tabBarHeight - safeAreaInsets.bottom - 16, width: bounds.width - 32, height: tabBarHeight)
        tabBarView.layer.cornerRadius = tabBarView.bounds.height / 2

        buttonWidth = tabBarView.bounds.width / CGFloat(tabIcons.count)

        for (index, _) in tabIcons.enumerated() {
            let xPosition = CGFloat(index) * buttonWidth
            let iconSize: CGFloat = 24
            let iconX = xPosition + (buttonWidth - iconSize) / 2
            let iconY = (tabBarHeight - iconSize) / 2
            outerIcons[index].frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
            maskIconContainers[index].frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
            innerIcons[index].frame = maskIconContainers[index].bounds
        }
        
        controlView.frame = CGRect(x: CGFloat(currentIndex) * buttonWidth + 8, y: 4, width: buttonWidth - 16, height: tabBarView.bounds.height - 8)
        controlView.layer.cornerRadius = controlView.bounds.height / 2
        liquidGlassLensView.center = controlView.center
        liquidGlassLensView.frame = controlView.frame
    }

    func updateLayout() {
        updateIndicatorPosition()
        updateMaskIconsVisibility()
    }
}

// MARK: - TabBar

private extension TabBarView {

    func setupTabElement(at index: Int, iconName: String) {
        let outerIcon = UIImageView(image: UIImage(systemName: iconName))
        outerIcon.tintColor = .systemGray
        outerIcon.contentMode = .scaleAspectFit
        outerIcons.append(outerIcon)
        let maskLayer = CAShapeLayer()
        outerIcon.layer.mask = maskLayer
        outerIconMaskLayers.append(maskLayer)
        tabBarView.addSubview(outerIcon)

        let maskIconContainer = UIView()
        maskIconContainer.isUserInteractionEnabled = false
        maskIconContainer.backgroundColor = .clear
        maskIconContainer.clipsToBounds = true
        tabBarView.addSubview(maskIconContainer)
        maskIconContainers.append(maskIconContainer)

        let innerIcon = UIImageView(image: UIImage(systemName: iconName))
        innerIcon.tintColor = .systemBlue
        innerIcon.contentMode = .scaleAspectFit
        innerIcons.append(innerIcon)
        maskIconContainer.addSubview(innerIcon)
        maskIconContainer.alpha = 0
    }

    func setSelectedTab(at index: Int) {
        guard index >= 0 && index < tabIcons.count else { return }
        if index == currentIndex && !isDragging && !isLongTapping {
            return
        }
        currentIndex = index
        updateIndicatorPosition()
        if !isDragging {
            updateMaskIconsVisibility()
        }
    }

    func updateIndicatorPosition() {
        if determineEnergySavingMode() {
            controlView.frame = CGRect(x: CGFloat(currentIndex) * buttonWidth + 8, y: 4, width: buttonWidth - 16, height: tabBarView.bounds.height - 8)
            liquidGlassLensView.center = controlView.center
        } else {
            indicatorPositionAnimator?.stopAnimation(false)
            indicatorPositionAnimator?.finishAnimation(at: .current)
            let springParameters = UISpringTimingParameters(dampingRatio: 0.7, initialVelocity: CGVector(dx: 0, dy: 0))
            indicatorPositionAnimator = UIViewPropertyAnimator(duration: 0.3, timingParameters: springParameters)
            indicatorPositionAnimator?.addAnimations { [weak self] in
                guard let self else { return }
                controlView.frame = CGRect(x: CGFloat(currentIndex) * buttonWidth + 8, y: 4, width: buttonWidth - 16, height: tabBarView.bounds.height - 8)
                liquidGlassLensView.center = controlView.center
            }
            indicatorPositionAnimator?.startAnimation()
//            showIndicatorPositionAnimation()
        }
    }

    func updateMaskIconsVisibility() {
        let shouldAnimate = !determineEnergySavingMode() && !isDragging && !isLongTapping
        let targetScale: CGFloat = isDragging || isLongTapping ? liquidGlassLensView.lensScale : 1.0

        var animations: [() -> Void] = []
        var immediateChanges: [() -> Void] = []

        for (index, container) in maskIconContainers.enumerated() {
            let outerIconFrame = outerIcons[index].frame
            let controlBoundsInTabBar = controlView.convert(controlView.bounds, to: tabBarView)
            let intersection = controlBoundsInTabBar.intersection(outerIconFrame)

            if !intersection.isEmpty && intersection.width > 0 && intersection.height > 0 {
                let normalizedIntersection = CGRect(
                    x: intersection.origin.x - outerIconFrame.origin.x,
                    y: intersection.origin.y - outerIconFrame.origin.y,
                    width: intersection.width,
                    height: intersection.height
                ).insetBy(dx: +2, dy: +2)

                updateMask(for: outerIcons[index],
                           maskLayer: outerIconMaskLayers[index],
                           intersection: normalizedIntersection,
                           hideIntersection: true)
                updateMask(for: container,
                           intersection: normalizedIntersection,
                           hideIntersection: false)

                if shouldAnimate {
                    animations.append {
                        container.alpha = 1
                        container.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
                    }
                } else {
                    immediateChanges.append {
                        container.alpha = 1
                        container.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
                    }
                }
            } else {
                let fullPath = UIBezierPath(rect: outerIcons[index].bounds)
                outerIconMaskLayers[index].path = fullPath.cgPath

                if shouldAnimate {
                    animations.append {
                        container.alpha = 0
                        container.transform = .identity
                    }
                } else {
                    immediateChanges.append {
                        container.alpha = 0
                        container.transform = .identity
                    }
                }
            }
        }

        immediateChanges.forEach { $0() }

        if !animations.isEmpty {
//            maskIconsVisibilityAnimator?.stopAnimation(false)
//            maskIconsVisibilityAnimator?.finishAnimation(at: .end)
//            maskIconsVisibilityAnimator = UIViewPropertyAnimator(duration: 0.3, curve: .linear)
//            maskIconsVisibilityAnimator?.addAnimations {
//                animations.forEach { $0() }
//            }
//            maskIconsVisibilityAnimator?.startAnimation()
            showMaskIconsVisibilityAnimation(animations: animations)
        }
    }

    func updateMask(
        for view: UIView,
        maskLayer: CAShapeLayer? = nil,
        intersection: CGRect,
        hideIntersection: Bool
    ) {
        var path = UIBezierPath(rect: view.bounds)

        if hideIntersection {
            path.append(UIBezierPath(rect: intersection).reversing())
        } else {
            path = UIBezierPath(rect: intersection)
        }

        if let existingMaskLayer = maskLayer {
            existingMaskLayer.path = path.cgPath
        } else {
            let newMaskLayer = CAShapeLayer()
            newMaskLayer.path = path.cgPath
            view.layer.mask = newMaskLayer
        }
    }
}

// MARK: - GestureRecognizer

private extension TabBarView {

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: tabBarView)

        switch gesture.state {
        case .began:
            liquidGlassLens()
            dragStartX = location.x
            indicatorStartX = controlView.frame.origin.x
            isDragging = true
        case .changed:
            let width: CGFloat = 12
            let minX: CGFloat = -width
            let maxX = tabBarView.bounds.width - controlView.bounds.width + width
            var newX = indicatorStartX + location.x - dragStartX
            newX = max(-width, min(maxX, newX))

            controlView.frame.origin.x = newX
            liquidGlassLensView.center = controlView.center

            liquidGlassLensView.correctLensEffect()

            updateMaskIconsVisibility()

            let progress = (newX - minX) / (maxX - minX)
            let pageIndex = Int(round(progress * CGFloat(tabIcons.count - 1)))
            if pageIndex != currentIndex {
                currentIndex = pageIndex
            }

            let velocityX = gesture.velocity(in: self).x
            if abs(velocityX) > 200 {
                var layers: [String: CALayer] = [
                    "ControlDropAnimation" : controlView.layer
                ]
                for (index, container) in maskIconContainers.enumerated() where container.alpha > 0 {
                    layers["MaskDropAnimation\(index)"] = container.layer
                }
                liquidGlassLensView.animateLensSquash(with: velocityX, min: 200, layers: layers)
            }
            tabBarView.updateShift(for: (newX + controlView.bounds.width / 2 - tabBarView.bounds.width / 2) / (tabBarView.bounds.width / 2))
        case .ended, .cancelled:
            isDragging = false
            liquidGlassLens(false)
            setSelectedTab(at: Int(round(controlView.center.x / buttonWidth)))
            tabBarView.resetShift()
        default:
            break
        }
    }

    @objc func handleLongTap(_ gesture: UITapGestureRecognizer) {
        let tappedIndex = Int(gesture.location(in: tabBarView).x / buttonWidth)
        switch gesture.state {
        case .began:
            isLongTapping = true
            if tappedIndex >= 0 && tappedIndex < tabIcons.count {
                if let container = maskIconContainers[safe: tappedIndex] {
                    if determineEnergySavingMode() {
                        container.transform = CGAffineTransform(scaleX: liquidGlassLensView.lensScale, y: liquidGlassLensView.lensScale)
                    } else {
                        showIconScaleAnimation(container: container)
                    }
                }
                liquidGlassLens()
                setSelectedTab(at: tappedIndex)
            }
        case .ended, .cancelled:
            isLongTapping = false
            if tappedIndex >= 0 && tappedIndex < tabIcons.count {
                setSelectedTab(at: tappedIndex)
                let location = gesture.location(in: tabBarView)
                if controlView.frame.contains(location) {
                    liquidGlassLens(false)
                } else {
                    controlView.alpha = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.liquidGlassLens(false)
                    }
                }
            }
        default:
            break
        }
    }
}

// MARK: - IconScaleAnimation

private extension TabBarView {

    func showIconScaleAnimation(container: UIView) {
        tearDownIconScaleDisplayLink()
        startTimeIconScale = CACurrentMediaTime()
        startXIconScale = container.transform.a
        startYIconScale = container.transform.d
        conteinerIconScale = container
        setupIconScaleDisplayLink()
    }

    func setupIconScaleDisplayLink () {
        displayLinkIconScale = CADisplayLink(target: self, selector: #selector(updateIconScaleAnimation))
        displayLinkIconScale?.add(to: .main, forMode: .common)

        if #available(iOS 15.0, *) {
            displayLinkIconScale?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            displayLinkIconScale?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func updateIconScaleAnimation() {
        let elapsed = CACurrentMediaTime() - startTimeIconScale
        let animationDuration: CFTimeInterval = 0.3
        if elapsed >= animationDuration {
            conteinerIconScale.transform = CGAffineTransform(scaleX: liquidGlassLensView.lensScale, y: liquidGlassLensView.lensScale)
            tearDownIconScaleDisplayLink()
        } else {
            let progress = CGFloat(elapsed / animationDuration)
            let currentScale = startXIconScale + (liquidGlassLensView.lensScale - startXIconScale) * progress
            let currentScaleY = startYIconScale + (liquidGlassLensView.lensScale - startYIconScale) * progress
            conteinerIconScale.transform = CGAffineTransform(scaleX: currentScale, y: currentScaleY)
        }
    }

    func tearDownIconScaleDisplayLink() {
        displayLinkIconScale?.invalidate()
        displayLinkIconScale = nil
    }
}

// MARK: - IndicatorPositionAnimation

private extension TabBarView {

    func showIndicatorPositionAnimation() {
        tearDownIndicatorPositionDisplayLink()
        targetFrameIndicatorPosition = CGRect(x: CGFloat(currentIndex) * buttonWidth + 8, y: 4, width: buttonWidth - 16, height: tabBarView.bounds.height - 8)
        targetCenterIndicatorPosition = CGPoint(x: targetFrameIndicatorPosition.midX, y: targetFrameIndicatorPosition.midY)
        startFrameIndicatorPosition = controlView.frame
        startCenterIndicatorPosition = liquidGlassLensView.center
        setupIndicatorPositionDisplayLink()
        startTimeIndicatorPosition = CACurrentMediaTime()
    }

    func setupIndicatorPositionDisplayLink() {
        displayLinkIndicatorPosition = CADisplayLink(target: self, selector: #selector(updateIndicatorPositionAnimation))
        displayLinkIndicatorPosition?.add(to: .main, forMode: .common)

        if #available(iOS 15.0, *) {
            displayLinkIndicatorPosition?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            displayLinkIndicatorPosition?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func updateIndicatorPositionAnimation() {
        let duration: TimeInterval = 0.3
        let elapsed = CACurrentMediaTime() - startTimeIndicatorPosition
        let progress = min(elapsed / duration, 1.0)

        let springProgress = springIndicatorPositionProgress(for: progress, dampingRatio: 0.7)
        let currentX = startFrameIndicatorPosition.origin.x + (targetFrameIndicatorPosition.origin.x - startFrameIndicatorPosition.origin.x) * springProgress
        let currentWidth = startFrameIndicatorPosition.width + (targetFrameIndicatorPosition.width - startFrameIndicatorPosition.width) * springProgress
        controlView.frame = CGRect(x: currentX, y: 4, width: currentWidth, height: tabBarView.bounds.height - 8)

        let currentCenterX = startCenterIndicatorPosition.x + (targetCenterIndicatorPosition.x - startCenterIndicatorPosition.x) * springProgress
        let currentCenterY = startCenterIndicatorPosition.y + (targetCenterIndicatorPosition.y - startCenterIndicatorPosition.y) * springProgress
        liquidGlassLensView.center = CGPoint(x: currentCenterX, y: currentCenterY)

        if progress >= 1.0 {
            tearDownIndicatorPositionDisplayLink()
            controlView.frame = targetFrameIndicatorPosition
            liquidGlassLensView.center = targetCenterIndicatorPosition
            updateMaskIconsVisibility()
        }
    }

    func springIndicatorPositionProgress(for time: CGFloat, dampingRatio: CGFloat, initialVelocity: CGFloat = 0) -> CGFloat {
        if dampingRatio >= 1.0 {
            let omega0: CGFloat = 10.0
            return 1 - (1 + omega0 * time) * exp(-omega0 * time)
        } else {
            let omega0: CGFloat = 10.0
            let omega = omega0 * sqrt(1 - dampingRatio * dampingRatio)
            let decay = exp(-dampingRatio * omega0 * time)
            return 1 - decay * ((dampingRatio * omega0 / omega) * sin(omega * time) + cos(omega * time))
        }
    }

    func tearDownIndicatorPositionDisplayLink() {
        displayLinkIndicatorPosition?.invalidate()
        displayLinkIndicatorPosition = nil
        startTimeIndicatorPosition = 0
    }
}

// MARK: - MaskIconsVisibilityAnimation

private extension TabBarView {

    func showMaskIconsVisibilityAnimation(animations: [() -> Void]) {
        tearDownMaskIconsVisibilityDisplayLink()
        animationMaskIconsVisibility = animations
        displayLinkMaskIconsVisibility = CADisplayLink(target: self, selector: #selector(updateMaskIconsVisibilityAnimation))
        setupMaskIconsVisibilityDisplayLink()
    }

    func setupMaskIconsVisibilityDisplayLink() {
        displayLinkMaskIconsVisibility?.add(to: .main, forMode: .common)
        startTimeMaskIconsVisibility = CACurrentMediaTime()

        if #available(iOS 15.0, *) {
            displayLinkIndicatorPosition?.preferredFrameRateRange = CAFrameRateRange(
                minimum: determineEnergySavingMode() ? 15 : 30,
                maximum: determineEnergySavingMode() ? 30 : 60,
                preferred: determineEnergySavingMode() ? 30 : 60)
        } else {
            let targetFPS = determineEnergySavingMode() ? 30 : 60
            let maxDeviceFPS = UIScreen.main.maximumFramesPerSecond
            displayLinkIndicatorPosition?.preferredFramesPerSecond = min(targetFPS, maxDeviceFPS)
        }
    }

    @objc func updateMaskIconsVisibilityAnimation() {
        let duration: TimeInterval = 0.3
        let progress = min((CACurrentMediaTime() - startTimeMaskIconsVisibility) / duration, 1.0)
        if progress >= 1.0 {
            animationMaskIconsVisibility.forEach { $0() }
            tearDownMaskIconsVisibilityDisplayLink()
        } else {
            animationMaskIconsVisibility.forEach { $0() }
        }
    }

    func tearDownMaskIconsVisibilityDisplayLink() {
        displayLinkMaskIconsVisibility?.invalidate()
        displayLinkMaskIconsVisibility = nil
        startTimeMaskIconsVisibility = 0
    }
}

// MARK: - liquidGlassLens

private extension TabBarView {

    func liquidGlassLens(_ isShow: Bool = true) {
        if isShow {
            controlView.layer.opacity = 0
            liquidGlassLensView.showLens(animation: { [weak self] in
                self?.tabBarView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                self?.tabBarView.blurContainer.layer.opacity = 0.8
                self?.tabBarView.highlightLayer.opacity = 0.6
            }) { [weak self] in
                guard let self else { return }
                controlView.frame = liquidGlassLensView.frame
            }
        } else {
            liquidGlassLensView.hideLens(animation: { [weak self] in
                self?.tabBarView.transform = .identity
                self?.tabBarView.blurContainer.layer.opacity = 0.4
                self?.tabBarView.highlightLayer.opacity = 0
            }) { [weak self] in
                guard let self else { return }
                controlView.frame = CGRect(x: CGFloat(currentIndex) * buttonWidth + 8, y: 4, width: buttonWidth - 16, height: tabBarView.bounds.height - 8)
                controlView.layer.opacity = 1
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TabBarView: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
