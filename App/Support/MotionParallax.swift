import CoreGraphics
import CoreMotion
import Observation

/// B5：陀螺仪视差。Demo 用指针驱动 --par-x/--par-y ∈ [-1,1]，
/// 真机改姿态驱动同一对系数：以进入页面时的握持姿态为零点，
/// 左右倾（roll）→ parX、前后倾（pitch）→ parY，低通滤波去抖。
/// 各层位移幅度沿用设计稿（±3…7pt），本就克制。
@Observable
final class MotionParallax {
    private(set) var parX: CGFloat = 0
    private(set) var parY: CGFloat = 0

    private let manager = CMMotionManager()
    private var reference: (roll: Double, pitch: Double)?

    /// 倾到 ±0.42 rad（约 24°）打满，再往外夹住
    private let fullTilt = 0.42
    /// 低通系数（30Hz 采样下 ~0.2s 收敛）
    private let smoothing: CGFloat = 0.16

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            if self.reference == nil {
                self.reference = (attitude.roll, attitude.pitch)
            }
            guard let ref = self.reference else { return }
            let nx = max(-1, min(1, (attitude.roll - ref.roll) / self.fullTilt))
            let ny = max(-1, min(1, (attitude.pitch - ref.pitch) / self.fullTilt))
            self.parX += (CGFloat(nx) - self.parX) * self.smoothing
            self.parY += (CGFloat(ny) - self.parY) * self.smoothing
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        parX = 0
        parY = 0
    }
}
