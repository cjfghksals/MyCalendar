import Foundation

/// 사용자의 캘린더 목록 항목.
/// Google Calendar API의 CalendarList 항목에서 화면에 필요한 값(id, summary, backgroundColor, primary)만 담는다.
struct CalendarInfo: Codable, Identifiable, Hashable, Sendable {
    /// Google Calendar 캘린더 ID
    let id: String
    let name: String
    /// "#RRGGBB" 형식의 캘린더 기본 색상
    let colorHex: String
    /// 계정의 기본 캘린더 여부
    let isPrimary: Bool
}

extension CalendarInfo {
    /// Google Calendar 연동 전, 화면과 위젯 확인용 샘플 캘린더
    static let samples: [CalendarInfo] = [
        CalendarInfo(id: "sample-personal", name: "개인", colorHex: "#30D158", isPrimary: true),
        CalendarInfo(id: "sample-work", name: "업무", colorHex: "#0A84FF", isPrimary: false),
        CalendarInfo(id: "sample-family", name: "가족", colorHex: "#FF375F", isPrimary: false),
    ]
}
