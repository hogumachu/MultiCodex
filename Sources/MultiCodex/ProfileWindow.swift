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
    window.contentView = NSHostingView(
      rootView: AccountsView(controller: controller, shortcuts: shortcuts)
        .environment(\.theme, BrianTheme()))
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
          .fixedSize(horizontal: false, vertical: true)
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
