//
//  AIAnalysisView.swift
//  Orderly
//
//  Created by Amelia Citra on 03/09/26.
//

import SwiftUI

struct AIAnalysisView: View {

    let result: String

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Orderly's Analysis")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView {

                Text(result)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
