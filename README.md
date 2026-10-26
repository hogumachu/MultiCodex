# MultiCodex

Codex 데스크톱 앱의 여러 계정을 나란히 실행하는 macOS 메뉴바 앱입니다. 로그인·설정·대화를 계정별로 보관하며, 다른 계정으로 이동해도 열어 둔 작업은 계속됩니다.

## 설치

[GitHub Releases](https://github.com/hogumachu/MultiCodex/releases)에서 **MultiCodex-0.3.0-macOS.zip**을 내려받아 압축을 풀고 **MultiCodex.app**을 응용 프로그램 폴더로 옮겨 실행합니다. macOS 15 이상과 호환되는 Codex 데스크톱 앱이 필요하며, Xcode는 필요하지 않습니다.

v0.3.0 배포본은 **Developer ID 서명과 Apple 공증**을 완료했으며, Apple Silicon과 Intel Mac을 지원합니다. 공증 티켓이 앱에 포함되어 있습니다. 첫 실행 시 인터넷에서 내려받은 앱을 열지 묻는 일반 확인 창은 표시될 수 있습니다. [Apple 안내](https://support.apple.com/ko-kr/102445)를 참고하세요.

각 사용자는 자신의 Mac에서 직접 로그인합니다. 배포 파일에는 개발자의 로그인 정보·계정 목록·대화가 포함되지 않습니다.

## 사용

1. **계정 추가**에서 이름을 입력하고 **계정 열기**를 누릅니다.
2. 처음 한 번 해당 계정으로 로그인합니다.
3. 다음부터 메뉴바, **창으로 이동**, 또는 계정 단축키로 전환합니다.

계정 목록에는 제목과 연결된 이메일이 표시됩니다. 제목 옆 편집 버튼으로 이름을 바꿀 수 있으며 로그인·대화·단축키는 유지됩니다. MultiCodex를 종료해도 실행 중인 Codex 앱은 계속 열려 있습니다.

추가한 계정은 제목 옆 휴지통 버튼으로 목록에서 삭제할 수 있습니다. 확인 후 계정 목록과 단축키 설정만 제거하며, 로그인·설정·대화 파일과 실행 중인 Codex 창은 유지됩니다. 기존 Codex 계정은 삭제 대상에서 제외됩니다.

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

로컬 빌드는 임시 서명을 사용합니다. 외부 배포 시에는 Release 아카이브를 Developer ID 인증서로 서명하고 Apple 공증을 받은 뒤, 공증 티켓을 포함한 앱을 ZIP으로 배포합니다. Release 구성에는 Hardened Runtime이 활성화되어 있습니다.

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

## 계정 데이터 가져오기

대상 계정 카드의 **가져오기**에서 원본 계정과 항목을 선택합니다. 원본·대상 Codex 앱과 해당 계정의 CLI 작업을 모두 종료한 뒤 실행하세요.

- **Codex 내부 단축키**: 원본의 사용자 지정 단축키로 교체합니다. 원본이 기본값을 사용하면 대상도 기본값으로 돌아갑니다. MultiCodex의 계정 전환 단축키는 별개입니다.
- **로컬 프로젝트**: 등록된 프로젝트와 폴더 경로를 추가합니다. 같은 ID가 있으면 대상 데이터를 유지합니다.
- **로컬 작업과 대화**: 일반·보관 대화, 프로젝트 연결, 페이지 단위 대화 기록을 가져옵니다. 같은 대화 ID는 대상 데이터를 유지하며, 새 대화의 기록 파일 경로는 대상 계정 폴더로 변경합니다.

원본 데이터와 대상 로그인·인증·설정 파일은 유지합니다. 프로젝트 소스 코드, 워크트리와 대화에서 참조하는 기존 첨부 파일은 같은 Mac의 기존 경로를 계속 사용하므로 원본 폴더를 삭제하지 마세요. 클라우드 작업, 연결 서비스 인증, 메모리와 자동화는 가져오지 않습니다.

변경 전 파일은 `~/Library/Application Support/MultiCodex/migration-backups/<UUID>/`에 저장됩니다. 실패하면 자동으로 원복합니다. 완료 화면의 **가져오기 되돌리기**, 또는 가져오기 화면의 **백업에서 복원…**으로 해당 백업 폴더를 선택해 수동 복원할 수도 있습니다. 복원 시 백업 이후의 대상 데이터 변경이 사라질 수 있습니다. 강제 종료로 중단된 가져오기는 해당 백업을 복원한 후 다시 실행해야 합니다.

Codex 내부 저장 형식에 의존합니다. 두 계정의 DB 버전이 다르면 각 계정을 같은 Codex 버전으로 열고 종료한 후 다시 시도하세요. 원본 대화 파일이 없는 항목은 관련 기록과 함께 제외하고, 완료 화면에 제외 건수를 표시합니다. 지원하지 않는 형식과 심볼릭 링크 경로는 오류를 표시하고 중단합니다. 설치된 Codex 0.164.0-alpha.11.1의 DB 스키마로 검증했으며, 격리된 테스트 데이터로 실제 앱 서버의 프로젝트 조회·대화 목록·대화 읽기·재개를 확인했습니다.
