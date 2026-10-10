import SwiftUI
import AppKit
import CleanCore

struct DetailsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Détails")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let r = model.report {
                        section(title: "Nettoyage sans risque",
                                results: r.categories.filter { $0.definition.risk == .safe })
                        section(title: "À vérifier",
                                results: r.categories.filter { $0.definition.risk == .review })
                        TrashSection(state: r.trash)
                        if !r.suggestions.isEmpty {
                            SuggestionsSection(suggestions: r.suggestions)
                        }
                        if !r.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(r.warnings, id: \.self) { w in
                                    Text(w).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("Aucune analyse disponible.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func section(title: String, results: [CategoryResult]) -> some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                ForEach(results) { result in
                    CategoryRow(result: result)
                }
            }
        }
    }
}

struct CategoryRow: View {
    @EnvironmentObject var model: AppModel
    let result: CategoryResult
    @State private var expanded = false
    @State private var showSkipped = false

    private var binding: Binding<Bool> {
        Binding(
            get: { model.selected.contains(result.id) },
            set: { model.setSelected(result.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.definition.symbol)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.definition.title)
                            .font(.headline)
                        if result.definition.risk == .review {
                            Text("À vérifier")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                        }
                    }
                    Text(result.definition.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let n = result.notice {
                        Text(n)
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Fmt.bytes(result.totalBytes))
                        .font(.headline.monospacedDigit())
                    Toggle("", isOn: binding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(result.items.isEmpty)
                }
            }
            if !result.items.isEmpty {
                DisclosureGroup("\(result.items.count) éléments", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.items.prefix(25)) { item in
                            HStack {
                                Text(item.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(Fmt.bytes(item.sizeBytes))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        if result.items.count > 25 {
                            Text("… et \(result.items.count - 25) autres")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }
            if !result.skipped.isEmpty {
                DisclosureGroup("\(result.skipped.count) éléments ignorés par sécurité", isExpanded: $showSkipped) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.skipped.prefix(25)) { s in
                            HStack {
                                Text(s.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(s.reason)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

struct TrashSection: View {
    @EnvironmentObject var model: AppModel
    let state: TrashState

    private var description: String {
        switch state {
        case .empty:
            return "La Corbeille est vide."
        case .measured(let bytes, let count):
            return "\(count) élément(s), \(Fmt.bytes(bytes))."
        case .unavailable(let reason):
            return reason + ". Vous pouvez tout de même la vider via le Finder."
        }
    }

    private var canEmpty: Bool {
        if case .empty = state { return false }
        return !model.trashBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Corbeille")
                .font(.headline)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "trash")
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vider la Corbeille")
                        .font(.headline)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Action séparée, soumise à une confirmation. Non incluse dans le nettoyage général.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Vider…") { model.showTrashConfirm = true }
                    .disabled(!canEmpty)
            }
            if let message = model.trashMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

struct SuggestionsSection: View {
    @EnvironmentObject var model: AppModel
    let suggestions: [ReviewSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("À examiner vous-même")
                .font(.headline)
            Text("CLEAN ne supprime jamais ces éléments. Ils ne sont pas comptés dans l'espace récupérable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(suggestions) { s in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(s.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.bytes(s.bytes))
                        .font(.callout.monospacedDigit())
                    Button("Afficher") { model.reveal(s.path) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
        }
    }
}

struct ReportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private func label(_ s: OutcomeStatus) -> String {
        switch s {
        case .removed: return "Supprimé"
        case .simulated: return "Simulé"
        case .skipped: return "Ignoré"
        case .failed: return "Échec"
        }
    }

    private func color(_ s: OutcomeStatus) -> Color {
        switch s {
        case .removed, .simulated: return .green
        case .skipped: return .secondary
        case .failed: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rapport")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Journal…") { model.openLogFolder() }
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            if let r = model.cleanReport {
                List {
                    ForEach(r.outcomes) { o in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(label(o.status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(o.status))
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let m = o.message {
                                    Text(m)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if o.bytes > 0 {
                                Text(Fmt.bytes(o.bytes))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Spacer()
                Text("Aucun rapport disponible.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Mode simulation", isOn: $model.dryRun)
                Text("Analyse et nettoie « à blanc » : rien n'est supprimé, le rapport indique ce qui l'aurait été.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Afficher le journal des opérations") { model.openLogFolder() }
                Text("Le journal reste sur votre Mac. CLEAN n'envoie aucune donnée, n'a ni compte ni publicité.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}
