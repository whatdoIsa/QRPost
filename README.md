<p align="center">
  <img src="docs/assets/app-icon.png" width="120" alt="큐알포스트 아이콘">
</p>

<h1 align="center">큐알포스트 (QRPost)</h1>

<p align="center">
  화면에 QR 코드를 연속 재생하고, 카메라로 찍어 파일을 받는 iOS 앱<br>
  네트워크 · 페어링 · 계정 · 서버 없음 — 보여주고 찍으면 끝
</p>

<p align="center">
  <a href="https://github.com/whatdoIsa/QRPost/actions/workflows/ci.yml"><img src="https://github.com/whatdoIsa/QRPost/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-black" alt="iOS 18+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

---

## 무엇을 하는 앱인가

보내는 기기가 파일을 QR 코드의 연속 재생(초당 15프레임, 동시 2코드)으로 바꿔 화면에 띄우고,
받는 기기가 카메라로 그 화면을 비추면 파일이 복원된다. 연결 절차가 전혀 없다 —
같은 Wi-Fi일 필요도, 블루투스도, 연락처 교환도, 계정도 필요 없다.

지원 조합: iPhone ↔ iPhone, iPad ↔ iPhone (유니버설 앱 하나로 송수신 모두).

<!-- 데모 GIF 자리: docs/assets/demo.gif 추가 후 아래 주석 해제
<p align="center"><img src="docs/assets/demo.gif" width="600" alt="전송 데모"></p>
-->

## 어떻게 동작하는가

```
파일
 └─ 블록 분할 (800B) ─ LT 파운틴 인코딩 ─ 와이어 프레임(헤더+CRC32) ─ QR 심볼(v20-L) ─ 화면 재생
                                                                                        │
                                                                              카메라 캡처 (순서 무관)
                                                                                        │
 파일 ─ 원본 길이 절단 ─ 필링 + GF(2) 가우스 소거 디코딩 ─ 프레임 검증(CRC) ─ QR 인식 ──┘
```

핵심은 **LT 파운틴 코드** 기반의 rateless 설계다:

- 패킷에는 인덱스만 실리고, 송수신이 같은 시드로 블록 조합을 재현한다 — 재전송 개념이 없다
- 프레임을 얼마나 놓치든 충분히 모이면 복원된다. 순서 무관, 중복 무시, 중간 진입 가능
- 시스터매틱 프리픽스: 처음 K개 프레임은 원본 블록 그대로 — 무손실이면 오버헤드 0
- 필링 디코더가 말단에서 멈추면 GF(2) 가우스 소거가 마무리한다
- 모든 프레임은 자기완결적(세션 파라미터 포함)이고 CRC32로 손상을 걸러낸다

파라미터는 실측으로 튜닝했다: Robust Soliton c=0.05/δ=0.05 (유실 50% 그리드 실측),
블록 800B x 15fps x 동시 2코드 (이론 상한 24KB/s).

## 빌드와 실행

요구 사항: Xcode 16 이상, iOS 18 이상 기기 2대 (수신은 카메라가 필요해 시뮬레이터 불가)

```bash
git clone https://github.com/whatdoIsa/QRPost.git
open QRPost/QRPost/QRPost.xcodeproj
```

서명 팀을 본인 계정으로 바꾸고 두 기기에 설치하면 된다.

코어 로직만 검증하려면 (시뮬레이터·기기 불필요):

```bash
cd QRPostCore && swift test
```

## 저장소 구조

| 경로 | 내용 |
|---|---|
| `QRPostCore/` | 플랫폼 중립 코어 Swift Package — 파운틴 코드, 와이어 포맷, QR 인코더. UIKit/AVFoundation 미사용, 외부 의존성 0 |
| `QRPost/` | iOS/iPadOS 유니버설 앱 (SwiftUI) |
| `docs/` | 기획서 · 아키텍처 · 디자인 가이드 |

설계 상세는 [아키텍처 문서](docs/아키텍처.md), 디자인 결정은 [디자인 가이드](docs/디자인-가이드.md) 참고.

## 함께 보기

- [qrdrop](https://github.com/Gojaehyeon/qrdrop) — 같은 팀의 형제 프로젝트. Mac에서 드롭한 파일을 iPhone으로 쏘는 오리지널. 큐알포스트의 파운틴 코드와 QR 인코더는 qrdrop에서 출발했다

## 기여

작업 흐름과 커밋 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md) 참고.

## 라이선스

[MIT](LICENSE)
