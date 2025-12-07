import UIKit
import CoreMotion
import simd

// MARK: - Исправленный системный менеджер
class LiquidGlassSystemManager {
    static let shared = LiquidGlassSystemManager()
    private init() {}

    private var activeViews = NSHashTable<AdvancedLiquidGlassView>.weakObjects()
    private let motionManager = CMMotionManager()
    private let renderQueue = DispatchQueue(label: "com.liquidglass.render", qos: .userInteractive)
    private var displayLink: CADisplayLink?

    func register(view: AdvancedLiquidGlassView) {
        activeViews.add(view)
        startMonitoringIfNeeded()
    }

    func unregister(view: AdvancedLiquidGlassView) {
        activeViews.remove(view)
    }

    private func startMonitoringIfNeeded() {
        // Запуск display link для синхронизации с частотой обновления экрана
        if displayLink == nil {
            displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink?.add(to: .main, forMode: .common)
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        }

        // Мониторинг движения устройства
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1/60
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    @objc private func updateFrame() {
        guard let motion = motionManager.deviceMotion else { return }

        // Получаем данные о вращении устройства
        let rotation = motion.attitude.rotationMatrix
        let intensity = SIMD3<Double>(rotation.m13, rotation.m23, rotation.m33)

        // Обновляем все активные вьюхи
        activeViews.allObjects.forEach { view in
            view.updateParallax(intensity: CGPoint(x: intensity.x, y: intensity.y))
        }
    }

    func stopAll() {
        displayLink?.invalidate()
        displayLink = nil
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - Конфигурации с исправленными значениями
struct GlassConfiguration {
    let blurRadius: CGFloat
    let lensingOpacity: CGFloat
    let causticsOpacity: CGFloat
    let parallaxIntensity: CGFloat
    let solidColor: UIColor
    let tintColor: UIColor
    let chromaKey: CGFloat
    let reflectionIntensity: CGFloat

    static let regular = GlassConfiguration(
        blurRadius: 15.0,
        lensingOpacity: 0.35,
        causticsOpacity: 0.45,
        parallaxIntensity: 0.6,
        solidColor: UIColor(white: 0.95, alpha: 1.0),
        tintColor: UIColor.systemBlue.withAlphaComponent(0.1),
        chromaKey: 0.85,
        reflectionIntensity: 0.25
    )

    static let thick = GlassConfiguration(
        blurRadius: 20.0,
        lensingOpacity: 0.45,
        causticsOpacity: 0.55,
        parallaxIntensity: 0.7,
        solidColor: UIColor(white: 0.92, alpha: 1.0),
        tintColor: UIColor.systemBlue.withAlphaComponent(0.15),
        chromaKey: 0.9,
        reflectionIntensity: 0.35
    )

    static let thin = GlassConfiguration(
        blurRadius: 10.0,
        lensingOpacity: 0.25,
        causticsOpacity: 0.35,
        parallaxIntensity: 0.4,
        solidColor: UIColor(white: 0.97, alpha: 1.0),
        tintColor: UIColor.systemBlue.withAlphaComponent(0.05),
        chromaKey: 0.75,
        reflectionIntensity: 0.15
    )

    static let ultraThin = GlassConfiguration(
        blurRadius: 6.0,
        lensingOpacity: 0.15,
        causticsOpacity: 0.25,
        parallaxIntensity: 0.3,
        solidColor: UIColor(white: 0.98, alpha: 1.0),
        tintColor: UIColor.clear,
        chromaKey: 0.6,
        reflectionIntensity: 0.1
    )
}

// MARK: - Улучшенный основной компонент
class AdvancedLiquidGlassView: UIView {
    enum GlassStyle {
        case regular, thick, thin, ultraThin
    }

    // MARK: - Конфигурация
    var style: GlassStyle = .regular {
        didSet {
            updateStyle()
            updateBlendMode()
        }
    }

    var chromaKey: CGFloat = 0.85 {
        didSet { updateChromaKey() }
    }

    var reflectionEnabled: Bool = true {
        didSet { updateReflection() }
    }

    private var currentConfiguration: GlassConfiguration {
        switch style {
        case .regular: return .regular
        case .thick: return .thick
        case .thin: return .thin
        case .ultraThin: return .ultraThin
        }
    }

    // MARK: - Слои
    private let blurContainer = UIView()
    private let reflectionLayer = CAGradientLayer()
    private let lensingLayer = CALayer()
    private let causticsLayer = CAEmitterLayer()
    private let contentLayer = CALayer()
    private let tintLayer = CALayer()
    private let overlayLayer = CALayer()

    // MARK: - Состояние
    private var isReducingMotion: Bool = false
    private var isReducingTransparency: Bool = false
    private var isIncreasingContrast: Bool = false
    private var isDarkMode: Bool = false

    // MARK: - Аниматоры
    private var dynamicAnimator: UIDynamicAnimator?
    private var attachmentBehavior: UIAttachmentBehavior?

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
        // Системная регистрация
        LiquidGlassSystemManager.shared.register(view: self)

        // Настройка базовых свойств
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true

        // Иерархия слоев
        layer.addSublayer(contentLayer)
        addSubview(blurContainer)
        layer.addSublayer(lensingLayer)
        layer.addSublayer(causticsLayer)
        layer.addSublayer(reflectionLayer)
        layer.addSublayer(tintLayer)
        layer.addSublayer(overlayLayer)

        // Настройка каждого слоя
        configureLayers()

        // Наблюдатели
        setupObservers()

        // Динамический аниматор для физики
        dynamicAnimator = UIDynamicAnimator(referenceView: self)

        // Инициализация
        updateStyle()
        updateBlendMode()
        updateAccessibility()
    }

    private func configureLayers() {
        // Blur Container с несколькими слоями размытия
        blurContainer.frame = bounds
        blurContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurContainer.isUserInteractionEnabled = false

        // Многоуровневое размытие для глубины
        for i in 0..<3 {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            blurView.frame = blurContainer.bounds
            blurView.alpha = 1.0 - CGFloat(i) * 0.3
            blurContainer.addSubview(blurView)
        }

        // Reflection layer - световые блики
        reflectionLayer.startPoint = CGPoint(x: 0.5, y: 0)
        reflectionLayer.endPoint = CGPoint(x: 0.5, y: 1)
        reflectionLayer.colors = [
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        reflectionLayer.locations = [0, 0.3, 0.6]

        // Lensing layer - эффект искажения
        lensingLayer.contentsGravity = .resize
        lensingLayer.masksToBounds = true

        // Caustics layer - частицы "жидкости"
        configureCausticsLayer()

        // Tint layer - цветной оттенок
        tintLayer.contentsGravity = .resize
        tintLayer.compositingFilter = "overlayBlendMode"

        // Overlay layer для доступности
        overlayLayer.backgroundColor = UIColor.white.withAlphaComponent(0.15).cgColor
        overlayLayer.isHidden = true

        // Content layer
        contentLayer.contentsGravity = .resize
        contentLayer.masksToBounds = true
    }

    private func configureCausticsLayer() {
        causticsLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        causticsLayer.emitterSize = bounds.size
        causticsLayer.emitterShape = .rectangle
        causticsLayer.emitterMode = .surface
        causticsLayer.renderMode = .additive
        causticsLayer.birthRate = 0.5

        // Создаем частицы каустики
        let cell = CAEmitterCell()
        cell.birthRate = 20
        cell.lifetime = 3.0
        cell.lifetimeRange = 1.0
        cell.velocity = 20
        cell.velocityRange = 10
        cell.emissionRange = .pi * 2
        cell.spin = 0.5
        cell.spinRange = 1.0
        cell.scale = 0.1
        cell.scaleRange = 0.05
        cell.scaleSpeed = -0.02
        cell.contents = createCausticImage().cgImage
        cell.color = UIColor.white.withAlphaComponent(0.3).cgColor
        cell.redRange = 0.1
        cell.greenRange = 0.1
        cell.blueRange = 0.1
        cell.alphaRange = 0.2
        cell.alphaSpeed = -0.1

        causticsLayer.emitterCells = [cell]
    }

    private func createCausticImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        return renderer.image { ctx in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.withAlphaComponent(0.8).cgColor,
                    UIColor.white.withAlphaComponent(0.0).cgColor
                ] as CFArray,
                locations: [0, 1]
            )!

            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 25, y: 25),
                startRadius: 0,
                endCenter: CGPoint(x: 25, y: 25),
                endRadius: 25,
                options: .drawsAfterEndLocation
            )
        }
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let bounds = self.bounds
        blurContainer.frame = bounds
        contentLayer.frame = bounds
        lensingLayer.frame = bounds
        causticsLayer.frame = bounds
        reflectionLayer.frame = bounds
        tintLayer.frame = bounds
        overlayLayer.frame = bounds

        updateCornerRadius()
        updateBlendMode()
        updateCausticsEmitter()

        CATransaction.commit()
    }

    private func updateCornerRadius() {
        let radius = min(bounds.height, bounds.width) / 4
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        contentLayer.cornerRadius = radius
        blurContainer.layer.cornerRadius = radius
        blurContainer.clipsToBounds = true
    }

    private func updateCausticsEmitter() {
        causticsLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        causticsLayer.emitterSize = CGSize(width: bounds.width * 0.8, height: bounds.height * 0.8)
    }

    // MARK: - Стиль и внешний вид
    private func updateStyle() {
        let config = currentConfiguration

        // Обновляем конфигурацию
        chromaKey = config.chromaKey
        reflectionLayer.opacity = Float(config.reflectionIntensity)
        tintLayer.backgroundColor = config.tintColor.cgColor

        // Применяем настройки доступности
        updateAccessibility()
    }

    private func updateBlendMode() {
        // Режимы смешивания для разных стилей
        switch style {
        case .regular, .thick:
            layer.compositingFilter = "screenBlendMode"
        case .thin, .ultraThin:
            layer.compositingFilter = "overlayBlendMode"
        }
    }

    private func updateChromaKey() {
        // Эффект хромакея (цветового ключа)
        let filter = CIFilter(name: "CIColorClamp")!
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        filter.setValue(CIVector(x: 1, y: 1, z: 1, w: chromaKey), forKey: "inputMaxComponents")
        contentLayer.filters = [filter]
    }

    private func updateReflection() {
        reflectionLayer.isHidden = !reflectionEnabled
    }

    // MARK: - Параллакс и физика
    func updateParallax(intensity: CGPoint) {
        guard !isReducingMotion else { return }

        let config = currentConfiguration
        let maxOffset: CGFloat = 20.0

        // Параллакс с учетом конфигурации
        let xOffset = CGFloat(intensity.x) * maxOffset * config.parallaxIntensity
        let yOffset = CGFloat(intensity.y) * maxOffset * config.parallaxIntensity

        // Анимация с пружинным эффектом
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(translationX: xOffset, y: yOffset)
            self.reflectionLayer.transform = CATransform3DMakeTranslation(-xOffset * 0.3, -yOffset * 0.3, 0)
        }

        // Обновляем позицию эмиттера каустик
        updateCausticsPosition(offset: CGPoint(x: xOffset, y: yOffset))
    }

    private func updateCausticsPosition(offset: CGPoint) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        causticsLayer.emitterPosition = CGPoint(
            x: bounds.midX + offset.x * 0.2,
            y: bounds.midY + offset.y * 0.2
        )
        CATransaction.commit()
    }

    // MARK: - Доступность
    private func setupObservers() {
        // Проверяем начальные настройки
        checkAccessibilitySettings()

        // Наблюдатели для изменений в реальном времени
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil
        )

        // Наблюдатель для темной темы
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(traitCollectionDidChangeNotification),
//            name: .traitCollectionDidChange,
//            object: nil
//        )
    }

    private func checkAccessibilitySettings() {
        isReducingMotion = UIAccessibility.isReduceMotionEnabled
        isReducingTransparency = UIAccessibility.isReduceTransparencyEnabled

        // Для Increase Contrast используем комбинацию настроек
        let isBoldTextEnabled = UIAccessibility.isBoldTextEnabled
        let isDarkerColorsEnabled = UIAccessibility.isDarkerSystemColorsEnabled
        isIncreasingContrast = isBoldTextEnabled || isDarkerColorsEnabled

        // Проверяем темную тему
        isDarkMode = traitCollection.userInterfaceStyle == .dark
    }

    @objc private func accessibilitySettingsChanged() {
        checkAccessibilitySettings()
        updateAccessibility()
    }

    @objc private func traitCollectionDidChangeNotification() {
        isDarkMode = traitCollection.userInterfaceStyle == .dark
        updateStyle()
    }

    private func updateAccessibility() {
        if isReducingTransparency {
            // Упрощенный вид
            blurContainer.alpha = 0.3
            causticsLayer.birthRate = 0
            reflectionLayer.opacity = 0.1
            tintLayer.opacity = 0.2

            if isIncreasingContrast {
                layer.borderWidth = 1.0
                layer.borderColor = UIColor.systemGray3.cgColor
            }
        } else {
            // Полный эффект
            blurContainer.alpha = 1.0
            reflectionLayer.opacity = Float(currentConfiguration.reflectionIntensity)
            tintLayer.opacity = 1.0
            layer.borderWidth = 0

            if isReducingMotion {
                causticsLayer.birthRate = 0.1
            } else {
                causticsLayer.birthRate = 0.5
            }
        }

        // Переключаем overlay для увеличения контраста
        overlayLayer.isHidden = !isIncreasingContrast

        // Обновляем цвета для темной темы
        updateColorsForCurrentTheme()
    }

    private func updateColorsForCurrentTheme() {
        if isDarkMode {
            reflectionLayer.colors = [
                UIColor.white.withAlphaComponent(0.15).cgColor,
                UIColor.white.withAlphaComponent(0.05).cgColor,
                UIColor.clear.cgColor
            ]
        } else {
            reflectionLayer.colors = [
                UIColor.white.withAlphaComponent(0.3).cgColor,
                UIColor.white.withAlphaComponent(0.1).cgColor,
                UIColor.clear.cgColor
            ]
        }
    }

    // MARK: - Взаимодействие
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        animateTouch(inside: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        animateTouch(inside: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        animateTouch(inside: false)
    }

    private func animateTouch(inside: Bool) {
        let scale: CGFloat = inside ? 0.97 : 1.0
        let alpha: CGFloat = inside ? 0.9 : 1.0

        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.blurContainer.alpha = alpha
        }
    }

    // MARK: - Деинициализация
    deinit {
        NotificationCenter.default.removeObserver(self)
        LiquidGlassSystemManager.shared.unregister(view: self)
    }
}

