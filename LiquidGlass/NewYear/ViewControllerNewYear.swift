import UIKit
import CoreMotion
import CoreImage
import simd

class WeakRef<T: AnyObject> {
    weak var value: T?
    init(value: T) { self.value = value }
}

// MARK: - Системный менеджер Liquid Glass
class LiquidGlassSystem {
    static let shared = LiquidGlassSystem()
    private init() {}

    private var activeGlassElements: [WeakRef<AnyObject>] = []
    private let motionManager = CMMotionManager()
    private var displayLink: CADisplayLink?
    private var globalLightPosition = SIMD2<Float>(0.5, 0.5)

    func register(element: LiquidGlassElement) {
        activeGlassElements.append(WeakRef(value: element))
        if activeGlassElements.count == 1 {
            startSystem()
        }
    }

    func unregister(element: LiquidGlassElement) {
        activeGlassElements.removeAll { $0.value === element }
        if activeGlassElements.isEmpty {
            stopSystem()
        }
    }

    private func startSystem() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateAllElements))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                self?.updateGlobalLight(with: motion)
            }
        }
    }

    private func stopSystem() {
        displayLink?.invalidate()
        motionManager.stopDeviceMotionUpdates()
    }

    private func updateGlobalLight(with motion: CMDeviceMotion) {
        let gravity = motion.gravity
        globalLightPosition = SIMD2<Float>(
            Float(gravity.x * 0.5 + 0.5),
            Float(gravity.y * 0.5 + 0.5)
        )
    }

    @objc private func updateAllElements() {
        for weakElement in activeGlassElements {
            guard let element = weakElement.value as? LiquidGlassElement else { continue }
            element.updateWithGlobalLight(position: globalLightPosition)
        }
    }
}

// MARK: - Основной элемент Liquid Glass
protocol LiquidGlassElement: AnyObject {
    func updateWithGlobalLight(position: SIMD2<Float>)
}

// MARK: - Реализация Lensing Effect (преломление света)
class LensingLayer: CALayer {
    private let lensingFilter = CIFilter(name: "CILightTunnel")
    private let distortionFilter = CIFilter(name: "CIDroste")
    private var displayLink: CADisplayLink?

