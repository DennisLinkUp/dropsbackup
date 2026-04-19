import SwiftUI
import FirebaseAuth

// MARK: - Admin Panel

struct AdminPanelView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUserEntry] = []
    @State private var stats: AdminStats? = nil
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var activeFilter: UserFilter = .all
    @State private var confirmAction: ConfirmAction? = nil
    @State private var selectedUser: AdminUserEntry? = nil
    @State private var auroraAnimate = false

    enum UserFilter { case all, banned, active, plus }

    struct ConfirmAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destructive: Bool
        let action: () -> Void
    }

    var filteredUsers: [AdminUserEntry] {
        var base = users
        switch activeFilter {
        case .all:    break
        case .banned: base = base.filter { $0.isBanned }
        case .active: base = base.filter { $0.hasActiveDrop }
        case .plus:   base = base.filter { $0.isPlusUser }
        }
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            $0.email.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── Stat-Kacheln ──────────────────────────────────────
                    if let s = stats {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            AdminStatCard(
                                title: "Nutzer gesamt",
                                value: "\(s.totalUsers)",
                                icon: "person.3.fill",
                                color: .blue,
                                isActive: activeFilter == .all
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .all }
                            }
                            AdminStatCard(
                                title: "Aktive Drops",
                                value: "\(s.activeDrops)",
                                icon: "dot.radiowaves.left.and.right",
                                color: .green,
                                isActive: activeFilter == .active
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .active }
                            }
                            AdminStatCard(
                                title: "Gesperrt",
                                value: "\(s.bannedUsers)",
                                icon: "xmark.shield.fill",
                                color: .red,
                                isActive: activeFilter == .banned
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .banned }
                            }
                            AdminStatCard(
                                title: "Drops+",
                                value: "\(users.filter { $0.isPlusUser }.count)",
                                icon: "star.fill",
                                color: .yellow,
                                isActive: activeFilter == .plus
                            ) {
                                withAnimation(.spring(response: 0.3)) { activeFilter = .plus }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── Suchfeld ──────────────────────────────────────────
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 15))
                        TextField("Name, Telefon oder E-Mail", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 14)
                    .padding(.horizontal, 20)

                    // ── Nutzerliste ───────────────────────────────────────
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().tint(.brand)
                            Text("Lade Daten…")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if filteredUsers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.textTertiary)
                            Text(searchText.isEmpty ? "Keine Nutzer" : "Keine Treffer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredUsers) { user in
                                AdminUserCard(user: user) {
                                    selectedUser = user
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 12)
            }
            .background(
                ZStack {
                    Color.bgPrimary
                    // Aurora — im Hintergrund, beeinflusst Layout nicht
                    ZStack {
                        Circle()
                            .fill(Color.brand.opacity(0.18))
                            .frame(width: 300, height: 300)
                            .blur(radius: 80)
                            .offset(x: auroraAnimate ? 60 : -20, y: auroraAnimate ? -60 : -100)
                        Circle()
                            .fill(Color.accentOrange.opacity(0.10))
                            .frame(width: 220, height: 220)
                            .blur(radius: 60)
                            .offset(x: auroraAnimate ? -50 : 30, y: auroraAnimate ? -20 : -80)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { isLoading = true }
                        loadData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.brand)
                    }
                }
            }
            .confirmationDialog(
                confirmAction?.title ?? "",
                isPresented: Binding(
                    get: { confirmAction != nil },
                    set: { if !$0 { confirmAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let ca = confirmAction {
                    Button(ca.title, role: ca.destructive ? .destructive : .none) { ca.action() }
                    Button("Abbrechen", role: .cancel) { confirmAction = nil }
                }
            } message: {
                Text(confirmAction?.message ?? "")
            }
            .sheet(item: $selectedUser) { user in
                AdminUserDetailSheet(
                    user: user,
                    onTogglePlus: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isPlusUser ? "Drops+ entziehen" : "Drops+ freischalten",
                                message: user.isPlusUser
                                    ? "\(user.name) den Plus-Zugang entziehen?"
                                    : "\(user.name) Drops+ kostenlos freischalten?",
                                destructive: user.isPlusUser,
                                action: {
                                    RealtimeDBManager.shared.adminSetPlus(uid: user.id, isPlus: !user.isPlusUser) { loadData() }
                                }
                            )
                        }
                    },
                    onEndDrop: user.activeDropID == nil ? nil : {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: "Drop beenden",
                                message: "Den aktiven Drop von \(user.name) sofort beenden?",
                                destructive: true,
                                action: {
                                    guard let dropID = user.activeDropID else { return }
                                    RealtimeDBManager.shared.adminEndDrop(dropID: dropID) { loadData() }
                                }
                            )
                        }
                    },
                    onBan: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isBanned ? "Sperre aufheben" : "User sperren",
                                message: user.isBanned
                                    ? "\(user.name) wieder freischalten?"
                                    : "\(user.name) sperren? Kein Login mehr möglich.",
                                destructive: !user.isBanned,
                                action: {
                                    RealtimeDBManager.shared.adminSetBan(uid: user.id, banned: !user.isBanned) { loadData() }
                                }
                            )
                        }
                    },
                    onToggleAdmin: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: user.isAdmin ? "Admin-Rechte entziehen" : "Zum Admin machen",
                                message: "\(user.name) \(user.isAdmin ? "Admin-Rechte entziehen" : "zum Admin ernennen")?",
                                destructive: false,
                                action: {
                                    RealtimeDBManager.shared.adminSetAdmin(uid: user.id, isAdmin: !user.isAdmin) { loadData() }
                                }
                            )
                        }
                    },
                    onDelete: {
                        selectedUser = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            confirmAction = ConfirmAction(
                                title: "Nutzer löschen",
                                message: "\(user.name) dauerhaft löschen? Nicht rückgängig machbar.",
                                destructive: true,
                                action: {
                                    RealtimeDBManager.shared.adminDeleteUser(uid: user.id) { loadData() }
                                }
                            )
                        }
                    }
                )
            }
        }
        .onAppear {
            loadData()
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                auroraAnimate = true
            }
        }
    }

    // MARK: - Load

    private func loadData() {
        isLoading = true
        RealtimeDBManager.shared.adminFetchAllUsers { result in
            DispatchQueue.main.async {
                users = result
                withAnimation { isLoading = false }
            }
        }
        RealtimeDBManager.shared.adminFetchStats { result in
            DispatchQueue.main.async { stats = result }
        }
    }
}

