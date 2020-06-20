//
//  ConversationsModels.swift
//  Messenger
//
//  Created by Afraz Siddiqui on 6/20/20.
//  Copyright © 2020 ASN GROUP LLC. All rights reserved.
//

import Foundation

struct Conversation {
    let id: String
    let name: String
    let otherUserEmail: String
    let latestMessage: LatestMessage
}

struct LatestMessage {
    let date: String
    let text: String
    let isRead: Bool
}
