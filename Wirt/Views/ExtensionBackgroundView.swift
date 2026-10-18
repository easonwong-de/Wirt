import AppKit
import SwiftUI

// MARK: - Tab 3: Extension Background View with Console Utilities

struct ExtensionBackgroundView: View {
	let ext: ExtensionDescriptor
	@ObservedObject private var state = AppState.shared
	@State private var consoleLogs: [ConsoleLogEntry] = []
	@State private var replCommand: String = ""
	@State private var isEvaluating = false
	@State private var logSearch: String = ""

	var filteredLogs: [ConsoleLogEntry] {
		let query = logSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !query.isEmpty else { return consoleLogs }
		return consoleLogs.filter { $0.message.lowercased().contains(query) }
	}

	var body: some View {
		VStack(spacing: 0) {
			headerControlBar

			Divider()

			consoleArea
		}
		.onAppear {
			loadLogs()
		}
		.onReceive(
			NotificationCenter.default.publisher(for: NSNotification.Name("WirtConsoleLogsUpdated"))
		) { notif in
			guard let id = notif.userInfo?["extensionId"] as? String,
				id == ext.id.lowercased()
			else { return }
			loadLogs()
		}
	}

	private func loadLogs() {
		consoleLogs = ExtensionRuntime.shared.getConsoleLogs(for: ext.id)
	}

	private var headerControlBar: some View {
		HStack(spacing: 12) {
			Text("ext-bg://\(ext.id)/")
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(.secondary)

			Spacer()

			Button {
				state.reloadExtension(id: ext.id)
			} label: {
				Label("Reload", systemImage: "arrow.clockwise")
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.3))
	}

	private var consoleArea: some View {
		VStack(spacing: 0) {
			consoleFilterBar

			Divider()

			consoleLogList

			Divider()

			replInputBar
		}
	}

	private var consoleFilterBar: some View {
		HStack(spacing: 8) {
			HStack(spacing: 4) {
				Image(systemName: "magnifyingglass")
					.font(.system(size: 10))
					.foregroundStyle(.tertiary)
				TextField("Filter logs…", text: $logSearch)
					.textFieldStyle(.plain)
					.font(.system(size: 11))
			}
			.padding(.horizontal, 6)
			.padding(.vertical, 3)
			.background(Color(NSColor.controlBackgroundColor).opacity(0.8))
			.clipShape(RoundedRectangle(cornerRadius: 6))
			.frame(maxWidth: 220)

			Spacer()

			Text("\(filteredLogs.count) logs")
				.font(.system(size: 10, design: .monospaced))
				.foregroundStyle(.tertiary)

			Button {
				let text = filteredLogs.map { "[\($0.level.rawValue.uppercased())] \($0.message)" }
					.joined(separator: "\n")
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(text, forType: .string)
			} label: {
				Image(systemName: "doc.on.doc")
					.font(.system(size: 11))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help("Copy all logs")

			Button {
				ExtensionRuntime.shared.clearConsoleLogs(for: ext.id)
				consoleLogs = []
			} label: {
				Image(systemName: "trash")
					.font(.system(size: 11))
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.help("Clear logs")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.2))
	}

	private var consoleLogList: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 2) {
					if filteredLogs.isEmpty {
						HStack {
							Spacer()
							Text("Console output will appear here.")
								.font(.system(size: 11, design: .monospaced))
								.foregroundStyle(.tertiary)
								.padding(.top, 40)
							Spacer()
						}
					} else {
						ForEach(filteredLogs) { log in
							consoleLogRow(log)
								.id(log.id)
						}
					}
				}
				.padding(8)
			}
			.background(Color(NSColor.textBackgroundColor))
			.onChange(of: filteredLogs.count) { _ in
				if let last = filteredLogs.last {
					withAnimation {
						proxy.scrollTo(last.id, anchor: .bottom)
					}
				}
			}
		}
	}

	private func consoleLogRow(_ log: ConsoleLogEntry) -> some View {
		HStack(alignment: .top, spacing: 6) {
			Text(logTimeFormatter.string(from: log.timestamp))
				.font(.system(size: 10, design: .monospaced))
				.foregroundStyle(.tertiary)

			Image(systemName: log.level.icon)
				.font(.system(size: 10))
				.foregroundStyle(colorForLogLevel(log.level))
				.frame(width: 12)

			Text(log.message)
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(colorForLogLevel(log.level))
				.textSelection(.enabled)

			Spacer(minLength: 0)
		}
		.padding(.vertical, 2)
		.padding(.horizontal, 4)
		.background(
			log.level == .error
				? Color.red.opacity(0.08)
				: (log.level == .warn ? Color.orange.opacity(0.08) : Color.clear)
		)
		.clipShape(RoundedRectangle(cornerRadius: 4))
	}

	private var replInputBar: some View {
		HStack(spacing: 8) {
			Text(">")
				.font(.system(size: 12, weight: .bold, design: .monospaced))
				.foregroundStyle(Color.accentColor)

			TextField("Evaluate JavaScript in background runtime…", text: $replCommand)
				.textFieldStyle(.plain)
				.font(.system(size: 12, design: .monospaced))
				.onSubmit {
					executeRepl()
				}

			if isEvaluating {
				ProgressView()
					.controlSize(.small)
			} else {
				Button {
					executeRepl()
				} label: {
					Image(systemName: "arrow.up.circle.fill")
						.font(.system(size: 14))
				}
				.buttonStyle(.plain)
				.foregroundStyle(
					replCommand.trimmingCharacters(in: .whitespaces).isEmpty
						? Color.secondary : Color.accentColor
				)
				.disabled(replCommand.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(Color(NSColor.controlBackgroundColor).opacity(0.4))
	}

	private func executeRepl() {
		let cmd = replCommand.trimmingCharacters(in: .whitespaces)
		guard !cmd.isEmpty, !isEvaluating else { return }
		isEvaluating = true
		replCommand = ""

		ExtensionRuntime.shared.addConsoleLog(
			ConsoleLogEntry(level: .log, message: "> \(cmd)"),
			for: ext.id
		)

		Task {
			let (res, err) = await ExtensionRuntime.shared.evaluateConsoleScript(cmd, for: ext.id)
			await MainActor.run {
				isEvaluating = false
				if let err = err {
					ExtensionRuntime.shared.addConsoleLog(
						ConsoleLogEntry(level: .error, message: "< \(err)"),
						for: ext.id
					)
				} else if let res = res {
					ExtensionRuntime.shared.addConsoleLog(
						ConsoleLogEntry(level: .info, message: "< \(res)"),
						for: ext.id
					)
				}
			}
		}
	}

	private func colorForLogLevel(_ level: ConsoleLogEntry.LogLevel) -> Color {
		switch level {
		case .log: return .primary
		case .info: return .blue
		case .warn: return .orange
		case .error: return .red
		}
	}

	private var logTimeFormatter: DateFormatter {
		let df = DateFormatter()
		df.dateFormat = "HH:mm:ss.SSS"
		return df
	}
}
