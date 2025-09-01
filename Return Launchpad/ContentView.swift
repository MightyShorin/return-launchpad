//
//  ContentView.swift
//  Return Launchpad
//
//  Created by Сергей Шорин on 22.08.2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var searchText: String = ""
    @State private var hoverId: UUID?
    @State private var currentPage: Int = 0
    @FocusState private var isSearchFocused: Bool
    
    // Drag & Drop состояния
    @StateObject private var dragSessionManager = DragSessionManager()
    @State private var draggedItem: AppInfo?
    @State private var isInDragMode: Bool = false
    @State private var draggedItemOriginalIndex: Int?
    @State private var stablePageApps: [AppInfo] = []

    // ОПТИМИЗАЦИЯ: Кэшируем конфигурацию макета
    @State private var layoutConfig: (itemsPerPage: Int, maxColumns: Int)?
    // ОПТИМИЗАЦИЯ: Кэшируем отфильтрованные приложения
    @State private var filteredApps: [AppInfo] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectBlur()
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        if isSearchFocused {
                            isSearchFocused = false
                        } else {
                            NSApplication.shared.terminate(nil)
                        }
                    }

                VStack(spacing: 0) {
                    searchAndInfoView

                    if !filteredApps.isEmpty {
                        if let config = layoutConfig {
                            let pageCount = (filteredApps.count + config.itemsPerPage - 1) / config.itemsPerPage
                            let pageApps = appsForPage(currentPage, itemsPerPage: config.itemsPerPage)
                            
                            mainGridView(pageApps: pageApps, geometry: geometry, config: config)
                            
                            dragTipView

                            Spacer()

                            if pageCount > 1 {
                                paginationView(pageCount: pageCount)
                            }
                        } else {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        notFoundView
                    }
                }
            }
            .background(
                KeyboardHandler(currentPage: $currentPage, pageCount: { () -> Int in
                    if let config = layoutConfig, !filteredApps.isEmpty {
                        return (filteredApps.count + config.itemsPerPage - 1) / config.itemsPerPage
                    }
                    return 0
                }, isSearchFocused: Binding(
                    get: { isSearchFocused },
                    set: { _ in } 
                ))
            )
            .onAppear {
                // Сначала инициализируем массив, чтобы избежать гонки состояний
                self.filteredApps = appManager.apps
                setupWindow()
                setupDragSessionManager()
                updateLayoutConfig(geometry: geometry, totalApps: self.filteredApps.count)
            }
            .onChange(of: geometry.size) {
                updateLayoutConfig(geometry: geometry, totalApps: filteredApps.count)
            }
            .onChange(of: filteredApps.count) {
                updateLayoutConfig(geometry: geometry, totalApps: filteredApps.count)
            }
            .onChange(of: appManager.apps) {
                updateFilteredApps()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchAndInfoView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                TextField("Найти приложение...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.title2)
                    .padding()
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(12)
                    .frame(maxWidth: 450)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) {
                        currentPage = 0
                        updateFilteredApps()
                    }
                
                if appManager.isCustomOrderEnabled || appManager.hasNewApps {
                    infoIndicatorsView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer()
        }
        .padding(.top, 20)
        .padding(.bottom, 15)
    }
    
    private var infoIndicatorsView: some View {
        HStack(spacing: 12) {
            if appManager.isCustomOrderEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Пользовательский порядок")
                }
                .font(.caption)
                .foregroundColor(.blue.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }
            
            if appManager.hasNewApps {
                let stats = appManager.getOrderingStats()
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Новых: \(stats.newApps)")
                }
                .font(.caption)
                .foregroundColor(.green.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
            
            if appManager.isCustomOrderEnabled {
                Button("Алфавит") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appManager.resetToAlphabeticalOrder()
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .buttonStyle(.plain)
            }
        }
    }
    
    private func mainGridView(pageApps: [AppInfo], geometry: GeometryProxy, config: (itemsPerPage: Int, maxColumns: Int)) -> some View {
        let columns = createGridColumns(geometry: geometry, maxColumns: config.maxColumns, totalItems: pageApps.count)
        return HStack {
            Spacer()
            dragDropGridView(pageApps: pageApps, itemsPerPage: config.itemsPerPage, columns: columns)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.2), value: currentPage)
        .animation(.easeInOut(duration: 0.2), value: filteredApps)
    }
    
    private var dragTipView: some View {
        Group {
            if !appManager.isCustomOrderEnabled && searchText.isEmpty && !isInDragMode {
                Text("Перетащите иконки, чтобы изменить порядок")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func paginationView(pageCount: Int) -> some View {
        HStack {
            Spacer()
            HStack {
                Button(action: { if currentPage > 0 { withAnimation(.easeInOut(duration: 0.3)) { currentPage -= 1 } } }) {
                    Image(systemName: "chevron.left").foregroundColor(currentPage == 0 ? .gray : .white)
                }
                .disabled(currentPage == 0)
                .background(
                    Rectangle().fill(Color.clear).frame(width: 60, height: 60)
                        .onDrop(of: [.text], delegate: CrossPageNavigationDelegate(direction: .previous, dragSessionManager: dragSessionManager, currentPage: $currentPage, maxPages: pageCount, onPageChange: { _ in }))
                )
                
                Text("\(currentPage + 1) из \(pageCount)")
                    .font(.body).foregroundColor(.white.opacity(0.8))
                
                Button(action: { if currentPage < pageCount - 1 { withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 } } }) {
                    Image(systemName: "chevron.right").foregroundColor(currentPage >= pageCount - 1 ? .gray : .white)
                }
                .disabled(currentPage >= pageCount - 1)
                .background(
                    Rectangle().fill(Color.clear).frame(width: 60, height: 60)
                        .onDrop(of: [.text], delegate: CrossPageNavigationDelegate(direction: .next, dragSessionManager: dragSessionManager, currentPage: $currentPage, maxPages: pageCount, onPageChange: { _ in }))
                )
            }
            .buttonStyle(.plain)
            .font(.title2)
            .padding()
            .background(Color.black.opacity(0.2))
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(dragSessionManager.autoScrollActive ? Color.blue.opacity(0.8) : Color.clear, lineWidth: 2)
                    .animation(.easeInOut(duration: 0.2), value: dragSessionManager.autoScrollActive)
            )
            Spacer()
        }
        .padding(.bottom, 20)
    }
    
    private var notFoundView: some View {
        VStack {
            Spacer()
            Text("Ничего не найдено")
                .font(.title)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }

    private func dragDropGridView(pageApps: [AppInfo], itemsPerPage: Int, columns: [GridItem]) -> some View {
        let itemsPerRow = columns.count
        let shouldUseStableLayout = isInDragMode && !dragSessionManager.isInCrossPageDrag && currentPage == dragSessionManager.startPage
        let displayApps = shouldUseStableLayout ? stablePageApps : pageApps
        
        return VStack(spacing: 20) {
            ForEach(0..<Int(ceil(Double(displayApps.count) / Double(itemsPerRow))), id: \.self) { rowIndex in
                HStack(spacing: 20) {
                    ForEach(0..<itemsPerRow, id: \.self) { colIndex in
                        let appIndex = rowIndex * itemsPerRow + colIndex
                        
                        if appIndex < displayApps.count {
                            let app = displayApps[appIndex]
                            appIconView(app: app, pageApps: pageApps, appIndex: appIndex, itemsPerPage: itemsPerPage)
                        } else {
                            Spacer().frame(width: 140, height: 120)
                        }
                    }
                }
            }
        }
    }
    
    private func appIconView(app: AppInfo, pageApps: [AppInfo], appIndex: Int, itemsPerPage: Int) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 80, height: 80)
                .opacity(draggedItem?.id == app.id ? 0.5 : 1.0)

            Text(app.name)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .foregroundColor(.white).shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .frame(height: 32)
        }
        .frame(width: 120, height: 120)
        .padding(10)
        .background(hoverId == app.id ? Color.white.opacity(0.2) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(isInDragMode ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2))
        .cornerRadius(15)
        .scaleEffect(hoverId == app.id ? 1.05 : 1.0)
        .rotationEffect(.degrees(draggedItem?.id == app.id ? 5 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: draggedItem?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hoverId)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isInDragMode)
        .onHover { isHovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                hoverId = isHovering ? app.id : nil
            }
        }
        .onTapGesture {
            if !isInDragMode {
                NSWorkspace.shared.open(app.url)
                NSApplication.shared.terminate(nil)
            }
        }
        .onDrag {
            draggedItem = app
            draggedItemOriginalIndex = appIndex
            stablePageApps = pageApps
            isInDragMode = true
            dragSessionManager.startDragSession(sourceIndex: appIndex, currentPage: currentPage, itemsPerPage: itemsPerPage)
            return NSItemProvider(object: app.bundleIdentifier as NSString)
        }
        .onDrop(of: [.text], delegate: PureIPhoneDropDelegate(
            targetIndex: appIndex, app: app, appManager: appManager,
            draggedItem: $draggedItem, draggedItemOriginalIndex: $draggedItemOriginalIndex,
            isInDragMode: $isInDragMode,
            currentPage: currentPage, itemsPerPage: itemsPerPage,
            dragSessionManager: dragSessionManager
        ))
        .opacity(draggedItem?.id == app.id ? 0.1 : 1.0)
        .opacity((dragSessionManager.isInCrossPageDrag && currentPage != dragSessionManager.startPage && draggedItem?.id == app.id) ? 0.0 : 1.0)
        .onChange(of: draggedItem) {
            if draggedItem == nil {
                dragSessionManager.endDragSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInDragMode = false
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
            window.level = .floating
            window.setFrame(NSScreen.main!.frame, display: true)
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
    
    private func setupDragSessionManager() {
        dragSessionManager.onPageChange = { signal in
            let pageCount = self.layoutConfig.map { (filteredApps.count + $0.itemsPerPage - 1) / $0.itemsPerPage } ?? 1
            if signal == -2 { // Previous
                let newPage = max(0, currentPage - 1)
                if newPage != currentPage { currentPage = newPage }
            } else if signal == -3 { // Next
                let newPage = min(pageCount - 1, currentPage + 1)
                if newPage != currentPage { currentPage = newPage }
            }
        }
        
        dragSessionManager.onDragComplete = { globalSource, globalTarget in
            appManager.moveApp(from: globalSource, to: globalTarget)
        }
    }
    
    private func updateLayoutConfig(geometry: GeometryProxy, totalApps: Int) {
        let searchAreaHeight: CGFloat = 95
        let navigationHeight: CGFloat = 80
        let gridPadding: CGFloat = 40
        let availableHeight = geometry.size.height - searchAreaHeight - navigationHeight - gridPadding
        let availableWidth = geometry.size.width - 80
        
        let itemHeight: CGFloat = 120
        let itemWidth: CGFloat = 140
        let spacing: CGFloat = 20

        let columnsCount = max(1, Int((availableWidth + spacing) / (itemWidth + spacing)))
        let rowsCount = max(1, Int((availableHeight + spacing) / (itemHeight + spacing)))
        
        var calculatedItemsPerPage = columnsCount * rowsCount
        if totalApps > calculatedItemsPerPage && rowsCount > 1 {
            calculatedItemsPerPage = columnsCount * (rowsCount - 1)
        }
        
        if layoutConfig?.itemsPerPage != calculatedItemsPerPage || layoutConfig?.maxColumns != columnsCount {
            self.layoutConfig = (calculatedItemsPerPage, columnsCount)
        }
    }
    
    private func createGridColumns(geometry: GeometryProxy, maxColumns: Int, totalItems: Int) -> [GridItem] {
        let itemWidth: CGFloat = 140
        let spacing: CGFloat = 20
        
        let columns = min(maxColumns, totalItems)
        return Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns)
    }
    
    private func appsForPage(_ page: Int, itemsPerPage: Int) -> [AppInfo] {
        guard itemsPerPage > 0 else { return [] }
        let startIndex = page * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, filteredApps.count)
        guard startIndex < endIndex else { return [] }
        return Array(filteredApps[startIndex..<endIndex])
    }
    
    private func updateFilteredApps() {
        if searchText.isEmpty {
            filteredApps = appManager.apps
        } else {
            filteredApps = appManager.apps.filter {
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }
}

// MARK: - Supporting Views & Delegates

struct KeyboardHandler: NSViewRepresentable {
    @Binding var currentPage: Int
    let pageCount: () -> Int
    @Binding var isSearchFocused: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyboardEventView()
        view.onKeyDown = { event in
            guard !isSearchFocused else { return }
            let totalPages = pageCount()
            guard totalPages > 1 else { return }
            
            switch event.keyCode {
            case 123: if currentPage > 0 { withAnimation(.easeInOut(duration: 0.2)) { currentPage -= 1 } }
            case 124: if currentPage < totalPages - 1 { withAnimation(.easeInOut(duration: 0.2)) { currentPage += 1 } }
            default: break
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyboardEventView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKeyDown?(event) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PureIPhoneDropDelegate: SwiftUI.DropDelegate {
    let targetIndex: Int
    let app: AppInfo
    let appManager: AppManager
    @Binding var draggedItem: AppInfo?
    @Binding var draggedItemOriginalIndex: Int?
    @Binding var isInDragMode: Bool
    let currentPage: Int
    let itemsPerPage: Int
    let dragSessionManager: DragSessionManager
    
    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedItem, let sourceIndex = draggedItemOriginalIndex, dragged.id != app.id else {
            return false
        }
        
        let sourcePage = dragSessionManager.isInCrossPageDrag ? dragSessionManager.startPage : currentPage
        let globalOriginalIndex = sourcePage * itemsPerPage + sourceIndex
        let globalTargetIndex = currentPage * itemsPerPage + targetIndex
        
        if globalOriginalIndex < appManager.apps.count && globalTargetIndex < appManager.apps.count {
            appManager.moveApp(from: globalOriginalIndex, to: globalTargetIndex)
        }
        
        DispatchQueue.main.async {
            self.draggedItem = nil
            self.draggedItemOriginalIndex = nil
            self.isInDragMode = false
        }
        
        return true
    }
}

struct CrossPageNavigationDelegate: DropDelegate {
    let direction: NavigationDirection
    let dragSessionManager: DragSessionManager
    @Binding var currentPage: Int
    let maxPages: Int
    let onPageChange: (Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard dragSessionManager.isInCrossPageDrag else { return }
        let canNavigate = (direction == .previous && currentPage > 0) || (direction == .next && currentPage < maxPages - 1)
        if canNavigate {
            dragSessionManager.handleArrowHover(direction: direction, isHovering: true, currentPage: currentPage, maxPages: maxPages)
        }
    }
    
    func dropExited(info: DropInfo) {
        dragSessionManager.handleArrowHover(direction: direction, isHovering: false, currentPage: currentPage, maxPages: maxPages)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dragSessionManager.handleArrowHover(direction: direction, isHovering: false, currentPage: currentPage, maxPages: maxPages)
        return false
    }
}