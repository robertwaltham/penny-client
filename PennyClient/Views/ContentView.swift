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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar

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
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: client.messages.count) { _, _ in
                        scrollToBottom(with: proxy)
                    }
                    .onChange(of: client.isTyping) { _, _ in
                        scrollToBottom(with: proxy)
                    }
                }

                composer
            }
            .navigationTitle("Penny")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        client.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reconnect")
                }
            }
        }
        .task {
            await client.connect()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onDisappear {
            client.disconnect()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(client.connectionColor)
                .frame(width: 10, height: 10)

            Text(client.statusText)
                .font(.subheadline.weight(.medium))

            Spacer()

            if client.pendingCount > 0 {
                Text("\(client.pendingCount) pending")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Penny", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !client.canSend)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(.background)
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

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let lastID = client.messages.last?.id else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

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

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(message.isOutgoing ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                ForEach(message.imageAttachments) { attachment in
                    Image(uiImage: attachment.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

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
