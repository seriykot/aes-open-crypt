import AESOpenCore
import AESCryptKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: BatchModel
    @State private var isTargeted = false
    @State private var showFormatHelp = false
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case password
        case confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fileArea

            if model.phase == .finished && !showsInlineRetry {
                finishedActions
            }

            if !model.rows.isEmpty {
                form
            }

            if model.phase == .working {
                progressSection
            }
            if let error = model.errorMessage {
                errorBanner(error)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Theme.Metrics.windowPadding)
        .padding(.top, Theme.Metrics.titleBarClearance)
        .padding(.bottom, Theme.Metrics.windowPadding)
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity, minHeight: 640, idealHeight: 660, maxHeight: .infinity)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .foregroundStyle(Theme.textPrimary)
        .ignoresSafeArea(.container, edges: .top)
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
        .onChange(of: model.passwordError) { error in
            if error != nil {
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
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.iconTileRadius, style: .continuous)
                        .fill(Theme.accentSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metrics.iconTileRadius, style: .continuous)
                                .strokeBorder(Theme.accentBorder, lineWidth: 1)
                        )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("AES Open Crypt")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("AES Crypt compatible encryption")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if !model.rows.isEmpty && model.phase != .working {
                Button("Clear") {
                    model.clear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.textSecondary)
            }
        }
    }

    private var fileArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.shadow, radius: 12, y: 4)
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)

            if model.rows.isEmpty {
                emptyDropZone
            } else {
                fileList
            }
        }
        .frame(minHeight: 160, idealHeight: 240, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyDropZone: some View {
        ZStack {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius - 4, style: .continuous)
                    .fill(Theme.accentSoft)
                    .padding(8)
            }

            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius - 4, style: .continuous)
                .strokeBorder(
                    isTargeted ? Theme.accent : Theme.borderStrong,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
                .padding(8)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 24, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.accentSoft))
                    .accessibilityHidden(true)

                Text("Drop files here")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("Up to 10 files. Plain files are encrypted, .aes files are decrypted.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Choose Files…") {
                    openFiles()
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.rows) { row in
                    FileRowView(
                        row: row,
                        phase: model.phase,
                        showsHint: model.decryptHints.count > 1,
                        onRemove: { model.remove(row.id) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .padding(6)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasMixedInputs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This drop has plain files and encrypted files")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
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
                field: .password,
                error: model.passwordError,
                showsRetry: showsInlineRetry,
                showsWeakHint: model.isPasswordWeak,
                hint: model.sharedDecryptHint
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
                        .foregroundStyle(Theme.danger)
                }

                hintField

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Format")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)

                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(2)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                showFormatHelp = hovering
                            }
                            .popover(isPresented: $showFormatHelp, arrowEdge: .top) {
                                formatHelp
                            }
                            .accessibilityLabel("Format help")
                            .accessibilityHint("Compatible v2 opens in every AES Crypt release. Strong v3 uses stronger password hashing and needs AES Crypt 4.x.")
                    }
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
                .tint(Theme.accentFill)
                .disabled(!model.canStart)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var hintField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hint (optional)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            TextField("e.g. pet name or project", text: $model.hint)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.fieldRadius, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.fieldRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .onChange(of: model.hint) { value in
                    if value.count > BatchModel.maximumHintLength {
                        model.hint = String(value.prefix(BatchModel.maximumHintLength))
                    }
                }
                .help("Stored as plain text in the file. Anyone can read it without the password.")
        }
    }

    private var actionTitle: String {
        let count = model.rows.count
        let files = count == 1 ? "1 File" : "\(count) Files"
        return model.mode == .decrypt ? "Decrypt \(files)" : "Encrypt \(files)"
    }

    private var formatHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password format")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Compatible (v2)")
                .font(.callout.weight(.semibold))
            Text("Opens in every AES Crypt release.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Strong (v3)")
                .font(.callout.weight(.semibold))
                .padding(.top, 4)
            Text("Stronger password hashing. Needs AES Crypt 4.x or this app.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        error: String? = nil,
        showsRetry: Bool = false,
        showsWeakHint: Bool = false,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

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
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help(model.showPassword ? "Hide password" : "Show password")
                .accessibilityLabel(model.showPassword ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.fieldRadius, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.fieldRadius, style: .continuous)
                    .strokeBorder(
                        focusedField == field ? Theme.accent : Theme.border,
                        lineWidth: focusedField == field ? 1.5 : 1
                    )
            )

            if let hint {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Hint: \(hint)")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .foregroundStyle(Theme.info)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsWeakHint {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Weak password. Use at least 8 characters and include an uppercase letter or a special character.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.warning)
            }

            if showsRetry {
                Button("Retry") {
                    model.retryFailed()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accentFill)
                .disabled(!canRetry)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 2)
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: model.overallProgress)
                .tint(Theme.accent)
            HStack {
                Text(progressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Cancel") {
                    model.cancel()
                }
                .buttonStyle(.link)
                .tint(Theme.accent)
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
            if let summary = finishedSummary {
                HStack(spacing: 5) {
                    Image(systemName: summary.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(summary.isWarning ? Theme.danger : Theme.successIcon)
                    Text(summary.text)
                        .foregroundStyle(summary.isWarning ? Theme.danger : Theme.success)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.body.weight(.medium))
            }

            Spacer(minLength: 0)

            if !model.completedOutputs.isEmpty {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(model.completedOutputs)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill)
            }
            if hasFailedRows {
                Button("Retry Failed") {
                    model.retryFailed()
                }
                .buttonStyle(.bordered)
                .disabled(!canRetry)
            }
            Button("Done") {
                model.clear()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var finishedSummary: (text: String, isWarning: Bool)? {
        let completed = model.completedOutputs.count
        let failed = model.rows.filter { row in
            switch row.status {
            case .failed, .wrongPassword: return true
            case .pending, .running, .succeeded, .cancelled: return false
            }
        }.count
        guard model.rows.isEmpty == false, completed + failed > 0 else { return nil }

        if failed == 0 {
            let files = completed == 1 ? "file" : "files"
            return (model.mode == .decrypt ? "\(completed) \(files) decrypted" : "\(completed) \(files) encrypted", false)
        }
        return ("\(completed) finished, \(failed) failed", true)
    }

    private var hasFailedRows: Bool {
        model.rows.contains { row in
            switch row.status {
            case .failed, .wrongPassword: return true
            case .pending, .running, .succeeded, .cancelled: return false
            }
        }
    }

    private var hasWrongPasswordRows: Bool {
        model.rows.contains { row in
            if case .wrongPassword = row.status { return true }
            return false
        }
    }

    private var showsInlineRetry: Bool {
        model.phase == .finished && hasWrongPasswordRows
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
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.dangerSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.danger.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack {
            Text("Offline. No telemetry. MIT licensed.")
            Spacer()
            Text("v0.2.0")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
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
            model.add(
                urls: urls,
                preferredMode: nil,
                unreadableCount: providers.count - urls.count
            )
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
        return "Maximum of \(maximum) files at a time is allowed."
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

private struct FileRowView: View {
    let row: BatchModel.Row
    let phase: BatchModel.Phase
    let showsHint: Bool
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.item.mode == .decrypt ? "lock.doc.fill" : "doc.fill")
                .font(.system(size: 16, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accentSoft)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.input.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.textPrimary)

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
                .foregroundStyle(Theme.textSecondary)

                if showsHint, let hint = row.item.info?.passwordHint {
                    Text("Hint: \(hint)")
                        .font(.caption)
                        .foregroundStyle(Theme.info)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if case .failed(let message) = row.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let issue = row.item.issue {
                    Text(issueText(issue))
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            statusView

            if phase != .working {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isHovered ? Theme.danger : Theme.danger.opacity(0.8))
                .help("Remove from batch")
                .accessibilityLabel("Remove \(row.item.input.lastPathComponent)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous)
                .fill(isHovered ? Theme.surfaceRaised : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var statusView: some View {
        switch row.status {
        case .pending:
            if row.item.issue == nil {
                Text("Ready")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surfaceRaised))
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
        case .running:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                Text("\(Int(row.fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.successIcon)
                .accessibilityLabel("Finished")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .accessibilityLabel("Failed")
        case .wrongPassword:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .accessibilityLabel("Wrong password")
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
