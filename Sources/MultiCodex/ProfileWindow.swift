import AppKit
import BrianUI
import MultiCodexCore
import SwiftUI

@MainActor
final class ProfileWindow: NSWindowController, NSWindowDelegate {
  private let controller: AppController
  private let shortcuts: ShortcutController

  init(controller: AppController, shortcuts: ShortcutController) {
    self.controller = controller
    self.shortcuts = shortcuts
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "MultiCodex"
    window.minSize = NSSize(width: 760, height: 580)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    let contentView = NSHostingView(
      rootView: AccountsView(controller: controller, shortcuts: shortcuts)
        .environment(\.theme, BrianTheme()))
    // AppKit owns this resizable window's size. SwiftUI's ideal/minimum measurements
    // can grow dramatically when a wrapping status message changes under a sheet.
    contentView.sizingOptions = []
    window.contentView = contentView
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  func present() {
    controller.refresh()
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) { shortcuts.cancelRecording() }
}

private enum Page: String, CaseIterable, Identifiable {
  case accounts = "계정"
  case shortcuts = "단축키"
  var id: Self { self }
  var symbol: String { self == .accounts ? "person.2" : "keyboard" }
}

private struct AccountsView: View {
  @Environment(\.theme) private var theme
  let controller: AppController
  let shortcuts: ShortcutController
  @State private var page = Page.accounts
  @State private var showsAddAccount = false
  @State private var editingProfile: Profile?
  @State private var removingProfile: Profile?
  @State private var migrationTarget: Profile?

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(theme.color.border.subtle).frame(width: 1)
      VStack(alignment: .leading, spacing: theme.spacing.xLarge) {
        header
        if let error = shortcuts.loadError {
          BrianCallout(error, systemImage: "exclamationmark.triangle").calloutTone(.critical)
        }
        ScrollView {
          VStack(alignment: .leading, spacing: theme.spacing.medium) {
            if page == .accounts {
              ForEach(controller.profiles) { profile in
                accountCard(profile)
              }
              BrianCallout(
                "다른 계정으로 이동해도 열어 둔 계정과 작업은 계속됩니다.",
                title: "함께 실행", systemImage: "square.stack.3d.up"
              )
              .padding(.top, theme.spacing.small)
            } else {
              ForEach(controller.profiles) { profile in
                ShortcutCard(profile: profile, shortcuts: shortcuts)
              }
            }
          }
          .padding(1)
        }
        footer
      }
      .padding(theme.spacing.xxLarge)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(theme.color.background.base)
    }
    .foregroundStyle(theme.color.foreground.primary)
    .sheet(isPresented: $showsAddAccount) { ProfileNameView(controller: controller) }
    .sheet(item: $editingProfile) { profile in
      ProfileNameView(controller: controller, profile: profile)
    }
    .sheet(item: $removingProfile) { profile in
      RemoveAccountView(controller: controller, profile: profile)
    }
    .sheet(item: $migrationTarget) { profile in
      MigrationView(controller: controller, target: profile)
    }
    .onChange(of: page) { _, _ in shortcuts.cancelRecording() }
    .onDisappear { shortcuts.cancelRecording() }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: theme.spacing.xxLarge) {
      VStack(alignment: .leading, spacing: theme.spacing.medium) {
        Image(systemName: "square.stack.3d.up.fill")
          .font(.system(size: 27, weight: .medium))
          .foregroundStyle(theme.color.foreground.brand.normal)
          .frame(width: 48, height: 48)
          .background(
            theme.color.background.brand.weak.normal, in: .rect(cornerRadius: theme.radius.large))
        Text("MultiCodex").typography(theme.typography.title.small)
      }
      VStack(spacing: theme.spacing.small) {
        ForEach(Page.allCases) { item in
          Button {
            page = item
          } label: {
            HStack(spacing: theme.spacing.small) {
              Image(systemName: item.symbol).frame(width: 18)
              Text(item.rawValue)
              Spacer()
            }
            .typography(theme.typography.label.medium)
            .padding(theme.spacing.medium)
            .foregroundStyle(
              page == item ? theme.color.foreground.brand.strong : theme.color.foreground.secondary
            )
            .background(
              page == item ? theme.color.background.brand.weak.normal : .clear,
              in: .rect(cornerRadius: theme.radius.medium))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("navigation-\(item.id)")
          .accessibilityAddTraits(page == item ? .isSelected : [])
        }
      }
      Spacer()
      VStack(alignment: .leading, spacing: theme.spacing.small) {
        BrianBadge(title: "\(controller.runningIDs.count)개 실행 중", systemImage: "circle.fill")
          .badgeTone(.positive)
        Text("로그인과 대화는\n계정별로 보관됩니다.")
          .typography(theme.typography.body.small)
          .foregroundStyle(theme.color.foreground.tertiary)
      }
    }
    .padding(theme.spacing.xLarge)
    .frame(width: 154, alignment: .leading)
    .frame(maxHeight: .infinity)
    .background(theme.color.background.subtle)
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: theme.spacing.small) {
        Text(page == .accounts ? "나의 계정" : "나만의 단축키")
          .typography(theme.typography.display.small)
        Text(page == .accounts ? "원하는 계정에서 바로 이어서 작업하세요." : "단축키로 쉽게 계정을 전환해요.")
          .typography(theme.typography.body.medium)
          .foregroundStyle(theme.color.foreground.secondary)
      }
      Spacer(minLength: theme.spacing.medium)
      if page == .accounts {
        Button {
          showsAddAccount = true
        } label: {
          Label("계정 추가", systemImage: "plus")
        }
        .buttonStyle(.solid).buttonTone(.brand).buttonSize(.small)
        .disabled(controller.busy)
      }
    }
  }

  private func accountCard(_ profile: Profile) -> some View {
    let running = controller.runningIDs.contains(profile.id)
    return VStack(alignment: .leading, spacing: theme.spacing.large) {
      HStack(alignment: .top, spacing: theme.spacing.medium) {
        VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
          HStack(spacing: theme.spacing.small) {
            Text(profile.name).typography(theme.typography.label.large)
              .lineLimit(1).help(profile.name)
            Button("이름 편집", systemImage: "pencil") { editingProfile = profile }
              .labelStyle(.iconOnly)
              .buttonStyle(.weak).buttonTone(.neutral).buttonSize(.xsmall)
              .disabled(controller.busy)
              .accessibilityLabel("\(profile.name) 이름 편집")
              .help("계정 이름 편집")
            if profile.kind == .managed {
              Button("목록에서 삭제", systemImage: "trash") { removingProfile = profile }
                .labelStyle(.iconOnly)
                .buttonStyle(.weak).buttonTone(.neutral).buttonSize(.xsmall)
                .disabled(controller.busy)
                .accessibilityLabel("\(profile.name) 목록에서 삭제")
                .help("계정 목록에서 삭제")
            }
          }
          Text(controller.loginLabels[profile.id] ?? "최초 로그인 필요")
            .typography(theme.typography.body.small)
            .foregroundStyle(theme.color.foreground.secondary)
            .lineLimit(1).truncationMode(.middle)
        }
        Spacer(minLength: 0)
        BrianBadge(title: running ? "실행 중" : "닫힘", systemImage: running ? "circle.fill" : nil)
          .badgeTone(running ? .positive : .neutral)
      }
      HStack {
        if let shortcut = shortcuts.values[profile.id] {
          Text(shortcut.display)
            .monospaced().typography(theme.typography.label.medium)
            .foregroundStyle(theme.color.foreground.secondary)
            .padding(.horizontal, theme.spacing.small).padding(.vertical, theme.spacing.xSmall)
            .background(
              theme.color.background.neutral.weak.normal,
              in: .rect(cornerRadius: theme.radius.small))
          if shortcuts.errors[profile.id] != nil {
            Image(systemName: "exclamationmark.circle").foregroundStyle(
              theme.color.foreground.warning.normal
            )
            .help("단축키 설정에서 충돌을 해결해 주세요.")
          }
        } else {
          Text("단축키 없음").typography(theme.typography.body.small).foregroundStyle(
            theme.color.foreground.tertiary)
        }
        Spacer()
        Button("가져오기", systemImage: "square.and.arrow.down") { migrationTarget = profile }
          .buttonStyle(.weak).buttonTone(.neutral).buttonSize(.small)
          .disabled(controller.busy || controller.profiles.count < 2)
          .accessibilityLabel("\(profile.name)에 다른 계정 데이터 가져오기")
        Button {
          Task { await controller.openProfile(profile) }
        } label: {
          Label(
            running ? "창으로 이동" : "계정 열기",
            systemImage: running ? "arrow.up.forward" : "plus.rectangle")
        }
        .buttonStyle(.outline).buttonSize(.small)
        .disabled(controller.busy)
        .accessibilityLabel("\(profile.name) \(running ? "창으로 이동" : "계정 열기")")
      }
    }
    .padding(theme.spacing.large)
    .background(theme.color.background.elevated, in: .rect(cornerRadius: theme.radius.xLarge))
    .overlay(
      RoundedRectangle(cornerRadius: theme.radius.xLarge).strokeBorder(
        theme.color.border.subtle, lineWidth: 1))
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: theme.spacing.medium) {
      if !controller.message.isEmpty {
        Text(controller.message)
          .typography(theme.typography.body.small)
          .foregroundStyle(theme.color.foreground.secondary)
          .lineLimit(2)
          .truncationMode(.tail)
          .help(controller.message)
          .accessibilityIdentifier("account-status")
      }
      HStack {
        Button {
          controller.refresh()
        } label: {
          Label("새로고침", systemImage: "arrow.clockwise")
        }
        Spacer()
        Button {
          NSWorkspace.shared.open(controller.store.root)
        } label: {
          Label("저장 폴더", systemImage: "folder")
        }
      }
      .buttonStyle(.weak).buttonTone(.neutral).buttonSize(.xsmall)
    }
  }
}

