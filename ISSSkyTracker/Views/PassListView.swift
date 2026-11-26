import SwiftUI

/// Upcoming ISS passes over the user's location, grouped by day.
struct PassListView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("visibleOnly") private var visibleOnly = true

    private var shown: [ISSPass] {
        visibleOnly ? model.passes.filter(\.isVisible) : model.passes
    }

    private var days: [(day: Date, passes: [ISSPass])] {
        let grouped = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.displayStart.date) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Only passes you can see", isOn: $visibleOnly)
                } footer: {
                    Text("The ISS is visible when it is sunlit, your sky is dark, and it's at least 10° above the horizon — usually shortly after sunset or before sunrise.")
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                }
                if model.location.isDenied {
                    Label("Turn on Location access in Settings to see passes for where you are.", systemImage: "location.slash")
                        .foregroundStyle(.orange)
                }

                ForEach(days, id: \.day) { group in
                    Section(group.day.dayTitle) {
                        ForEach(group.passes) { pass in
                            NavigationLink(value: pass) { PassRow(pass: pass) }
                        }
                    }
                }

                if shown.isEmpty && model.errorMessage == nil && !model.location.isDenied {
                    Section {
                        if model.passes.isEmpty {
                            HStack { ProgressView(); Text("Calculating passes…").padding(.leading, 8) }
                        } else {
                            Text("No visible passes in the next 10 days. Turn off the filter to see every pass.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let tle = model.tle {
                    Section {
                        LabeledContent("Orbit data from", value: "CelesTrak")
                        LabeledContent("Orbit data epoch", value: tle.epoch.formatted(date: .abbreviated, time: .shortened))
                        if let place = model.location.placeName { LabeledContent("Your location", value: place) }
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("ISS Passes")
            .navigationDestination(for: ISSPass.self) { PassDetailView(pass: $0) }
            .refreshable { await model.refresh() }
        }
    }
}

private struct PassRow: View {
    let pass: ISSPass

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pass.isVisible ? "eye.fill" : "eye.slash")
                .foregroundStyle(pass.isVisible ? .yellow : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(pass.displayStart.date.clock).font(.headline.monospacedDigit())
                Text(pass.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(pass.displayEnd.date.timeIntervalSince(pass.displayStart.date).minutesText)
                    .font(.subheadline.monospacedDigit())
                if let reason = pass.invisibilityReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("max \(Int(pass.displayPeak.rounded()))°").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
