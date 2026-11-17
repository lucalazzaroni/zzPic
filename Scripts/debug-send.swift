#!/usr/bin/env swift
// Debug builds only: sends an action to the running zzPic, e.g. `swift Scripts/debug-send.swift nextImage:`
import Foundation
for command in CommandLine.arguments.dropFirst() {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("io.github.lucalazzaroni.zzPic.debug"), object: command, userInfo: nil, deliverImmediately: true)
    Thread.sleep(forTimeInterval: 0.4)
}
