import UIKit
import CoreHaptics

// MARK: - Расширенная имитация Liquid Glass для старых iOS
class CompatibleLiquidGlassView: UIView {

    // MARK: - Свойства границы
    var borderWidth: CGFloat = 2.0 {
        didSet { updateBorder() }
    }

    var borderColor: UIColor = .white {
        didSet { updateBorder() }
    }

    // MARK: - Конфигурация
    struct GlassConfig {
        var opacity: CGFloat
        var tintColor: UIColor?
        var cornerRadius: CGFloat
        var isInteractive: Bool
        var sizeCategory: SizeCategory

        enum SizeCategory {
            case small, medium, large
        }
    }

    // MARK: - Слои
    private let blurContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tintLayer = CALayer()
    private let highlightLayer = CAGradientLayer()
    private let reflectionLayer = CAGradientLayer()
    private let contentContainer = UIView()
    private let borderLayer = CAShapeLayer()
    private let borderMaskLayer = CAShapeLayer()

    // MARK: - Состояние
    private var isPressed = false
    private var isDragging = false
    private var currentDragLocation: CGPoint = .zero
    private var hapticEngine: CHHapticEngine?
    private var borderAnimationTimer: CADisplayLink?

    let longPressGesture = UILongPressGestureRecognizer()
    let panGesture = UIPanGestureRecognizer()

    // MARK: - Конфигурация
    var config = GlassConfig(
        opacity: 0.5,
        tintColor: nil,
        cornerRadius: 12,
        isInteractive: true,
        sizeCategory: .medium
    ) {
        didSet { updateAppearance() }
    }

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
        // 1. Настройка базовых свойств
        //      backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = true

        // 2. Настройка слоев
        setupBlurContainer()
        setupTintLayer()
        setupBorderLayer()

        // 3. Настройка жестов
        setupGestures()

        // 4. Настройка тактильной отдачи
        setupHaptics()

