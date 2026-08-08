# 큐알포스트 (QRPost)

화면에 QR 코드를 연속 재생하고 카메라로 찍어 받는 파일 전송 앱.
페어링 · 연락처 교환 · 계정 · 서버 없음 — 보여주고 찍으면 끝.

## 구조

| 경로 | 내용 |
|---|---|
| `QRPostCore/` | 플랫폼 중립 코어 Swift Package (파운틴 코드, 와이어 포맷, QR 인코더) |
| `QRPost/` | iOS/iPadOS 유니버설 앱 (Xcode 프로젝트) |
| `docs/` | 기획서 · 아키텍처 설계 문서 |

## 개발

```bash
cd QRPostCore && swift test   # 코어 로직 전체 검증 (시뮬레이터 불필요)
```

앱 프로젝트는 Xcode에서 `QRPostCore`를 로컬 패키지로 참조한다
(File → Add Package Dependencies → Add Local).

## 기술 요약

- LT 파운틴 코드 기반 — 프레임 유실·순서 무관 수신
- 코어는 UIKit/AVFoundation 미사용 (비트 매트릭스 입출력) → macOS 이식 대비
- 외부 의존성 0개
