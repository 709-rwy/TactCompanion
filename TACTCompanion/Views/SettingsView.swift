import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showsNotificationPermissionAlert = false
    @State private var showsLogoutConfirmation = false
    @State private var isLoggingOut = false
    let logout: () async -> Void

    var body: some View {
        Form {
            Section {
                Toggle(
                    "春期中に秋期、秋期中に春期も表示",
                    isOn: $settings.showsOtherSeason
                )
                Toggle(
                    "時間割の件数に期限切れを含める",
                    isOn: $settings.countsOverdueItems
                )
            } header: {
                Text("時間割")
            } footer: {
                Text("オフの場合、4月から9月は春1期・春2期、10月から3月は秋1期・秋2期だけを選べます。")
            }

            Section {
                Stepper(
                    "直近日: \(settings.urgentDayCount)日後まで",
                    value: $settings.urgentDayCount,
                    in: 0...14
                )

                DatePicker(
                    "色分けの基準時刻",
                    selection: boundaryTime,
                    displayedComponents: .hourAndMinute
                )

                Picker("週の区切り", selection: $settings.referenceWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(AppSettings.weekdayNames[weekday] ?? "")
                            .tag(weekday)
                    }
                }

                Stepper(
                    "第1区切り: \(settings.firstBoundaryWeek)週間先",
                    value: $settings.firstBoundaryWeek,
                    in: 1...8
                )

                Stepper(
                    "第2区切り: \(settings.secondBoundaryWeek)週間先",
                    value: $settings.secondBoundaryWeek,
                    in: max(settings.firstBoundaryWeek + 1, 2)...12
                )
            } header: {
                Text("提出期限の色分け")
            } footer: {
                Text("直近日と週の区切りは、指定した時刻を境界として判定します。")
            }

            Section {
                Toggle(
                    "橙色になった提出物を通知",
                    isOn: notificationEnabled
                )

                DatePicker(
                    "通知時刻",
                    selection: notificationTime,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!settings.deadlineNotificationsEnabled)
            } header: {
                Text("提出期限の通知")
            } footer: {
                Text("課題・小テストが橙色の期間に入った後、最初に訪れる設定時刻に一度通知します。")
            }

            Section {
                Button("ログアウト", role: .destructive) {
                    showsLogoutConfirmation = true
                }
                .disabled(isLoggingOut)
            } footer: {
                Text("ログアウトすると、保存された授業・課題・小テスト・お知らせと認証情報を消去します。")
            }
        }
        .navigationTitle("設定")
        .onChange(of: settings.firstBoundaryWeek) { _, newValue in
            if settings.secondBoundaryWeek <= newValue {
                settings.secondBoundaryWeek = newValue + 1
            }
        }
        .alert("通知を許可できませんでした", isPresented: $showsNotificationPermissionAlert) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("iPhoneの設定からTACT Companionの通知を許可してください。")
        }
        .alert(
            "TACTからログアウトしますか？",
            isPresented: $showsLogoutConfirmation
        ) {
            Button("ログアウト", role: .destructive) {
                isLoggingOut = true
                Task {
                    await logout()
                    isLoggingOut = false
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ログイン情報とキャッシュが消去されます。この操作は取り消せません。")
        }
    }

    private var boundaryTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.deadlineBoundaryHour,
                minute: settings.deadlineBoundaryMinute,
                second: 0,
                of: .now
            ) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: newValue
            )
            settings.deadlineBoundaryHour = components.hour ?? 0
            settings.deadlineBoundaryMinute = components.minute ?? 0
        }
    }

    private var notificationEnabled: Binding<Bool> {
        Binding {
            settings.deadlineNotificationsEnabled
        } set: { isEnabled in
            if !isEnabled {
                settings.deadlineNotificationsEnabled = false
                return
            }
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])) ?? false
                await MainActor.run {
                    settings.deadlineNotificationsEnabled = granted
                    showsNotificationPermissionAlert = !granted
                }
            }
        }
    }

    private var notificationTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.notificationHour,
                minute: settings.notificationMinute,
                second: 0,
                of: .now
            ) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: newValue
            )
            settings.notificationHour = components.hour ?? 9
            settings.notificationMinute = components.minute ?? 0
        }
    }
}
