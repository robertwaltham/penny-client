import SwiftUI
import UIKit

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var client = PennyWebSocketClient()
    @State private var draftMessage = ""
    @State private var isShowingConnectionError = false
    @State private var composerHeight: CGFloat = 64
    @State private var keyboardHeight: CGFloat = 0

    private let keyboardComposerSpacing: CGFloat = -24

    private var keyboardOffset: CGFloat {
        keyboardHeight > 0 ? keyboardHeight + keyboardComposerSpacing : 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(client.messages) { message in
                                ChatMessageRow(message: message)
                                    .id(message.id)
                            }

                            if client.isTyping {
                                TypingRow()
                            }

                            Color.clear
                                .frame(height: composerHeight + keyboardOffset + 12)
                                .id(bottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                    .background(Color(.systemGroupedBackground))
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollToBottom(with: proxy, animated: false)
                        }
                    }
                    .onChange(of: client.messages.count) { _, _ in
                        scrollToBottom(with: proxy)
                    }
                    .onChange(of: client.isTyping) { _, _ in
                        scrollToBottom(with: proxy)
                    }
                    .onChange(of: keyboardHeight) { _, _ in
                        scrollToBottom(with: proxy)
                    }
                }

                
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .bottom) {
                composer
                    .offset(y: -keyboardOffset)
                    .readHeight { height in
                        guard height > 0 else { return }
                        composerHeight = height
                    }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleBar
                }

                if client.lastError != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingConnectionError = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Connection error")
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .alert("Connection Error", isPresented: $isShowingConnectionError, presenting: client.lastError) { _ in
                Button("Reconnect") {
                    client.reconnect()
                }
                Button("OK", role: .cancel) {}
            } message: { errorMessage in
                Text(errorMessage)
            }
        }
        .task {
            await client.connect()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onDisappear {
            client.disconnect()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image("penny")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            Text("Penny")
                .font(.headline)

            Circle()
                .fill(client.connectionColor)
                .frame(width: 9, height: 9)
                .accessibilityLabel(client.statusText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

            Button(action: sendDraft) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !client.canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
    }

    private func sendDraft() {
        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        draftMessage = ""
        client.sendMessage(trimmedMessage)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { await client.connect() }
        case .background:
            client.disconnect()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? keyboardFrame.maxY
        let overlap = max(0, screenHeight - keyboardFrame.minY)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25

        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = overlap
        }
    }

    private var bottomAnchorID: String {
        "message-list-bottom"
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        overlay {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

    private var markdownTextBlocks: [AttributedString] {
        message.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let text = line.isEmpty ? " " : String(line)
                return (try? AttributedString(markdown: text)) ?? AttributedString(text)
            }
    }

    @ViewBuilder
    private var messageBubble: some View {
        if message.isOutgoing {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(markdownTextBlocks.indices, id: \.self) { index in
                    Text(markdownTextBlocks[index])
                        .lineLimit(nil)
                        .font(.body)
                }

                ForEach(message.imageAttachments) { attachment in
                    Image(uiImage: attachment.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 5) {
                if let sourceHint = message.sourceHint, !sourceHint.isEmpty {
                    Text(sourceHint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                messageBubble

                Text(message.displayTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !message.isOutgoing {
                Spacer(minLength: 48)
            }
        }
    }
}

private struct TypingRow: View {
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(index == 1 ? 0.7 : 0.45)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 48)
        }
        .accessibilityLabel("Penny is typing")
    }
}

#Preview {
    ContentView()
}