private struct ShortcutCard: View {
  @Environment(\.theme) private var theme
  let profile: Profile
  let shortcuts: ShortcutController
  private var recording: Bool { shortcuts.recordingID == profile.id }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.medium) {
      HStack {
        Text(profile.name).typography(theme.typography.label.large)
        Spacer()
        Button {
          shortcuts.beginRecording(for: profile.id)
        } label: {
          Text(recording ? "새 조합을 누르세요…" : (shortcuts.values[profile.id]?.display ?? "단축키 설정"))
            .monospaced().frame(minWidth: 112)
        }
        .buttonStyle(.outline).buttonSize(.small).buttonTone(recording ? .brand : .neutral)
        .disabled(shortcuts.loadError != nil)
        .accessibilityLabel("\(profile.name) 단축키 변경")
        .accessibilityValue(
          recording ? "입력 대기 중" : (shortcuts.values[profile.id]?.display ?? "사용 안 함"))
      }
      if recording {
        Text(shortcuts.recordingError ?? "원하는 키를 누르세요. Esc로 취소")
          .typography(theme.typography.body.small)
          .foregroundStyle(
            shortcuts.recordingError == nil
              ? theme.color.foreground.brand.normal : theme.color.foreground.critical.normal
          )
          .fixedSize(horizontal: false, vertical: true)
      } else if let error = shortcuts.errors[profile.id] {
        Text(error).typography(theme.typography.body.small).foregroundStyle(
          theme.color.foreground.critical.normal
        )
        .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        statusBadge
        Spacer()
        if recording {
          Button("취소") { shortcuts.cancelRecording() }
        } else {
          Button("기본값") { shortcuts.restoreDefault(for: profile.id) }
            .accessibilityLabel("\(profile.name) 기본 단축키 복원")
          Button("사용 안 함") { shortcuts.change(nil, for: profile.id) }
            .disabled(shortcuts.values[profile.id] == nil)
            .accessibilityLabel("\(profile.name) 단축키 사용 안 함")
        }
      }
      .buttonStyle(.weak).buttonTone(.neutral).buttonSize(.xsmall)
      .disabled(shortcuts.loadError != nil)
    }
    .padding(theme.spacing.large)
    .background(theme.color.background.elevated, in: .rect(cornerRadius: theme.radius.xLarge))
    .overlay(
      RoundedRectangle(cornerRadius: theme.radius.xLarge)
        .strokeBorder(
          recording ? theme.color.border.focus : theme.color.border.subtle, lineWidth: 1))
  }
  private var statusBadge: some View {
    let state: (title: String, tone: BrianBadgeProperty.Tone)
    if recording {
      state = ("입력 중", .brand)
    } else if shortcuts.recordingID != nil {
      state = ("일시 중지", .neutral)
    } else if shortcuts.activeIDs.contains(profile.id) {
      state = ("사용 중", .positive)
    } else if shortcuts.loadError != nil || shortcuts.values[profile.id] != nil {
      state = ("등록 안 됨", .warning)
    } else {
      state = ("사용 안 함", .neutral)
    }
    return BrianBadge(title: state.title)
      .badgeTone(state.tone)
      .accessibilityLabel("\(profile.name) 단축키 \(state.title)")
  }
}

