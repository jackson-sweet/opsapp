//
//  AuthError.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

// MARK: - Auth Errors
// Human-readable authentication errors for field crew members

enum AuthError: Error {
    case credentialsNotFound
    case invalidCredentials
    case invalidResponse
    case serverError(Int)
    case networkError(String)
    case decodingFailed
    
    var localizedDescription: String {
        switch self {
        case .credentialsNotFound:
            return "Sign in required. Please enter your username and password."
        case .invalidCredentials:
            return "Incorrect username or password. Please try again."
        case .invalidResponse:
            return "Unable to connect to server. Please try again."
        case .serverError(let code):
            return "Server issue (code: \(code)). Please try again later."
        case .networkError(let message):
            return "Connection issue: \(message). Check your signal and try again."
        case .decodingFailed:
            return "Decoding Error: Unable to parse response. Please try again."
        }
    }
}
