//
// Copyright © 2020 NHSX. All rights reserved.
//

import Combine
import Common
import Domain
import Foundation
import Interface
import Localization
import UIKit

struct HomeFlowViewControllerInteractor: HomeFlowViewController.Interacting {
    func save(postcode: String) -> Result<Void, DisplayableError> {
        context.savePostcode?(postcode).mapError(DisplayableError.init) ?? .success(())
    }
    
    var context: RunningAppContext
    var pasteboardCopier: PasteboardCopying
    var currentDateProvider: () -> Date
    
    func makeDiagnosisViewController() -> UIViewController? {
        WrappingViewController {
            SelfDiagnosisOrderFlowState.makeState(context: context, pasteboardCopier: pasteboardCopier)
                .map { state in
                    switch state {
                    case .selfDiagnosis(let interactor, let isolationState):
                        return SelfDiagnosisFlowViewController(interactor, initialIsolationState: isolationState)
                    case .testOrdering(let interactor):
                        return VirologyTestingFlowViewController(interactor)
                    }
                }
        }
    }
    
    func makeCheckInViewController() -> UIViewController? {
        guard let checkInContext = context.checkInContext else { return nil }
        
        let interactor = CheckInInteractor(
            _openSettings: context.openSettings,
            _process: {
                let (venueName, removeCurrentCheckIn) = try checkInContext.checkInsStore.checkIn(with: $0, currentDate: self.context.currentDateProvider())
                return CheckInDetail(venueName: venueName, removeCurrentCheckIn: removeCurrentCheckIn)
            }
        )
        
        let qrCodeScanner = checkInContext.qrCodeScanner
        
        let cameraPermissionStatePublisher = qrCodeScanner.cameraStateController.$authorizationState.map { state -> CameraPermissionState in
            switch state {
            case .notDetermined:
                return .notDetermined
            case .authorized:
                return .authorized
            case .denied, .restricted:
                return .denied
            }
        }.eraseToAnyPublisher()
        
        qrCodeScanner.reset()
        let scanner = QRScanner(
            state: qrCodeScanner.getState().map { state in
                switch state {
                case .starting:
                    return .starting
                case .failed:
                    return .failed
                case .requestingPermission:
                    return .requestingPermission
                case .running:
                    return .running
                case .scanning:
                    return .scanning
                case .processing:
                    return .processing
                case .stopped:
                    return .stopped
                }
            }.eraseToAnyPublisher(),
            startScanning: qrCodeScanner.startScanner,
            stopScanning: qrCodeScanner.stopScanner,
            layoutFinished: qrCodeScanner.changeOrientation
        )
        
        return CheckInFlowViewController(
            cameraPermissionState: cameraPermissionStatePublisher,
            scanner: scanner,
            interactor: interactor,
            currentDateProvider: currentDateProvider,
            goHomeCompletion: context.appReviewPresenter.presentReview
        )
    }
    
    func makeTestingInformationViewController() -> UIViewController? {
        WrappingViewController {
            BookATestFlowState.makeState(context: context, pasteboardCopier: pasteboardCopier)
                .map { state in
                    switch state {
                    case .bookATest(let interactor):
                        return UINavigationController(rootViewController: BookATestInfoViewController(interactor: interactor, shouldHaveCancelButton: true))
                    case .testOrdering(let interactor):
                        return VirologyTestingFlowViewController(interactor)
                    }
                }
        }
    }
    
    func makeLinkTestResultViewController() -> UIViewController? {
        let interactor = LinkTestResultInteractor(
            _submit: { testCode in
                self.context.virologyTestingManager.linkExternalTestResult(with: testCode)
                    .mapError(DisplayableError.init)
                    .eraseToAnyPublisher()
            }
        )
        return UINavigationController(rootViewController: LinkTestResultViewController(interactor: interactor))
    }
    
    func setExposureNotifcationEnabled(_ enabled: Bool) -> AnyPublisher<Void, Never> {
        context.exposureNotificationStateController.setEnabled(enabled)
    }
    
    public func scheduleReminderNotification(reminderIn: ExposureNotificationReminderIn) {
        context.exposureNotificationReminder.scheduleUserNotification(in: reminderIn.rawValue)
    }
    
    var shouldShowCheckIn: Bool {
        context.checkInContext != nil
    }
    
    func getMyDataViewModel() -> MyDataViewController.ViewModel {
        let venueHistories = context.checkInContext?.checkInsStore.load()?.map { checkIn -> VenueHistory in
            VenueHistory(
                id: checkIn.venueId,
                organisation: checkIn.venueName,
                checkedIn: checkIn.checkedIn.date,
                checkedOut: checkIn.checkedOut.date,
                delete: {
                    self.context.deleteCheckIn(checkIn.id)
                }
            )
        } ?? []
        
        let testResult = context.testInfo.currentValue.map {
            (Interface.TestResult(domainTestResult: $0.result), $0.receivedOnDay.startDate(in: .current))
        }
        
        let symptomsOnsetDate = context.symptomsDateAndEncounterDateProvider.provideSymptomsOnsetDate()
        let encounterDate = context.symptomsDateAndEncounterDateProvider.provideEncounterDate()
        
        return .init(
            postcode: context.postcodeInfo.map { $0?.postcode.value }.interfaceProperty,
            testData: testResult,
            venueHistories: venueHistories,
            symptomsOnsetDate: symptomsOnsetDate,
            encounterDate: encounterDate
        )
    }
    
    func openIsolationAdvice() {
        context.openURL(ExternalLink.isolationAdvice.url)
    }
    
    func openAdvice() {
        context.openURL(ExternalLink.generalAdvice.url)
    }
    
    func deleteAppData() {
        context.deleteAllData()
    }
    
    func updateVenueHistories(deleting venueHistory: VenueHistory) -> [VenueHistory] {
        venueHistory.delete()
        
        return context.checkInContext?.checkInsStore.load()?.map { checkIn -> VenueHistory in
            VenueHistory(
                id: checkIn.venueId,
                organisation: checkIn.venueName,
                checkedIn: checkIn.checkedIn.date,
                checkedOut: checkIn.checkedOut.date,
                delete: {
                    self.context.deleteCheckIn(checkIn.id)
                }
            )
        } ?? []
    }
    
    func openTearmsOfUseLink() {
        context.openURL(ExternalLink.ourPolicies.url)
    }
    
    func openPrivacyLink() {
        context.openURL(ExternalLink.privacy.url)
    }
    
    func openFAQ() {
        context.openURL(ExternalLink.faq.url)
    }
    
    func openAccessibilityStatementLink() {
        context.openURL(ExternalLink.accessibilityStatement.url)
    }
    
    func openHowThisAppWorksLink() {
        context.openURL(ExternalLink.howThisAppWorks.url)
    }
    
    func openWebsiteLinkfromRisklevelInfoScreen() {
        context.openURL(ExternalLink.moreInfoOnPostcodeRisk.url)
    }
    
    func openProvideFeedbackLink() {
        context.openURL(ExternalLink.provideFeedback.url)
    }
    
}
