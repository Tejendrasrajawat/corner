import Foundation
import Testing
@testable import CornerKit

private let ist = TimeZone(identifier: "Asia/Kolkata")!

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = ist
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Wednesday 21 Oct 2026, 14:32 IST.
private let now = at(10, 21, 14, 32)

private let prefs = Preferences(primaryZone: ZoneClock(id: "Asia/Kolkata", label: "IST"),
                                secondaryZones: [ZoneClock(id: "UTC", label: "UTC")])

private func parse(_ text: String) -> Result<ParsedEntry, ParseError> {
    QuickParse.parse(text, now: now, calendar: calendar)
}

@Suite struct QuickParseTests {
    @Test func timers() {
        let cases: [(String, String, TimeInterval)] = [
            ("25m focus", "Focus", 1500),
            ("25m Deep Work", "Deep Work", 1500),
            ("1h30m", "Timer", 5400),
            ("1h30", "Timer", 5400),
            ("1h 30m deep work", "Deep work", 5400),
            ("90s tea", "Tea", 90),
            ("25 min", "Timer", 1500),
            ("2 hours", "Timer", 7200),
            ("45", "Timer", 2700),
            ("5 tea", "Tea", 300),
            ("in 2h deploy", "Deploy", 7200),
            ("1.5h", "Timer", 5400),
            ("focus for 25m", "Focus", 1500),
        ]
        for (text, label, seconds) in cases {
            #expect(parse(text) == .success(.timer(label: label, duration: seconds)), "\(text)")
        }
    }

    @Test func countdowns() {
        let cases: [(String, String, Date, RepeatRule)] = [
            ("until 6pm", "Countdown", at(10, 21, 18, 0), .none),
            ("6pm standup", "Standup", at(10, 21, 18, 0), .none),
            ("6 pm standup", "Standup", at(10, 21, 18, 0), .none),
            ("9am standup", "Standup", at(10, 22, 9, 0), .none),
            ("fri 6pm release freeze", "Release freeze", at(10, 23, 18, 0), .none),
            ("wed 10am retro", "Retro", at(10, 28, 10, 0), .none),
            ("wed 6pm demo", "Demo", at(10, 21, 18, 0), .none),
            ("tomorrow 9:30 dentist", "Dentist", at(10, 22, 9, 30), .none),
            ("24 dec 18:00 party", "Party", at(12, 24, 18, 0), .none),
            ("dec 24 party", "Party", at(12, 24, 0, 0), .none),
            ("24th dec party", "Party", at(12, 24, 0, 0), .none),
            ("24/12 party", "Party", at(12, 24, 0, 0), .none),
            ("2026-11-02 audit", "Audit", at(11, 2, 0, 0), .none),
            ("1 jan new year", "New year", at(1, 1, 0, 0, year: 2027), .none),
            ("sat weekend", "Weekend", at(10, 24, 0, 0), .none),
            ("18:30", "Countdown", at(10, 21, 18, 30), .none),
            ("noon lunch", "Lunch", at(10, 22, 12, 0), .none),
            ("release at 6pm", "Release", at(10, 21, 18, 0), .none),
            ("next mon 10am planning", "Planning", at(10, 26, 10, 0), .none),
            ("every weekday 12:00 tracker", "Tracker", at(10, 22, 12, 0), .weekdays),
            ("daily 12:00 tracker", "Tracker", at(10, 22, 12, 0), .daily),
            ("every fri 5pm demo", "Demo", at(10, 23, 17, 0), .weekly),
        ]
        for (text, label, target, rule) in cases {
            #expect(parse(text) == .success(.countdown(label: label, target: target, repeatRule: rule)), "\(text)")
        }
    }

    @Test func fillerWordsStayInLabelsWhenNoTimeFollows() {
        #expect(parse("sign up to gym 6pm") == .success(.countdown(label: "Sign up to gym", target: at(10, 21, 18, 0), repeatRule: .none)))
    }

    @Test func stopwatch() {
        #expect(parse("sw") == .success(.stopwatch))
        #expect(parse("Stopwatch") == .success(.stopwatch))
    }

    @Test func failures() {
        #expect(parse("") == .failure(.notUnderstood))
        #expect(parse("today 9am") == .failure(.inThePast))
        #expect(parse("31/02 thing") == .failure(.notUnderstood))
        #expect(parse("2025-01-01 old") == .failure(.inThePast))
    }

    @Test func descriptions() {
        func describe(_ text: String) -> String? {
            (try? parse(text).get()).map { QuickParse.describe($0, now: now, calendar: calendar) }
        }
        #expect(describe("25m focus") == "25 min timer · Focus")
        #expect(describe("90s") == "1 min 30 s timer · Timer")
        #expect(describe("6pm standup") == "Countdown to today, 18:00 · Standup")
        #expect(describe("9am standup") == "Countdown to tomorrow, 09:00 · Standup")
        #expect(describe("fri 6pm release freeze") == "Countdown to Fri 23 Oct, 18:00 · Release freeze")
        #expect(describe("every weekday 12:00 tracker") == "Every weekday at 12:00 · Tracker")
        #expect(describe("every fri 5pm demo") == "Every Friday at 17:00 · Demo")
    }

