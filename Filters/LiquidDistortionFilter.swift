import CoreImage

final class LiquidDistortionFilter: CIFilter {

    enum FilterStrategy {
        case positionKernel(_ kernel: CIWarpKernel)
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
        intensity: CGFloat = 0.5
    ) {
        switch filter {
        case let .positionKernel(kernel):
            let center: CIVector = center ?? CIVector(x: inputImage.extent.midX, y: inputImage.extent.midY)
            let radius = radius ?? sqrt(pow(inputImage.extent.width, 2) + pow(inputImage.extent.height, 2)) / 2
            guard let kernelImage = kernel.apply(
                extent: inputImage.extent,
                roiCallback: { _, rect in rect },
                image: inputImage,
                arguments: [
                    center,
                    radius,
                    intensity
                ]) else { return }
            inputImage = kernelImage
        case .coreImage, .none:
            break
        }
    }
}

// MARK: - Config

private extension LiquidDistortionFilter {

    func setupFilterStrategy() {
        filter = createFilterStrategy()
    }

    func createFilterStrategy() -> FilterStrategy {
        let kernelString = """
        kernel vec2 liquidDistortion(
            vec2 center,
            float radius,
            float intensity
        ) {
            vec2 uv = destCoord();
            vec2 d = uv - center;
            float distance = length(d);
            
            if (distance > radius) {
                return uv;
            }
            
            float t =  1.0 - distance / radius;
            
            // Волновая дисторсия
            float wave1 = intensity * 10.0 * sin(t * 20.0) * (1.0 - t);
            float wave2 = intensity * 5.0 * sin(t * 15.0 + 2.0) * (1.0 - t);
            
            // Комбинируем волны
            float combinedWave = (wave1 + wave2) * 0.5;
            
            // Применяем искажение
            float newDistance = distance * (1.0 + combinedWave * 0.02);
            float angle = atan(d.y, d.x) + combinedWave * 0.01;
            
            vec2 distortedUV = center + newDistance * vec2(cos(angle), sin(angle));
            return distortedUV;
        }
        """
        
        guard let wrapKernel = CIWarpKernel(source: kernelString) else {
            return .coreImage
        }
        return .positionKernel(wrapKernel)
    }
}