    override init() {
        super.init()
        setupLensing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLensing()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    private func setupLensing() {
        // Настройка фильтров преломления
        lensingFilter?.setValue(100.0, forKey: "inputRadius")
        lensingFilter?.setValue(0.5, forKey: "inputRotation")

        distortionFilter?.setValue(0.1, forKey: "inputStrands")
        distortionFilter?.setValue(0.5, forKey: "inputPeriodicity")

        // Динамическое обновление
        displayLink = CADisplayLink(target: self, selector: #selector(updateLensing))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateLensing() {
        // Динамическое изменение параметров преломления
        let time = CACurrentMediaTime()
        let rotation = sin(time * 0.5) * 0.1 + 0.5
        lensingFilter?.setValue(rotation, forKey: "inputRotation")

        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard let currentFilter = lensingFilter,
              let outputImage = currentFilter.outputImage else {
            super.draw(in: ctx)
            return
        }

        let ciContext = CIContext(cgContext: ctx, options: nil)
        let cgImage = ciContext.createCGImage(outputImage, from: bounds)

        if let cgImage = cgImage {
            ctx.draw(cgImage, in: bounds)
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - Адаптивный Shadow Layer (тень реагирует на контент)
class AdaptiveShadowLayer: CALayer {
    private var backgroundAnalyzer: BackgroundAnalyzer?
    var isOverText: Bool = false {
        didSet { updateShadow() }
    }

    override init() {
        super.init()
        setupShadow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupShadow()
    }

    private func setupShadow() {
        shadowColor = UIColor.black.cgColor
        shadowOffset = CGSize(width: 0, height: 2)
        shadowRadius = 8
        masksToBounds = false
        shouldRasterize = true
        rasterizationScale = UIScreen.main.scale
    }

    private func updateShadow() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)

        if isOverText {
            // Усиленная тень над текстом для лучшего разделения
            shadowOpacity = 0.4
            shadowRadius = 12
        } else {
            // Мягкая тень над сплошным фоном
            shadowOpacity = 0.2
            shadowRadius = 8
        }

        CATransaction.commit()
    }

    func updateWithBackground(brightness: CGFloat, hasComplexContent: Bool) {
        // Адаптация тени к яркости и сложности фона
        let targetOpacity: Float

        if brightness < 0.3 { // Темный фон
            targetOpacity = hasComplexContent ? 0.3 : 0.2
        } else if brightness > 0.7 { // Светлый фон
            targetOpacity = hasComplexContent ? 0.25 : 0.15
        } else { // Средняя яркость
            targetOpacity = hasComplexContent ? 0.35 : 0.25
        }

//        shadowOpacity = targetOpacity
    }
}

// MARK: - Анализатор фона для адаптивности
class BackgroundAnalyzer {
    func analyzeBackground(for view: UIView) -> (brightness: CGFloat, hasText: Bool, complexity: CGFloat) {
        guard let window = view.window else { return (0.5, false, 0.5) }

        // Получаем снимок области под вьюхой
        let glassFrame = view.convert(view.bounds, to: window)
        let renderer = UIGraphicsImageRenderer(bounds: glassFrame)
        let snapshot = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        // Анализируем изображение
        return analyzeImage(snapshot)
    }

    private func analyzeImage(_ image: UIImage) -> (brightness: CGFloat, hasText: Bool, complexity: CGFloat) {
        guard let cgImage = image.cgImage else { return (0.5, false, 0.5) }

        let ciImage = CIImage(cgImage: cgImage)

        // 1. Анализ яркости
        let brightnessFilter = CIFilter(name: "CIAreaAverage")!
        brightnessFilter.setValue(ciImage, forKey: kCIInputImageKey)
        brightnessFilter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = brightnessFilter.outputImage else {
            return (0.5, false, 0.5)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: nil)
        context.render(outputImage,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: nil)

        let brightness = CGFloat(bitmap[0]) / 255.0 * 0.299 +
                        CGFloat(bitmap[1]) / 255.0 * 0.587 +
                        CGFloat(bitmap[2]) / 255.0 * 0.114

        // 2. Анализ сложности (вариация яркости)
        let varianceFilter = CIFilter(name: "CIColorMatrix")!
        // Упрощенный анализ - в реальности нужна более сложная логика

        return (brightness, brightness < 0.5, 0.5)
    }
}

// MARK: - Полная реализация Liquid Glass View
class LiquidGlassView: UIView, LiquidGlassElement {

    enum GlassVariant {
        case regular    // Универсальный, адаптивный
        case clear      // Только для медиаконтента, требует затемнения
    }

    enum SizeCategory {
        case small      // Кнопки, иконки (более прозрачные)
        case medium     // Панели, меню
        case large      // Боковые панели, большие элементы (менее прозрачные)
    }

    // MARK: - Конфигурация
    var variant: GlassVariant = .regular {
        didSet { updateVariant() }
    }

    var sizeCategory: SizeCategory = .medium {
        didSet { updateSizeCategory() }
    }

    override var tintColor: UIColor? {
        didSet { updateTint() }
    }

    var isInteractive: Bool = true {
        didSet { updateInteractivity() }
    }

    // MARK: - Слои
    private let lensingLayer = LensingLayer()
    private let shadowLayer = AdaptiveShadowLayer()
    private let highlightsLayer = CALayer()
    private let reflectionsLayer = CAGradientLayer()
    private let tintLayer = CALayer()
    private let dimmingLayer = CALayer()
    private let contentContainer = UIView()

    // MARK: - Состояние
    private var isPressed = false
    private var isDragging = false
    private var currentTouchLocation: CGPoint = .zero
    private var backgroundAnalyzer = BackgroundAnalyzer()
    private var backgroundUpdateTimer: Timer?

    // MARK: - Инициализация
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Регистрация в системе
        LiquidGlassSystem.shared.register(element: self)

        // Настройка
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        // Иерархия слоев
        layer.addSublayer(shadowLayer)
        layer.addSublayer(lensingLayer)
        layer.addSublayer(highlightsLayer)
        layer.addSublayer(reflectionsLayer)
        layer.addSublayer(tintLayer)
        layer.addSublayer(dimmingLayer)
        addSubview(contentContainer)

        // Настройка каждого слоя
        setupLensingLayer()
        setupShadowLayer()
        setupHighlightsLayer()
        setupReflectionsLayer()
        setupTintLayer()
        setupDimmingLayer()

        // Жесты
        setupGestures()

        // Анализ фона
        startBackgroundAnalysis()

        // Обновление
        updateAppearance()
    }

    // MARK: - Настройка слоев
    private func setupLensingLayer() {
        lensingLayer.frame = bounds
        lensingLayer.cornerRadius = layer.cornerRadius
        lensingLayer.masksToBounds = true
    }

    private func setupShadowLayer() {
        shadowLayer.frame = bounds
        shadowLayer.cornerRadius = layer.cornerRadius
    }

    private func setupHighlightsLayer() {
        highlightsLayer.frame = bounds
        highlightsLayer.cornerRadius = layer.cornerRadius
        highlightsLayer.masksToBounds = true

        // Динамические блики
        let highlightGradient = CAGradientLayer()
        highlightGradient.frame = bounds
        highlightGradient.type = .radial
        highlightGradient.colors = [
            UIColor.white.withAlphaComponent(0.8).cgColor,
            UIColor.white.withAlphaComponent(0.2).cgColor,
            UIColor.clear.cgColor
        ]
        highlightGradient.locations = [0, 0.3, 1.0]
        highlightGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        highlightGradient.endPoint = CGPoint(x: 1.0, y: 1.0)

        highlightsLayer.addSublayer(highlightGradient)
    }

    private func setupReflectionsLayer() {
        reflectionsLayer.frame = bounds
        reflectionsLayer.cornerRadius = layer.cornerRadius
        reflectionsLayer.masksToBounds = true

        reflectionsLayer.colors = [
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionsLayer.locations = [0, 0.5, 1.0]
        reflectionsLayer.startPoint = CGPoint(x: 0.5, y: 0)
        reflectionsLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func setupTintLayer() {
        tintLayer.frame = bounds
        tintLayer.cornerRadius = layer.cornerRadius
        tintLayer.masksToBounds = true
        tintLayer.compositingFilter = "overlayBlendMode"
        tintLayer.isHidden = true
    }

    private func setupDimmingLayer() {
        dimmingLayer.frame = bounds
        dimmingLayer.cornerRadius = layer.cornerRadius
        dimmingLayer.masksToBounds = true
        dimmingLayer.backgroundColor = UIColor.black.withAlphaComponent(0.3).cgColor
        dimmingLayer.isHidden = true
    }

    // MARK: - Адаптация к фону
    private func startBackgroundAnalysis() {
        backgroundUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.analyzeBackground()
        }
    }

    private func analyzeBackground() {
        let analysis = backgroundAnalyzer.analyzeBackground(for: self)

        // Адаптация к яркости фона
        let brightness = analysis.brightness
        let isDarkBackground = brightness < 0.5

        // Переключение светлого/темного режима
        if variant == .regular && sizeCategory != .large {
            // Малые и средние элементы переключают режим
            UIView.transition(with: self, duration: 0.3, options: .transitionCrossDissolve) {
                self.updateForBackgroundBrightness(brightness, isDark: isDarkBackground)
            }
        }

        // Адаптация тени
        shadowLayer.updateWithBackground(brightness: brightness,
                                        hasComplexContent: analysis.hasText)

        // Для Clear variant требуется затемнение
        if variant == .clear {
            let dimmingAlpha = isDarkBackground ? 0.2 : 0.4
            dimmingLayer.backgroundColor = UIColor.black.withAlphaComponent(dimmingAlpha).cgColor
            dimmingLayer.isHidden = false
        }
    }

    private func updateForBackgroundBrightness(_ brightness: CGFloat, isDark: Bool) {
        if isDark {
            // Темный режим для темного фона
            highlightsLayer.opacity = 0.3
            reflectionsLayer.opacity = 0.2
            lensingLayer.opacity = 0.4
        } else {
            // Светлый режим для светлого фона
            highlightsLayer.opacity = 0.6
            reflectionsLayer.opacity = 0.4
            lensingLayer.opacity = 0.6
        }

        // Адаптация прозрачности
        let targetAlpha: CGFloat
        switch sizeCategory {
        case .small:
            targetAlpha = 0.7
        case .medium:
            targetAlpha = 0.8
        case .large:
            targetAlpha = 0.9
        }

        UIView.animate(withDuration: 0.3) {
            self.alpha = targetAlpha
        }
    }

    // MARK: - LiquidGlassElement Protocol
    func updateWithGlobalLight(position: SIMD2<Float>) {
        // Обновление бликов в зависимости от глобального источника света
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let xPercent = CGFloat(position.x)
        let yPercent = CGFloat(position.y)

        // Перемещаем блики
        if let gradient = highlightsLayer.sublayers?.first as? CAGradientLayer {
            gradient.startPoint = CGPoint(x: xPercent, y: yPercent)
            gradient.endPoint = CGPoint(x: xPercent + 0.5, y: yPercent + 0.5)
        }

        CATransaction.commit()
    }

    // MARK: - Эффект растягивания (как вода)
    private func applyLiquidStretch(to location: CGPoint) {
        guard isInteractive else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let delta = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let distance = hypot(delta.x, delta.y)
        let maxDistance = min(bounds.width, bounds.height) * 0.4

        if distance > maxDistance {
            // Эффект растягивания за пределы
            let overshoot = (distance - maxDistance) / maxDistance
            applyOvershootStretch(delta: delta, overshoot: overshoot)
        } else {
            // Нормальное растягивание
            let intensity = distance / maxDistance
            applyNormalStretch(delta: delta, intensity: intensity)
        }

        // Обновляем блики в сторону растягивания
        updateHighlightsForStretch(delta: delta)
    }

    private func applyNormalStretch(delta: CGPoint, intensity: CGFloat) {
        let scaleX = 1.0 + abs(delta.x) / bounds.width * intensity * 0.3
        let scaleY = 1.0 + abs(delta.y) / bounds.height * intensity * 0.3

        let rotation = atan2(delta.y, delta.x) * intensity * 0.1

        UIView.animate(withDuration: 0.2, delay: 0,
                      usingSpringWithDamping: 0.6,
                      initialSpringVelocity: 0,
                      options: [.allowUserInteraction]) {
            self.transform = CGAffineTransform(rotationAngle: rotation)
                .scaledBy(x: scaleX, y: scaleY)
        }
    }

    private func applyOvershootStretch(delta: CGPoint, overshoot: CGFloat) {
        // Эффект упругого перерастяжения
        let resistance: CGFloat = 0.3
        let stretchFactor = 1.0 + overshoot * resistance

        let direction = CGPoint(x: delta.x / hypot(delta.x, delta.y),
                               y: delta.y / hypot(delta.x, delta.y))

        let targetTransform = CGAffineTransform(scaleX: 1.0 + direction.x * stretchFactor * 0.4,
                                               y: 1.0 + direction.y * stretchFactor * 0.4)

        UIView.animate(withDuration: 0.3, delay: 0,
                      usingSpringWithDamping: 0.4,
                      initialSpringVelocity: 0.5,
                      options: [.allowUserInteraction]) {
            self.transform = targetTransform
        }
    }

    private func updateHighlightsForStretch(delta: CGPoint) {
        let angle = atan2(delta.y, delta.x)
        let distance = hypot(delta.x, delta.y)
        let maxDistance = min(bounds.width, bounds.height) * 0.5

        let highlightX = 0.5 + cos(angle) * (distance / maxDistance) * 0.3
        let highlightY = 0.5 + sin(angle) * (distance / maxDistance) * 0.3

        if let gradient = highlightsLayer.sublayers?.first as? CAGradientLayer {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1)
            gradient.startPoint = CGPoint(x: highlightX, y: highlightY)
            CATransaction.commit()
        }
    }

    private func resetStretch() {
        UIView.animate(withDuration: 0.8, delay: 0,
                      usingSpringWithDamping: 0.3,
                      initialSpringVelocity: 0,
                      options: [.allowUserInteraction]) {
            self.transform = .identity
        }
    }

    // MARK: - Жесты и взаимодействие
    private func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.15
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPressed = true
            animateMaterialization()
            playHapticFeedback(.light)

        case .ended, .cancelled:
            isPressed = false
            animateDematerialization()
            resetStretch()

        default:
            break
        }
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDragging = true
            currentTouchLocation = gesture.location(in: self)

        case .changed:
            currentTouchLocation = gesture.location(in: self)
            applyLiquidStretch(to: currentTouchLocation)
        case .ended, .cancelled:
            isDragging = false
            resetStretch()
        default:
            break
        }
    }

    // MARK: - Анимации материала
    private func animateMaterialization() {
        // Эффект "материализации" как в оригинале
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.9
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = 0.3
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.5
        opacityAnimation.toValue = 1.0
        opacityAnimation.duration = 0.3

        layer.add(scaleAnimation, forKey: "materializeScale")
        layer.add(opacityAnimation, forKey: "materializeOpacity")

        // Подсветка при нажатии
        let glowAnimation = CABasicAnimation(keyPath: "opacity")
        glowAnimation.fromValue = 0.3
        glowAnimation.toValue = 0.8
        glowAnimation.duration = 0.2
        glowAnimation.autoreverses = true

        tintLayer.add(glowAnimation, forKey: "pressGlow")
    }

    private func animateDematerialization() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.8
        animation.duration = 0.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)

        layer.add(animation, forKey: "dematerialize")
    }

    private func playHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    // MARK: - Обновление внешнего вида
    private func updateVariant() {
        switch variant {
        case .regular:
            dimmingLayer.isHidden = true
            lensingLayer.opacity = 0.6
            highlightsLayer.opacity = 0.6

        case .clear:
            dimmingLayer.isHidden = false
            lensingLayer.opacity = 0.4
            highlightsLayer.opacity = 0.3
            // Clear variant не адаптирует цвет
            shadowLayer.isOverText = false
        }
    }

    private func updateSizeCategory() {
        switch sizeCategory {
        case .small:
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
            alpha = 0.7
            shadowLayer.shadowRadius = 4

        case .medium:
            layer.cornerRadius = 12
            alpha = 0.8
            shadowLayer.shadowRadius = 8

        case .large:
            layer.cornerRadius = 16
            alpha = 0.9
            shadowLayer.shadowRadius = 12
        }

        // Обновляем радиусы всех слоев
        updateCornerRadius()
    }

    private func updateTint() {
        if let tintColor = tintColor {
            tintLayer.isHidden = false
            tintLayer.backgroundColor = tintColor.withAlphaComponent(0.2).cgColor
        } else {
            tintLayer.isHidden = true
        }
    }

    private func updateInteractivity() {
        isUserInteractionEnabled = isInteractive
    }

    private func updateCornerRadius() {
        let radius = layer.cornerRadius
        lensingLayer.cornerRadius = radius
//        shadowLayer.cornerRadius = radius
        highlightsLayer.cornerRadius = radius
        reflectionsLayer.cornerRadius = radius
        tintLayer.cornerRadius = radius
        dimmingLayer.cornerRadius = radius
    }

    private func updateAppearance() {
        updateVariant()
        updateSizeCategory()
        updateTint()
        updateInteractivity()
        updateCornerRadius()
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()

        lensingLayer.frame = bounds
//        shadowLayer.frame = bounds
        highlightsLayer.frame = bounds
        reflectionsLayer.frame = bounds
        tintLayer.frame = bounds
        dimmingLayer.frame = bounds
        contentContainer.frame = bounds

        updateSizeCategory()
    }

    // MARK: - Доступность
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            analyzeBackground()
        }

        // Проверка настроек доступности
        updateForAccessibilitySettings()
    }

    private func updateForAccessibilitySettings() {
        if UIAccessibility.isReduceTransparencyEnabled {
            // Упрощенный вид
            alpha = 0.9
            lensingLayer.opacity = 0
            highlightsLayer.opacity = 0
            reflectionsLayer.opacity = 0
            shadowLayer.shadowOpacity = 0.1
        } else {
            analyzeBackground()
        }

        if UIAccessibility.isReduceMotionEnabled {
            // Отключаем анимации
            lensingLayer.removeAllAnimations()
            highlightsLayer.removeAllAnimations()
        }

        if UIAccessibility.isDarkerSystemColorsEnabled {
            // Увеличиваем контраст
            shadowLayer.shadowOpacity = 0.4
            shadowLayer.shadowRadius += 2
        }
    }

    // MARK: - Слияние элементов
    func prepareForMerge() {
        // Подготовка к слиянию с другим элементом
        UIView.animate(withDuration: 0.3) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.alpha = 0.9
        }
    }

    func resetFromMerge() {
        UIView.animate(withDuration: 0.3) {
            self.transform = .identity
            self.alpha = 1.0
        }
    }

    // MARK: - Деинициализация
    deinit {
        backgroundUpdateTimer?.invalidate()
        LiquidGlassSystem.shared.unregister(element: self)
    }
}

