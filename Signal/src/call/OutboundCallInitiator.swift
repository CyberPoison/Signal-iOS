//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Creates an outbound call via either Redphone or WebRTC depending on participant preferences.
 */
@objc class OutboundCallInitiator: NSObject {
    let TAG = "[OutboundCallInitiator]"

    let callUIAdapter: CallUIAdapter
    let redphoneManager: PhoneManager
    let contactsManager: OWSContactsManager
    let contactsUpdater: ContactsUpdater

    init(redphoneManager: PhoneManager, callUIAdapter: CallUIAdapter, contactsManager: OWSContactsManager, contactsUpdater: ContactsUpdater) {
        self.redphoneManager = redphoneManager
        self.callUIAdapter = callUIAdapter

        self.contactsManager = contactsManager
        self.contactsUpdater = contactsUpdater
    }

    /**
     * |handle| is a user formatted phone number, e.g. from a system contacts entry
     */
    public func initiateCall(handle: String) -> Bool {
        Logger.info("\(TAG) in \(#function) with handle: \(handle)")
        guard let recipientId = PhoneNumber(fromUserSpecifiedText: handle).toE164() else {
            Logger.warn("\(TAG) unable to parse signalId from phone number: \(handle)")
            return false
        }

        return initiateCall(recipientId: recipientId)
    }

    /**
     * |recipientId| is a e164 formatted phone number.
     */
    public func initiateCall(recipientId: String) -> Bool {

        let localWantsWebRTC = Environment.preferences().isWebRTCEnabled()
        if !localWantsWebRTC {
            return self.initiateRedphoneCall(recipientId: recipientId)
        }

        // Since users can toggle this setting, which is only communicated during contact sync, it's easy to imagine the
        // preference getting stale. Especially as users are toggling the feature to test calls. So here, we opt for a
        // blocking network request *every* time we place a call to make sure we've got up to date preferences.
        //
        // e.g. The following would suffice if we weren't worried about stale preferences.
        // SignalRecipient *recipient = [SignalRecipient recipientWithTextSecureIdentifier:self.thread.contactIdentifier];
        self.contactsUpdater.lookupIdentifier(recipientId,
                                              success: { recipient in
                                                let remoteWantsWebRTC = recipient.supportsWebRTC
                                                Logger.debug("\(self.TAG) localWantsWebRTC: \(localWantsWebRTC), remoteWantsWebRTC: \(remoteWantsWebRTC)")

                                                if localWantsWebRTC, remoteWantsWebRTC {
                                                    _ = self.initiateWebRTCAudioCall(recipientId: recipientId)
                                                } else {
                                                    _ = self.initiateRedphoneCall(recipientId: recipientId)
                                                }
        },
                                              failure: { error in
                                                Logger.warn("\(self.TAG) looking up recipientId: \(recipientId) failed with error \(error)")
                                                // TODO fail with alert. e.g. when someone tries to call a non signal user from their contacts we should inform them.
        })

        // Since we've already dispatched async to make sure we have fresh webrtc preference data
        // we don't have a meaningful value to return here - but we're not using it anway. =/
        return true
    }

    private func initiateRedphoneCall(recipientId: String) -> Bool {
        Logger.info("\(TAG) Placing redphone call to: \(recipientId)")

        let number = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: recipientId)
        let contact = self.contactsManager.latestContact(for: number)
        assert(number != nil)
        assert(contact != nil)

        redphoneManager.initiateOutgoingCall(to: contact, atRemoteNumber: number)

        return true
    }

    private func initiateWebRTCAudioCall(recipientId: String) -> Bool {
        callUIAdapter.callBack(recipientId: recipientId)
        return true
    }

}
