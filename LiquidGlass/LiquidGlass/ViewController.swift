import UIKit

// MARK: - Glass Button
class LiquidGlassButton: UIButton {
    private let glassView = CompatibleLiquidGlassView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Настройка кнопки
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        setTitleColor(.label, for: .normal)

        // Добавление эффекта стекла
        glassView.config = CompatibleLiquidGlassView.GlassConfig(
            opacity: 0.8,
            tintColor: tintColor,
            cornerRadius: min(bounds.height, bounds.width) / 2,
            isInteractive: true,
            sizeCategory: .medium
        )

        insertSubview(glassView, at: 0)

        // Настройка взаимодействия
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

        // Адаптивный радиус
        let radius = min(bounds.height, bounds.width) / 2
        glassView.layer.cornerRadius = radius
    }
}

// MARK: - Glass Switch
class LiquidGlassSwitch: UIControl {
    private let glassView = CompatibleLiquidGlassView()
    private let thumbView = UIView()
    private let backgroundView = UIView()

    var isOn: Bool = false {
        didSet {
            updateThumbPosition(animated: true)
            sendActions(for: .valueChanged)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Фон
        backgroundView.backgroundColor = .systemGray4
        backgroundView.layer.cornerRadius = bounds.height / 2
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)

        // Эффект стекла
        glassView.config = CompatibleLiquidGlassView.GlassConfig(
            opacity: 0.7,
            tintColor: .systemGreen,
            cornerRadius: bounds.height / 2,
            isInteractive: true,
            sizeCategory: .small
        )
        addSubview(glassView)

        // Ползунок
        thumbView.backgroundColor = .white
        thumbView.layer.cornerRadius = (bounds.height - 8) / 2
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
    }

    @objc private func toggleSwitch() {
        isOn.toggle()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // Растягивание при перетаскивании
        glassView.handlePan(gesture)

        // Переключение при достаточном движении
        let translation = gesture.translation(in: self)
        if abs(translation.x) > bounds.width * 0.3 {
            isOn = translation.x > 0
            gesture.setTranslation(.zero, in: self)
        }
    }

    private func updateThumbPosition(animated: Bool) {
        let thumbPosition = isOn ? bounds.width - (bounds.height - 4) : 4

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0,
                          usingSpringWithDamping: 0.7,
                          initialSpringVelocity: 0,
                          options: [.curveEaseInOut]) {
                self.thumbView.frame = CGRect(
                    x: thumbPosition,
                    y: 4,
                    width: self.bounds.height - 8,
                    height: self.bounds.height - 8
                )
                self.backgroundView.backgroundColor = self.isOn ? .systemGreen : .systemGray4
                self.glassView.alpha = self.isOn ? 0.8 : 0.5
            }
        } else {
            thumbView.frame = CGRect(
                x: thumbPosition,
                y: 4,
                width: bounds.height - 8,
                height: bounds.height - 8
            )
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

// MARK: - Pointer Interaction для трекпада
@available(iOS 13.0, *)
extension LiquidGlassButton: UIPointerInteractionDelegate {
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

class ViewController: UIViewController {

   override func viewDidLoad() {
      super.viewDidLoad()
      let view3 = UITextView(frame: CGRect(x: 150, y: 400, width: 30, height: 30))
      view3.text = "12edfqvegrjw hbinfjomwe kpd;c"
      view.addSubview(view3)

      let glassView1 = CompatibleLiquidGlassView(frame: CGRect(x: 100, y: 400, width: 30, height: 30))
      let glassView2 = CompatibleLiquidGlassView(frame: CGRect(x: 150, y: 400, width: 30, height: 30))
      view.addSubview(glassView1)
      view.addSubview(glassView2)
   }
}