// MARK: - Готовые компоненты
class LiquidGlassButton2: UIButton {
    let glassView: LiquidGlassView

    init(variant: LiquidGlassView.GlassVariant = .regular,
         sizeCategory: LiquidGlassView.SizeCategory = .small) {
        self.glassView = LiquidGlassView()
        super.init(frame: .zero)

        glassView.variant = variant
        glassView.sizeCategory = sizeCategory
        glassView.isInteractive = true

        setup()
    }

    required init?(coder: NSCoder) {
        self.glassView = LiquidGlassView()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Настройка кнопки
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        setTitleColor(.label, for: .normal)

        // Добавление эффекта
        insertSubview(glassView, at: 0)

        // Жесты
        addTarget(self, action: #selector(playHaptic), for: .touchDown)

        // Для трекпада
        if #available(iOS 13.4, *) {
            addInteraction(UIPointerInteraction(delegate: self))
        }
    }

    @objc private func playHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
    }
}

class LiquidGlassSwitch1: UIControl {
    let glassView: LiquidGlassView
    private let thumbView = UIView()
    private let backgroundView = UIView()

    var isOn: Bool = false {
        didSet {
            updateThumbPosition(animated: true)
            sendActions(for: .valueChanged)
        }
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 60, height: 36)
    }

    init() {
        self.glassView = LiquidGlassView()
        super.init(frame: .zero)

        glassView.variant = .regular
        glassView.sizeCategory = .small
        glassView.isInteractive = true

        setup()
    }

    required init?(coder: NSCoder) {
        self.glassView = LiquidGlassView()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Фон
        backgroundView.backgroundColor = .systemGray4
        backgroundView.layer.cornerRadius = 18
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        // Эффект стекла
        addSubview(glassView)

        // Ползунок с эффектом
        thumbView.backgroundColor = .white
        thumbView.layer.cornerRadius = 14
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOpacity = 0.2
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 2)
        thumbView.layer.shadowRadius = 2
        addSubview(thumbView)

        // Жесты
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleSwitch))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        updateThumbPosition(animated: false)
    }

    @objc private func toggleSwitch() {
        isOn.toggle()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .changed:
            // Растягивание при перетаскивании
            let location = gesture.location(in: self)
            glassView.handlePan(gesture)

            // Перемещение ползунка
            let minX: CGFloat = 4
            let maxX = bounds.width - thumbView.bounds.width - 4
            let newX = min(max(thumbView.frame.origin.x + translation.x, minX), maxX)

            thumbView.frame.origin.x = newX
            gesture.setTranslation(.zero, in: self)

        case .ended:
            // Определяем положение
            let shouldTurnOn = thumbView.center.x > bounds.midX
            isOn = shouldTurnOn

        default:
            break
        }
    }

    private func updateThumbPosition(animated: Bool) {
        let thumbPosition = isOn ? bounds.width - 32 : 4

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0,
                          usingSpringWithDamping: 0.7,
                          initialSpringVelocity: 0,
                          options: [.curveEaseInOut]) {
                self.thumbView.frame = CGRect(x: thumbPosition, y: 4, width: 28, height: 28)
                self.backgroundView.backgroundColor = self.isOn ? .systemGreen : .systemGray4
                self.glassView.alpha = self.isOn ? 0.8 : 0.5
            }
        } else {
            thumbView.frame = CGRect(x: thumbPosition, y: 4, width: 28, height: 28)
            backgroundView.backgroundColor = isOn ? .systemGreen : .systemGray4
            glassView.alpha = isOn ? 0.8 : 0.5
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        glassView.frame = bounds
        updateThumbPosition(animated: false)
    }
}

