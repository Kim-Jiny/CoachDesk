import SwiftUI
import WidgetKit

private let appGroupId = "group.com.jiny.coachdesk"

private struct TodayClassItem: Decodable, Identifiable {
    var id: String { "\(primary)-\(secondary)-\(status)" }
    let primary: String
    let secondary: String
    let status: String
}

private struct TodayClassesEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
    let accessDeniedMessage: String
    let emptyMessage: String
    let hasAccess: Bool
    let updatedAt: String
    let items: [TodayClassItem]
}

private struct TodayClassesProvider: TimelineProvider {
    let title: String
    let subtitle: String
    let accessKey: String
    let itemsKey: String
    let updatedAtKey: String
    let accessDeniedMessage: String
    let emptyMessage: String

    func placeholder(in context: Context) -> TodayClassesEntry {
        TodayClassesEntry(
            date: Date(),
            title: title,
            subtitle: subtitle,
            accessDeniedMessage: accessDeniedMessage,
            emptyMessage: emptyMessage,
            hasAccess: true,
            updatedAt: "09:00",
            items: [
                TodayClassItem(primary: "10:00 - 11:00", secondary: "홍길동", status: "확정"),
                TodayClassItem(primary: "14:00 - 15:00", secondary: "김코치", status: "대기")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayClassesEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayClassesEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> TodayClassesEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let hasAccess = defaults?.bool(forKey: accessKey) ?? false
        let updatedAt = defaults?.string(forKey: updatedAtKey) ?? ""
        let rawItems = defaults?.string(forKey: itemsKey) ?? "[]"
        let data = rawItems.data(using: .utf8) ?? Data()
        let items = (try? JSONDecoder().decode([TodayClassItem].self, from: data)) ?? []

        return TodayClassesEntry(
            date: Date(),
            title: title,
            subtitle: subtitle,
            accessDeniedMessage: accessDeniedMessage,
            emptyMessage: emptyMessage,
            hasAccess: hasAccess,
            updatedAt: updatedAt,
            items: Array(items.prefix(4))
        )
    }
}

private struct TodayClassesWidgetView: View {
    let entry: TodayClassesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.headline.weight(.bold))
                .foregroundColor(Color(red: 0.07, green: 0.09, blue: 0.15))

            Text(entry.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if !entry.updatedAt.isEmpty {
                Text("\(entry.updatedAt) 기준")
                    .font(.caption2)
                    .foregroundColor(Color.gray)
            }

            if !entry.hasAccess {
                Spacer(minLength: 4)
                Text(entry.accessDeniedMessage)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.22, green: 0.25, blue: 0.32))
            } else if entry.items.isEmpty {
                Spacer(minLength: 4)
                Text(entry.emptyMessage)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.22, green: 0.25, blue: 0.32))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entry.items) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.primary)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color(red: 0.07, green: 0.09, blue: 0.15))
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(item.status)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(Color(red: 0.15, green: 0.39, blue: 0.92))
                                    .lineLimit(1)
                            }

                            Text(item.secondary)
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.29, green: 0.33, blue: 0.39))
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .modifier(WidgetCardBackground())
    }
}

private struct WidgetCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(Color(red: 1.0, green: 0.99, blue: 0.97), for: .widget)
        } else {
            content
                .padding()
                .background(Color(red: 1.0, green: 0.99, blue: 0.97))
        }
    }
}

struct AdminTodayClassesWidget: Widget {
    let kind = "AdminTodayClassesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TodayClassesProvider(
                title: "관리자 위젯",
                subtitle: "오늘 예약된 고객과 시간",
                accessKey: "widget_admin_has_access",
                itemsKey: "widget_admin_items",
                updatedAtKey: "widget_admin_updated_at",
                accessDeniedMessage: "관리자 계정으로 로그인하면 위젯을 사용할 수 있어요.",
                emptyMessage: "오늘 예약된 수업이 없어요."
            )
        ) { entry in
            TodayClassesWidgetView(entry: entry)
        }
        .configurationDisplayName("CoachDesk 관리자")
        .description("오늘 예약된 고객과 시간을 확인합니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct MemberTodayClassesWidget: Widget {
    let kind = "MemberTodayClassesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TodayClassesProvider(
                title: "회원 위젯",
                subtitle: "오늘 예약된 수업",
                accessKey: "widget_member_has_access",
                itemsKey: "widget_member_items",
                updatedAtKey: "widget_member_updated_at",
                accessDeniedMessage: "회원 계정으로 로그인하면 위젯을 사용할 수 있어요.",
                emptyMessage: "오늘 예약된 수업이 없어요."
            )
        ) { entry in
            TodayClassesWidgetView(entry: entry)
        }
        .configurationDisplayName("CoachDesk 회원")
        .description("오늘 예약된 수업을 확인합니다.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct TodayClassesWidgetBundle: WidgetBundle {
    var body: some Widget {
        AdminTodayClassesWidget()
        MemberTodayClassesWidget()
    }
}
