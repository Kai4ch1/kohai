import Foundation

// =============================================================================
// MOCK DATA, previews and snapshots only. These are not Core models.
// =============================================================================

enum PreviewData {

    private static func row(
        _ id: String, _ agent: AgentKind, _ project: String, _ name: String,
        _ account: String?, _ status: SessionStatus, _ seconds: Int, _ message: String
    ) -> SessionRowModel {
        SessionRowModel(
            id: id, agent: agent, project: project, sessionName: name, account: account,
            status: status, secondsInStatus: seconds, lastMessage: message)
    }

    /// Mixed list: two need input (in different projects), working and done mixed in.
    static let mixed: [SessionRowModel] = [
        row("a1f3", .claudeCode, "yheat", "popup-heatmap-fix", "work@boosta", .needsInput, 192,
            "May I run the migration on the staging database?"),
        row("b2c4", .codex, "yheat", "seo-advice-panel", "personal", .working, 47,
            "Reading overlay.ts and the three components that import it"),
        row("c3d5", .claudeCode, "kohai", "dropdown-layout", "work@boosta", .working, 604,
            "Applying tokens to SessionRow"),
        row("d4e6", .codex, "kohai", "socket-reconnect", "personal", .done, 5_400,
            "Done. Tests pass and the branch is ready for review."),
        row("e5f7", .claudeCode, "autoLoans", "lead-form-validation", "work@boosta", .needsInput, 75,
            "Should I delete the old validation helper or keep it behind a flag?"),
        row("f6a8", .claudeCode, "autoLoans", "locale-routing", "work@boosta", .done, 93_600,
            "Finished. Summary of the changes is in the PR description."),
        row("a7b9", .codex, "web", "pricing-page", "personal", .working, 12,
            "Running the build"),
    ]

    /// Long project / session names and long last messages.
    static let longNames: [SessionRowModel] = [
        row("l001", .claudeCode,
            "boosta-affiliate-landing-multilocale-redirect-service-staging-eu-west",
            "refactor-the-entire-locale-detection-and-geo-redirect-pipeline-v2",
            "marketing-team-shared-account@very-long-company-domain.example", .needsInput, 3_725,
            "I found 41 call sites that depend on the old redirect behaviour and I need to know whether to migrate all of them in one change"),
        row("l002", .codex,
            "boosta-affiliate-landing-multilocale-redirect-service-staging-eu-west",
            "add-tests", "personal", .working, 31, "Writing tests"),
        row("l003", .claudeCode, "kohai", "a-session-name-that-keeps-going-and-going-and-going",
            "work@boosta", .done, 600, "Done"),
    ]

    /// One recognised agent and two unknown ones (one with an empty type string).
    static let unknownAgent: [SessionRowModel] = [
        row("u001", .unknown("aider"), "kohai", "tokens-pass", "personal", .needsInput, 128,
            "Which of the two palettes should I keep?"),
        row("u002", .unknown(""), "kohai", "mystery-session", nil, .working, 9,
            "Thinking"),
        row("u003", .claudeCode, "kohai", "dropdown-layout", "work@boosta", .done, 1_800,
            "Finished"),
    ]

    /// 24 sessions across 6 projects.
    static let many: [SessionRowModel] = {
        let projects = ["yheat", "kohai", "autoLoans", "web", "planet-vpn", "nitrix"]
        let statuses: [SessionStatus] = [.working, .done, .working, .needsInput, .done, .working]
        var items: [SessionRowModel] = []
        for i in 0..<24 {
            let project = projects[i % projects.count]
            let status = statuses[(i / projects.count + i) % statuses.count]
            items.append(row(
                String(format: "m%03d", i),
                i % 3 == 0 ? .codex : .claudeCode,
                project,
                "session-\(i + 1)",
                i % 2 == 0 ? "work@boosta" : "personal",
                status,
                30 + i * 97,
                "Last message from session \(i + 1)"))
        }
        return items
    }()
}
