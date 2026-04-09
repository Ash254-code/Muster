import SwiftUI

struct MarkerSheet: View {
    @Environment(\.dismiss) private var dismiss

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
            }
        }
        .presentationDetents(step == .pickEmoji ? [.height(380)] : [.height(220)])
        .presentationDragIndicator(.visible)
    }

    private var pickEmojiView: some View {
        VStack(spacing: 16) {
            if templates.isEmpty {
                Text("No marker templates available.")
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

            Button(action: {
                guard selectedTemplate != nil else { return }
                step = .enterName
            }) {
                Text("Drop")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(dropButtonBackgroundColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedTemplate == nil)
        }
    }

    private func templateRow(_ template: MarkerTemplate) -> some View {
        Button(action: {
            selectedTemplateID = template.id
        }) {
            HStack(spacing: 12) {
                Text("🙂")
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
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(rowBackground(for: template))
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(for template: MarkerTemplate) -> some ShapeStyle {
        if selectedTemplateID == template.id {
            return Color.accentColor.opacity(0.18)
        } else {
            return Color.secondary.opacity(0.10)
        }
    }

    private var dropButtonBackgroundColor: Color {
        selectedTemplate == nil ? Color.gray.opacity(0.25) : Color.accentColor
    }

    private var enterNameView: some View {
        VStack(spacing: 16) {
            if let template = selectedTemplate {
                Text(template.emoji)
                    .font(.system(size: 42))
            }

            TextField("Name", text: $markerName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            HStack(spacing: 12) {
                Button {
                    step = .pickEmoji
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
