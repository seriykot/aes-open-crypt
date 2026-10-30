import AESOpenCore
import AESCryptKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: BatchModel
    @State private var isTargeted = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case password
        case confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fileArea

            if !model.rows.isEmpty {
                form
            }

            if model.phase == .working {
                progressSection
            }
            if model.phase == .finished {
                finishedActions
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
        .frame(width: 640, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.rows.count) { count in
            if count > 0, model.phase == .ready {
                focusPasswordSoon()
            }
        }
        .onChange(of: model.phase) { phase in
            if phase == .ready, !model.rows.isEmpty {
                focusPasswordSoon()
            }
        }
        .onAppear {
            if !model.rows.isEmpty, model.phase == .ready {
                focusPasswordSoon()
            }
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

            if !model.rows.isEmpty && model.phase != .working {
                Button("Clear") {
                    model.clear()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var fileArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

            if model.rows.isEmpty {
                emptyDropZone
            } else {
                fileList
            }
        }
        .frame(height: 300)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop up to 10 files here")
                .font(.headline)
            Text("Plain files are encrypted. .aes files are decrypted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Files…") {
                openFiles()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.rows) { row in
                    fileRow(row)
                    if row.id != model.rows.last?.id {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .padding(6)
    }

    private func fileRow(_ row: BatchModel.Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.item.mode == .decrypt ? "lock.doc.fill" : "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.input.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(sizeText(for: row.item))
                    Text("·")
                    Text(row.item.mode == .decrypt ? "Decrypt" : "Encrypt")
                    if let output = outputName(for: row) {
                        Text("→")
                        Text(output)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if case .failed(let message) = row.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let issue = row.item.issue {
                    Text(issueText(issue))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            statusView(row)

            if model.phase != .working {
                Button {
                    model.remove(row.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove from batch")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func statusView(_ row: BatchModel.Row) -> some View {
        switch row.status {
        case .pending:
            if row.item.issue == nil {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .running:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("\(Int(row.fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Finished")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Failed")
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasMixedInputs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This drop has plain files and encrypted files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Action", selection: $model.mode) {
                        Text("Encrypt").tag(AESCryptBatchMode.encrypt)
                        Text("Decrypt").tag(AESCryptBatchMode.decrypt)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            passwordField(
                title: "Password",
                placeholder: model.mode == .decrypt ? "File password" : "Choose a password",
                text: $model.password,
                field: .password
            )

            if model.mode == .encrypt {
                passwordField(
                    title: "Confirm password",
                    placeholder: "Repeat the password",
                    text: $model.confirmation,
                    field: .confirmation
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
                }
            }

            if model.phase == .ready {
                Button {
                    model.start()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.mode == .decrypt ? "lock.open" : "lock")
                        Text(actionTitle)
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
    }

    private var actionTitle: String {
        let count = model.rows.count
        let files = count == 1 ? "1 File" : "\(count) Files"
        return model.mode == .decrypt ? "Decrypt \(files)" : "Encrypt \(files)"
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
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
                .focused($focusedField, equals: field)

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
            ProgressView(value: model.overallProgress)
            HStack {
                Text(progressLabel)
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

    private var progressLabel: String {
        let total = model.rows.count
        let position = model.rows.firstIndex { $0.status == .running }.map { $0 + 1 } ?? total
        return "File \(position) of \(total) · \(Int(model.overallProgress * 100))%"
    }

    private var finishedActions: some View {
        HStack(spacing: 10) {
            if !model.completedOutputs.isEmpty {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(model.completedOutputs)
                }
                .buttonStyle(.borderedProminent)
            }
            if hasFailedRows {
                Button("Retry Failed") {
                    model.retryFailed()
                }
                .disabled(!canRetry)
            }
            Button("Done") {
                model.clear()
            }
            Spacer()
            if hasFailedRows {
                Text("Enter a password to retry the failed files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasFailedRows: Bool {
        model.rows.contains { row in
            if case .failed = row.status { return true }
            return false
        }
    }

    private var canRetry: Bool {
        guard hasFailedRows, !model.password.isEmpty else { return false }
        if model.mode == .encrypt {
            return model.password == model.confirmation
        }
        return true
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
            Text("v0.2.0")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func focusPasswordSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedField = .password
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        let lock = NSLock()
        var loaded: [Int: URL] = [:]
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else {
                    url = nil
                }

                if let url {
                    lock.lock()
                    loaded[index] = url
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let urls = loaded.keys.sorted().compactMap { loaded[$0] }
            lock.unlock()
            model.add(urls: urls, preferredMode: nil)
        }

        return true
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.add(urls: panel.urls, preferredMode: nil)
        }
    }

    private func sizeText(for item: AESCryptBatchItem) -> String {
        if let info = item.info {
            return ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file)
        }
        let values = try? item.input.resourceValues(forKeys: [.fileSizeKey])
        return ByteCountFormatter.string(
            fromByteCount: Int64(values?.fileSize ?? 0),
            countStyle: .file
        )
    }

    private func outputName(for row: BatchModel.Row) -> String? {
        switch row.status {
        case .succeeded:
            return row.item.output.lastPathComponent
        default:
            return nil
        }
    }

    private func issueText(_ issue: AESCryptBatchIssue) -> String {
        switch issue {
        case .tooManyFiles(let maximum):
            return "Up to \(maximum) files at a time."
        case .notAFile:
            return "This is a folder, not a file."
        case .alreadyEncrypted:
            return "This file is already encrypted."
        case .notEncrypted:
            return "This is not an AES Crypt file."
        case .invalidAESFile:
            return "This .aes file is not a valid AES Crypt file."
        case .unsupportedVersion(let version):
            return "AES Crypt stream format \(version) is not supported."
        case .outputExists:
            return "An output file with that name already exists."
        case .sameFile:
            return "The input and output would be the same file."
        case .inspectFailed(let detail):
            return "Could not read the file: \(detail)"
        }
    }
}
