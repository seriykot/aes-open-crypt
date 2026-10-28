import AESCryptKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isTargeted = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            dropZone

            if let completed = model.completedURL {
                success(completed)
            } else if model.fileURL != nil {
                form
            }

            if model.isWorking {
                progressSection
            }
            if let error = model.errorMessage {
                errorBanner(error)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 560, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.fileURL) { _ in
            passwordFocused = model.fileURL != nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("AES Open Crypt")
                    .font(.title2.weight(.semibold))
                Text("AES Crypt compatible encryption")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.fileURL != nil && !model.isWorking {
                Button("Clear") {
                    model.clear()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

            if let file = model.fileURL {
                fileSummary(file)
            } else {
                emptyDropZone
            }
        }
        .frame(height: 148)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a file here")
                .font(.headline)
            Button("Choose File…") {
                openFile()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileSummary(_ file: URL) -> some View {
        HStack(spacing: 14) {
            Image(systemName: model.mode == .decrypt ? "lock.doc.fill" : "doc.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let info = model.info {
                    Text("\(byteCount(info.fileSize)) · AES Crypt format \(info.version.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(byteCount(fileSize(file))) · plain file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(model.mode == .decrypt ? "Encrypted" : "To encrypt")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            passwordField(
                title: "Password",
                placeholder: model.mode == .decrypt ? "File password" : "Choose a password",
                text: $model.password,
                submit: true
            )

            if model.mode == .encrypt {
                passwordField(
                    title: "Confirm password",
                    placeholder: "Repeat the password",
                    text: $model.confirmation,
                    submit: true
                )

                if !model.confirmation.isEmpty && model.password != model.confirmation {
                    Text("Passwords do not match.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Format", selection: $model.format) {
                        Text("Compatible (v2)").tag(AESFormatVersion.v2)
                        Text("Strong (v3)").tag(AESFormatVersion.v3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(
                        model.format == .v2
                            ? "Opens in every AES Crypt version, including 3.14."
                            : "Needs AES Crypt 4.x or this app. Stronger password hashing."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                model.start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.mode == .decrypt ? "lock.open" : "lock")
                    Text(model.mode == .decrypt ? "Decrypt File" : "Encrypt File")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canStart)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        submit: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Group {
                    if model.showPassword {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.plain)
                .focused($passwordFocused)

                Button {
                    model.showPassword.toggle()
                } label: {
                    Image(systemName: model.showPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.showPassword ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: model.progress)
            HStack {
                Text("\(Int(model.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    model.cancel()
                }
                .buttonStyle(.link)
            }
        }
    }

    private func success(_ url: URL) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text(model.mode == .decrypt ? "Decrypted" : "Encrypted")
                .font(.title3.weight(.semibold))
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 10) {
                Button("Show in Finder") {
                    model.reveal()
                }
                .buttonStyle(.borderedProminent)
                Button("Done") {
                    model.clear()
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private var footer: some View {
        HStack {
            Text("Offline. No telemetry. MIT licensed.")
            Spacer()
            Text("v0.1.0")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            }
            if let url {
                DispatchQueue.main.async {
                    model.open(url: url, preferredMode: nil)
                }
            }
        }
        return true
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url: url, preferredMode: nil)
        }
    }

    private func byteCount(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
