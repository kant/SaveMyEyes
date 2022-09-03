//
//  MainViewModel.swift
//  SaveMyEyes
//
//  Created by Max Omelchenko on 03/03/20.
//  Copyright © 2020 Max Omelchenko. All rights reserved.
//

import Foundation
import ServiceManagement
import Combine

class TimerWorker {
    private var timer: Timer?
    private var timerHandler: (Timer) -> Void
    private var timerInterval: TimeInterval
    
    init(timerInterval: TimeInterval, timerHandler: @escaping (Timer) -> Void) {
        self.timerHandler = timerHandler
        self.timerInterval = timerInterval
    }
    
    func initInternalTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true, block: timerHandler)
    }
    
    func stopInternalTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func resumeInternalTimer() {
        initInternalTimer()
    }
    
    func isTimerRunning() -> Bool {
        return timer != nil
    }
    
    func toggleInternalTimer(_ shouldTimerRun: Bool) {
        if shouldTimerRun {
            resumeInternalTimer()
        } else {
            stopInternalTimer()
        }
    }
}


class MainViewModel: ObservableObject {
    @Published private(set) var isBreakTimeNow = false
    @Published private(set) var remainingMins: Int = 0
    
    @Published var shouldTimerRun = Observable<Bool>(Preferences.shouldTimerRun(Defaults.shouldTimerRun))
    @Published var isSoundEnabled = Observable<Bool>(Preferences.isSoundEnabled(Defaults.isSoundEnabled))
    @Published var workInterval = Observable<Int>(Preferences.getWorkIntervalValue(Defaults.workInterval))
    @Published var breakInterval = Observable<Int>(Preferences.getBreakIntervalValue(Defaults.breakInterval))
    @Published var launchAtLogin = Observable<Bool>(Preferences.launchAtLogin(Defaults.launchAtLogin))
    
    private var timerWorker: TimerWorker!
    private var cancellables = [AnyCancellable]()
    private var isUserInactive = false
    
    private let allowedUserInactivityInterval: TimeInterval
    private let timerInterval: TimeInterval
    
    let terminateApp: () -> ()
    
    init(
        timerInterval: TimeInterval,
        allowedUserInactivityInterval: TimeInterval,
        terminateApp: @escaping () -> ()
    ) {
        self.timerInterval = timerInterval
        self.allowedUserInactivityInterval = allowedUserInactivityInterval
        self.terminateApp = terminateApp
        
        remainingMins = isBreakTimeNow ? breakInterval.value : workInterval.value
        timerWorker = TimerWorker(timerInterval: timerInterval, timerHandler: timerHandler)
        
        cancellables = [
            shouldTimerRun.subject.sink(receiveValue: timerWorker.toggleInternalTimer),
            shouldTimerRun.subject.sink(receiveValue: Preferences.setTimerRun),
            
            workInterval.subject.sink(receiveValue: onWorkIntervalChanged),
            workInterval.subject.sink(receiveValue: Preferences.setWorkTimeIntervalValue),
            
            breakInterval.subject.sink(receiveValue: onBreakIntervalChanged),
            breakInterval.subject.sink(receiveValue: Preferences.setBreakIntervalValue),
            
            launchAtLogin.subject.sink(receiveValue: onLaunchAtLoginChanged),
            launchAtLogin.subject.sink(receiveValue: Preferences.setLaunchAtLogin),
            
            isSoundEnabled.subject.sink(receiveValue: Preferences.setSoundEnabled),
        ]
        
        if shouldTimerRun.value {
            timerWorker.resumeInternalTimer()
        }
    }
    
    /**
     Applyes changes on the work time interval value
     */
    private func onWorkIntervalChanged(_ workInterval: Int) {
        if !isBreakTimeNow {
            remainingMins = workInterval
        }
    }
    
    /**
     Applyes changes on the break time interval value
     */
    private func onBreakIntervalChanged(_ breakInterval: Int) {
        if isBreakTimeNow {
            remainingMins = breakInterval
        }
    }
    
    private func onLaunchAtLoginChanged(_ launchAtLogin: Bool) {
        SMLoginItemSetEnabled(Constants.helperBundleID as CFString, launchAtLogin)
    }
    
    /**
     Handles timer ticks
     
     Performs time management only if user was active for at least last `allowedUserInactivityInterval` seconds
     */
    public func timerHandler(timer: Timer) {
        let isUserIncativeNew = System.isUserInactive(forMinutes: Constants.allowedUserInactivityMinutes)
        if !isUserInactive && isUserIncativeNew {
            let maxIncrementValue = workInterval.value - remainingMins
            remainingMins += min(maxIncrementValue, Constants.allowedUserInactivityMinutes)
        }
        isUserInactive = isUserIncativeNew
        
        if isBreakTimeNow || !isUserInactive {
            remainingMins -= 1
            if remainingMins <= 0 {
                if isBreakTimeNow {
                    remainingMins = workInterval.value
                } else {
                    remainingMins = breakInterval.value
                }
                isBreakTimeNow.toggle()
                sendNotification()
            }
        }
    }
    
    /**
     Sends user notification
     
     Notification content depends on the `isBreakTimeNow`
     */
    public func sendNotification() {
        let notification: AppNotification
        let notificationSound = isSoundEnabled.value ? AppNotification.defaultSound : AppNotification.withoutSound
        if isBreakTimeNow {
            notification = AppNotification(title: "It's time for break".localized, subtitle: String(format: "Relax from your computer for %d min.".localized, breakInterval.value), sound: notificationSound)
        } else {
            notification = AppNotification(title: "It's time to work".localized, subtitle: "Let's continue to do amazing things!".localized, sound: notificationSound)
        }
        AppNotificationManager.sendSingle(notification)
    }
    
    public func pauseTimer() {
        shouldTimerRun.value = false
        
        // A temporary crutch to update view content:)
        // TODO: Remove it
        remainingMins -= 0
    }
    
    public func resetToDefaults() {
        isSoundEnabled.value = Defaults.isSoundEnabled
        workInterval.value = Defaults.workInterval
        breakInterval.value = Defaults.breakInterval
        shouldTimerRun.value = Defaults.shouldTimerRun
    }
}
