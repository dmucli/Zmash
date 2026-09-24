import SwiftUI
import ZmashKit

/// Strava and intervals.icu, each with your own credentials (roadmap Phase 9).
/// Zmash has no server: the FIT file goes straight from the iPad to the service.
struct UploadSettingsView: View {
    @State private var stravaID = UploadSettings.stravaClientID
    @State private var stravaSecret = UploadSettings.stravaSecret
    @State private var athlete = UploadSettings.intervalsAthleteID
    @State private var key = UploadSettings.intervalsKey
    @State private var autoUpload = UploadSettings.autoUpload
    @State private var connecting = false
    @State private var error: String?

    private let center = UploadCenter.shared

    var body: some View {
        Form {
            Section {
                Toggle("Upload every saved ride", isOn: $autoUpload)
                    .onChange(of: autoUpload) { _, on in UploadSettings.autoUpload = on }
            } footer: {
                Text("Rides go to every service set up below. You can also send a single ride from its summary or from History.")
            }

            let _ = center.accounts // redraw on connect and disconnect
            Section {
                if UploadSettings.stravaConnected {
                    Label("Connected", systemImage: "checkmark.circle")
                    Button("Disconnect", role: .destructive) { UploadSettings.disconnect(.strava) }
                } else {
                    TextField("Client ID", text: $stravaID)
                        .onChange(of: stravaID) { _, v in UploadSettings.stravaClientID = v.trimmingCharacters(in: .whitespaces) }
                        .textInputAutocapitalization(.never)
                    SecureField("Client secret", text: $stravaSecret)
                        .onChange(of: stravaSecret) { _, v in UploadSettings.stravaSecret = v.trimmingCharacters(in: .whitespaces) }
                    Button(connecting ? "Connecting…" : "Connect Strava") { connect() }
                        .disabled(connecting || stravaID.isEmpty || stravaSecret.isEmpty)
                }
                Text(UploadService.strava.help)
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            } header: { SectionHeader("Strava") }

            Section {
                TextField("Athlete ID (i12345)", text: $athlete)
                    .onChange(of: athlete) { _, v in UploadSettings.intervalsAthleteID = v.trimmingCharacters(in: .whitespaces) }
                    .textInputAutocapitalization(.never)
                SecureField("API key", text: $key)
                    .onChange(of: key) { _, v in UploadSettings.intervalsKey = v.trimmingCharacters(in: .whitespaces) }
                if UploadSettings.intervalsConnected {
                    Button("Disconnect", role: .destructive) {
                        UploadSettings.disconnect(.intervals)
                        athlete = ""
                        key = ""
                    }
                }
                Text(UploadService.intervals.help)
                    .font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
            } header: { SectionHeader("intervals.icu") }

            if center.waiting > 0 {
                Section {
                    HStack {
                        Text("\(center.waiting) upload\(center.waiting == 1 ? "" : "s") waiting to send")
                            .font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                        Spacer()
                        Button("Try now") { Task { await center.retryDue(now: true) } }
                    }
                } footer: {
                    Text("They're tried again when the network comes back, and at intervals, for up to a day.")
                }
            }

            Section {
                ForEach(UploadService.allCases) { service in
                    if case .failed(let message) = center.latest[service] {
                        Text("\(service.name): \(message)").font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    } else if case .done(let message) = center.latest[service] {
                        Text("\(service.name): \(message)").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                }
            }
        }
        .zmashForm()
        .navigationTitle("Uploads")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't connect", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {} message: {
            Text(error ?? "")
        }
    }

    private func connect() {
        connecting = true
        Task {
            do { try await center.connectStrava() } catch { self.error = error.localizedDescription }
            connecting = false
        }
    }
}

/// "Send this ride" buttons, shared by the end-of-ride summary and a ride's detail page. The ride itself is only
/// built (samples decoded) when a button is tapped.
struct UploadRow: View {
    let id: UUID
    let ride: () -> FinishedRide
    private let center = UploadCenter.shared

    var body: some View {
        let services = UploadService.allCases.filter(UploadSettings.connected)
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(services) { service in
                        Button {
                            Task { await center.upload(ride(), to: service) }
                        } label: {
                            HStack(spacing: 8) {
                                if case .working = center.state(service, ride: id) { ProgressView().controlSize(.small) }
                                Text(label(service)).font(Design.Font.label)
                            }
                            .foregroundStyle(Design.Palette.primary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
                        }
                        .buttonStyle(.plain)
                        .disabled(center.state(service, ride: id) == .working)
                    }
                }
                ForEach(services) { service in
                    if case .failed(let message) = center.state(service, ride: id) {
                        Text("\(service.name): \(message)").font(Design.Font.small).foregroundStyle(Design.Status.caution)
                    } else if center.state(service, ride: id) == .idle, center.isWaiting(id, service) {
                        Text("\(service.name): waiting to send").font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                    }
                }
            }
        }
    }

    private func label(_ service: UploadService) -> String {
        switch center.state(service, ride: id) {
        case .done: "Sent to \(service.name)"
        case .working: "Sending…"
        default: "Send to \(service.name)"
        }
    }
}
