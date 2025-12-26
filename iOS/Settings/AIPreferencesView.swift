//
//  AIPreferencesView.swift
//  NetNewsWire-iOS
//

import SwiftUI

private enum AIUIConstants {
	static let rateLimits: [String] = ["0.5/s", "1/s", "2/s", "5/s", "Unlimited"]
}

@MainActor
struct AIPreferencesView: View {
	@ObservedObject private var settings = AISettings.shared

	@State private var showingAlert = false
	@State private var alertMessage = ""
	@State private var isTestingConnection = false

	var body: some View {
		Form {
			Section {
				Toggle("Enable AI", isOn: Binding(
					get: { settings.isEnabled },
					set: { settings.isEnabled = $0 }
				))
			} footer: {
				Text("AI features require a compatible provider and API key.")
			}

			Section("Translation") {
				TextField("Output Language", text: Binding(
					get: { settings.outputLanguage },
					set: { settings.outputLanguage = $0 }
				))
				.textInputAutocapitalization(.words)
				.disableAutocorrection(true)

				Toggle("Auto Translate Article", isOn: Binding(
					get: { settings.autoTranslate },
					set: { settings.autoTranslate = $0 }
				))

				Toggle("Auto Translate Titles", isOn: Binding(
					get: { settings.autoTranslateTitles },
					set: { settings.autoTranslateTitles = $0 }
				))
			}

			profileSection(title: "Summary Provider", usage: .summary)
			profileSection(title: "Translation Provider", usage: .translation)

			Section("Prompts") {
				VStack(alignment: .leading, spacing: 8) {
					Text("Summary Prompt")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					TextEditor(text: Binding(
						get: { settings.summaryPrompt },
						set: { settings.summaryPrompt = $0 }
					))
					.frame(minHeight: 140)
				}

				Button("Reset Summary Prompt") {
					settings.resetSummaryPrompt()
				}

				VStack(alignment: .leading, spacing: 8) {
					Text("Translation Prompt")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					TextEditor(text: Binding(
						get: { settings.translationPrompt },
						set: { settings.translationPrompt = $0 }
					))
					.frame(minHeight: 180)
				}

				Button("Reset Translation Prompt") {
					settings.resetTranslationPrompt()
				}
			}

			Section("Maintenance") {
				Button {
					testConnection()
				} label: {
					if isTestingConnection {
						HStack {
							ProgressView()
							Text("Testing Connection…")
						}
					} else {
						Text("Test Connection")
					}
				}
				.disabled(isTestingConnection)

				Button("Clear Summary Cache") {
					AICacheManager.shared.clearSummaryCache()
					showAlert("Summary cache cleared.")
				}

				Button("Clear Translation Cache") {
					AICacheManager.shared.clearTranslationCache()
					AICacheManager.shared.clearTitleTranslationCache()
					showAlert("Translation cache cleared.")
				}
			}
		}
		.alert("AI", isPresented: $showingAlert) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(alertMessage)
		}
	}

	@ViewBuilder
	private func profileSection(title: String, usage: AISettings.AIUsage) -> some View {
		Section(title) {
			if settings.profiles.isEmpty {
				Text("No profiles configured.")
					.foregroundStyle(.secondary)
				Button("Create Default Profile") {
					let profile = AIProviderProfile(
						name: "Default (OpenAI)",
						baseURL: "https://api.openai.com/v1",
						apiKey: "",
						model: "gpt-4o-mini",
						rateLimit: "2/s"
					)
					settings.addProfile(profile)
					settings.summaryProfileID = profile.id
					settings.translationProfileID = profile.id
				}
			} else {
				Button("Add Profile") {
					let profile = AIProviderProfile(
						name: "New Profile",
						baseURL: "https://api.openai.com/v1",
						apiKey: "",
						model: "gpt-4o-mini",
						rateLimit: "2/s"
					)
					settings.addProfile(profile)
					switch usage {
					case .summary:
						settings.summaryProfileID = profile.id
					case .translation:
						settings.translationProfileID = profile.id
					case .general:
						break
					}
				}

				Picker("Selected Profile", selection: Binding(
					get: { selectedProfileID(for: usage) },
					set: { setSelectedProfileID($0, for: usage) }
				)) {
					ForEach(settings.profiles) { profile in
						Text(profile.name).tag(profile.id)
					}
				}

				if let id = profileID(for: usage), let binding = bindingForProfile(id: id) {
					AIProfileEditor(profile: binding)
				}
			}
		}
	}

	private func profileID(for usage: AISettings.AIUsage) -> UUID? {
		switch usage {
		case .summary:
			return settings.summaryProfileID ?? settings.profiles.first?.id
		case .translation:
			return settings.translationProfileID ?? settings.profiles.first?.id
		case .general:
			return settings.summaryProfileID ?? settings.profiles.first?.id
		}
	}

	private func selectedProfileID(for usage: AISettings.AIUsage) -> UUID {
		profileID(for: usage) ?? UUID()
	}

	private func setSelectedProfileID(_ id: UUID, for usage: AISettings.AIUsage) {
		switch usage {
		case .summary:
			settings.summaryProfileID = id
		case .translation:
			settings.translationProfileID = id
		case .general:
			break
		}
	}

	private func bindingForProfile(id: UUID) -> Binding<AIProviderProfile>? {
		guard let index = settings.profiles.firstIndex(where: { $0.id == id }) else {
			return nil
		}
		return Binding(
			get: { settings.profiles[index] },
			set: { settings.profiles[index] = $0 }
		)
	}

	private func testConnection() {
		isTestingConnection = true
		Task {
			do {
				let response = try await AIService.shared.testConnection()
				await MainActor.run {
					isTestingConnection = false
					showAlert("Connection OK: \(response)")
				}
			} catch {
				await MainActor.run {
					isTestingConnection = false
					showAlert("Connection failed: \(error.localizedDescription)")
				}
			}
		}
	}

	private func showAlert(_ message: String) {
		alertMessage = message
		showingAlert = true
	}
}

private struct AIProfileEditor: View {
	@Binding var profile: AIProviderProfile

	var body: some View {
		TextField("Name", text: $profile.name)
		TextField("Base URL", text: $profile.baseURL)
			.textInputAutocapitalization(.never)
			.disableAutocorrection(true)
		SecureField("API Key", text: $profile.apiKey)
			.textInputAutocapitalization(.never)
			.disableAutocorrection(true)
		TextField("Model", text: $profile.model)
			.textInputAutocapitalization(.never)
			.disableAutocorrection(true)

		Picker("Rate Limit", selection: $profile.rateLimit) {
			ForEach(AIUIConstants.rateLimits, id: \.self) { value in
				Text(value).tag(value)
			}
		}
	}
}