private struct ProfileNameView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let controller: AppController
  let profile: Profile?
  @State private var name: String
  @State private var error: String?
  @FocusState private var nameFocused: Bool

  init(controller: AppController, profile: Profile? = nil) {
    self.controller = controller
    self.profile = profile
    _name = State(initialValue: profile?.name ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.xLarge) {
      Text(profile == nil ? "새 계정 추가" : "계정 이름 편집").typography(theme.typography.title.medium)
      if profile == nil {
        Text("알아보기 쉬운 이름을 정해 주세요. 계정을 연 뒤 처음 한 번 로그인하면 됩니다.")
          .typography(theme.typography.body.medium).foregroundStyle(
            theme.color.foreground.secondary)
      }
      BrianTextField(title: "계정 이름", text: $name, placeholder: "예: 개인, 업무")
        .maximumLength(40).errorMessage(error).textFieldFocused($nameFocused)
        .onSubmit(saveButtonTapped)
      HStack {
        Spacer()
        Button("취소") { dismiss() }.buttonStyle(.weak).buttonTone(.neutral)
        Button(profile == nil ? "추가" : "저장", action: saveButtonTapped).buttonStyle(.solid)
          .buttonTone(.brand)
          .disabled(
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40
              || controller.busy)
      }
      .buttonSize(.small)
    }
    .padding(theme.spacing.xxLarge)
    .frame(width: 420)
    .background(theme.color.background.base)
    .foregroundStyle(theme.color.foreground.primary)
    .onAppear { nameFocused = true }
  }

  private func saveButtonTapped() {
    do {
      if let profile {
        try controller.renameProfile(profile, name: name)
      } else {
        _ = try controller.addProfile(name: name)
      }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct RemoveAccountView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let controller: AppController
  let profile: Profile
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.large) {
      Text("계정을 목록에서 삭제할까요?")
        .typography(theme.typography.title.medium)
      Text(profile.name)
        .typography(theme.typography.label.large)
        .fixedSize(horizontal: false, vertical: true)
      Text("로그인·설정·대화 파일은 저장 폴더에 보관됩니다. 이 계정의 단축키는 해제됩니다.")
        .typography(theme.typography.body.medium)
        .foregroundStyle(theme.color.foreground.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if controller.runningIDs.contains(profile.id) {
        Text("열려 있는 Codex 창과 작업은 계속됩니다.")
          .typography(theme.typography.body.small)
          .foregroundStyle(theme.color.foreground.secondary)
      }
      if let error {
        BrianCallout(error, systemImage: "exclamationmark.triangle").calloutTone(.critical)
      }
      HStack {
        Spacer()
        Button("취소") { dismiss() }.buttonStyle(.weak).buttonTone(.neutral)
        Button("목록에서 삭제", action: removeButtonTapped)
          .buttonStyle(.solid).buttonTone(.critical)
          .disabled(controller.busy)
      }
      .buttonSize(.small)
    }
    .padding(theme.spacing.xxLarge)
    .frame(width: 420)
    .background(theme.color.background.base)
    .foregroundStyle(theme.color.foreground.primary)
  }

  private func removeButtonTapped() {
    do {
      try controller.removeProfile(profile)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

private struct MigrationView: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let controller: AppController
  let target: Profile
  @State private var sourceID = ""
  @State private var sourceMenu: String?
  @State private var selection = MigrationSelection()
  @State private var error: String?
  @State private var result: MigrationResult?
  @State private var restoreURL: URL?
  @State private var restored = false

  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing.xLarge) {
      VStack(alignment: .leading, spacing: theme.spacing.small) {
        Text("다른 계정에서 가져오기").typography(theme.typography.title.medium)
        Text("필요한 설정과 작업을 선택해 이어서 사용하세요.")
          .typography(theme.typography.body.medium)
          .foregroundStyle(theme.color.foreground.secondary)
      }
      HStack(spacing: theme.spacing.small) {
        BrianBadge(title: "대상 계정", systemImage: "arrow.down.to.line").badgeTone(.brand)
        Text(target.name).typography(theme.typography.label.large).lineLimit(1).help(target.name)
      }
      if restored {
        BrianCallout(
          "계정을 열어 복원된 내용을 확인하세요.", title: "가져오기 전 상태로 복원했습니다", systemImage: "checkmark.circle"
        )
        .calloutTone(.positive)
        HStack {
          Spacer()
          Button("닫기") { dismiss() }.buttonStyle(.solid).buttonTone(.brand)
        }
      } else if let result {
        BrianCallout(
          "프로젝트 \(result.projects)개 · 대화 \(result.conversations)개를 가져오거나 누락된 기록을 복구했습니다. 기존 대화는 유지됩니다.",
          title: "가져오기를 완료했습니다", systemImage: "checkmark.circle"
        ).calloutTone(.positive)
        if result.skippedConversations > 0 {
          BrianCallout(
            "대화 원본이나 이전 기록 파일이 없는 대화 \(result.skippedConversations)개는 제외했습니다. 필요한 기록이 모두 있는 대화만 가져왔으며 원본 계정은 변경하지 않았습니다.",
            title: "일부 대화 제외", systemImage: "exclamationmark.triangle"
          ).calloutTone(.warning)
        }
        HStack {
          Button("백업 폴더 열기", systemImage: "folder") { NSWorkspace.shared.open(result.backup) }
          Spacer()
          Button("가져오기 되돌리기", systemImage: "arrow.uturn.backward") { restoreURL = result.backup }
        }
        .buttonStyle(.weak).buttonTone(.neutral).disabled(controller.busy)
        errorCallout
        HStack {
          if controller.busy { ProgressView().controlSize(.small) }
          Spacer()
          Button("닫기") { dismiss() }.buttonStyle(.weak).buttonTone(.neutral)
            .disabled(controller.busy)
          Button("계정 열기") {
            dismiss()
            Task { await controller.openProfile(target) }
          }
          .buttonStyle(.solid).buttonTone(.brand).disabled(controller.busy)
        }
      } else {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
          Text("원본 계정").typography(theme.typography.label.medium)
          Button {
            sourceMenu = "source"
          } label: {
            HStack {
              Text(controller.profiles.first(where: { $0.id == sourceID })?.name ?? "계정을 선택하세요")
                .lineLimit(1)
              Spacer()
              Image(systemName: "chevron.up.chevron.down")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.outline).buttonTone(.neutral)
          .menuAnchor(id: "source")
          .accessibilityLabel("원본 계정 선택")
          .disabled(controller.busy)
        }
        VStack(alignment: .leading, spacing: theme.spacing.large) {
          Text("가져올 항목").typography(theme.typography.label.medium)
          migrationOption("Codex 내부 단축키", description: "원본 설정으로 교체합니다.", isOn: $selection.shortcuts)
          migrationOption(
            "등록한 로컬 프로젝트", description: "대상에 없는 프로젝트를 추가합니다.", isOn: $selection.projects)
          migrationOption(
            "로컬 작업과 대화", description: "원본 파일이 있는 대화만 가져오며, 기존 대화는 유지합니다.",
            isOn: $selection.conversations)
        }
        .padding(theme.spacing.large)
        .background(theme.color.background.elevated, in: .rect(cornerRadius: theme.radius.large))
        .overlay(
          RoundedRectangle(cornerRadius: theme.radius.large).strokeBorder(theme.color.border.subtle)
        )
        .disabled(controller.busy)
        BrianCallout(
          "원본·대상 Codex 앱과 CLI 작업을 모두 종료해 주세요. 로그인은 유지하고, 변경 전 데이터는 자동 백업합니다.",
          title: "가져오기 전 확인", systemImage: "info.circle"
        ).calloutTone(.informative)
        Text("프로젝트와 워크트리는 이 Mac의 기존 폴더를 사용합니다. 클라우드 작업과 서비스 연결은 포함하지 않습니다.")
          .typography(theme.typography.body.small)
          .foregroundStyle(theme.color.foreground.tertiary)
          .fixedSize(horizontal: false, vertical: true)
        errorCallout
        HStack(spacing: theme.spacing.small) {
          Button("백업에서 복원…", systemImage: "arrow.counterclockwise") { chooseBackup() }
            .buttonStyle(.weak).buttonTone(.neutral).disabled(controller.busy)
          Spacer()
          if controller.busy { ProgressView().controlSize(.small).accessibilityLabel("가져오는 중") }
          Button("취소") { dismiss() }.buttonStyle(.weak).buttonTone(.neutral).disabled(
            controller.busy)
          Button(controller.busy ? "가져오는 중…" : "가져오기") { importData() }
            .buttonStyle(.solid).buttonTone(.brand)
            .disabled(controller.busy || sourceID.isEmpty || selection.isEmpty)
        }
      }
    }
    .buttonSize(.small)
    .padding(theme.spacing.xxLarge).frame(width: 540)
    .background(theme.color.background.base)
    .foregroundStyle(theme.color.foreground.primary)
    .menuScope(selection: $sourceMenu) { _ in
      ScrollView {
        VStack(spacing: 0) {
          ForEach(controller.profiles.filter { $0.id != target.id }) { profile in
            BrianMenuItem(
              title: profile.name, systemImage: "person.crop.circle",
              isSelected: sourceID == profile.id
            ) {
              sourceID = profile.id
            }
          }
        }
      }
      .frame(maxHeight: 220)
    }
    .interactiveDismissDisabled(controller.busy)
    .alert(
      "가져오기 전 상태로 복원할까요?",
      isPresented: Binding(get: { restoreURL != nil }, set: { if !$0 { restoreURL = nil } })
    ) {
      Button("취소", role: .cancel) { restoreURL = nil }
      Button("복원", role: .destructive) {
        guard let backup = restoreURL else { return }
        restoreURL = nil
        Task {
          do {
            try await controller.restoreMigration(for: target, backup: backup)
            restored = true
          } catch { self.error = error.localizedDescription }
        }
      }
    } message: {
      Text("선택한 백업 이후의 단축키·프로젝트·대화 변경이 사라질 수 있습니다. 대상 Codex 계정과 CLI 작업을 종료해 주세요.")
    }
  }

  private var errorCallout: some View {
    Group {
      if let error {
        BrianCallout(error, systemImage: "exclamationmark.triangle")
          .calloutTone(.critical).textSelection(.enabled)
      }
    }
  }

  private func migrationOption(_ title: String, description: String, isOn: Binding<Bool>)
    -> some View
  {
    BrianCheckbox(isOn: isOn) {
      VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
        Text(title).typography(theme.typography.label.medium)
        Text(description).typography(theme.typography.body.small)
          .foregroundStyle(theme.color.foreground.secondary)
      }
    }
    .accessibilityValue(isOn.wrappedValue ? "선택됨" : "선택 안 됨")
  }

  private func chooseBackup() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = controller.store.root.appendingPathComponent("migration-backups")
    panel.prompt = "백업 선택"
    if panel.runModal() == .OK { restoreURL = panel.url }
  }

  private func importData() {
    guard let source = controller.profiles.first(where: { $0.id == sourceID }) else { return }
    error = nil
    Task {
      do {
        result = try await controller.migrate(from: source, to: target, selection: selection)
      } catch { self.error = error.localizedDescription }
    }
  }

}
