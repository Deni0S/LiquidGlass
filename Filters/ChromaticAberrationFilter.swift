import CoreImage

final class ChromaticAberrationFilter: CIFilter {

    enum FilterStrategy {
        case colorKernel(_ kernel: CIKernel)
        case coreImage
        case none
    }

    // MARK: - Property

    private var filter: FilterStrategy = .none

    // MARK: - LifeCycle

    override init() {
        super.init()
        setupFilterStrategy()
    }

    required init?(coder: NSCoder) {
        super.init()
        setupFilterStrategy()
    }

    // MARK: - Public

    public func applyFilter(
        to inputImage: inout CIImage,
        center: CIVector? = nil,
        radius: CGFloat? = nil,
        redShift: CGPoint = CGPoint(x: 0.015, y: 0.01),
        greenShift: CGPoint = CGPoint(x: 0.0, y: 0.0),
        blueShift: CGPoint = CGPoint(x: -0.015, y: -0.01)
    ) {
        switch filter {
        case let .colorKernel(kernel):
            let center = center ?? CIVector(x: inputImage.extent.midX, y: inputImage.extent.midY)
            let radius = radius ?? sqrt(pow(inputImage.extent.width, 2) + pow(inputImage.extent.height, 2)) / 2
            guard let kernelImage = kernel.apply(
                extent: inputImage.extent,
                roiCallback: { _, rect in rect },
                arguments: [
                    inputImage,
                    center,
                    radius,
                    redShift.x,
                    redShift.y,
                    greenShift.x,
                    greenShift.y,
                    blueShift.x,
                    blueShift.y
                ]) else { return }
            inputImage = kernelImage
        case .coreImage, .none:
            break
        }
    }
}

// MARK: - Config

private extension ChromaticAberrationFilter {

    func setupFilterStrategy() {
        filter = createFilterStrategy()
    }

    func createFilterStrategy() -> FilterStrategy {
        let kernelString = """
        kernel vec4 chromaticAberration(
            sampler image,
            vec2 center,
            float radius,
            float redShiftX,
            float redShiftY,
            float greenShiftX,
            float greenShiftY,
            float blueShiftX,
            float blueShiftY
        ) {
            vec2 uv = samplerCoord(image);
            vec2 offset = uv - center;
            float distance = length(offset);
            
            // Рассчитываем силу эффекта (больше на краях)
            float strength = 0.0;
            if (distance > radius * 0.7) {
                strength = smoothstep(radius * 0.7, radius, distance);
            }
            
            // Получаем направление от центра
            vec2 direction = normalize(offset);
            
            // Создаем перпендикулярный вектор для зеркального смещения
            // Вращаем на 90 градусов: (x, y) -> (-y, x) или (y, -x)
            // Выбираем (-y, x) для поворота влево, (y, -x) для поворота вправо
            vec2 perpendicular = vec2(-direction.y, direction.x);
            
            // Смещаем UV координаты для каждого канала
            // Используем перпендикулярный вектор для зеркального смещения
            vec2 redUV = uv + perpendicular * vec2(redShiftX, redShiftY) * strength;
            vec2 greenUV = uv + direction * vec2(greenShiftX, greenShiftY) * strength;
            vec2 blueUV = uv - perpendicular * vec2(blueShiftX, blueShiftY) * strength;
            
            // Получаем цвета из смещенных позиций
            float red = sample(image, redUV).r;
            float green = sample(image, greenUV).g;
            float blue = sample(image, blueUV).b;
            
            // Сохраняем альфа из исходной позиции
            float alpha = sample(image, uv).a;
            
            return vec4(red, green, blue, alpha);
        }
        """

        guard let kernel = CIKernel(source: kernelString) else {
            return .coreImage
        }
        return .colorKernel(kernel)
    }
}