    @Test func icons() {
        #expect(QuickParse.icon(for: "Release freeze") == "paperplane")
        #expect(QuickParse.icon(for: "Standup") == "person.2")
        #expect(QuickParse.icon(for: "Dentist") == "calendar")
    }
}

@Suite struct FormatTests {
    @Test func countdowns() {
        let twoDays: TimeInterval = 2 * 86400
        let fourHours12: TimeInterval = 4 * 3600 + 720
        let elevenMin20: TimeInterval = 680
        #expect(Format.countdownLong(twoDays + 10800 + 1685) == "2d 03h 28m")
        #expect(Format.countdownLong(fourHours12) == "4h 12m")
        #expect(Format.countdownLong(elevenMin20) == "11m 20s")
        #expect(Format.countdownShort(twoDays + 14400) == "2d 4h")
        #expect(Format.countdownShort(fourHours12) == "4h 12m")
        #expect(Format.countdownShort(elevenMin20) == "11m")
        #expect(Format.countdownShort(44.2) == "45s")
    }

    @Test func timers() {
        #expect(Format.remaining(1121.2) == "18:42")
        #expect(Format.remaining(3912) == "1:05:12")
        #expect(Format.overtime(72.9) == "+01:12")
        #expect(Format.stopwatch(728) == "00:12:08")
        #expect(Format.clock(now, in: ist, seconds: false) == "14:32")
        #expect(Format.clock(now, in: TimeZone(identifier: "UTC")!, seconds: true) == "09:02:00")
    }
}

@Suite struct AppStateTests {
    @Test func timerFiresOnceThenCountsOvertime() {
        var s = AppState(settings: prefs)
        s.timers = [CTimer(label: "Focus", duration: 60, startedAt: now)]
        #expect(s.advance(to: now.addingTimeInterval(59), calendar: calendar).isEmpty)
        #expect(s.advance(to: now.addingTimeInterval(61), calendar: calendar) == [.timerDone(id: s.timers[0].id, label: "Focus")])
        #expect(s.advance(to: now.addingTimeInterval(62), calendar: calendar).isEmpty)
        let face = s.face(at: now.addingTimeInterval(72))
        #expect(face.tone == .alert)
        #expect(face.value == "+00:12")
        #expect(face.label == "Focus over")
    }

    @Test func overdueTimerFoundAfterSleepFiresSilently() {
        var s = AppState(settings: prefs)
        s.timers = [CTimer(label: "Focus", duration: 60, startedAt: now)]
        #expect(s.advance(to: now.addingTimeInterval(3600), calendar: calendar).isEmpty)
        #expect(s.timers[0].firedAt != nil)
    }

    @Test func plusFiveInOvertimeStartsOver() {
        var t = CTimer(label: "Focus", duration: 60, startedAt: now)
        let later = now.addingTimeInterval(90)
        t.extend(by: 300, at: later)
        #expect(t.remaining(at: later) == 300)
        #expect(t.firedAt == nil)
    }

    @Test func dailyCountdownRollsForward() {
        var s = AppState(settings: prefs)
        s.countdowns = [Countdown(label: "Tracker", icon: "chart.bar", target: at(10, 22, 12, 0), since: now, repeatRule: .daily)]
        let fire = at(10, 22, 12, 0).addingTimeInterval(5)
        #expect(s.advance(to: fire, calendar: calendar).count == 1)
        #expect(s.countdowns[0].target == at(10, 23, 12, 0))
        #expect(s.face(at: fire).tone == .alert)
        #expect(s.face(at: fire).value == "now")
        s.acknowledgeAlerts()
        #expect(!s.countdowns[0].isAlerting(at: fire))
        #expect(s.advance(to: fire.addingTimeInterval(60), calendar: calendar).isEmpty)
    }

    @Test func weekdayCountdownSkipsTheWeekend() {
        var s = AppState(settings: prefs)
        s.countdowns = [Countdown(label: "Standup", icon: "person.2", target: at(10, 23, 12, 0), since: now, repeatRule: .weekdays)]
        _ = s.advance(to: at(10, 23, 12, 1), calendar: calendar)
        #expect(s.countdowns[0].target == at(10, 26, 12, 0))
    }

    @Test func finishedOneOffCountdownIsRemovedAfterAnHour() {
        var s = AppState(settings: prefs)
        let c = Countdown(label: "Demo", icon: "person.2", target: now.addingTimeInterval(60), since: now)
        s.countdowns = [c]
        s.pinned = .countdown(c.id)
        #expect(s.advance(to: now.addingTimeInterval(61), calendar: calendar).count == 1)
        #expect(s.countdowns.count == 1)
        _ = s.advance(to: now.addingTimeInterval(61 + 3601), calendar: calendar)
        #expect(s.countdowns.isEmpty)
        #expect(s.pinned == nil)
    }

