# tunaPop

[English Version](README.md)

[![Build Status](https://github.com/hang-in/tunaPop/actions/workflows/build.yml/badge.svg)](https://github.com/hang-in/tunaPop/actions/workflows/build.yml)
[![Lint Status](https://github.com/hang-in/tunaPop/actions/workflows/lint.yml/badge.svg)](https://github.com/hang-in/tunaPop/actions/workflows/lint.yml)
[![Platform](https://img.shields.io/badge/platform-macOS_14.0+-black.svg?style=flat&logo=apple)](https://img.shields.io/badge/platform-macOS_14.0+-black.svg?style=flat&logo=apple)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)
[![Homebrew](https://img.shields.io/badge/Homebrew-hang--in%2Ftap-orange.svg?style=flat&logo=homebrew)](https://github.com/hang-in/homebrew-tap)

tunaPop은 macOS에서 텍스트를 선택했을 때 팝업 창을 통해 AI 기반 액션과 시스템 유틸리티 기능을 빠르게 수행할 수 있도록 돕는 PopClip 스타일의 macOS 네이티브 애플리케이션입니다.

## 주요 기능

- **네이티브 UX**: 마우스 드래그 완료를 감지하여 선택된 텍스트 주변에 직관적인 액션 바(ActionBar) 팝업을 표시합니다.
- **AI 액션**: 요약, 설명, 번역 등 자주 사용하는 프롬프트를 원클릭으로 실행하며, 사용자의 선택 상태에 반응하여 동적으로 프롬프트를 구성합니다.
- **시스템 기본 기능**: LLM 호출 없이 즉시 처리할 수 있는 4가지 기본 기능(복사, 붙여넣기, 웹 검색, 사전 조회)을 내장하고 있습니다.
- **액션 편집 및 숨김**: 내장 액션 7종(AI 액션 3종, 시스템 기능 4종)과 사용자 정의 커스텀 액션을 자유롭게 편집하여 사용할 수 있습니다. 사용하지 않는 기본 액션은 숨길 수 있으며, 원클릭으로 초기 설정 상태로 되돌리는 초기화 기능을 제공합니다.
- **커스텀 액션 에디터**: 사용자가 직접 AI 프롬프트 액션이나 시스템 기본 제어 액션을 새롭게 정의하여 추가할 수 있으며, SF Symbols 아이콘을 선택하여 시각적으로 꾸밀 수 있습니다.
- **로컬 LLM 및 에이전트 제공자 연동**: Ollama 호환 API를 연동하여 로컬 환경에서 모델을 독립 실행하므로 개인정보 유출을 방지합니다. Gemini, OpenAI, Anthropic 등 다양한 외부 클라이언트 연동도 지원합니다.
- **보안 및 권한 관리**: 시스템 키체인(Keychain)을 활용하여 API 토큰을 안전하게 관리하며, 손쉬운 사용(Accessibility) 권한을 메뉴 막대 및 설정 창을 통해 제어할 수 있습니다.

## 시작하기

### 요구 사항

- macOS 14.0 이상 (Swift 5.9 이상, AppKit 및 SwiftUI)
- 로컬 또는 원격 Ollama 서버 (기본값: http://localhost:11434) 혹은 기타 AI 서비스 제공자 API 키

### 설치 (OSS 빌드)

서명되지 않은 빌드라 macOS가 처음 실행 시 차단합니다. 아래 방법으로 실행할 수 있습니다.

#### 방법 1 (Homebrew, 권장)
```bash
brew tap hang-in/tap
brew install --cask tunapop
```

#### 방법 2 (DMG 직접 설치)
1. GitHub Releases에서 `tunaPop-x.y.z.dmg` 다운로드 후 마운트합니다.
2. `tunaPop.app`을 `/Applications` (응용 프로그램) 폴더로 드래그합니다.
3. 격리 속성을 제거하여 서명되지 않은 번들을 macOS가 실행하도록 허용합니다:
   ```bash
   xattr -dr com.apple.quarantine /Applications/tunaPop.app
   ```
   혹은 `tunaPop.app`을 마우스 우클릭 -> **열기** (최초 1회만 필요), 또는
   **시스템 설정** -> **개인정보 보호 및 보안** -> **어쨌든 열기**를 클릭합니다.

### 빌드 및 실행

프로젝트 루트 디렉토리에서 아래 명령어를 실행하여 앱을 빌드하고 실행할 수 있습니다.

```bash
swift build
```

마우스 드래그 및 텍스트 선택 치환을 감지하고 제어하기 위해 실행 시 macOS '손쉬운 사용(Accessibility)' 권한 승인이 필요합니다.

## 설정

설정 화면을 통해 다음과 같은 내용을 조정할 수 있습니다.

- **Agent**: 에이전트 제공자, 엔드포인트 주소, API 토큰(키체인 저장), 모델 목록 및 커스텀 모델 설정
- **응답 언어**: AI 결과물 응답 언어 고정 설정 (자동, 영어, 한국어, 일본어, 중국어)
- **ActionBar**: 액션 바가 나타나는 8방향 위치 세부 설정
- **액션**: 7종의 기본 내장 액션(수정, 숨김, 공장 초기화) 및 커스텀 액션 추가/정렬/삭제 제어
- **권한**: 시스템 접근성 권한 상태 확인 및 바로가기 제공

## 개발 및 아키텍처

tunaPop은 Swift, AppKit, SwiftUI 기반의 네이티브 아키텍처로 구현되었습니다. 최근 코드 품질 및 안정성 강화를 위해 다음과 같은 대규모 리팩토링을 성공적으로 마쳤습니다:

- **MVVM 디자인 패턴 도입**: 설정 화면(`SettingsView`)의 UI 및 선언적 정의와 모델 갱신, 타이머 핸들링, 키체인 연동 등의 비즈니스 로직을 `SettingsViewModel`로 분리하여 모듈 간 높은 결합도를 완화했습니다.
- **LLM 비동기 실행 엔진 분리**: 팝업 전체 조율과 패널 윈도우의 제어(Mediator)를 맡고 있는 `PopupController`가 더 이상 LLM 스트리밍 상태 관리나 취소 처리를 직접 하지 않도록, 전용 `LLMTaskRunner`를 추가하여 단일 책임 원칙(SRP)을 확립했습니다.
- **SSE Stream 파서 공통화 및 중복 제거**: 각 LLM 제공자 클라이언트(`GeminiClient`, `OpenAIClient`, `OllamaClient`, `AnthropicClient`)에 개별적으로 작성되었던 SSE(Server-Sent Events) 바이트 스트림 파싱 함수와 응답 조립 로직을 `SSEStreamParser` 제네릭 유틸리티로 병합하여 유지보수 생산성을 극대화했습니다.
