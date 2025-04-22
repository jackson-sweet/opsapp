//
//  APIError.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

// MARK: - API Errors
// Field-worker-friendly error messages

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case unauthorized
    case rateLimited
    case serverError
    case networkError
    case httpError(statusCode: Int)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid address. Contact support if this continues."
        case .invalidResponse:
            return "Invalid response from server. Try again in a moment."
        case .decodingFailed:
            return "Couldn't read server response. Try restarting the app."
        case .unauthorized:
            return "Your login has expired. Please sign in again."
        case .rateLimited:
            return "Too many requests at once. Please wait a moment."
        case .serverError:
            return "Server error. We're working to fix this issue."
        case .networkError:
            return "Network error. Check your signal and try again."
        case .httpError(let statusCode):
            return "Connection error (\(statusCode)). Try again in a moment."
        }
    }
}