    @Test func closingAOneOffCountdownRemovesIt() {
        var s = AppState(settings: prefs)
        let c = Countdown(label: "Demo", icon: "person.2", target: now.addingTimeInterval(3600), since: now)
        s.countdowns = [c]
        s.pinned = .countdown(c.id)
        s.closeCountdown(c.id, at: now, calendar: calendar)
        #expect(s.countdowns.isEmpty)
        #expect(s.pinned == nil)
        #expect(s.advance(to: now.addingTimeInterval(3601), calendar: calendar).isEmpty)
    }

    @Test func closingARepeatingCountdownSkipsToTheNextOne() {
        var s = AppState(settings: prefs)
        s.countdowns = [Countdown(label: "Tracker", icon: "chart.bar", target: at(10, 22, 12, 0), since: now, repeatRule: .daily)]
        let id = s.countdowns[0].id
        s.closeCountdown(id, at: now, calendar: calendar)
        #expect(s.countdowns[0].target == at(10, 23, 12, 0))
        #expect(s.countdowns[0].since == now)
        // The skipped occurrence passes quietly; the next one still fires.
        #expect(s.advance(to: at(10, 22, 12, 1), calendar: calendar).isEmpty)
        #expect(s.advance(to: at(10, 23, 12, 1), calendar: calendar).count == 1)
    }

    @Test func closingARepeatingCountdownThatsGoingOffOnlyStopsTheAlert() {
        var s = AppState(settings: prefs)
        s.countdowns = [Countdown(label: "Tracker", icon: "chart.bar", target: at(10, 22, 12, 0), since: now, repeatRule: .daily)]
        let fire = at(10, 22, 12, 0).addingTimeInterval(5)
        _ = s.advance(to: fire, calendar: calendar)
        s.closeCountdown(s.countdowns[0].id, at: fire, calendar: calendar)
        #expect(!s.countdowns[0].isAlerting(at: fire))
        #expect(s.countdowns[0].target == at(10, 23, 12, 0))
    }

    @Test func cornerPriority() {
        var s = AppState(settings: prefs)
        let idle = s.face(at: now)
        #expect(idle.ref == .clock)
        #expect(idle.value == "14:32")
        #expect(idle.label == "IST")
        #expect(abs(idle.progress - 272.0 / 540.0) < 0.001)

        let soon = Countdown(label: "Standup", icon: "person.2", target: now.addingTimeInterval(600), since: now)
        let later = Countdown(label: "Release", icon: "paperplane", target: now.addingTimeInterval(86400), since: now)
        s.countdowns = [later, soon]
        #expect(s.face(at: now).ref == .countdown(soon.id))
        #expect(s.face(at: now).tone == .warning)
        #expect(s.face(at: now).value == "10m")

        let t = CTimer(label: "Focus", duration: 1500, startedAt: now)
        s.timers = [t]
        #expect(s.face(at: now).ref == .timer(t.id))
        #expect(s.face(at: now).value == "25:00")

        s.pinned = .countdown(later.id)
        #expect(s.face(at: now).ref == .countdown(later.id))
        #expect(s.face(at: now, manual: .clock).ref == .clock)

        // Something going off beats a pin.
        #expect(s.face(at: now.addingTimeInterval(1600)).ref == .timer(t.id))
        #expect(s.face(at: now.addingTimeInterval(1600)).tone == .alert)
    }

    @Test func cycleOrder() {
        var s = AppState(settings: prefs)
        let t = CTimer(label: "Focus", duration: 1500, startedAt: now)
        let late = Countdown(label: "B", icon: "calendar", target: now.addingTimeInterval(900), since: now)
        let early = Countdown(label: "A", icon: "calendar", target: now.addingTimeInterval(300), since: now)
        s.timers = [t]
        s.countdowns = [late, early]
        #expect(s.cycle(at: now) == [.timer(t.id), .countdown(early.id), .countdown(late.id), .clock])
        s.meetings = [Meeting(id: "m", title: "Standup", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(5400))]
        #expect(s.cycle(at: now) == [.timer(t.id), .meeting, .countdown(early.id), .countdown(late.id), .clock])
    }

    @Test func menuBarText() {
        var s = AppState(settings: prefs)
        #expect(s.menuBarText(at: now) == nil)
        s.timers = [CTimer(label: "Focus", duration: 1500, startedAt: now)]
        #expect(s.menuBarText(at: now.addingTimeInterval(378)) == "Focus 18:42")
        #expect(s.menuBarText(at: now.addingTimeInterval(1572)) == "Focus +01:12")
    }

    @Test func oldStateFilesStillDecode() throws {
        let json = #"{"timers":[],"settings":{"primaryZone":{"id":"Asia/Kolkata","label":"IST"}}}"#
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        #expect(s.settings.cornerSize == .medium)
        #expect(s.settings.autoCollapseSeconds == 10)
        #expect(!s.settings.tuckAway)
        #expect(!s.settings.hidden)
        #expect(s.settings.theme == .system)
        #expect(s.countdowns.isEmpty)
    }

    @Test func unknownThemeFallsBackInsteadOfLosingState() throws {
        let json = #"{"todos":[{"id":"6F1E8A3C-3B9B-4C5E-9F1A-2D3C4B5A6E7F","text":"keep me","createdAt":0}],"settings":{"primaryZone":{"id":"UTC","label":"UTC"},"theme":"neon"}}"#
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        #expect(s.settings.theme == .system)
        #expect(s.todos.map(\.text) == ["keep me"])
    }
}

