import CoreImage

final class WaveDistortionFilter: CIFilter {

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
        intensity: CGFloat,
        frequency: CGFloat
    ) {
        switch filter {
        case let .positionKernel(kernel):
            let center = center ?? CIVector(x: inputImage.extent.midX, y: inputImage.extent.midY)
            let radius = radius ?? sqrt(pow(inputImage.extent.width, 2) + pow(inputImage.extent.height, 2)) / 2
            guard let kernelImage = kernel.apply(
                extent: inputImage.extent,
                roiCallback: { _, rect in rect },
                image: inputImage,
                arguments: [
                    center,
                    radius,
                    intensity,
                    frequency
                ]) else { return }
            inputImage = kernelImage
        case .coreImage, .none:
            break
        }
    }
}

// MARK: - Config

private extension WaveDistortionFilter {

    func setupFilterStrategy() {
        filter = createFilterStrategy()
    }

    func createFilterStrategy() -> FilterStrategy {
        let kernelString = """
        kernel vec2 waveDistortion(
            vec2 center,
            float radius,
            float intensity,
            float frequency
        ) {
            vec2 uv = destCoord();
            vec2 d = uv - center;
            float distance = length(d);
            
            if (distance > radius) {
                return uv;
            }
            
            float t = distance / radius;
            
            // Волновая дисторсия
            float wave = intensity * sin(t * frequency) * (1.0 - t);
            float wave2 = intensity * 0.5 * sin(t * frequency * 1.5) * (1.0 - t);
            
            // Случайное смещение
            float randomOffset = sin(uv.x * 0.05) * cos(uv.y * 0.05) * 0.05;
            
            float newDistance = distance * (1.0 + (wave + wave2 + randomOffset) * 0.02);
            float angle = atan(d.y, d.x);
            
            vec2 newUV = center + newDistance * vec2(cos(angle), sin(angle));
            return newUV;
        }
        """

        guard let wrapKernel = CIWarpKernel(source: kernelString) else {
            return .coreImage
        }
        return .positionKernel(wrapKernel)
    }
}
