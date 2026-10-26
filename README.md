# MultiCodex

Codex 데스크톱 앱의 여러 계정을 나란히 실행하는 macOS 메뉴바 앱입니다. 로그인·설정·대화를 계정별로 보관하며, 다른 계정으로 이동해도 열어 둔 작업은 계속됩니다.

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