@Suite struct MeetingTests {
    private func standup(startingIn seconds: TimeInterval, link: URL? = nil) -> Meeting {
        Meeting(id: "standup@1", title: "Standup", start: now.addingTimeInterval(seconds),
                end: now.addingTimeInterval(seconds + 1800), calendarTitle: "Work", joinURL: link)
    }

    @Test func findsJoinLinks() {
        #expect(JoinLink.find(in: [nil, "https://us02web.zoom.us/j/123456?pwd=abc", nil])
            == URL(string: "https://us02web.zoom.us/j/123456?pwd=abc"))
        #expect(JoinLink.find(in: ["Room 4", "Join with Google Meet: https://meet.google.com/abc-defg-hij."])
            == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(JoinLink.find(in: ["Click <https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0> to join"])
            == URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0"))
        // An agenda doc isn't a call link, and a lookalike host doesn't count.
        #expect(JoinLink.find(in: ["https://docs.google.com/document/d/1", "https://notzoom.us/j/1"]) == nil)
        #expect(JoinLink.find(in: ["https://docs.google.com/d/1 then https://meet.google.com/x-y-z"])
            == URL(string: "https://meet.google.com/x-y-z"))
    }

    @Test func soonMeetingTakesTheCornerUnlessACountdownIsSooner() {
        var s = AppState(settings: prefs)
        s.meetings = [standup(startingIn: 600)]
        let face = s.face(at: now)
        #expect(face.ref == .meeting)
        #expect(face.value == "10m")
        #expect(face.label == "Standup")
        #expect(face.tone == .warning)

        let lunch = Countdown(label: "Lunch", icon: "fork.knife", target: now.addingTimeInterval(300), since: now)
        s.countdowns = [lunch]
        #expect(s.face(at: now).ref == .countdown(lunch.id))

        // An hour away it waits its turn, but a pin shows it anyway.
        s.countdowns = []
        s.meetings = [standup(startingIn: 3600)]
        #expect(s.face(at: now).ref == .clock)
        s.pinned = .meeting
        #expect(s.face(at: now).value == "1h 0m")
        #expect(s.face(at: now).tone == .normal)
    }

    @Test func startedMeetingIsRedUntilYouOpenTheCard() {
        var s = AppState(settings: prefs)
        s.meetings = [standup(startingIn: -90)]
        #expect(s.face(at: now).tone == .alert)
        #expect(s.face(at: now).value == "+1m")
        #expect(s.menuBarText(at: now) == "Standup now")
        s.acknowledgeAlerts(at: now)
        #expect(s.face(at: now).ref == .clock)
        s.pinned = .meeting
        #expect(s.face(at: now).label == "Standup ends")
        #expect(s.face(at: now).tone == .muted)
    }

    @Test func alertsOnceAtTheLeadTime() {
        var s = AppState(settings: prefs)
        let m = standup(startingIn: 120)
        s.meetings = [m]
        #expect(s.advance(to: now, calendar: calendar).isEmpty)
        #expect(s.advance(to: now.addingTimeInterval(61), calendar: calendar) == [.meetingSoon(m)])
        #expect(s.advance(to: now.addingTimeInterval(62), calendar: calendar).isEmpty)
        // A refetch that briefly drops the meeting doesn't make it alert again.
        s.meetings = []
        _ = s.advance(to: now.addingTimeInterval(63), calendar: calendar)
        s.meetings = [m]
        #expect(s.advance(to: now.addingTimeInterval(64), calendar: calendar).isEmpty)
    }

    @Test func meetingAlreadyUnderWayIsNotAnnounced() {
        var s = AppState(settings: prefs)
        s.meetings = [standup(startingIn: -600)]
        #expect(s.advance(to: now, calendar: calendar).isEmpty)
    }

    @Test func alertsCanBeTurnedOff() {
        var s = AppState(settings: prefs)
        s.settings.meetingAlertMinutes = -1
        s.meetings = [standup(startingIn: 30)]
        #expect(s.advance(to: now.addingTimeInterval(31), calendar: calendar).isEmpty)
    }

    @Test func menuBarShowsAMeetingFiveMinutesOut() {
        var s = AppState(settings: prefs)
        s.meetings = [standup(startingIn: 400)]
        #expect(s.menuBarText(at: now) == nil)
        s.meetings = [standup(startingIn: 240)]
        #expect(s.menuBarText(at: now) == "Standup 4m")
    }

    @Test func meetingsAreNeverSaved() throws {
        var s = AppState(settings: prefs)
        s.meetings = [standup(startingIn: 60)]
        s.meetingsAlerted = ["standup@1": now]
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s))
        #expect(decoded.meetings.isEmpty)
        #expect(decoded.meetingsAlerted.isEmpty)
        #expect(decoded.settings.showMeetings)
        #expect(decoded.settings.meetingAlertMinutes == 1)
    }
}