// MARK: - Расширения для интеграции
@available(iOS 13.4, *)
extension LiquidGlassButton2: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction,
                           styleFor region: UIPointerRegion) -> UIPointerStyle? {
        var pointerStyle: UIPointerStyle?

        if let interactionView = interaction.view {
            let targetedPreview = UITargetedPreview(view: interactionView)
            pointerStyle = UIPointerStyle(effect: .lift(targetedPreview))
        }

        return pointerStyle
    }
}

// MARK: - Пример использования
class ViewController1: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Кнопка с эффектом Liquid Glass
        let button = LiquidGlassButton2(variant: .regular, sizeCategory: .small)
        button.setTitle("L", for: .normal)
        button.frame = CGRect(x: 100, y: 200, width: 50, height: 50)

        // Свитч с эффектом
        let glassSwitch = LiquidGlassSwitch1()
        glassSwitch.frame = CGRect(x: 50, y: 400, width: 60, height: 36)
        glassSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        // Еще одна кнопка для демонстрации слияния
        let button2 = LiquidGlassButton2(variant: .clear, sizeCategory: .small)
        button2.setTitle("C", for: .normal)
        button2.tintColor = .systemBlue
        button2.frame = CGRect(x: 200, y: 200, width: 50, height: 50)

        view.addSubview(button)
        view.addSubview(glassSwitch)
        view.addSubview(button2)
    }

    @objc func switchChanged() {
        print("Switch changed")
    }
}
