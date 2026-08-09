import Foundation

/// 전송 속도 파라미터. 실측 결과에 따라 이 파일만 조정한다.
///
/// 1차 실측(2026-08-09, 시뮬레이터 -> 실기기): 블록 400B x 12fps x 1코드에서
/// 실효 3KB/s, 프레임 포착률 약 67%. 상한 자체가 병목이라 밀도·fps·동시 코드 수를 올린다.
enum TransferTuning {
    /// 프레임 총 바이트(블록 + 헤더 38B)가 QR v20-L 용량(858B)에 들어가는 크기
    nonisolated static let blockSize = 800
    /// 표시 프레임레이트. 카메라 인식이 따라오는 상한을 실측으로 확인한다
    nonisolated static let framesPerSecond = 15
    /// 화면에 세로로 동시 표시하는 QR 수. 수신은 한 카메라 프레임에서
    /// 여러 코드를 동시에 인식하므로 표시 수만큼 처리량이 곱해진다
    nonisolated static let simultaneousCodes = 2

    /// 초당 표시되는 프레임 수 (예상 시간 계산용)
    nonisolated static var framesPerSecondTotal: Int {
        framesPerSecond * simultaneousCodes
    }
}
