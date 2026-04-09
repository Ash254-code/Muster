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
                        ForEach(templates) { template in
                            Button {
                                selectedTemplateID = template.id
                            } label: {
                                HStack(spacing: 12) {
                                    Text(template.emoji)
                                        .font(.title2)

                                    Text(template.displayTitle)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if selectedTemplateID == template.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.accent)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            selectedTemplateID == template.id
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.10)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 240)
            }

            Button {
                guard selectedTemplate != nil else { return }
                step = .enterName
            } label: {
                Text("Drop")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        selectedTemplate == nil
                        ? Color.gray.opacity(0.25)
                        : Color.accentColor
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedTemplate == nil)
        }
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
