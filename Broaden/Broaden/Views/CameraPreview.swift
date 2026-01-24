import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraController: CameraSessionController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        view.cameraController = cameraController
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = session
        uiView.cameraController = cameraController
    }
}

final class PreviewView: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var pinchGesture: UIPinchGestureRecognizer?

    var session: AVCaptureSession? {
        didSet {
            previewLayer.session = session
        }
    }
    
    weak var cameraController: CameraSessionController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        
        // 添加双指缩放手势
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
        pinchGesture = pinch
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let controller = cameraController else { return }
        
        switch gesture.state {
        case .began:
            controller.beginZoom()
        case .changed:
            controller.updateZoom(scale: gesture.scale)
        case .ended, .cancelled:
            break
        default:
            break
        }
    }
}
