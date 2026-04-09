import SwiftUI

struct MarkerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var showAddCustomCategorySheet = false

    let templates: [MarkerTemplate]
    let onDrop: (MarkerTemplate, String?) -> Void

    private enum Step {
        case pickEmoji
        case enterName
    }

    @State private var step: Step = .pickEmoji
    @State private var selectedTemplateID: UUID? = nil
    @State private var markerName: String = ""

    private var selectedTemplate: MarkerTemplate? {
        templates.first(where: { $0.id == selectedTemplateID })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if step == .pickEmoji {
                    pickEmojiView
                } else {
                    enterNameView
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(step == .pickEmoji ? "Drop Marker" : "Marker Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddCustomCategorySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add marker category")
                }
            }
        }
        .sheet(isPresented: $showAddCustomCategorySheet) {
            NavigationStack {
                NewCustomImportCategoryView()
                    .environmentObject(app)
            }
        }
        .presentationDetents(step == .pickEmoji ? [.height(340)] : [.height(240)])
        .presentationDragIndicator(.visible)
    }

    private var pickEmojiView: some View {
        VStack(spacing: 16) {
            if templates.isEmpty {
                Text("No custom marker categories yet. Tap + to add POI types.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(templates, id: \.id) { template in
                            templateRow(template)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 240)
            }

        }
    }

    private func templateRow(_ template: MarkerTemplate) -> some View {
        Button(action: {
            selectedTemplateID = template.id
            step = .enterName
        }) {
            HStack(spacing: 12) {
                Text(template.emoji)
                    .font(.title2)

                Text(template.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                if selectedTemplateID == template.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        selectedTemplateID == template.id ? Color.accentColor.opacity(0.45) : .white.opacity(0.12),
                        lineWidth: selectedTemplateID == template.id ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var enterNameView: some View {
        VStack(spacing: 16) {
            if let template = selectedTemplate {
                Text(template.emoji)
                    .font(.system(size: 42))
            }

            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)

                TextField("Marker name", text: $markerName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button {
                    step = .pickEmoji
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                }

                Button {
                    guard let template = selectedTemplate else { return }
                    let trimmed = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDrop(template, trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accentColor.gradient, in: Capsule())
                        .foregroundStyle(.white)
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                        )
                }
            }
        }
    }
}
