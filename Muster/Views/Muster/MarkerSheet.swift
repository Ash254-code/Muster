import SwiftUI
import CoreLocation

struct MarkerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var showAddCustomCategorySheet = false

    let templates: [MarkerTemplate]
    let currentCoordinate: CLLocationCoordinate2D?
    let markedPointA: CLLocationCoordinate2D?
    let markedPointB: CLLocationCoordinate2D?
    let onMarkPointA: (CLLocationCoordinate2D) -> Void
    let onMarkPointB: (CLLocationCoordinate2D) -> Void
    let onUndoPointB: () -> Void
    let onDrop: (MarkerTemplate, String?) -> Void

    private enum Step {
        case pickEmoji
        case markPoints
        case enterName
    }

    @State private var step: Step = .pickEmoji
    @State private var selectedTemplateID: UUID? = nil
    @State private var markerName: String = ""
    @State private var showPointBActionPopup = false

    private var selectedTemplate: MarkerTemplate? {
        templates.first(where: { $0.id == selectedTemplateID })
    }

    private var selectedTemplateNeedsABPoints: Bool {
        guard let template = selectedTemplate else { return false }
        let title = template.displayTitle.lowercased()
        return title == "a + b" || title == "a+ heading"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch step {
                case .pickEmoji:
                    pickEmojiView
                case .markPoints:
                    markPointsView
                case .enterName:
                    enterNameView
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(step == .enterName ? "Marker Name" : "Drop Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if step == .pickEmoji {
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
        }
        .sheet(isPresented: $showAddCustomCategorySheet) {
            NavigationStack {
                NewCustomImportCategoryView()
                    .environmentObject(app)
            }
        }
        .presentationDetents(step == .pickEmoji ? [.height(340)] : [.height(280), .medium])
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
            let title = template.displayTitle.lowercased()
            if title == "a + b" || title == "a+ heading" {
                step = .markPoints
            } else {
                step = .enterName
            }
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

    private var markPointsView: some View {
        VStack(spacing: 14) {
            Text("Mark Point A and Point B")
                .font(.headline)

            if markedPointA != nil {
                Label("Point A marked", systemImage: "a.circle.fill")
                    .foregroundStyle(.green)
            }

            if markedPointB != nil {
                Label("Point B marked", systemImage: "b.circle.fill")
                    .foregroundStyle(.green)
            }

            Button("Mark point A") {
                guard let currentCoordinate else { return }
                onMarkPointA(currentCoordinate)
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentCoordinate == nil)

            Button("Mark point B") {
                guard let currentCoordinate else { return }
                onMarkPointB(currentCoordinate)
                showPointBActionPopup = true
            }
            .buttonStyle(.bordered)
            .disabled(markedPointA == nil || currentCoordinate == nil)

            if markedPointA != nil && markedPointB != nil {
                Text("Line preview created between A and B.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Choose Undo or Save from the popup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if currentCoordinate == nil {
                Text("Current location unavailable. Wait for GPS fix to mark points.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Back") {
                step = .pickEmoji
            }
            .padding(.top, 4)
        }
        .confirmationDialog(
            "Point B marked",
            isPresented: $showPointBActionPopup,
            titleVisibility: .visible
        ) {
            Button("Undo Point B", role: .destructive) {
                onUndoPointB()
            }

            Button("Save Track") {
                step = .enterName
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A and B were marked and connected. Undo Point B or save this track to continue naming it.")
        }
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
                    step = selectedTemplateNeedsABPoints ? .markPoints : .pickEmoji
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
