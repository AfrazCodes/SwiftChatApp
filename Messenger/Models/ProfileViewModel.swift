//
//  ProfileViewModel.swift
//  Messenger
//
//  Created by Afraz Siddiqui on 6/20/20.
//  Copyright © 2020 ASN GROUP LLC. All rights reserved.
//

import Foundation

enum ProfileViewModelType {
    case info, logout
}

struct ProfileViewModel {
    let viewModelType: ProfileViewModelType
    let title: String
    let handler: (() -> Void)?
}
