# MultiCodex

Codex 데스크톱 앱의 여러 계정을 나란히 실행하는 macOS 메뉴바 앱입니다. 로그인·설정·대화를 계정별로 보관하며, 다른 계정으로 이동해도 열어 둔 작업은 계속됩니다.

## 설치

[GitHub Releases](https://github.com/hogumachu/MultiCodex/releases)에서 **MultiCodex-0.2.1-macOS.zip**을 내려받아 압축을 풀고 **MultiCodex.app**을 응용 프로그램 폴더로 옮겨 실행합니다. macOS 15 이상과 호환되는 Codex 데스크톱 앱이 필요하며, Xcode는 필요하지 않습니다.

현재 전달용 빌드는 Developer ID 서명과 Apple 공증을 받지 않은 테스트 배포본입니다. 첫 실행이 차단되면 출처를 신뢰하는 경우에만 **시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기**로 이 앱의 실행을 허용할 수 있습니다. [Apple 안내](https://support.apple.com/ko-kr/102445)를 참고하세요.

각 사용자는 자신의 Mac에서 직접 로그인합니다. 배포 파일에는 개발자의 로그인 정보·계정 목록·대화가 포함되지 않습니다.

## 사용

1. **계정 추가**에서 이름을 입력하고 **계정 열기**를 누릅니다.
2. 처음 한 번 해당 계정으로 로그인합니다.
3. 다음부터 메뉴바, **창으로 이동**, 또는 계정 단축키로 전환합니다.

계정 목록에는 제목과 연결된 이메일이 표시됩니다. 제목 옆 편집 버튼으로 이름을 바꿀 수 있으며 로그인·대화·단축키는 유지됩니다. MultiCodex를 종료해도 실행 중인 Codex 앱은 계속 열려 있습니다.

## 단축키

첫 9개 계정의 기본값은 **⌃⌥⌘1–9**입니다. **단축키** 화면에서 조합을 눌러 원하는 키로 변경하거나, **사용 안 함**·**기본값**을 선택할 수 있습니다.

- 보조 키 개수 제한 없이 문자·숫자·기호, 방향키, Space, F1–F12를 지정할 수 있습니다.
- Esc, 취소, 창 닫기 또는 다른 앱으로 이동하면 입력을 취소합니다.
- 중복되거나 OS가 등록을 거부한 조합은 오류를 표시하고 기존 설정을 유지합니다.
- 접근성·입력 모니터링 권한은 필요하지 않습니다.

## 저장 위치

`~/Library/Application Support/MultiCodex`에 다음 파일을 보관합니다.

- `profiles.json`: 계정 제목과 저장 경로
- `shortcuts.json`: 계정별 단축키
- `profiles/<UUID>/`: 추가 계정의 인증·설정·대화와 앱 데이터

기존 계정은 원래 저장 위치를 그대로 사용합니다. MultiCodex는 인증 파일을 교체하지 않고 계정별 경로로 Codex를 실행합니다. Codex 내부 옵션을 사용하므로 Codex 업데이트에 따라 호환성 확인이 필요할 수 있습니다.

## 개발

macOS 15 이상과 Swift 6을 지원하는 Xcode가 필요합니다. `MultiCodex.xcodeproj`를 열고 **MultiCodex** 스킴에서 ⌘R로 실행하거나 ⌘U로 테스트합니다. 패키지 의존성은 Xcode가 내려받습니다.

터미널에서도 별도 스크립트 없이 빌드·테스트할 수 있습니다.

```sh
xcodebuild -project MultiCodex.xcodeproj -scheme MultiCodex -configuration Release -derivedDataPath build build
xcodebuild -project MultiCodex.xcodeproj -scheme MultiCodex -destination 'platform=macOS' -derivedDataPath build test
```

릴리스 앱은 `build/Build/Products/Release/MultiCodex.app`에 생성됩니다. 개발 시 `--data-dir <경로>` 실행 인자로 별도 계정 목록을 사용할 수 있습니다.

프로젝트 설정은 Xcode 프로젝트에서 관리합니다. [BrianUI](https://github.com/thebriancompany/swift-brian-ui)의 `main` 브랜치를 사용하며, 해석된 버전은 `Package.resolved`에 고정합니다. 테스트는 Swift Testing과 CustomDump를 사용합니다.

Swift 코드는 Xcode에 포함된 `swift-format` 기본 규칙(2칸 들여쓰기)을 따릅니다.

```sh
xcrun swift-format format --in-place --recursive Sources Tests
xcrun swift-format lint --strict --recursive Sources Tests
```

## 앱 아이콘

아이콘 원본은 [icon-1024.png](Sources/MultiCodex/Assets.xcassets/AppIcon.appiconset/icon-1024.png)이며, 같은 폴더에 macOS 표시 크기별 이미지가 있습니다. Codex의 내장 이미지 생성 도구로 제작했습니다.

<details>
<summary>아이콘 생성 프롬프트</summary>

Use case: logo-brand.
Asset type: production macOS application icon for MultiCodex, an app that keeps multiple coding accounts in separate windows.
Create one polished, memorable app icon, square 1024 by 1024 pixels. A centered deep midnight-blue rounded-square tile with generous macOS-style rounded corners, occupying about 88 percent of the canvas, with a completely transparent exterior. The symbol is two overlapping upright application-window cards, slightly offset diagonally, representing two independent accounts. The back card is saturated cobalt blue, the front card is luminous pale blue/near-white with a dark navy interior and one bold, simple terminal chevron and short underscore. Keep the geometry extremely clean and the symbol large, legible at 32 pixels. Subtle soft three-dimensional depth, precise edges, restrained soft highlights, premium native Mac utility aesthetic. Balanced centered composition, front-on orthographic view. Color palette drawn from an existing dark UI with blue accents. No app name, letters, words, tiny interface details, people, avatar circles, official OpenAI logo, watermarks, background scene, mockup device, extra symbols, or multiple variants. Deliver only the finished icon artwork with real alpha transparency around the rounded tile.

</details>
