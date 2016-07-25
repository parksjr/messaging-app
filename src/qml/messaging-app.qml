/*
 * Copyright 2012-2015 Canonical Ltd.
 *
 * This file is part of messaging-app.
 *
 * messaging-app is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * messaging-app is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.2
import QtQuick.Window 2.2
import Qt.labs.settings 1.0
import Ubuntu.Components 1.3
import Ubuntu.Components.Popups 1.3
import Ubuntu.Telephony 0.1
import Ubuntu.Content 1.3
import Ubuntu.History 0.1
import "Stickers"

MainView {
    id: mainView

    property bool multiplePhoneAccounts: {
        var numAccounts = 0
        for (var i in telepathyHelper.activeAccounts) {
            if (telepathyHelper.activeAccounts[i].type == AccountEntry.PhoneAccount) {
                numAccounts++
            }
        }
        return numAccounts > 1
    }
    property QtObject account: defaultPhoneAccount()
    property bool applicationActive: Qt.application.active
    property alias mainStack: layout
    property bool dualPanel: mainStack.columns > 1
    property QtObject bottomEdge: null
    property bool composingNewMessage: bottomEdge.status === BottomEdge.Committed
    property alias inputInfo: inputInfoObject

    signal emptyStackRequested()

    activeFocusOnPress: false

    /* Multiple MessagingBottomEdge instances can be created simultaneously
       and ask to become the unique 'bottomEdge'.
       Queue the requests until only one MessagingBottomEdge instance is left.
    */
    property var bottomEdgeQueue: []
    function setBottomEdge(newBottomEdge) {
        /* If the queue is empty and no other bottom edge is set then
           set 'bottomEdge' to newBottomEdge. Otherwise insert newBottomEdge
           in the queue
        */
        if (!bottomEdge && bottomEdgeQueue.length == 0) {
            bottomEdge = newBottomEdge;
        } else {
            if (bottomEdge) {
                bottomEdgeQueue.unshift(bottomEdge)
                bottomEdge = null
            }
            bottomEdgeQueue.push(newBottomEdge)
        }
    }

    function unsetBottomEdge(oldBottomEdge) {
        /* Remove all references to oldBottomEdge (from the queue and from 'bottomEdge')
           If only one bottom edge remains in the queue then set 'bottomEdge' to it
        */
        if (bottomEdge == oldBottomEdge) {
            bottomEdge = null;
        } else {
            var index = bottomEdgeQueue.indexOf(oldBottomEdge);
            if (index != -1) {
                bottomEdgeQueue.splice(index, 1);
                if (bottomEdgeQueue.length == 1) {
                    bottomEdge = bottomEdgeQueue.pop();
                }
            }
        }
    }

    function defaultPhoneAccount() {
        // we only use the default account property if we have more
        // than one account, otherwise we use always the first one
        if (multiplePhoneAccounts) {
            return telepathyHelper.defaultMessagingAccount
        } else {
            for (var i in telepathyHelper.activeAccounts) {
                var tmpAccount = telepathyHelper.activeAccounts[i]
                if (tmpAccount.type == AccountEntry.PhoneAccount) {
                    return tmpAccount
                }
            }
        }
        return null
    }

    function showContactDetails(currentPage, contact, contactListPage, contactsModel) {
        var initialProperties = {}
        if (contactListPage) {
            initialProperties["contactListPage"] = contactListPage
        }
        if (contactsModel) {
            initialProperties["model"] = contactsModel
        }

        if (typeof(contact) == 'string') {
            initialProperties['contactId'] = contact
        } else {
            initialProperties['contact'] = contact
        }

        mainStack.addPageToCurrentColumn(currentPage,
                                         Qt.resolvedUrl("MessagingContactViewPage.qml"),
                                         initialProperties)
    }

    function addPhoneToContact(currentPage, contact, phoneNumber, contactListPage, contactsModel) {
        if (contact === "") {
            mainStack.addPageToCurrentColumn(currentPage,
                                             Qt.resolvedUrl("NewRecipientPage.qml"),
                                             { "phoneToAdd": phoneNumber })
        } else {
            var initialProperties = { "addPhoneToContact": phoneNumber }
            if (contactListPage) {
                initialProperties["contactListPage"] = contactListPage
            }
            if (contactsModel) {
                initialProperties["model"] = contactsModel
            }
            if (typeof(contact) == 'string') {
                initialProperties['contactId'] = contact
            } else {
                initialProperties['contact'] = contact
            }
            mainStack.addPageToCurrentColumn(currentPage,
                                             Qt.resolvedUrl("MessagingContactViewPage.qml"),
                                             initialProperties)
        }
    }

    onApplicationActiveChanged: {
        if (applicationActive) {
            telepathyHelper.registerChannelObserver()
        } else {
            telepathyHelper.unregisterChannelObserver()
        }
    }

    function removeThreads(threads) {
        for (var i in threads) {
            var thread = threads[i];
            var participants = [];
            for (var j in thread.participants) {
                participants.push(thread.participants[j].identifier)
            }
            // and acknowledge all messages for the threads to be removed
            chatManager.acknowledgeAllMessages(participants, thread.accountId)
        }
        // at last remove the threads
        threadModel.removeThreads(threads);
    }

    property var pendingCommitProperties
    function bottomEdgeCommit() {
        if (bottomEdge) {
            mainView.onBottomEdgeChanged.disconnect(bottomEdgeCommit);
            bottomEdge.commitWithProperties(pendingCommitProperties);
            pendingCommitProperties = null;
        }
    }

    function showBottomEdgePage(properties) {
        pendingCommitProperties = properties;
        if (bottomEdge) {
            bottomEdgeCommit();
        } else {
            mainView.onBottomEdgeChanged.connect(bottomEdgeCommit);
        }
    }

    function startImport(transfer) {
        var properties = {}
        emptyStack()
        properties["sharedAttachmentsTransfer"] = transfer
        mainView.showBottomEdgePage(properties)
    }

    Connections {
        target: telepathyHelper
        // restore default bindings if any system settings changed
        onActiveAccountsChanged: {
            for (var i in telepathyHelper.activeAccounts) {
                if (telepathyHelper.activeAccounts[i] == account) {
                    return;
                }
            }
            account = Qt.binding(defaultPhoneAccount)
        }
        onDefaultMessagingAccountChanged: account = Qt.binding(defaultPhoneAccount)
    }

    automaticOrientation: true
    implicitWidth: units.gu(90)
    implicitHeight: units.gu(71)
    anchorToKeyboard: false

    Component.onCompleted: {
        i18n.domain = "messaging-app"
        i18n.bindtextdomain("messaging-app", i18nDirectory)

        // when running in windowed mode, do not allow resizing
        view.minimumWidth  = Qt.binding( function() { return units.gu(40) } )
        view.minimumHeight = Qt.binding( function() { return units.gu(60) } )
    }

    Connections {
        target: telepathyHelper
        onSetupReady: {
            if (multiplePhoneAccounts && !telepathyHelper.defaultMessagingAccount &&
                !settings.mainViewIgnoreFirstTimeDialog && mainPage.displayedThreadIndex < 0) {
                PopupUtils.open(Qt.createComponent("Dialogs/NoDefaultSIMCardDialog.qml").createObject(mainView))
            }
        }
    }

    HistoryGroupedThreadsModel {
        id: threadModel
        type: HistoryThreadModel.EventTypeText
        sort: HistorySort {
            sortField: "lastEventTimestamp"
            sortOrder: HistorySort.DescendingOrder
        }
        groupingProperty: "participants"
        filter: HistoryFilter {}
        matchContacts: true
    }

    Settings {
        id: settings
        category: "DualSim"
        property bool messagesDontShowFileSizeWarning: false
        property bool messagesDontAsk: false
        property bool mainViewIgnoreFirstTimeDialog: false
    }

    StickerPacksModel {
        id: stickerPacksModel
    }

    StickersModel {
        id: stickersModel
    }

    Connections {
        target: ContentHub
        onImportRequested: startImport(transfer)
        onShareRequested: startImport(transfer)
    }

    signal applicationReady

    function startsWith(string, prefix) {
        return string.toLowerCase().slice(0, prefix.length) === prefix.toLowerCase();
    }

    function getContentType(filePath) {
        var contentType = application.fileMimeType(String(filePath).replace("file://",""))
        if (startsWith(contentType, "image/")) {
            return ContentType.Pictures
        } else if (startsWith(contentType, "text/vcard") ||
                   startsWith(contentType, "text/x-vcard")) {
            return ContentType.Contacts
        } else if (startsWith(contentType, "video/")) {
            return ContentType.Videos
        }
        return ContentType.Unknown
    }

    function emptyStack(showEmpty) {
        if (typeof showEmpty === 'undefined') { showEmpty = true; }
        mainView.emptyStackRequested()
        mainStack.removePages(mainPage)
        if (showEmpty) {
            showEmptyState()
        }
        mainPage.displayedThreadIndex = -1
    }

    function showEmptyState() {
        if (mainStack.columns > 1 && !application.findMessagingChild("emptyStatePage")) {
            layout.addPageToNextColumn(mainPage, emptyStatePageComponent)
        }
    }

    function startNewMessage() {
        var properties = {}
        emptyStack()
        mainView.showBottomEdgePage(properties)
    }

    function startChat(identifiers, text, accountId) {
        var properties = {}
        var participantIds = identifiers.split(";")

        if (participantIds.length === 0) {
            return;
        }

        if (mainView.account) {
            var thread = threadModel.threadForParticipants(mainView.account.accountId,
                                                           HistoryThreadModel.EventTypeText,
                                                           participantIds,
                                                           mainView.account.type == AccountEntry.PhoneAccount ? HistoryThreadModel.MatchPhoneNumber
                                                                                                              : HistoryThreadModel.MatchCaseSensitive,
                                                           false)
            if (thread.hasOwnProperty("participants")) {
                properties["participants"] = thread.participants
            }
        }

        if (!properties.hasOwnProperty("participants")) {
            var participants = []
            for (var i in participantIds) {
                var participant = {}
                participant["identifier"] = participantIds[i]
                participant["contactId"] = ""
                participant["alias"] = ""
                participant["avatar"] = ""
                participant["detailProperties"] = {}
                participants.push(participant)
            }
            properties["participants"] = participants;
        }

        properties["participantIds"] = participantIds
        properties["text"] = text
        if (typeof(accountId)!=='undefined') {
            properties["accountId"] = accountId
        }

        emptyStack(false)
        // FIXME: AdaptivePageLayout takes a really long time to create pages,
        // so we create manually and push that
        mainStack.addPageToNextColumn(mainPage, messagesWithBottomEdge, properties)
    }

    InputInfo {
        id: inputInfoObject
    }

    // WORKAROUND: Due the missing feature on SDK, they can not detect if
    // there is a mouse attached to device or not. And this will cause the
    // bootom edge component to not work correct on desktop.
    Binding {
        target:  QuickUtils
        property: "mouseAttached"
        value: inputInfo.hasMouse
    }


    Connections {
        target: UriHandler
        onOpened: {
           for (var i = 0; i < uris.length; ++i) {
               application.parseArgument(uris[i])
           }
       }
    }

    Component {
        id: messagesWithBottomEdge

        Messages {
            id: messages
            height: mainPage.height

            Component.onCompleted: mainPage._messagesPage = messages
            Loader {
                id: messagesBottomEdgeLoader
                active: mainView.dualPanel
                asynchronous: true
                /* FIXME: would be even more efficient to use setSource() to
                   delay the compilation step but a bug in Qt prevents us.
                   Ref.: https://bugreports.qt.io/browse/QTBUG-54657
                */
                sourceComponent: MessagingBottomEdge {
                    id: messagesBottomEdge
                    parent: messages
                    hint.text: ""
                    hint.height: 0
                }
            }
        }
    }

    Component {
        id: emptyStatePageComponent
        Page {
            id: emptyStatePage
            objectName: "emptyStatePage"

            Connections {
                target: layout
                onColumnsChanged: {
                    if (layout.columns == 1) {
                        if (!application.findMessagingChild("fakeItem")) {
                            emptyStack()
                        }
                    }
                }
            }

            EmptyState {
                labelVisible: false
            }

            header: PageHeader { }

            Loader {
                id: bottomEdgeLoader
                asynchronous: true
                /* FIXME: would be even more efficient to use setSource() to
                   delay the compilation step but a bug in Qt prevents us.
                   Ref.: https://bugreports.qt.io/browse/QTBUG-54657
                */
                sourceComponent: MessagingBottomEdge {
                    parent: emptyStatePage
                    hint.text: ""
                    hint.height: 0
                }
            }
        }
    }

    AdaptivePageLayout {
        id: layout
        anchors.fill: parent
        layouts: PageColumnsLayout {
            when: mainStack.width >= units.gu(90)
            PageColumn {
                maximumWidth: units.gu(50)
                minimumWidth: units.gu(40)
                preferredWidth: units.gu(40)
            }
            PageColumn {
                fillWidth: true
            }
        }
        asynchronous: false
        primaryPage: MainPage {
            id: mainPage
        }

        property bool completed: false

        onColumnsChanged: {
            // we only have things to do here in case no thread is selected
            if (layout.completed && layout.columns == 2 && !application.findMessagingChild("emptyStatePage") && !application.findMessagingChild("fakeItem")) {
                emptyStack()
            }
        }
        Component.onCompleted: {
            if (layout.columns == 2 && !application.findMessagingChild("emptyStatePage")) {
                emptyStack()
            }
            layout.completed = true;
        }
    }
}