// MARK: - Применение к системным элементам
extension UIView {
    func applyAdvancedLiquidGlass(style: AdvancedLiquidGlassView.GlassStyle = .regular) {
        // Удаляем старые эффекты
        subviews.filter { $0 is AdvancedLiquidGlassView }.forEach { $0.removeFromSuperview() }

        // Создаем и настраиваем эффект
        let liquidView = AdvancedLiquidGlassView(frame: bounds)
        liquidView.style = style
        liquidView.isUserInteractionEnabled = false
        insertSubview(liquidView, at: 0)

        // Автоматическое изменение размера
        liquidView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Сохраняем ссылку для дальнейшего управления
        objc_setAssociatedObject(self, "liquidGlassView", liquidView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func removeLiquidGlass() {
        if let liquidView = objc_getAssociatedObject(self, "liquidGlassView") as? AdvancedLiquidGlassView {
            liquidView.removeFromSuperview()
            objc_setAssociatedObject(self, "liquidGlassView", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

class ViewController2: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 1. Создание кнопки с эффектом Liquid Glass
        let liquidButton = wrapViewInLiquidGlass(
            originalView: createSystemButton(title: "Liquid Button"),
            style: .regular,
            insets: UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        )
        liquidButton.center = CGPoint(x: view.center.x, y: view.center.y - 80)
        view.addSubview(liquidButton)

        // 2. Создание кастомного свитча с эффектом
        let liquidSwitch = wrapViewInLiquidGlass(
            originalView: createCustomSwitch(),
            style: .regular,
            insets: UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        )
        liquidSwitch.center = CGPoint(x: view.center.x, y: view.center.y + 80)
        view.addSubview(liquidSwitch)
    }

    // Вспомогательная функция для создания системной кнопки
    private func createSystemButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.sizeToFit()
        return button
    }

    // Вспомогательная функция для создания кастомного свитча
    private func createCustomSwitch() -> UISwitch {
        let customSwitch = UISwitch()
//        customSwitch.onTintColor = .clear // Фон будет обеспечивать LiquidGlassView
        customSwitch.thumbTintColor = .white
        return customSwitch
    }

    // Основная функция-обертка: применяет эффект к любому UIView
    private func wrapViewInLiquidGlass(originalView: UIView,
                                       style: AdvancedLiquidGlassView.GlassStyle,
                                       insets: UIEdgeInsets) -> UIView {
        // Контейнер, который будет иметь эффект Liquid Glass
        let container = AdvancedLiquidGlassView(frame: CGRect.zero)
        container.style = style
        container.reflectionEnabled = true

        // Добавляем исходное представление внутрь контейнера
        originalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(originalView)

        // Настраиваем констрейнты с отступами
        NSLayoutConstraint.activate([
            originalView.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            originalView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            originalView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            originalView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom)
        ])

        // Корректируем размер контейнера под содержимое
        container.sizeToFit()
        container.frame.size = CGSize(
            width: originalView.frame.width + insets.left + insets.right,
            height: originalView.frame.height + insets.top + insets.bottom
        )

        return container
    }
}
