import SwiftUI

struct LogView: View {
    @Bindable var log: ProbeLog

    var body: some View {
        ScrollViewReader { proxy in
            List(log.entries) { entry in
                Text(entry.line)
                    .font(.caption.monospaced())
                    .foregroundStyle(entry.direction == .tx ? Color.accentColor : entry.direction == .event ? .secondary : .primary)
                    .textSelection(.enabled)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: log.entries.last?.id) { _, id in
                if let id, !log.paused { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .navigationTitle("Log")
        .toolbar {
            Toggle("Hide streaming", isOn: $log.hideStreaming)
            Toggle("Pause", isOn: $log.paused)
            Button("Clear", role: .destructive) { log.clear() }
            ShareLink(item: log.exportText, preview: SharePreview("zmash-probe-log.txt"))
        }
    }
}