@Suite struct TodoTests {
    @Test func plainTextBecomesATodo() {
        #expect(parse("buy milk") == .success(.todo("buy milk")))
        #expect(parse("  Review PR 1390  ") == .success(.todo("Review PR 1390")))
        #expect(parse("finish report today") == .success(.todo("finish report today")))
        // A prefix forces a to-do when the text would otherwise read as a timer.
        #expect(parse("5 things to fix") == .success(.timer(label: "Things to fix", duration: 300)))
        #expect(parse("todo 5 things to fix") == .success(.todo("5 things to fix")))
        #expect(parse("note: call bank at 6pm") == .success(.todo("call bank at 6pm")))
        #expect(parse("- ship it") == .success(.todo("ship it")))
        // Anything with a time is still a timer or countdown.
        #expect(parse("call bank at 6pm") == .success(.countdown(label: "Call bank", target: at(10, 21, 18, 0), repeatRule: .none)))
        #expect(QuickParse.describe(.todo("buy milk"), now: now, calendar: calendar) == "To-do · buy milk")
    }

    @Test func cardListsOpenThenDone() {
        var s = AppState(settings: prefs)
        s.addTodo("a", at: now)
        s.addTodo("b", at: now.addingTimeInterval(1))
        s.addTodo("c", at: now.addingTimeInterval(2))
        let (a, b, c) = (s.todos[0].id, s.todos[1].id, s.todos[2].id)
        s.toggleTodo(b, at: now.addingTimeInterval(10))
        s.toggleTodo(a, at: now.addingTimeInterval(20))
        #expect(s.cardTodos.map(\.text) == ["c", "b", "a"])
        s.toggleTodo(b, at: now.addingTimeInterval(30))
        #expect(s.cardTodos.map(\.text) == ["b", "c", "a"])
        _ = c
    }

    @Test func movingSkipsDoneItems() {
        var s = AppState(settings: prefs)
        for (i, t) in ["a", "b", "c"].enumerated() { s.addTodo(t, at: now.addingTimeInterval(Double(i))) }
        s.toggleTodo(s.todos[1].id, at: now)
        s.moveTodo(s.todos[2].id, by: -1)
        #expect(s.cardTodos.map(\.text) == ["c", "a", "b"])
        s.moveTodo(s.cardTodos[0].id, by: -1)
        #expect(s.cardTodos.map(\.text) == ["c", "a", "b"])
    }

    @Test func clearingKeepsHistoryAndUntickingBringsItBack() {
        var s = AppState(settings: prefs)
        s.addTodo("ship it", at: now)
        let id = s.todos[0].id
        s.toggleTodo(id, at: now)
        s.clearDoneTodos(at: now)
        #expect(s.cardTodos.isEmpty)
        #expect(s.todos.count == 1)
        #expect(s.todoHistory(filter: .done, search: "", calendar: calendar).first?.todos.map(\.id) == [id])
        s.toggleTodo(id, at: now)
        #expect(s.cardTodos.map(\.id) == [id])
    }

    @Test func emptyEditDeletes() {
        var s = AppState(settings: prefs)
        s.addTodo("typo", at: now)
        s.editTodo(s.todos[0].id, text: "  fixed  ")
        #expect(s.todos[0].text == "fixed")
        s.editTodo(s.todos[0].id, text: " ")
        #expect(s.todos.isEmpty)
    }

    @Test func doneOnAnEarlierDayLeavesTheCardNextMorning() {
        var s = AppState(settings: prefs)
        s.addTodo("yesterday's", at: now)
        s.addTodo("still open", at: now)
        s.toggleTodo(s.todos[0].id, at: now)
        _ = s.advance(to: now.addingTimeInterval(3600), calendar: calendar)
        #expect(s.cardTodos.count == 2)
        _ = s.advance(to: at(10, 22, 9, 0), calendar: calendar)
        #expect(s.cardTodos.map(\.text) == ["still open"])
        #expect(s.todos.count == 2)
    }

    @Test func historyGroupsByDayNewestFirst() {
        var s = AppState(settings: prefs)
        s.addTodo("old one", at: at(10, 19, 10, 0))
        s.addTodo("Review deploy", at: now)
        s.addTodo("buy milk", at: now.addingTimeInterval(60))
        s.toggleTodo(s.todos[2].id, at: now)
        let all = s.todoHistory(filter: .all, search: "", calendar: calendar)
        #expect(all.map(\.day) == [at(10, 21, 0, 0), at(10, 19, 0, 0)])
        #expect(all[0].todos.map(\.text) == ["Review deploy", "buy milk"])
        #expect(s.todoHistory(filter: .open, search: "", calendar: calendar).flatMap(\.todos).map(\.text) == ["Review deploy", "old one"])
        #expect(s.todoHistory(filter: .all, search: "DEPLOY", calendar: calendar).flatMap(\.todos).map(\.text) == ["Review deploy"])
    }

    @Test func todosAreSaved() throws {
        var s = AppState(settings: prefs)
        s.addTodo("keep me", at: now)
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s))
        #expect(decoded.todos.map(\.text) == ["keep me"])
    }
}

