import SwiftUI
import CleanCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderView()
                Spacer(minLength: 12)
                MainStage()
                Spacer(minLength: 12)
                FooterView()
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $model.showDetails) {
            DetailsView()
                .environmentObject(model)
                .frame(minWidth: 580, minHeight: 640)
        }
        .sheet(isPresented: $model.showReport) {
            ReportView()
                .environmentObject(model)
                .frame(minWidth: 580, minHeight: 560)
        }
        .alert("Nettoyer aussi les éléments à vérifier ?", isPresented: $model.showReviewConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Nettoyer", role: .destructive) { model.startClean() }
        } message: {
            Text("Vous avez sélectionné des résidus d'applications dont l'origine ne peut pas être confirmée avec certitude. Ils seront supprimés définitivement et ne pourront pas être restaurés par CLEAN.")
        }
        .alert("Vider la Corbeille ?", isPresented: $model.showTrashConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Vider la Corbeille", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Les éléments de la Corbeille seront supprimés définitivement. Cette action est irréversible.")
        }
    }
}

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("CLEAN")
                .font(.system(size: 15, weight: .semibold))
                .tracking(3)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Réglages")
        }
    }
}

struct FooterView: View {
    @EnvironmentObject var model: AppModel

    private var health: (text: String, color: Color)? {
        guard let d = model.disk, d.totalBytes > 0 else { return nil }
        let free = Double(d.availableWithPurgeableBytes) / Double(d.totalBytes)
        if free >= 0.20 { return ("Stockage confortable", .green) }
        if free >= 0.10 { return ("Stockage limité", .orange) }
        return ("Stockage presque plein", .red)
    }

    var body: some View {
        VStack(spacing: 8) {
            if model.dryRun {
                Text("Mode simulation : aucune suppression")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }
            if let h = health {
                HStack(spacing: 6) {
                    Circle().fill(h.color).frame(width: 7, height: 7)
                    Text(h.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Tout reste sur votre Mac. Aucune donnée n'est envoyée.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct MainStage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                IdleView()
            case .scanning:
                ProgressStage(heading: "Analyse en cours")
            case .ready:
                ReadyView()
            case .cleaning:
                ProgressStage(heading: model.dryRun ? "Simulation en cours" : "Nettoyage en cours")
            case .done:
                DoneView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: model.phase)
    }
}

struct IdleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 26) {
            StorageRing(fraction: model.disk?.usedFraction ?? 0) {
                RingLabel(
                    title: model.disk.map { Fmt.bytes($0.availableWithPurgeableBytes) } ?? "—",
                    subtitle: model.disk.map { "disponibles sur \(Fmt.bytes($0.totalBytes))" } ?? "Stockage indisponible")
            }
            VStack(spacing: 6) {
                Text("Prêt à analyser")
                    .font(.title3.weight(.medium))
                Text("L'analyse est en lecture seule. Rien n'est supprimé sans votre accord.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Nettoyer mon Mac") { model.startScan() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            if let n = model.notice {
                Text(n)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProgressStage: View {
    @EnvironmentObject var model: AppModel
    let heading: String

    var body: some View {
        VStack(spacing: 26) {
            StorageRing(fraction: model.progress) {
                RingLabel(title: "\(Int(model.progress * 100)) %", subtitle: model.statusMessage)
            }
            Text(heading)
                .font(.title3.weight(.medium))
            Button("Annuler") { model.cancel() }
                .buttonStyle(QuietButtonStyle())
        }
    }
}

struct ReadyView: View {
    @EnvironmentObject var model: AppModel

    private var summary: String {
        guard let r = model.report else { return "" }
        let names = r.categories
            .filter { model.selected.contains($0.id) && $0.totalBytes > 0 }
            .map { $0.definition.title }
        if names.isEmpty { return "" }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? shown + "…" : shown
    }

    var body: some View {
        let bytes = model.selectedBytes
        VStack(spacing: 24) {
            if bytes > 0 {
                Text("Votre Mac peut récupérer")
                    .font(.title3.weight(.medium))
                StorageRing(fraction: 1) {
                    RingLabel(title: Fmt.bytes(bytes), subtitle: "estimation")
                }
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(model.dryRun ? "Lancer la simulation" : "Lancer le nettoyage") {
                    model.requestClean()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button("Voir les détails") { model.showDetails = true }
                    .buttonStyle(QuietButtonStyle())
            } else {
                StorageRing(fraction: 1) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Rien à nettoyer en toute sécurité")
                    .font(.title3.weight(.medium))
                Text("Votre Mac est déjà propre, ou les éléments trouvés sont trop récents ou protégés.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Terminé") { model.reset() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("Voir les détails") { model.showDetails = true }
                    .buttonStyle(QuietButtonStyle())
            }
            if bytes > 0 {
                Text("Estimation avant nettoyage. L'espace réellement libéré sera mesuré ensuite.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct DoneView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let r = model.cleanReport {
            VStack(spacing: 22) {
                StorageRing(fraction: 1) {
                    RingLabel(
                        title: Fmt.bytes(r.dryRun ? r.simulatedBytes : r.removedBytes),
                        subtitle: r.dryRun ? "seraient libérés" : "supprimés")
                }
                Text(heading(r))
                    .font(.title3.weight(.medium))
                VStack(spacing: 5) {
                    if !r.dryRun, let before = r.availableBefore, let after = r.availableAfter {
                        Text("Espace libre mesuré : \(Fmt.bytes(before)) → \(Fmt.bytes(after))")
                    }
                    Text("\(r.dryRun ? r.count(.simulated) : r.count(.removed)) éléments traités · \(r.count(.skipped)) ignorés · \(r.count(.failed)) en échec")
                    if r.cancelled {
                        Text("Opération interrompue avant la fin.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button("Terminé") { model.reset() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("Voir le rapport") { model.showReport = true }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func heading(_ r: CleanReport) -> String {
        if r.dryRun { return "Simulation terminée" }
        return r.cancelled ? "Nettoyage interrompu" : "Nettoyage terminé"
    }
}
