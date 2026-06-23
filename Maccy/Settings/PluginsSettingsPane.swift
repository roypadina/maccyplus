import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct PluginsSettingsPane: View {
  // Persisted local-folder marketplace paths (read for display; mutated via the store).
  @Default(.localMarketplaceFolders) private var localFolderPaths

  // Transient UI state.
  @State private var marketplaces: [Marketplace] = []
  @State private var installedDescriptors: [ProviderDescriptor] = []
  @State private var isRefreshing = false
  @State private var refreshError: String?

  @State private var showingAddMarketplace = false
  @State private var newMarketplaceURL = ""
  @State private var addMarketplaceError: String?

  @State private var consentEntry: MarketplaceEntry?
  @State private var consentMarketplaceID: String?
  @State private var consentCapabilities: [Capability] = []

  private let store = MarketplaceStore.shared
  private let registry = ProviderRegistry.shared
  private let capabilities = CapabilityManager.shared

  // MARK: Body

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        marketplacesBox
        availableBox
        installedBox
        localFoldersBox
      }
      .padding(20)
    }
    .frame(width: 760, height: 520)
    .task { await reloadEverything() }
    .sheet(isPresented: $showingAddMarketplace) { addMarketplaceSheet }
    .sheet(item: $consentEntry) { entry in consentSheet(for: entry) }
  }

  // MARK: Marketplaces section

  private var marketplacesBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(store.registeredMarketplaceURLs(), id: \.absoluteString) { url in
          HStack {
            Image(systemName: "globe")
              .foregroundStyle(.secondary)
            Text(url.absoluteString)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
          }
        }
        if store.registeredMarketplaceURLs().isEmpty {
          Text("No marketplaces yet. Add one to browse plugins.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Divider()

        HStack(spacing: 8) {
          Button {
            Task { await refresh() }
          } label: {
            if isRefreshing {
              ProgressView().controlSize(.small)
            } else {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
          }
          .disabled(isRefreshing)

          Button {
            newMarketplaceURL = ""
            addMarketplaceError = nil
            showingAddMarketplace = true
          } label: {
            Label("Add marketplace…", systemImage: "plus")
          }

          Spacer()

          if let refreshError {
            Text(refreshError)
              .font(.caption)
              .foregroundStyle(.red)
              .lineLimit(1)
          }
        }
      }
      .padding(4)
    } label: {
      Text("Marketplaces").font(.headline)
    }
  }

  // MARK: Available plugins section

  private var availableBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        if availableEntries.isEmpty {
          Text("Refresh a marketplace to see available plugins.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(availableEntries, id: \.entry.id) { row in
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(row.entry.name)
                  .fontWeight(.medium)
                if !row.source.isVerified {
                  unverifiedBadge
                }
              }
              Text(row.entry.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .help(row.entry.description)

            Spacer()

            Button("Install") {
              install(entry: row.entry, marketplaceID: row.marketplaceID, source: row.source)
            }
            .disabled(isInstalled(row.entry.id))
          }
          .padding(.vertical, 2)
        }
      }
      .padding(4)
    } label: {
      Text("Available plugins").font(.headline)
    }
  }

  private var unverifiedBadge: some View {
    Text("Unverified source")
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.orange.opacity(0.2), in: Capsule())
      .foregroundStyle(.orange)
      .help("This plugin comes from a source Maccay can't verify. Review its requested capabilities before installing.")
  }

  // MARK: Installed plugins section

  private var installedBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        if installedDescriptors.isEmpty {
          Text("No plugins installed.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(installedDescriptors) { descriptor in
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(descriptor.name)
                  .fontWeight(.medium)
                if !descriptor.isVerified {
                  unverifiedBadge
                }
              }
              Text(descriptor.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .help(descriptor.description)

            Spacer()

            Button(role: .destructive) {
              remove(pluginID: descriptor.id)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
          }
          .padding(.vertical, 2)
        }
      }
      .padding(4)
    } label: {
      Text("Installed plugins").font(.headline)
    }
  }

  // MARK: Local folders section

  private var localFoldersBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(localFolderPaths, id: \.self) { path in
          HStack {
            Image(systemName: "folder")
              .foregroundStyle(.secondary)
            Text(path)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
          }
        }
        if localFolderPaths.isEmpty {
          Text("Add a folder to load plugins from disk during development.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Divider()

        Button {
          addLocalFolder()
        } label: {
          Label("Add folder…", systemImage: "plus")
        }
      }
      .padding(4)
    } label: {
      Text("Local folders").font(.headline)
    }
  }

  // MARK: Add-marketplace sheet

  private var addMarketplaceSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Add marketplace")
        .font(.headline)
      Text("Enter the URL of a marketplace.json index.")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField("https://example.com/marketplace.json", text: $newMarketplaceURL)
        .textFieldStyle(.roundedBorder)
        .frame(width: 380)
      if let addMarketplaceError {
        Text(addMarketplaceError)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel") { showingAddMarketplace = false }
        Button("Add") { addMarketplace() }
          .keyboardShortcut(.defaultAction)
          .disabled(newMarketplaceURL.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 440)
  }

  // MARK: Consent sheet

  private func consentSheet(for entry: MarketplaceEntry) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.title2)
          .foregroundStyle(.orange)
        Text("\"\(entry.name)\" requests permissions")
          .font(.headline)
      }
      Text("If you install this plugin, it will be able to:")
        .font(.callout)
      VStack(alignment: .leading, spacing: 6) {
        // Sorted by rawValue: grants store capabilities in unstable Set order (C3),
        // so sorting here keeps the displayed list deterministic.
        ForEach(consentCapabilities.sorted { $0.rawValue < $1.rawValue }, id: \.self) { capability in
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle")
              .foregroundStyle(.orange)
            Text(capability.consentSentence)
          }
        }
      }
      Divider()
      HStack {
        Spacer()
        Button("Cancel") {
          consentEntry = nil
        }
        Button("Install anyway") {
          confirmConsentAndInstall()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 460)
  }

  // MARK: - Testable logic

  /// True when at least one declared capability has not yet been granted for this plugin.
  /// Pure function so it can be unit-tested without a view instance.
  static func requiresConsent(
    declared: [Capability],
    source: ProviderSource,
    manager: CapabilityManager,
    pluginID: String
  ) -> Bool {
    _ = source  // source is surfaced via the unverified badge; consent keys on capabilities + grants
    guard !declared.isEmpty else { return false }
    return manager.needsConsent(pluginID: pluginID, declared: declared)
  }

  // MARK: - Derived data

  private struct AvailableRow {
    let entry: MarketplaceEntry
    let marketplaceID: String
    let source: ProviderSource
  }

  private var availableEntries: [AvailableRow] {
    marketplaces.flatMap { marketplace in
      marketplace.plugins.map { entry in
        AvailableRow(
          entry: entry,
          marketplaceID: marketplace.id,
          source: .marketplace(marketplace.id)
        )
      }
    }
  }

  private func isInstalled(_ pluginID: String) -> Bool {
    installedDescriptors.contains { $0.id == pluginID }
  }

  // MARK: - Actions

  private func reloadEverything() async {
    await refresh()
    reloadInstalled()
  }

  private func reloadInstalled() {
    installedDescriptors = registry.descriptors().filter { descriptor in
      switch descriptor.source {
      case .builtin, .bundled:
        return false
      case .marketplace, .local:
        return true
      }
    }
  }

  private func refresh() async {
    isRefreshing = true
    refreshError = nil
    defer { isRefreshing = false }
    await store.refreshAll()
    var loaded: [Marketplace] = []
    for url in store.registeredMarketplaceURLs() {
      do {
        loaded.append(try await MarketplaceResolver.fetchIndex(url))
      } catch {
        refreshError = "Couldn't load \(url.lastPathComponent): \(error.localizedDescription)"
      }
    }
    marketplaces = loaded
  }

  private func addMarketplace() {
    addMarketplaceError = nil
    let trimmed = newMarketplaceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else {
      addMarketplaceError = "That doesn't look like a valid URL."
      return
    }
    Task {
      do {
        _ = try await store.addMarketplace(url)
        showingAddMarketplace = false
        await refresh()
      } catch {
        addMarketplaceError = error.localizedDescription
      }
    }
  }

  private func install(entry: MarketplaceEntry, marketplaceID: String, source: ProviderSource) {
    let declared = capabilitiesDeclared(by: entry)
    if Self.requiresConsent(
      declared: declared,
      source: source,
      manager: capabilities,
      pluginID: entry.id
    ) {
      // Stable display order — grants persist capabilities in unstable Set order (C3).
      consentCapabilities = declared.sorted { $0.rawValue < $1.rawValue }
      consentMarketplaceID = marketplaceID
      consentEntry = entry  // triggers the .sheet(item:)
    } else {
      performInstall(entry: entry, marketplaceID: marketplaceID)
    }
  }

  private func confirmConsentAndInstall() {
    guard let entry = consentEntry, let marketplaceID = consentMarketplaceID else { return }
    capabilities.grant(consentCapabilities, pluginID: entry.id)
    consentEntry = nil
    performInstall(entry: entry, marketplaceID: marketplaceID)
  }

  private func performInstall(entry: MarketplaceEntry, marketplaceID: String) {
    Task {
      do {
        try await store.install(entry, marketplaceID: marketplaceID)
        PluginLoader.loadAll(into: registry, extraFolders: store.localFolders())
        reloadInstalled()
      } catch {
        refreshError = "Install failed: \(error.localizedDescription)"
      }
    }
  }

  private func remove(pluginID: String) {
    store.remove(pluginID: pluginID)
    capabilities.revokeAll(pluginID: pluginID)
    PluginLoader.loadAll(into: registry, extraFolders: store.localFolders())
    reloadInstalled()
  }

  private func addLocalFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    store.addLocalFolder(url)
    PluginLoader.loadAll(into: registry, extraFolders: store.localFolders())
    reloadInstalled()
  }

  /// Declared capabilities for an entry. The marketplace index doesn't carry the
  /// capability list; it is read from the already-registered descriptor when present,
  /// otherwise treated as empty (consent will be re-checked at load time).
  private func capabilitiesDeclared(by entry: MarketplaceEntry) -> [Capability] {
    // Prefer the entry's declared capabilities (known BEFORE install, so the consent
    // sheet fires pre-download — even for a network/FS plugin from the verified
    // marketplace). Fall back to the registered descriptor for already-installed plugins.
    if let caps = entry.capabilities { return caps }
    return registry.descriptors().first { $0.id == entry.id }?.capabilities ?? []
  }
}

#Preview {
  PluginsSettingsPane()
}