@Suite struct ClockStyleTests {
    @Test func twelveHourFormatting() {
        let afternoon = at(10, 21, 14, 32)
        let justAfterMidnight = at(10, 21, 0, 5)
        let noon = at(10, 21, 12, 0)
        #expect(Format.clock(afternoon, in: ist, seconds: false, style: .h12) == "2:32")
        #expect(Format.clock(afternoon, in: ist, seconds: true, style: .h12) == "2:32:00")
        #expect(Format.clock(justAfterMidnight, in: ist, seconds: false, style: .h12) == "12:05")
        #expect(Format.time(afternoon, in: ist, style: .h12) == "2:32 PM")
        #expect(Format.time(justAfterMidnight, in: ist, style: .h12) == "12:05 AM")
        #expect(Format.time(noon, in: ist, style: .h12) == "12:00 PM")
        #expect(Format.time(afternoon, in: ist, style: .h24) == "14:32")
    }

    @Test func ranges() {
        #expect(Format.timeRange(at(10, 21, 19, 48), at(10, 21, 20, 18), in: ist, style: .h12) == "7:48–8:18 PM")
        #expect(Format.timeRange(at(10, 21, 11, 30), at(10, 21, 12, 30), in: ist, style: .h12) == "11:30 AM–12:30 PM")
        #expect(Format.timeRange(at(10, 21, 19, 48), at(10, 21, 20, 18), in: ist, style: .h24) == "19:48–20:18")
    }

    @Test func workdayHours() {
        #expect(Format.minutesOfDay(600, style: .h12) == "10:00 AM")
        #expect(Format.minutesOfDay(1140, style: .h12) == "7:00 PM")
        #expect(Format.minutesOfDay(0, style: .h12) == "12:00 AM")
        #expect(Format.minutesOfDay(720, style: .h12) == "12:00 PM")
        #expect(Format.minutesOfDay(1140) == "19:00")
    }

    @Test func cornerClockPutsAMPMOnTheLabel() {
        var s = AppState(settings: prefs)
        s.settings.clockStyle = .h12
        #expect(s.face(at: now).value == "2:32")
        #expect(s.face(at: now).label == "PM · IST")
    }

    @Test func quickAddPreviewFollowsTheStyle() {
        let entry = try! parse("6pm standup").get()
        #expect(QuickParse.describe(entry, now: now, calendar: calendar, style: .h12) == "Countdown to today, 6:00 PM · Standup")
        #expect(QuickParse.describe(entry, now: now, calendar: calendar) == "Countdown to today, 18:00 · Standup")
    }

    @Test func oldTuckSettingBecomesTuckedRestStyle() throws {
        let json = #"{"settings":{"primaryZone":{"id":"UTC","label":"UTC"},"tuckAway":true}}"#
        let s = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        #expect(s.settings.restStyle == .tucked)
        #expect(s.settings.tuckAway)
        #expect(s.settings.clockStyle == .h24)
        let fresh = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"primaryZone":{"id":"UTC","label":"UTC"},"restStyle":"mini","clockStyle":"h12"}}"#.utf8))
        #expect(fresh.settings.restStyle == .mini)
        #expect(fresh.settings.clockStyle == .h12)
    }
}

@Suite struct ClaudeTests {
    private func event(_ kind: ClaudeEvent.Kind, _ id: String = "s1", cwd: String = "/Users/me/Desktop/Media",
                       prompt: String? = nil, message: String? = nil, type: String? = nil) -> ClaudeEvent {
        ClaudeEvent(kind: kind, sessionID: id, cwd: cwd, prompt: prompt, message: message, notificationType: type)
    }

    private func claudeState() -> AppState {
        var s = AppState(settings: prefs)
        s.settings.showClaude = true
        return s
    }

    @Test func hiddenWhileSwitchedOff() {
        var s = AppState(settings: prefs)
        _ = s.apply(event(.promptSubmitted), at: now)
        #expect(s.face(at: now).ref == .clock)
        #expect(s.menuBarText(at: now) == nil)
        #expect(!s.cycle(at: now).contains(.claude("s1")))
    }

