//
//  SignInViewModel.swift
//  ...
//
//  Created by aaaus on 25.03.2023.
//  Copyright © 2023 ... All rights reserved.
//

import Foundation
import Combine
import AuthenticationServices

class SignInViewModel {
    @Published private(set) var state: State = .initial
    @Published private(set) var signInOptions: SignInOptions
    
    private var cancellables = Set<AnyCancellable>()
    private let signInHandler: SignInHandler
    private let socialSignInHandler: SocialSignInHandler
    
    init(signInOptions: SignInOptions) {
        self.signInOptions = signInOptions
        self.signInHandler = SignInHandler()
        self.socialSignInHandler = SocialSignInHandler()
    }
    
    func signIn(with socialProvider: SocialSignInHandler.SocialProvider,
                on viewController: UIViewController) {
        
        socialSignInHandler.signIn(with: socialProvider, on: viewController)
            .sink { [weak self] (completion) in
                if let error = completion.error {
                    self?.state = .failure(error: error)
                }
            } receiveValue: { [weak self] (userInfo) in
                self?.validateSocialToken(using: userInfo)
            }
            .store(in: &cancellables)
    }
    
    func requestSMS(for phone: String) {
        self.state = .loading
        RequestSMS(phone: phone).execute()
            .sink { [weak self] (completion) in
                if let error = completion.error {
                    self?.state = .failure(error: error)
                }
                self?.trackPhoneRestore(phone: phone, error: completion.error)
            } receiveValue: { [weak self] (response) in
                self?.state = .finished(code: response.code, phone: phone, registered: response.registered)
            }
            .store(in: &cancellables)
    }
    
    private func handleRegisteredUser(with token: String, socialID: String) {
        signInHandler
            .signIn(using: token, loginType: .social(socialId: socialID))
            .sink(receiveCompletion: { [weak self] (completion) in
                switch completion {
                case .finished:
                    self?.state = .userIsRegistered
                case .failure(let error):
                    self?.state = .failure(error: error)
                }
            }, receiveValue: { _ in})
            .store(in: &cancellables)
    }
    
    private func validateSocialToken(using userInfo: UserInfo) {
        guard let socialId = userInfo.id
        else { return }
        
        self.state = .loading
        ValidateSocialID(socialId: socialId)
            .execute()
            .sink { [weak self] (completion) in
                if let error = completion.error {
                    self?.state = .failure(error: error)
                }
            } receiveValue: { [weak self] (response) in
                if response.registered {
                    self?.handleRegisteredUser(with: response.token, socialID: socialId)
                } else {
                    self?.state = .userNeedsRegistration(token: response.token, userInfo: userInfo)
                }
            }
            .store(in: &cancellables)
    }
    
    private func trackPhoneRestore(phone: String, error: Error?) {
        switch self.signInOptions {
        case .phoneOnly(restore: let restore):
            if restore {
                let eventParams: SignInEvents.DataRestoreParams = .init(phone: phone, error: error)
                EventTracker.default.track(SignInEvents.dataRestore(params: eventParams))
            }
        default: break
        }
    }
    
    func validateCognitoCode(code: String, phone: String, completion: @escaping ((String) -> Void)) {
        self.state = .loading
        ValidateSMS(code: code, phone: phone).execute()
            .sink { [weak self] (completion) in
                if let error = completion.error {
                    self?.state = .failure(error: error)
                }
            } receiveValue: { [weak self] (response) in
                if response.registered {
                    self?.handleRegisteredUser(with: response.token, socialID: "")
                } else {
                    completion(response.token)
                    self?.state = .finished(code: code, phone: phone, registered: response.registered)
                }
            }
            .store(in: &cancellables)
    }
}

extension SignInViewModel {
    enum State {
        case initial
        case loading // sending sms request, getting info from fb
        case failure(error: Error)
        case userIsRegistered
        case userNeedsRegistration(token: String, userInfo: UserInfo)
        case finished(code: String, phone: String, registered: Bool = false) // succesfully sent sms request
    }
    
    enum SignInOptions {
        case phoneOnly(restore: Bool = false)
        case phoneAndSocial
    }
}