// MARK: - User Detail Sheet

private struct AdminUserDetailSheet: View {
    let user: AdminUserEntry
    let onTogglePlus: () -> Void
    let onEndDrop: (() -> Void)?
    let onBan: () -> Void
    let onToggleAdmin: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var initials: String { String(user.name.prefix(1)).uppercased() }
    private var avatarColor: Color {
        user.isBanned ? .red : user.isAdmin ? .orange : .blue
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // Avatar + Name
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(avatarColor.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Text(initials)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(avatarColor)
                        }

                        VStack(spacing: 4) {
                            Text(user.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.textPrimary)
                            if user.email != "–" {
                                Text(user.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        HStack(spacing: 6) {
                            if user.hasActiveDrop {
                                AdminBadge(text: user.activeDropActivity ?? "Drop aktiv",
                                           icon: "dot.radiowaves.left.and.right", color: .green)
                            }
                            if user.isPlusUser {
                                AdminBadge(text: "Drops+", icon: "star.fill", color: .yellow)
                            }
                            if user.isAdmin {
                                AdminBadge(text: "Admin", icon: "star.fill", color: .orange)
                            }
                            if user.isBanned {
                                AdminBadge(text: "Gesperrt", icon: "xmark.shield.fill", color: .red)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Info-Zeilen
                    VStack(spacing: 0) {
                        infoRow(icon: "person.text.rectangle", label: "UID",
                                value: String(user.id.prefix(16)) + "…")
                        if let date = user.createdAt {
                            Divider().padding(.leading, 44)
                            infoRow(icon: "calendar", label: "Registriert",
                                    value: date.formatted(.dateTime.day().month().year()))
                        }
                        if user.email != "–" {
                            Divider().padding(.leading, 44)
                            infoRow(icon: "envelope", label: "E-Mail", value: user.email)
                        }
                    }
                    .liquidGlass(cornerRadius: 18)
                    .padding(.horizontal, 20)

                    // Aktionen
                    VStack(spacing: 10) {
                        if let endDrop = onEndDrop {
                            DetailActionButton(
                                icon: "xmark.circle.fill",
                                label: "Drop beenden (\(user.activeDropActivity ?? "Aktiv"))",
                                color: .accentOrange,
                                action: endDrop
                            )
                        }
                        DetailActionButton(
                            icon: user.isPlusUser ? "star.slash.fill" : "star.fill",
                            label: user.isPlusUser ? "Drops+ entziehen" : "Drops+ freischalten",
                            color: .yellow,
                            action: onTogglePlus
                        )
                        DetailActionButton(
                            icon: user.isBanned ? "lock.open.fill" : "xmark.shield.fill",
                            label: user.isBanned ? "Sperre aufheben" : "Nutzer sperren",
                            color: user.isBanned ? .green : .red, action: onBan
                        )
                        if user.id != Auth.auth().currentUser?.uid {
                            DetailActionButton(
                                icon: user.isAdmin ? "star.slash" : "star.fill",
                                label: user.isAdmin ? "Admin-Status entziehen" : "Zum Admin machen",
                                color: .orange, action: onToggleAdmin
                            )
                            DetailActionButton(
                                icon: "trash.fill",
                                label: "Nutzer löschen",
                                color: .red, action: onDelete
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(user.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brand)
                .frame(width: 20)
                .padding(.leading, 16)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

private struct DetailActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

private struct AdminStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? color.opacity(0.25) : color.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlass(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - User Card (List Row)

private struct AdminUserCard: View {
    let user: AdminUserEntry
    let onTap: () -> Void

    private var initials: String { String(user.name.prefix(1)).uppercased() }
    private var avatarColor: Color {
        user.isBanned ? .red : user.isAdmin ? .orange : .blue
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(avatarColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(initials)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(avatarColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        if user.isAdmin {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    if user.email != "–" {
                        Text(user.email)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if user.isBanned {
                        AdminBadge(text: "Gesperrt", icon: "xmark.shield.fill", color: .red)
                    } else if user.hasActiveDrop {
                        AdminBadge(text: "Aktiv", icon: "dot.radiowaves.left.and.right", color: .green)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlass(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badge

private struct AdminBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