    @Test func parsesInboxLinesWithTimestamps() {
        let parsed = ClaudeEvent.parseInboxLine(#"1793030000 {"session_id":"abc","cwd":"/x/Corner","hook_event_name":"Stop","last_assistant_message":"Built and installed.\nAll 35 tests pass."}"#)
        #expect(parsed?.time == Date(timeIntervalSince1970: 1793030000))
        #expect(parsed?.event.kind == .stopped)
        #expect(parsed?.event.lastMessage == "Built and installed.\nAll 35 tests pass.")
        #expect(ClaudeEvent.parseInboxLine("1793030000 garbage") == nil)
    }

    @Test func doneKeepsTheStartOfClaudesReply() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted), at: now)
        _ = s.apply(ClaudeEvent(kind: .stopped, sessionID: "s1", lastMessage: "Fixed the sizing bug.\nThe card now resizes."), at: now.addingTimeInterval(40))
        #expect(s.claudeSessions[0].reply == "Fixed the sizing bug.")
    }

    @Test func parsesHookJSON() {
        let line = #"{"session_id":"abc","transcript_path":"/t.jsonl","cwd":"/Users/me/Desktop/Corner","hook_event_name":"UserPromptSubmit","prompt":"make corner smallest on hover"}"#
        let e = ClaudeEvent.parse(line)
        #expect(e == ClaudeEvent(kind: .promptSubmitted, sessionID: "abc", cwd: "/Users/me/Desktop/Corner", prompt: "make corner smallest on hover"))
        #expect(ClaudeEvent.parse("") == nil)
        #expect(ClaudeEvent.parse("{not json") == nil)
        #expect(ClaudeEvent.parse(#"{"session_id":"abc","hook_event_name":"PreCompact"}"#) == nil)
    }

    @Test func workingNeedsYouWorkingDone() {
        var s = claudeState()
        #expect(s.apply(event(.promptSubmitted, prompt: "why are these messages\nin the DLQ?"), at: now) == nil)
        #expect(s.claudeSessions[0].status == .working)
        #expect(s.claudeSessions[0].project == "Media")
        #expect(s.claudeSessions[0].prompt == "why are these messages")
        #expect(s.face(at: now.addingTimeInterval(252)).value == "04:12")
        #expect(s.face(at: now).tone == .working)
        #expect(s.face(at: now).indeterminate)

        let needs = s.apply(event(.notification, message: "Claude needs your permission to use Bash", type: "permission_prompt"), at: now.addingTimeInterval(300))
        #expect(needs == .claudeNeedsYou(s.claudeSessions[0]))
        #expect(s.face(at: now.addingTimeInterval(301)).label == "Needs you")
        #expect(s.menuBarText(at: now.addingTimeInterval(301)) == "Claude needs you")
        // A second reminder doesn't alert again.
        #expect(s.apply(event(.notification, message: "still waiting", type: "permission_prompt"), at: now.addingTimeInterval(320)) == nil)

        _ = s.apply(event(.toolFinished), at: now.addingTimeInterval(330))
        #expect(s.claudeSessions[0].status == .working)

        let done = s.apply(event(.stopped), at: now.addingTimeInterval(423))
        #expect(done == .claudeDone(s.claudeSessions[0]))
        let face = s.face(at: now.addingTimeInterval(430))
        #expect(face.value == "Done")
        #expect(face.label == "Media · 7m")
        #expect(face.tone == .success)
    }

    @Test func quickTurnsFinishQuietly() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted), at: now)
        #expect(s.apply(event(.stopped), at: now.addingTimeInterval(8)) == nil)
        #expect(s.claudeSessions[0].status == .done)
    }

    @Test func idleReminderAfterDoneChangesNothing() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted), at: now)
        _ = s.apply(event(.stopped), at: now.addingTimeInterval(60))
        #expect(s.apply(event(.notification, message: "Claude is waiting for your input", type: "idle_prompt"), at: now.addingTimeInterval(120)) == nil)
        #expect(s.claudeSessions[0].status == .done)
    }

    @Test func unrelatedNotificationTypesAreIgnored() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted), at: now)
        #expect(s.apply(event(.notification, message: "Signed in", type: "auth_success"), at: now) == nil)
        #expect(s.claudeSessions[0].status == .working)
    }

    @Test func openingTheCardRetiresDoneButNotNeedsYou() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted, "a"), at: now)
        _ = s.apply(event(.stopped, "a"), at: now.addingTimeInterval(60))
        _ = s.apply(event(.promptSubmitted, "b", cwd: "/x/Corner"), at: now)
        _ = s.apply(event(.notification, "b", cwd: "/x/Corner", type: "permission_prompt"), at: now.addingTimeInterval(30))
        #expect(s.face(at: now.addingTimeInterval(61)).label == "Needs you")
        s.acknowledgeAlerts(at: now.addingTimeInterval(62))
        #expect(s.face(at: now.addingTimeInterval(63)).label == "Needs you")
        _ = s.apply(event(.toolFinished, "b", cwd: "/x/Corner"), at: now.addingTimeInterval(64))
        // "a" was seen, so the working session takes the corner instead of the done one.
        #expect(s.face(at: now.addingTimeInterval(65)).label == "Corner")
        #expect(s.claudeCardSessions.map(\.id) == ["b", "a"])
    }

    @Test func sessionsEndAndExpire() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted, "a"), at: now)
        _ = s.apply(event(.promptSubmitted, "b"), at: now)
        _ = s.apply(event(.sessionEnded, "a"), at: now)
        #expect(s.claudeSessions.map(\.id) == ["b"])
        _ = s.apply(event(.stopped, "b"), at: now.addingTimeInterval(10))
        _ = s.advance(to: now.addingTimeInterval(10 + 31 * 60), calendar: calendar)
        #expect(s.claudeSessions.isEmpty)
        _ = s.apply(event(.promptSubmitted, "c"), at: now)
        _ = s.advance(to: now.addingTimeInterval(13 * 3600), calendar: calendar)
        #expect(s.claudeSessions.isEmpty)
    }

    @Test func runningTimerOutranksClaudeWorkingInTheCornerAndMenuBar() {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted), at: now)
        let t = CTimer(label: "Focus", duration: 1500, startedAt: now)
        s.timers = [t]
        #expect(s.face(at: now).ref == .timer(t.id))
        #expect(s.menuBarText(at: now) == "Focus 25:00")
        s.timers = []
        #expect(s.menuBarText(at: now.addingTimeInterval(65)) == "Claude 01:05")
    }

    @Test func sessionsAreSaved() throws {
        var s = claudeState()
        _ = s.apply(event(.promptSubmitted, prompt: "hello"), at: now)
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s))
        #expect(decoded.claudeSessions == s.claudeSessions)
    }
}

