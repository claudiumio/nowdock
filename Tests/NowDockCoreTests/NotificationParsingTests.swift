import Foundation
import Testing
@testable import NowDockCore

@Test func parseSpotifyPlayingTrack() {
    let parsed = NotificationParsing.parseSpotify(userInfo: [
        "Name": "Come As You Are",
        "Artist": "Nirvana",
        "Album": "Nevermind",
        "Track ID": "spotify:track:abc",
        "Duration": 219_000.0,
        "Playback Position": 32.5,
        "Player State": "Playing",
    ])

    #expect(parsed?.track.id == "spotify:track:abc")
    #expect(parsed?.track.title == "Come As You Are")
    #expect(parsed?.track.artist == "Nirvana")
    #expect(parsed?.track.album == "Nevermind")
    #expect(parsed?.track.duration == 219)
    #expect(parsed?.status == .playing)
    #expect(parsed?.position == 32.5)
}

@Test func parseSpotifyMissingTitleReturnsNil() {
    #expect(NotificationParsing.parseSpotify(userInfo: [
        "Artist": "Nirvana",
        "Duration": 219_000,
        "Player State": "Playing",
    ]) == nil)
    #expect(NotificationParsing.parseSpotify(userInfo: [
        "Name": "   ",
        "Artist": "Nirvana",
    ]) == nil)
}

@Test func parseSpotifyMissingKeysDefaultSafely() {
    let parsed = NotificationParsing.parseSpotify(userInfo: [
        "Name": "Lithium",
    ])

    #expect(parsed?.track.id == "")
    #expect(parsed?.track.artist == "")
    #expect(parsed?.track.album == nil)
    #expect(parsed?.track.duration == nil)
    #expect(parsed?.status == .stopped)
    #expect(parsed?.position == 0)
}

@Test func parseSpotifyUnknownStateIsStopped() {
    let parsed = NotificationParsing.parseSpotify(userInfo: [
        "Name": "Lithium",
        "Player State": "Buffering",
    ])
    #expect(parsed?.status == .stopped)
}

@Test func parseSpotifyAcceptsNSNumberAndStringNumerics() {
    let fromNumber = NotificationParsing.parseSpotify(userInfo: [
        "Name": "Polly",
        "Duration": NSNumber(value: 174_000),
        "Playback Position": NSNumber(value: 8),
        "Player State": "Paused",
    ])
    let fromString = NotificationParsing.parseSpotify(userInfo: [
        "Name": "Polly",
        "Duration": "174000",
        "Playback Position": "8.25",
        "Player State": "paused",
    ])

    #expect(fromNumber?.track.duration == 174)
    #expect(fromNumber?.position == 8)
    #expect(fromNumber?.status == .paused)
    #expect(fromString?.track.duration == 174)
    #expect(fromString?.position == 8.25)
    #expect(fromString?.status == .paused)
}

@Test func parseAppleMusicPausedTrack() {
    let parsed = NotificationParsing.parseAppleMusic(userInfo: [
        "Name": "Imagine",
        "Artist": "John Lennon",
        "Album": "Imagine",
        "Total Time": 183_000,
        "Player State": "Paused",
        "PersistentID": "0x1234",
    ])

    #expect(parsed?.track.id == "0x1234")
    #expect(parsed?.track.title == "Imagine")
    #expect(parsed?.track.artist == "John Lennon")
    #expect(parsed?.track.album == "Imagine")
    #expect(parsed?.track.duration == 183)
    #expect(parsed?.status == .paused)
    #expect(parsed?.position == 0)
}

@Test func parseAppleMusicMissingTitleReturnsNil() {
    #expect(NotificationParsing.parseAppleMusic(userInfo: [
        "Artist": "John Lennon",
        "Total Time": 183_000,
        "PersistentID": "0x1234",
    ]) == nil)
}

@Test func parseAppleMusicConvertsMillisecondsAndUnknownState() {
    let parsed = NotificationParsing.parseAppleMusic(userInfo: [
        "Name": "Imagine",
        "Total Time": "183000",
        "Player State": "Seeking",
    ])

    #expect(parsed?.track.duration == 183)
    #expect(parsed?.status == .stopped)
    #expect(parsed?.position == 0)
    #expect(parsed?.track.id == "")
}
