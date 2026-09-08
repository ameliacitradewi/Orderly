//
//  LLMService.swift
//  Orderly
//
//  Created by Amelia Citra on 08/09/26.
//
import Foundation

protocol LLMService {
    func generate(prompt: String) async throws -> String
}