@Suite struct ClaudeHooksTests {
    @Test func addsAlongsideExistingSettingsAndRemovesCleanly() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let added = ClaudeHooks.adding(to: existing)
        #expect(ClaudeHooks.isInstalled(in: added))
        #expect(added["model"] as? String == "opus")
        let hooks = added["hooks"] as! [String: Any]
        #expect((hooks["Stop"] as! [[String: Any]]).count == 2)
        #expect(Set(hooks.keys) == Set(ClaudeHooks.events))
        let post = (hooks["PostToolUse"] as! [[String: Any]])[0]
        #expect(post["matcher"] as? String == "*")

        // Adding twice doesn't duplicate.
        let twice = ClaudeHooks.adding(to: added)
        #expect(((twice["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]).count == 2)

        let removed = ClaudeHooks.removing(from: twice)
        #expect(!ClaudeHooks.isInstalled(in: removed))
        let left = removed["hooks"] as! [String: Any]
        #expect(Array(left.keys) == ["Stop"])
        #expect(((left["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["command"] as? String == "say done")
    }

    @Test func removingFromSettingsWithoutHooksIsANoOp() {
        let removed = ClaudeHooks.removing(from: ["theme": "dark"])
        #expect(removed["theme"] as? String == "dark")
        #expect(removed["hooks"] == nil)
        #expect(ClaudeHooks.removing(from: ClaudeHooks.adding(to: [:]))["hooks"] == nil)
    }
}

@Suite struct ClaudeWaitingTextTests {
    @Test func shortensPermissionMessages() {
        var s = ClaudeSession(id: "x", cwd: "/a", status: .needsYou, at: now)
        #expect(s.waitingFor == "Waiting for you")
        s.detail = "Claude needs your permission to use Bash"
        #expect(s.waitingFor == "Permission for Bash")
        s.detail = "Claude is waiting for your input"
        #expect(s.waitingFor == "Waiting for your reply")
        s.detail = "Something else"
        #expect(s.waitingFor == "Something else")
    }
}

@Suite struct ClaudeDesktopTests {
    private func record(_ fields: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: fields)
    }

    @Test func findsTheChatRunningASession() {
        let data = record(["sessionId": "local_abc", "cliSessionId": "s1", "title": "Mac top-left widget proposal"])
        #expect(ClaudeDesktop.chat(inRecord: data, session: "s1") == ClaudeChat(id: "local_abc", title: "Mac top-left widget proposal"))
        #expect(ClaudeDesktop.chat(inRecord: data, session: "s2") == nil)
        // After /clear the chat runs a new session but still answers to the old one.
        let cleared = record(["sessionId": "local_abc", "cliSessionId": "s3", "preClearCliSessionId": "s1"])
        #expect(ClaudeDesktop.chat(inRecord: cleared, session: "s1")?.id == "local_abc")
    }

    @Test func unnamedChatsHaveNoTitle() {
        let fresh = record(["sessionId": "local_abc", "cliSessionId": "s1", "title": "New session"])
        #expect(ClaudeDesktop.chat(inRecord: fresh, session: "s1")?.title == nil)
        #expect(ClaudeDesktop.chat(inRecord: record(["sessionId": "abc", "cliSessionId": "s1"]), session: "s1") == nil)
        #expect(ClaudeDesktop.chat(inRecord: Data("not json".utf8), session: "s1") == nil)
    }

    @Test func linksOpenTheChatOrResumeATerminalSession() {
        let uuid = "1bca5d1b-4055-4637-a80f-53608a5e44e9"
        #expect(ClaudeDesktop.link(session: uuid, chat: "local_ed328c1c")?.absoluteString == "claude://code/continue?session=local_ed328c1c")
        #expect(ClaudeDesktop.link(session: uuid, chat: nil)?.absoluteString == "claude://resume?session=\(uuid)")
        #expect(ClaudeDesktop.link(session: "not-a-uuid", chat: nil) == nil)
    }

    @Test func titlesNameTheSessionInTheCardAndCorner() {
        var s = AppState(settings: prefs)
        s.settings.showClaude = true
        _ = s.apply(ClaudeEvent(kind: .promptSubmitted, sessionID: "s1", cwd: "/Users/me/Desktop/inventory-apis"), at: now)
        #expect(s.claudeSessions[0].name == "inventory-apis")
        #expect(s.face(at: now).label == "inventory-apis")
        let chats = ["s1": ClaudeChat(id: "local_a", title: "Fix the DLQ")]
        let first = s.setClaudeChats(chats)
        let again = s.setClaudeChats(chats)
        #expect(first && !again)
        #expect(s.claudeSessions[0].chatID == "local_a")
        #expect(s.face(at: now).label == "Fix the DLQ")
    }
}
