import Foundation
import AVFoundation
import MediaPlayer

/// 音量控制（iOS 无公开的系统音量 setter，用 MPVolumeView 的 slider 间接设置）
final class VolumeController {
    static let shared = VolumeController()
    private let volumeView = MPVolumeView(frame: .zero)
    private var slider: UISlider?

    init() {
        volumeView.showsRouteButton = false
        slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    func setVolume(_ value: CGFloat) {
        slider?.value = Float(value)
        slider?.sendActions(for: .valueChanged)
    }

    var current: Float { AVAudioSession.sharedInstance().outputVolume }
}
