//
//  InvoicesListView.swift
//  OPS
//
//  List of invoices with filter chips, search, swipe actions, and payment recording.
//

import SwiftUI

struct InvoicesListView: View {
    @StateObject private var viewModel = InvoiceViewModel()
    @EnvironmentObject private var dataController: DataController

    @State private var selectedInvoice: Invoice? = nil
    @State private var showPaymentSheet = false
    @State private var paymentInvoice: Invoice? = nil
    @State private var showVoidConfirm = false
    @State private var voidTarget: Invoice? = nil
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(InvoiceViewModel.InvoiceFilter.allCases, id: \.self) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Search invoices...", text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .onChange(of: searchText) { _, newValue in
                        viewModel.searchText = newValue
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.top, OPSStyle.Layout.spacing2)

            // Content
            if viewModel.isLoading && viewModel.invoices.isEmpty {
                Spacer()
                TacticalLoadingBarAnimated()
                Spacer()
            } else if viewModel.filteredInvoices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(viewModel.filteredInvoices) { invoice in
                            InvoiceCard(
                                invoice: invoice,
                                onTap: { selectedInvoice = invoice },
                                onSwipeRight: {
                                    paymentInvoice = invoice
                                    showPaymentSheet = true
                                },
                                onSwipeLeft: {
                                    voidTarget = invoice
                                    showVoidConfirm = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }
                .refreshable { await viewModel.loadInvoices() }
            }
        }
        .background(OPSStyle.Colors.background)
        .navigationDestination(item: $selectedInvoice) { invoice in
            InvoiceDetailView(invoice: invoice, viewModel: viewModel)
        }
        .sheet(isPresented: $showPaymentSheet) {
            if let inv = paymentInvoice {
                PaymentRecordSheet(invoice: inv, viewModel: viewModel)
            }
        }
        .confirmationDialog("Void Invoice?", isPresented: $showVoidConfirm) {
            Button("Void Invoice", role: .destructive) {
                if let inv = voidTarget {
                    Task { await viewModel.voidInvoice(inv) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will void the invoice. This action cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId)
                await viewModel.loadInvoices()
            }
        }
    }

    // MARK: - Components

    private func filterChip(_ filter: InvoiceViewModel.InvoiceFilter) -> some View {
        Button(action: { viewModel.selectedFilter = filter }) {
            Text(filter.rawValue)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(
                    viewModel.selectedFilter == filter
                    ? OPSStyle.Colors.primaryText
                    : OPSStyle.Colors.tertiaryText
                )
                .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                .background(
                    viewModel.selectedFilter == filter
                    ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                    : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                )
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(
                            viewModel.selectedFilter == filter
                            ? OPSStyle.Colors.primaryAccent
                            : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: OPSStyle.Icons.invoiceReceipt)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if viewModel.invoices.isEmpty {
                Text("NO INVOICES YET")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("Invoices appear here when estimates are converted")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("NO MATCHES")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
