import CoreMotion
import SwiftUI

/// 壁纸动态（Telegram 的 Motion 开关，step 92）：手机倾斜时壁纸
/// 跟着轻轻移，视差感。原生 CoreMotion 的 deviceMotion，
/// 不自己算陀螺仪。视差最多 ±10pt；图在动态开着时多放大 8%
/// （WallpaperLayout 的 extraScale），边缘永远有余量，不露白。
/// 开始时先记一个参考姿态，之后都算相对它的 roll/pitch；
/// 每 30ms 更新一次，往目标值平滑 30%，不抖。
/// 用之前要在 Info.plist 里写 NSMotionUsageDescription，
/// 不然系统不让读（project.pbxproj 里和相机/相册那几条放一起）。
final class WallpaperMotionProvider: ObservableObject {
    @Published var offset: CGSize = .zero

    private let manager = CMMotionManager()
    private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        offset = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            if reference == nil {
                reference = data.attitude.copy() as? CMAttitude
                return
            }
            let attitude = data.attitude.copy() as! CMAttitude
            attitude.multiply(byInverseOf: reference!)
            // 左右倾 → 图反向移；前后俯仰 → 图上下移；各夹到 ±10pt。
            let targetX = CGFloat(min(max(-attitude.roll, -0.5), 0.5)) * 20
            let targetY = CGFloat(min(max(attitude.pitch, -0.5), 0.5)) * 20
            offset = CGSize(
                width: offset.width * 0.7 + targetX * 0.3,
                height: offset.height * 0.7 + targetY * 0.3
            )
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        reference = nil
        offset = .zero
    }

    deinit { manager.stopDeviceMotionUpdates() }
}