        // 5. Обновление внешнего вида
        updateAppearance()
    }

    private func setupBorderLayer() {
        // Настройка слоя границы
        borderLayer.frame = bounds
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = borderColor.cgColor
        borderLayer.lineWidth = borderWidth
        borderLayer.lineCap = .round
        borderLayer.lineJoin = .round
        borderLayer.mask = borderMaskLayer

        // Добавляем слой поверх размытия
        layer.addSublayer(borderLayer)

        // Настройка маски
        borderMaskLayer.fillRule = .evenOdd
    }

    private func setupBlurContainer() {
        blurContainer.frame = bounds
        blurContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurContainer.isUserInteractionEnabled = true

        // Многоуровневое размытие для глубины
        let extraBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        extraBlur.frame = blurContainer.bounds
        extraBlur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        extraBlur.alpha = 0.3

        blurContainer.contentView.addSubview(extraBlur)
        addSubview(blurContainer)
    }

    private func setupTintLayer() {
        tintLayer.frame = bounds
        tintLayer.cornerRadius = config.cornerRadius
        tintLayer.compositingFilter = "overlayBlendMode"
        blurContainer.contentView.layer.addSublayer(tintLayer)
    }

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptic engine error: \(error)")
        }
    }

    // MARK: - Адаптивный внешний вид
    private func updateAppearance() {
        // 1. Прозрачность в зависимости от размера
        switch config.sizeCategory {
        case .small:
            blurContainer.alpha = 0.6
            highlightLayer.opacity = 0.4
        case .medium:
            blurContainer.alpha = 0.8
            highlightLayer.opacity = 0.6
        case .large:
            blurContainer.alpha = 0.9
            highlightLayer.opacity = 0.8
        }

        // 2. Цвет tint
        if let tintColor = config.tintColor {
            tintLayer.backgroundColor = tintColor.withAlphaComponent(0.15).cgColor
            tintLayer.isHidden = false
        } else {
            tintLayer.isHidden = true
        }

        // 3. Скругления
        layer.cornerRadius = config.cornerRadius
        blurContainer.layer.cornerRadius = config.cornerRadius
        tintLayer.cornerRadius = config.cornerRadius

        // 4. Обновление границы
        updateBorder()

        // 5. Адаптация к теме
        updateForCurrentInterfaceStyle()
    }

    private func updateBorder() {
        // Обновляем путь границы с учетом скруглений
        let path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: borderWidth/2, dy: borderWidth/2),
            cornerRadius: config.cornerRadius
        )
        borderLayer.path = path.cgPath
        borderLayer.strokeColor = borderColor.cgColor
        borderLayer.lineWidth = borderWidth

        updateBorderMask()
    }

    private func updateForCurrentInterfaceStyle() {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark

        // Автоматическое переключение светлых/темных бликов
        if isDarkMode {
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

    // MARK: - Эффект растягивания (как вода)
    private func applyStretchEffect(to location: CGPoint) {
        guard config.isInteractive else { return }

        // 1. Вычисляем вектор растягивания от центра
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y

        // 2. Вычисляем расстояние и нормализуем
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        let maxDistance: CGFloat = min(bounds.width, bounds.height) * 0.9
        let normalizedDistance = min(distance / maxDistance, 1.0)

        // 3. Применяем трансформацию с пружинной анимацией
        let scaleX = 1.388 + (normalizedDistance * abs(deltaX) / maxDistance) * 0.3
        let scaleY = 1.388 + (normalizedDistance * abs(deltaY) / maxDistance) * 0.3

        // 4. Вращаем в направлении растягивания
        let rotationAngle = atan2(deltaY, deltaX) * 0.2 * normalizedDistance

        self.transform = CGAffineTransform(rotationAngle: rotationAngle)
            .scaledBy(x: scaleX, y: scaleY)
            .translatedBy(x: deltaX * 0.2 * normalizedDistance, y: deltaY * 0.2 * normalizedDistance)


        // 5. Деформация внутренних слоев
        self.highlightLayer.setAffineTransform(
            CGAffineTransform(scaleX: 1/scaleX, y: 1/scaleY)
                .rotated(by: -rotationAngle * 0.5))

        // 6. Тактильная отдача
        playStretchHaptic(intensity: Float(normalizedDistance))

        // 7. Обновляем маску при растяжении
        updateBorderMask()
    }

    // MARK: - Умная граница с исчезновением при пересечении
    func updateBorderMask() {
        // Получаем другую view через супервью
        guard let superview = superview,
              let otherView = findOtherView() else {
            // Нет другой view - показываем полную границу
            // Создаем маску, которая скрывает границу в области пересечения
            let maskPath = CGMutablePath()

            // Добавляем основной прямоугольник (вся view)
            let insetBounds = bounds.insetBy(dx: borderWidth/2, dy: borderWidth/2)
            maskPath.addRoundedRect(in: insetBounds,
                                    cornerWidth: config.cornerRadius,
                                    cornerHeight: config.cornerRadius)
            borderMaskLayer.path = maskPath
            return
        }

        // Находим пересечение в координатах супервью
        let intersection = frame.intersection(otherView.frame)

        if intersection.isNull {
            // Нет пересечения - показываем полную границу
            let maskPath = CGMutablePath()

            // Добавляем основной прямоугольник (вся view)
            let insetBounds = bounds.insetBy(dx: borderWidth/2, dy: borderWidth/2)
            maskPath.addRoundedRect(in: insetBounds,
                                    cornerWidth: config.cornerRadius,
                                    cornerHeight: config.cornerRadius)
            borderMaskLayer.path = maskPath
            return
        }

        // Преобразуем пересечение в локальные координаты этой view
        let localIntersection = convert(intersection, from: superview)

        // Создаем маску, которая скрывает границу в области пересечения
        let maskPath = CGMutablePath()

        // Добавляем основной прямоугольник (вся view)
        let insetBounds = bounds.insetBy(dx: borderWidth/2, dy: borderWidth/2)
        maskPath.addRoundedRect(in: insetBounds,
                                cornerWidth: config.cornerRadius,
                                cornerHeight: config.cornerRadius)

        // Добавляем "дырку" в месте пересечения (с небольшим отступом)
        let holeRect = localIntersection.insetBy(dx: 0, dy: 0)
        maskPath.addRoundedRect(in: holeRect,
                                cornerWidth: config.cornerRadius,
                                cornerHeight: config.cornerRadius)

        borderMaskLayer.path = maskPath
    }

    private func findOtherView() -> CompatibleLiquidGlassView? {
        // Ищем другую CompatibleLiquidGlassView в том же супервью
        return superview?.subviews.first {
            $0 is CompatibleLiquidGlassView && $0 != self
        } as? CompatibleLiquidGlassView
    }

    private func startBorderAnimation() {
        // Запускаем анимацию обновления границы
        borderAnimationTimer?.invalidate()
        borderAnimationTimer = CADisplayLink(target: self, selector: #selector(updateBorderContinuously))
        borderAnimationTimer?.add(to: .main, forMode: .common)
    }

    private func stopBorderAnimation() {
        borderAnimationTimer?.invalidate()
        borderAnimationTimer = nil
    }

    @objc private func updateBorderContinuously() {
        // Оптимизация: обновляем только если view видима и есть супервью
        guard window != nil, superview != nil else { return }
        updateBorderMask()
        // Добавляем: обновляем границу другой view
        if let otherView = findOtherView() {
            otherView.updateBorderMask()
        }
    }

    private func resetStretchEffect() {
        UIView.animate(withDuration: 0.8, delay: 0,
                       usingSpringWithDamping: 0.4,
                       initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.transform = .identity
            self.highlightLayer.setAffineTransform(.identity)
        }
    }

    private func playStretchHaptic(intensity: Float) {
        guard let engine = hapticEngine else { return }

        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [sharpness, intensityParam],
            relativeTime: 0,
            duration: 0.1
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Haptic error: \(error)")
        }
    }

    // MARK: - Жесты
    private func setupGestures() {

        longPressGesture.minimumPressDuration = 0
        longPressGesture.addTarget(self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPressGesture)

        // Настраиваем pan gesture
        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        longPressGesture.delegate = self
        panGesture.delegate = self
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPressed = true
            animatePress(inside: true)
            startBorderAnimation()
            // Добавляем: обновляем границу другой view
            if let otherView = findOtherView() {
                otherView.updateBorderMask()
            }
        case .ended, .cancelled:
            isPressed = false
            animatePress(inside: false)
            resetStretchEffect()
            stopBorderAnimation()
            // Добавляем: останавливаем анимацию у другой view
            if let otherView = findOtherView() {
                otherView.stopBorderAnimation()
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
            startBorderAnimation()
            // Добавляем: запускаем анимацию границы у другой view
            if let otherView = findOtherView() {
                otherView.startBorderAnimation()
                otherView.updateBorderMask()
            }
        case .changed:
            currentDragLocation = gesture.location(in: self)
            if !bounds.contains(currentDragLocation) {
                applyStretchEffect(to: currentDragLocation)
            }

        case .ended, .cancelled:
            isDragging = false
            resetStretchEffect()
            stopBorderAnimation()
        default:
            break
        }
    }

    private func animatePress(inside: Bool) {
        let scale: CGFloat = inside ? 1.388 : 1.0

        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 1,
                       initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.blurContainer.alpha = inside ? 0.7 : self.blurContainer.alpha
        }
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()

        blurContainer.frame = bounds
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        highlightLayer.frame = bounds
        reflectionLayer.frame = bounds

        // Обновляем границу при изменении размера
        updateBorder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateForCurrentInterfaceStyle()
    }

    // MARK: - Очистка
    deinit {
        stopBorderAnimation()
    }
}

extension CompatibleLiquidGlassView: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
