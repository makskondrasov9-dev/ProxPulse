import SwiftUI
import ProxPulseCore

struct IncidentSheet: View {
    @Bindable var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    T("Что случилось?").font(.system(size: 25, weight: .semibold))
                    T("\(model.profileName) / \(model.node.id) · \(model.incidentReport.isDemo ? "DEMO-сценарии" : "Проверки по доступным данным")").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isDiagnosing { ProgressView().controlSize(.small) }
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.hasSnapshot { T(model.connectionError ?? "Дождитесь получения данных ноды.").foregroundStyle(.orange) }
                    ForEach(model.incidentReport.checks) { check in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: check.state == .checked ? "checkmark.circle" : check.state == .warning ? "exclamationmark.triangle" : "questionmark.circle").foregroundStyle(check.state == .checked ? PulseTheme.green : check.state == .warning ? .orange : .secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { T(check.title).font(.system(size: 12, weight: .semibold)); Spacer(); T(check.state == .checked ? "Проверено" : check.state == .warning ? "Обнаружено" : "Нет данных").font(.system(size: 10)).foregroundStyle(.secondary) }
                                T(check.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !model.incidentReport.findings.isEmpty { T("Причины и рекомендации").font(.headline).padding(.top, 7) }
                    ForEach(model.incidentReport.findings) { finding in
                        VStack(alignment: .leading, spacing: 9) {
                            T(finding.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                            T(finding.reason).font(.system(size: 11)).textSelection(.enabled)
                            LB(finding.solution + " · скопировать команду") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(finding.command, forType: .string) }
                            T(finding.command).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(model.incidentReport.stoppedGuests) { guest in
                        VStack(alignment: .leading, spacing: 6) {
                            T("\(guest.name) · \(guest.kind.rawValue.uppercased()) \(guest.id)").font(.system(size: 12, weight: .semibold))
                            T("Гостевая система не работает. Причина не установлена: статус stopped не отличает штатное выключение от сбоя. Проверьте Task History ноды \(guest.node) и журнал гостевой ОС.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack { T("Снимок: \(model.incidentReport.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()))").font(.caption2).foregroundStyle(.secondary); Spacer(); LB("Повторить проверки") { model.showIncidents() }.disabled(model.isDiagnosing || !model.hasSnapshot); LB("Готово") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 680, height: 750)
    }
}
