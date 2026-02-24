# OPS iOS Major Version Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the iOS app to full feature parity with the ops-web platform — adding Pipeline CRM, Estimates, Invoices, Products, and Accounting via direct Supabase integration, while field crew UI remains completely unchanged.

**Architecture:** Two parallel networking stacks — existing `BubbleAPIService` for operational data, new `SupabaseService` for financial/CRM data. Both sync into SwiftData. The tab bar is role-gated: Admin/Office Crew get a new Pipeline tab at position 2; Field Crew see no change. All new screens are Admin/Office only except task source attribution badges (visible to all roles).

**Tech Stack:** SwiftUI + SwiftData + supabase-swift package + existing OPSStyle system + existing BubbleAPIService/CentralizedSyncManager patterns

**Supabase credentials:** Already configured — `OPS/Network/Supabase/SupabaseConfig.swift` exists with the correct URL and anon key. Do not regenerate this file.
- URL: `https://ijeekuhbatykdomumfjx.supabase.co`
- Project ID: `ijeekuhbatykdomumfjx`

**Design doc:** `docs/plans/2026-02-18-ios-major-version-design.md` — read this for wireframes, token tables, and screen specs before implementing any UI.

**Key files to read before starting:**
- `OPS/Styles/OPSStyle.swift` — all color/spacing/layout tokens
- `OPS/Styles/Components/ButtonStyles.swift` — button components
- `OPS/Styles/Components/CardStyles.swift` — card components
- `OPS/Network/APIService.swift` — existing networking pattern to mirror
- `OPS/AppState.swift` — role detection and app state
- `OPS/ContentView.swift` — tab bar and navigation structure
- `OPS/DataModels/` — existing SwiftData model patterns

---

## Sprint 1 — Foundation

### Task 1: Add supabase-swift Package

**Files:**
- Modify: `opsapp-ios.xcodeproj` (via Xcode SPM UI)

**Step 1: Add package in Xcode**

In Xcode: File → Add Package Dependencies
URL: `https://github.com/supabase/supabase-swift`
Version: Up to Next Major from `2.0.0`
Add to target: `OPS`

**Step 2: Verify build passes**

Build the project (Cmd+B). Expected: SUCCESS with no errors.

**Step 3: Commit**

```bash
git add opsapp-ios.xcodeproj/project.pbxproj
git commit -m "chore: add supabase-swift package dependency"
```

---

### Task 2: SupabaseService — Client Setup + Firebase JWT Bridge

**Files:**
- Create: `OPS/Network/Supabase/SupabaseService.swift`
- ~~Create: `OPS/Network/Supabase/SupabaseConfig.swift`~~ ✅ **Already exists** — do not recreate.

**Context:** The web app (ops-web) already uses a Firebase JWT bridge to authenticate Supabase requests. The iOS app already has Firebase auth via `AuthManager`. We mirror the same pattern: pass the Firebase ID token as the Supabase access token. `SupabaseConfig.swift` is already present at `OPS/Network/Supabase/SupabaseConfig.swift` with the correct credentials.

**Step 1: Create SupabaseService.swift**

```swift
// OPS/Network/Supabase/SupabaseService.swift
import Foundation
import Supabase
import FirebaseAuth

@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    private(set) var client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    /// Call this after Firebase sign-in to bridge the Firebase JWT into Supabase.
    func setFirebaseSession() async throws {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw SupabaseServiceError.notAuthenticated
        }
        let idToken = try await firebaseUser.getIDToken()
        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken)
        )
    }

    /// Call on sign-out.
    func signOut() async throws {
        try await client.auth.signOut()
    }

    enum SupabaseServiceError: Error {
        case notAuthenticated
        case networkError(Error)
    }
}
```

**Step 3: Hook into existing auth flow**

Open `OPS/Services/AuthManager.swift`. Find the method where Firebase sign-in completes (look for `Auth.auth().signIn` completion or similar). After successful Firebase sign-in, add:

```swift
Task {
    try? await SupabaseService.shared.setFirebaseSession()
}
```

Also find the sign-out method and add:
```swift
Task {
    try? await SupabaseService.shared.signOut()
}
```

**Step 4: Build and verify no errors**

Cmd+B. Expected: SUCCESS.

**Step 5: Commit**

```bash
git add OPS/Network/Supabase/
git commit -m "feat: add SupabaseService with Firebase JWT bridge"
```

---

### Task 3: Update Bubble SwiftData Models with New Optional Fields

**Files:**
- Modify: `OPS/DataModels/Project.swift`
- Modify: `OPS/DataModels/ProjectTask.swift`
- Modify: `OPS/DataModels/CalendarEvent.swift`
- Modify: `OPS/DataModels/TaskType.swift` (if exists, else find where TaskType is defined)

**Context:** The web app has added new fields to Bubble data types (see `ops-web/BUBBLE_FIELD_ADDITIONS.md`). These fields are optional and may be nil for existing records. We add them as optional properties; the existing sync logic will populate them once Bubble returns them.

**Step 1: Add to Project model**

Find the `@Model class Project` (or `struct Project`) definition. Add:

```swift
var opportunityId: String?  // Supabase Opportunity UUID — links this project to its pipeline deal
```

**Step 2: Add to ProjectTask model**

Find the `@Model class ProjectTask` definition. Add:

```swift
var sourceLineItemId: String?   // Supabase LineItem UUID this task was generated from
var sourceEstimateId: String?   // Supabase Estimate UUID this task was generated from
```

**Step 3: Add CalendarEventType enum**

Create a new file or add to an existing enums file:

```swift
// OPS/DataModels/Enums/CalendarEventType.swift
import Foundation

enum CalendarEventType: String, Codable, CaseIterable {
    case task       = "task"
    case siteVisit  = "site_visit"
    case other      = "other"
}
```

**Step 4: Add to CalendarEvent model**

Find the `@Model class CalendarEvent` definition. Add:

```swift
var eventType: CalendarEventType  = .task   // Default to task for backward compat
var calendarOpportunityId: String?          // Named to avoid conflict; Supabase Opportunity UUID
var siteVisitId: String?                    // Supabase SiteVisit UUID
```

(Use `calendarOpportunityId` to avoid name collision since `opportunityId` may already exist.)

**Step 5: Add to TaskType model**

Find the `@Model class TaskType` (or wherever TaskType is defined). Add:

```swift
var defaultTeamMemberIds: [String] = []  // Default crew user IDs for auto-generated tasks
```

**Step 6: Update BubbleFields constants**

Open `OPS/Network/BubbleFields.swift` (or wherever field constants are defined). Add constants for the new fields:

```swift
// New fields — Feb 2026
static let opportunityId          = "opportunityId"
static let sourceLineItemId       = "sourceLineItemId"
static let sourceEstimateId       = "sourceEstimateId"
static let eventType              = "eventType"
static let calendarOpportunityId  = "opportunityId"   // Bubble field name
static let siteVisitId            = "siteVisitId"
static let defaultTeamMemberIds   = "defaultTeamMemberIds"
```

**Step 7: Update DTOs to decode new fields**

Find the DTO structs used to decode Bubble API responses for each entity. Add corresponding optional properties matching the field names above. The existing `CodingKeys` pattern should handle nil gracefully.

**Step 8: Build and verify**

Cmd+B. Expected: SUCCESS. Check for any SwiftData migration warnings in console on first run (expected, since we added properties).

**Step 9: Commit**

```bash
git add OPS/DataModels/
git commit -m "feat: add new Bubble fields to existing SwiftData models (opportunityId, sourceEstimateId, sourceLineItemId, eventType)"
```

---

### Task 4: New Supabase SwiftData Models

**Files:**
- Create: `OPS/DataModels/Supabase/Opportunity.swift`
- Create: `OPS/DataModels/Supabase/Activity.swift`
- Create: `OPS/DataModels/Supabase/FollowUp.swift`
- Create: `OPS/DataModels/Supabase/StageTransition.swift`
- Create: `OPS/DataModels/Supabase/Estimate.swift`
- Create: `OPS/DataModels/Supabase/EstimateLineItem.swift`
- Create: `OPS/DataModels/Supabase/Invoice.swift`
- Create: `OPS/DataModels/Supabase/InvoiceLineItem.swift`
- Create: `OPS/DataModels/Supabase/Payment.swift`
- Create: `OPS/DataModels/Supabase/Product.swift`
- Create: `OPS/DataModels/Supabase/SiteVisit.swift`

**Context:** These models mirror the Supabase schema defined in `ops-web/supabase/migrations/EXECUTED/001_pipeline_schema.sql`. All use UUID primary keys (String). All are `@Model` for SwiftData local caching.

**Step 1: PipelineStage enum**

```swift
// OPS/DataModels/Enums/PipelineStage.swift
enum PipelineStage: String, Codable, CaseIterable, Identifiable {
    case newLead      = "new_lead"
    case qualifying   = "qualifying"
    case quoting      = "quoting"
    case quoted       = "quoted"
    case followUp     = "follow_up"
    case negotiation  = "negotiation"
    case won          = "won"
    case lost         = "lost"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newLead:     return "NEW LEAD"
        case .qualifying:  return "QUALIFYING"
        case .quoting:     return "QUOTING"
        case .quoted:      return "QUOTED"
        case .followUp:    return "FOLLOW-UP"
        case .negotiation: return "NEGOTIATION"
        case .won:         return "WON"
        case .lost:        return "LOST"
        }
    }

    var isTerminal: Bool {
        self == .won || self == .lost
    }

    var next: PipelineStage? {
        switch self {
        case .newLead:     return .qualifying
        case .qualifying:  return .quoting
        case .quoting:     return .quoted
        case .quoted:      return .followUp
        case .followUp:    return .negotiation
        case .negotiation: return .won
        case .won, .lost:  return nil
        }
    }

    var winProbability: Int {
        switch self {
        case .newLead:     return 10
        case .qualifying:  return 20
        case .quoting:     return 40
        case .quoted:      return 60
        case .followUp:    return 50
        case .negotiation: return 75
        case .won:         return 100
        case .lost:        return 0
        }
    }

    var staleThresholdDays: Int {
        switch self {
        case .newLead:     return 3
        case .qualifying:  return 7
        case .quoting:     return 5
        case .quoted:      return 7
        case .followUp:    return 3
        case .negotiation: return 2
        case .won, .lost:  return Int.max
        }
    }
}
```

**Step 2: Opportunity model**

```swift
// OPS/DataModels/Supabase/Opportunity.swift
import SwiftData
import Foundation

@Model
class Opportunity {
    @Attribute(.unique) var id: String
    var companyId: String
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var jobDescription: String?
    var estimatedValue: Double?
    var stage: PipelineStage
    var source: String?          // "referral", "website", "email", etc.
    var projectId: String?       // Bubble project UUID, set when won
    var clientId: String?        // Bubble client UUID
    var lossReason: String?
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date?

    // Computed
    var weightedValue: Double {
        (estimatedValue ?? 0) * Double(stage.winProbability) / 100.0
    }

    var daysInStage: Int {
        guard let last = lastActivityAt else {
            return Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }

    var isStale: Bool {
        daysInStage > stage.staleThresholdDays
    }

    init(id: String = UUID().uuidString, companyId: String, contactName: String, stage: PipelineStage = .newLead, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.contactName = contactName
        self.stage = stage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

**Step 3: ActivityType enum + Activity model**

```swift
// OPS/DataModels/Enums/ActivityType.swift
enum ActivityType: String, Codable, CaseIterable {
    case note             = "note"
    case email            = "email"
    case call             = "call"
    case meeting          = "meeting"
    case estimateSent     = "estimate_sent"
    case estimateApproved = "estimate_accepted"
    case estimateDeclined = "estimate_declined"
    case invoiceSent      = "invoice_sent"
    case paymentReceived  = "payment_received"
    case stageChange      = "stage_change"
    case created          = "created"
    case won              = "won"
    case lost             = "lost"
    case siteVisit        = "site_visit"
    case system           = "system"

    var icon: String {
        switch self {
        case .note:             return "note.text"
        case .email:            return "envelope.fill"
        case .call:             return "phone.fill"
        case .meeting:          return "person.2.fill"
        case .estimateSent:     return "doc.text.fill"
        case .estimateApproved: return "checkmark.circle.fill"
        case .estimateDeclined: return "xmark.circle.fill"
        case .invoiceSent:      return "receipt"
        case .paymentReceived:  return "dollarsign.circle.fill"
        case .stageChange:      return "arrow.forward.circle.fill"
        case .created:          return "plus.circle.fill"
        case .won:              return "checkmark.seal.fill"
        case .lost:             return "xmark.seal.fill"
        case .siteVisit:        return "mappin.circle.fill"
        case .system:           return "gear"
        }
    }

    var isSystemGenerated: Bool {
        switch self {
        case .stageChange, .created, .won, .lost, .system,
             .estimateSent, .estimateApproved, .estimateDeclined,
             .invoiceSent, .paymentReceived: return true
        default: return false
        }
    }
}
```

```swift
// OPS/DataModels/Supabase/Activity.swift
import SwiftData
import Foundation

@Model
class Activity {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var body: String?
    var createdBy: String?      // User ID
    var createdAt: Date
    var metadata: String?       // JSON blob for stage change data etc.

    init(id: String = UUID().uuidString, opportunityId: String, companyId: String, type: ActivityType, createdAt: Date = Date()) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.type = type
        self.createdAt = createdAt
    }
}
```

**Step 4: FollowUp model**

```swift
// OPS/DataModels/Supabase/FollowUp.swift
import SwiftData
import Foundation

enum FollowUpType: String, Codable, CaseIterable {
    case call           = "call"
    case email          = "email"
    case meeting        = "meeting"
    case quoteFollowUp  = "quote_follow_up"
    case invoiceFollowUp = "invoice_follow_up"
    case custom         = "custom"
}

enum FollowUpStatus: String, Codable {
    case pending   = "pending"
    case completed = "completed"
    case skipped   = "skipped"
}

@Model
class FollowUp {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: FollowUpType
    var status: FollowUpStatus
    var dueAt: Date
    var assignedTo: String?
    var notes: String?
    var createdAt: Date

    var isOverdue: Bool {
        status == .pending && dueAt < Date()
    }

    var isDueToday: Bool {
        status == .pending && Calendar.current.isDateInToday(dueAt)
    }

    init(id: String = UUID().uuidString, opportunityId: String, companyId: String, type: FollowUpType, dueAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.type = type
        self.status = .pending
        self.dueAt = dueAt
        self.createdAt = createdAt
    }
}
```

**Step 5: Estimate + EstimateLineItem models**

```swift
// OPS/DataModels/Supabase/Estimate.swift
import SwiftData
import Foundation

enum EstimateStatus: String, Codable, CaseIterable {
    case draft    = "draft"
    case sent     = "sent"
    case viewed   = "viewed"
    case approved = "approved"
    case converted = "converted"
    case declined  = "declined"
    case expired   = "expired"

    var displayName: String { rawValue.uppercased() }

    var canSend: Bool     { self == .draft }
    var canApprove: Bool  { self == .sent || self == .viewed }
    var canConvert: Bool  { self == .approved }
}

@Model
class Estimate {
    @Attribute(.unique) var id: String
    var companyId: String
    var estimateNumber: String      // "EST-0001"
    var status: EstimateStatus
    var clientId: String?           // Bubble client UUID
    var projectId: String?          // Bubble project UUID
    var opportunityId: String?      // Supabase opportunity UUID
    var title: String?
    var clientMessage: String?
    var internalNotes: String?
    var taxRate: Double             // e.g. 0.13 for 13%
    var discountPercent: Double     // e.g. 0.10 for 10%
    var subtotal: Double            // Computed server-side, cached
    var taxAmount: Double           // Computed server-side, cached
    var total: Double               // Computed server-side, cached
    var validUntil: Date?
    var sentAt: Date?
    var version: Int
    var parentId: String?           // For revised estimates
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, companyId: String, estimateNumber: String = "", status: EstimateStatus = .draft, taxRate: Double = 0, discountPercent: Double = 0, version: Int = 1, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.estimateNumber = estimateNumber
        self.status = status
        self.taxRate = taxRate
        self.discountPercent = discountPercent
        self.subtotal = 0
        self.taxAmount = 0
        self.total = 0
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

```swift
// OPS/DataModels/Supabase/EstimateLineItem.swift
import SwiftData
import Foundation

enum LineItemType: String, Codable, CaseIterable {
    case labor    = "LABOR"
    case material = "MATERIAL"
    case other    = "OTHER"
}

@Model
class EstimateLineItem {
    @Attribute(.unique) var id: String
    var estimateId: String
    var productId: String?          // If from catalog
    var name: String
    var description: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?               // "hr", "sqft", "each"
    var unitPrice: Double
    var discountPercent: Double
    var taxable: Bool
    var optional: Bool              // Client can include/exclude
    var lineTotal: Double           // Server-computed: qty * unitPrice * (1 - discount)
    var displayOrder: Int
    var taskTypeId: String?         // Bubble TaskType ID for task generation
    var createdAt: Date

    init(id: String = UUID().uuidString, estimateId: String, name: String, type: LineItemType = .labor, quantity: Double = 1, unitPrice: Double = 0, displayOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.estimateId = estimateId
        self.name = name
        self.type = type
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPercent = 0
        self.taxable = true
        self.optional = false
        self.lineTotal = quantity * unitPrice
        self.displayOrder = displayOrder
        self.createdAt = createdAt
    }
}
```

**Step 6: Invoice + InvoiceLineItem + Payment models**

```swift
// OPS/DataModels/Supabase/Invoice.swift
import SwiftData
import Foundation

enum InvoiceStatus: String, Codable, CaseIterable {
    case draft           = "draft"
    case sent            = "sent"
    case awaitingPayment = "awaiting_payment"
    case partiallyPaid   = "partially_paid"
    case paid            = "paid"
    case pastDue         = "past_due"
    case void            = "void"

    var displayName: String {
        switch self {
        case .awaitingPayment: return "AWAITING"
        case .partiallyPaid:   return "PARTIAL"
        default:               return rawValue.uppercased()
        }
    }

    var isPaid: Bool { self == .paid }
    var needsPayment: Bool { self == .awaitingPayment || self == .partiallyPaid || self == .pastDue }
}

@Model
class Invoice {
    @Attribute(.unique) var id: String
    var companyId: String
    var invoiceNumber: String       // "INV-0001"
    var status: InvoiceStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var estimateId: String?         // Source estimate if converted
    var title: String?
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var amountPaid: Double          // Maintained by DB trigger — do NOT update manually
    var balanceDue: Double          // Maintained by DB trigger — do NOT update manually
    var taxRate: Double
    var dueDate: Date?
    var sentAt: Date?
    var paidAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return balanceDue > 0 && due < Date() && status != .void
    }

    init(id: String = UUID().uuidString, companyId: String, invoiceNumber: String = "", status: InvoiceStatus = .draft, taxRate: Double = 0, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.invoiceNumber = invoiceNumber
        self.status = status
        self.subtotal = 0
        self.taxAmount = 0
        self.total = 0
        self.amountPaid = 0
        self.balanceDue = 0
        self.taxRate = taxRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

```swift
// OPS/DataModels/Supabase/Payment.swift
import SwiftData
import Foundation

enum PaymentMethod: String, Codable, CaseIterable {
    case cash        = "cash"
    case check       = "check"
    case creditCard  = "credit_card"
    case ach         = "ach"
    case bankTransfer = "bank_transfer"
    case stripe      = "stripe"
    case other       = "other"

    var displayName: String {
        switch self {
        case .creditCard:   return "CREDIT CARD"
        case .ach:          return "ACH"
        case .bankTransfer: return "BANK TRANSFER"
        default:            return rawValue.uppercased()
        }
    }
}

@Model
class Payment {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var companyId: String
    var amount: Double
    var method: PaymentMethod
    var paidAt: Date
    var notes: String?
    var voidedAt: Date?
    var voidedBy: String?
    var createdAt: Date

    var isVoided: Bool { voidedAt != nil }

    init(id: String = UUID().uuidString, invoiceId: String, companyId: String, amount: Double, method: PaymentMethod, paidAt: Date = Date(), createdAt: Date = Date()) {
        self.id = id
        self.invoiceId = invoiceId
        self.companyId = companyId
        self.amount = amount
        self.method = method
        self.paidAt = paidAt
        self.createdAt = createdAt
    }
}
```

**Step 7: Product model**

```swift
// OPS/DataModels/Supabase/Product.swift
import SwiftData
import Foundation

@Model
class Product {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var description: String?
    var type: LineItemType          // reuse LineItemType enum
    var defaultPrice: Double
    var unitCost: Double?           // For margin calculation
    var unit: String?
    var taxable: Bool
    var isActive: Bool
    var taskTypeId: String?         // Bubble TaskType UUID for task auto-generation
    var createdAt: Date

    var marginPercent: Double? {
        guard let cost = unitCost, cost > 0, defaultPrice > 0 else { return nil }
        return ((defaultPrice - cost) / defaultPrice) * 100
    }

    init(id: String = UUID().uuidString, companyId: String, name: String, type: LineItemType = .labor, defaultPrice: Double = 0, taxable: Bool = true, isActive: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.type = type
        self.defaultPrice = defaultPrice
        self.taxable = taxable
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
```

**Step 8: SiteVisit model**

```swift
// OPS/DataModels/Supabase/SiteVisit.swift
import SwiftData
import Foundation

enum SiteVisitStatus: String, Codable {
    case scheduled  = "scheduled"
    case completed  = "completed"
    case cancelled  = "cancelled"
}

@Model
class SiteVisit {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var completedAt: Date?
    var notes: String?
    var address: String?
    var assignedTo: String?         // User ID
    var createdAt: Date

    init(id: String = UUID().uuidString, opportunityId: String, companyId: String, status: SiteVisitStatus = .scheduled, createdAt: Date = Date()) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.status = status
        self.createdAt = createdAt
    }
}
```

**Step 9: Build**

Cmd+B. Expected: SUCCESS.

**Step 10: Commit**

```bash
git add OPS/DataModels/Supabase/ OPS/DataModels/Enums/
git commit -m "feat: add Supabase SwiftData models — Opportunity, Activity, FollowUp, Estimate, Invoice, Payment, Product, SiteVisit"
```

---

### Task 5: SupabaseRepository — CRUD Operations

**Files:**
- Create: `OPS/Network/Supabase/OpportunityRepository.swift`
- Create: `OPS/Network/Supabase/EstimateRepository.swift`
- Create: `OPS/Network/Supabase/InvoiceRepository.swift`
- Create: `OPS/Network/Supabase/ProductRepository.swift`

**Context:** Each repository talks to Supabase and populates SwiftData. Mirror the pattern used by existing Bubble repositories in `OPS/Network/` — fetch returns decoded objects, errors are thrown. All network calls run on background task; SwiftData writes happen on `@MainActor`.

**Step 1: OpportunityRepository**

```swift
// OPS/Network/Supabase/OpportunityRepository.swift
import Foundation
import Supabase

class OpportunityRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [OpportunityDTO] {
        let response: [OpportunityDTO] = try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchActivities(for opportunityId: String) async throws -> [ActivityDTO] {
        let response: [ActivityDTO] = try await client
            .from("activities")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchFollowUps(for opportunityId: String) async throws -> [FollowUpDTO] {
        let response: [FollowUpDTO] = try await client
            .from("follow_ups")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("due_at", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Create

    func create(_ dto: CreateOpportunityDTO) async throws -> OpportunityDTO {
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func logActivity(_ dto: CreateActivityDTO) async throws -> ActivityDTO {
        let response: ActivityDTO = try await client
            .from("activities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func createFollowUp(_ dto: CreateFollowUpDTO) async throws -> FollowUpDTO {
        let response: FollowUpDTO = try await client
            .from("follow_ups")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    // MARK: - Update

    func advanceStage(opportunityId: String, to stage: PipelineStage, lossReason: String? = nil) async throws -> OpportunityDTO {
        var updates: [String: AnyJSON] = ["stage": .string(stage.rawValue)]
        if let reason = lossReason { updates["loss_reason"] = .string(reason) }
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .update(updates)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ opportunityId: String, fields: UpdateOpportunityDTO) async throws -> OpportunityDTO {
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .update(fields)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    // MARK: - Delete

    func delete(_ opportunityId: String) async throws {
        try await client
            .from("opportunities")
            .delete()
            .eq("id", value: opportunityId)
            .execute()
    }
}
```

**Step 2: Create DTOs**

```swift
// OPS/Network/Supabase/DTOs/OpportunityDTOs.swift
import Foundation

struct OpportunityDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let jobDescription: String?
    let estimatedValue: Double?
    let stage: String
    let source: String?
    let projectId: String?
    let clientId: String?
    let lossReason: String?
    let createdAt: String
    let updatedAt: String
    let lastActivityAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId        = "company_id"
        case contactName      = "contact_name"
        case contactEmail     = "contact_email"
        case contactPhone     = "contact_phone"
        case jobDescription   = "job_description"
        case estimatedValue   = "estimated_value"
        case stage
        case source
        case projectId        = "project_id"
        case clientId         = "client_id"
        case lossReason       = "loss_reason"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastActivityAt   = "last_activity_at"
    }

    func toModel() -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: companyId,
            contactName: contactName,
            stage: PipelineStage(rawValue: stage) ?? .newLead,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
            updatedAt: ISO8601DateFormatter().date(from: updatedAt) ?? Date()
        )
        opp.contactEmail = contactEmail
        opp.contactPhone = contactPhone
        opp.jobDescription = jobDescription
        opp.estimatedValue = estimatedValue
        opp.source = source
        opp.projectId = projectId
        opp.clientId = clientId
        opp.lossReason = lossReason
        if let la = lastActivityAt { opp.lastActivityAt = ISO8601DateFormatter().date(from: la) }
        return opp
    }
}

struct CreateOpportunityDTO: Codable {
    let companyId: String
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let jobDescription: String?
    let estimatedValue: Double?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case contactName    = "contact_name"
        case contactEmail   = "contact_email"
        case contactPhone   = "contact_phone"
        case jobDescription = "job_description"
        case estimatedValue = "estimated_value"
        case source
    }
}

struct UpdateOpportunityDTO: Codable {
    var contactName: String?
    var contactEmail: String?
    var contactPhone: String?
    var jobDescription: String?
    var estimatedValue: Double?
    var source: String?
    var clientId: String?
    var projectId: String?

    enum CodingKeys: String, CodingKey {
        case contactName    = "contact_name"
        case contactEmail   = "contact_email"
        case contactPhone   = "contact_phone"
        case jobDescription = "job_description"
        case estimatedValue = "estimated_value"
        case source
        case clientId       = "client_id"
        case projectId      = "project_id"
    }
}

struct ActivityDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String
    let companyId: String
    let type: String
    let body: String?
    let createdBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case body
        case createdBy     = "created_by"
        case createdAt     = "created_at"
    }

    func toModel() -> Activity {
        let act = Activity(
            id: id,
            opportunityId: opportunityId,
            companyId: companyId,
            type: ActivityType(rawValue: type) ?? .note,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date()
        )
        act.body = body
        act.createdBy = createdBy
        return act
    }
}

struct CreateActivityDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case body
    }
}

struct FollowUpDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String
    let companyId: String
    let type: String
    let status: String
    let dueAt: String
    let assignedTo: String?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case status
        case dueAt         = "due_at"
        case assignedTo    = "assigned_to"
        case notes
        case createdAt     = "created_at"
    }

    func toModel() -> FollowUp {
        FollowUp(
            id: id,
            opportunityId: opportunityId,
            companyId: companyId,
            type: FollowUpType(rawValue: type) ?? .custom,
            dueAt: ISO8601DateFormatter().date(from: dueAt) ?? Date(),
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date()
        )
    }
}

struct CreateFollowUpDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let dueAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case dueAt         = "due_at"
        case notes
    }
}
```

**Step 3: EstimateRepository**

```swift
// OPS/Network/Supabase/EstimateRepository.swift
import Foundation
import Supabase

class EstimateRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [EstimateDTO] {
        try await client
            .from("estimates")
            .select("*, estimate_line_items(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func create(_ dto: CreateEstimateDTO) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .insert(dto)
            .select("*, estimate_line_items(*)")
            .single()
            .execute()
            .value
    }

    func addLineItem(_ dto: CreateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("estimate_line_items")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func updateLineItem(_ id: String, fields: UpdateLineItemDTO) async throws -> EstimateLineItemDTO {
        try await client
            .from("estimate_line_items")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteLineItem(_ id: String) async throws {
        try await client
            .from("estimate_line_items")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func updateStatus(_ estimateId: String, status: EstimateStatus) async throws -> EstimateDTO {
        try await client
            .from("estimates")
            .update(["status": status.rawValue])
            .eq("id", value: estimateId)
            .select("*, estimate_line_items(*)")
            .single()
            .execute()
            .value
    }

    /// Convert approved estimate to invoice — atomic RPC, never do this manually.
    func convertToInvoice(estimateId: String) async throws -> InvoiceDTO {
        try await client
            .rpc("convert_estimate_to_invoice", params: ["p_estimate_id": estimateId])
            .execute()
            .value
    }
}
```

**Step 4: InvoiceRepository**

```swift
// OPS/Network/Supabase/InvoiceRepository.swift
import Foundation
import Supabase

class InvoiceRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [InvoiceDTO] {
        try await client
            .from("invoices")
            .select("*, invoice_line_items(*), payments(*)")
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func recordPayment(_ dto: CreatePaymentDTO) async throws -> PaymentDTO {
        // Insert only — DB trigger maintains invoice balance and status automatically.
        // NEVER update invoice.amount_paid or invoice.balance_due manually.
        try await client
            .from("payments")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func voidInvoice(_ invoiceId: String) async throws {
        try await client
            .from("invoices")
            .update(["status": "void"])
            .eq("id", value: invoiceId)
            .execute()
    }
}
```

**Step 5: ProductRepository**

```swift
// OPS/Network/Supabase/ProductRepository.swift
import Foundation
import Supabase

class ProductRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [ProductDTO] {
        try await client
            .from("products")
            .select()
            .eq("company_id", value: companyId)
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func create(_ dto: CreateProductDTO) async throws -> ProductDTO {
        try await client
            .from("products")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func update(_ id: String, fields: UpdateProductDTO) async throws -> ProductDTO {
        try await client
            .from("products")
            .update(fields)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deactivate(_ id: String) async throws {
        try await client
            .from("products")
            .update(["is_active": false])
            .eq("id", value: id)
            .execute()
    }
}
```

**Step 6: Add remaining DTOs** (EstimateDTO, InvoiceDTO, ProductDTO, PaymentDTO)

Follow the exact same pattern as OpportunityDTO above: snake_case CodingKeys, `toModel()` conversion method, Create/Update variants.

**Step 7: Build**

Cmd+B. Expected: SUCCESS.

**Step 8: Commit**

```bash
git add OPS/Network/Supabase/
git commit -m "feat: add Supabase repositories and DTOs for Opportunity, Estimate, Invoice, Product"
```

---

### Task 6: New OPSStyle Additions

**Files:**
- Modify: `OPS/Styles/OPSStyle.swift`

**Step 1: Add new icons**

In `OPSStyle.Icons`, add after the existing icons:

```swift
// Pipeline & Financial (Feb 2026)
static let opportunity      = "arrow.up.right.circle.fill"
static let pipelineChart    = "chart.bar.doc.horizontal.fill"
static let estimateDoc      = "doc.text.fill"
static let invoiceReceipt   = "receipt"
static let paymentDollar    = "dollarsign.circle.fill"
static let siteVisitPin     = "mappin.circle.fill"
static let activityBubble   = "bubble.left.and.text.bubble.right.fill"
static let followUpAlarm    = "alarm.fill"
static let stageAdvance     = "arrow.forward.circle.fill"
static let dealWon          = "checkmark.seal.fill"
static let dealLost         = "xmark.seal.fill"
static let accountingChart  = "chart.bar.fill"
static let productTag       = "tag.fill"
```

**Step 2: Add pipeline stage colors**

In `OPSStyle.Colors`, add a new utility function:

```swift
static func pipelineStageColor(for stage: PipelineStage) -> Color {
    switch stage {
    case .newLead:     return Color(hex: "#BCBCBC")
    case .qualifying:  return Color(hex: "#B5A381")
    case .quoting:     return Color(hex: "#8195B5")
    case .quoted:      return Color(hex: "#9DB582")
    case .followUp:    return Color(hex: "#C4A868")
    case .negotiation: return Color(hex: "#B58289")
    case .won:         return Color("StatusSuccess")
    case .lost:        return Color("StatusError")
    }
}
```

Add a `Color(hex:)` initializer if it doesn't exist:

```swift
// In a Color extension file, or at the bottom of OPSStyle.swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

**Step 3: Build and commit**

```bash
git add OPS/Styles/OPSStyle.swift
git commit -m "feat: add pipeline icons and stage colors to OPSStyle"
```

---

### Task 7: Role-Gated Tab Bar

**Files:**
- Modify: `OPS/ContentView.swift` (or wherever `CustomTabBar` / `MainTabView` is defined)
- Modify: `OPS/AppState.swift`

**Context:** Read `OPS/AppState.swift` first to understand how user role is determined. The existing role detection checks `company.adminIds` first, then `employeeType`, then defaults to Field Crew.

**Step 1: Read existing tab bar code**

Open `ContentView.swift`. Find how tabs are constructed. Note the exact pattern — whether it's a `TabView`, a custom `CustomTabBar`, or a `switch` on tab index.

**Step 2: Add pipeline tab to Admin/Office role paths**

Find the place where tabs are built (likely a switch or array based on `appState.currentUser?.role` or similar). Add the Pipeline tab for admin and officeCrew roles only:

```swift
// Pseudo-code — adapt to match existing pattern exactly
var visibleTabs: [TabItem] {
    switch appState.userRole {
    case .admin, .officeCrew:
        return [.home, .pipeline, .jobBoard, .schedule, .settings]
    case .fieldCrew:
        return [.home, .jobBoard, .schedule, .settings]
    }
}
```

**Step 3: Add Pipeline tab enum case**

Find the `TabItem` or similar enum (check `CustomTabBar.swift` or `ContentView.swift`). Add:

```swift
case pipeline
```

With icon `"chart.bar.doc.horizontal.fill"` and label `"PIPELINE"`.

**Step 4: Wire Pipeline tab destination**

For the pipeline case, return `PipelineTabView()` as the destination. This view will be created in Sprint 2 — for now, use a placeholder:

```swift
case .pipeline:
    Text("PIPELINE")
        .foregroundColor(OPSStyle.Colors.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
```

**Step 5: Build and verify**

Build (Cmd+B) and run in simulator. Sign in as an admin user. Confirm 5 tabs visible. Sign in as field crew. Confirm 4 tabs visible, no Pipeline tab.

**Step 6: Commit**

```bash
git add OPS/ContentView.swift OPS/AppState.swift
git commit -m "feat: add role-gated Pipeline tab for Admin/Office Crew"
```

---

## Sprint 2 — Pipeline CRM

### Task 8: PipelineViewModel

**Files:**
- Create: `OPS/ViewModels/PipelineViewModel.swift`

```swift
// OPS/ViewModels/PipelineViewModel.swift
import SwiftUI
import SwiftData

@MainActor
class PipelineViewModel: ObservableObject {
    @Published var opportunities: [Opportunity] = []
    @Published var selectedStage: PipelineStage = .newLead
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: OpportunityRepository?

    var filteredOpportunities: [Opportunity] {
        opportunities.filter { $0.stage == selectedStage }
    }

    var weightedPipelineValue: Double {
        opportunities
            .filter { !$0.stage.isTerminal }
            .reduce(0) { $0 + $1.weightedValue }
    }

    var activeDealsCount: Int {
        opportunities.filter { !$0.stage.isTerminal }.count
    }

    var stagesWithCounts: [(stage: PipelineStage, count: Int)] {
        PipelineStage.allCases.map { stage in
            (stage, opportunities.filter { $0.stage == stage }.count)
        }
    }

    func setup(companyId: String) {
        repository = OpportunityRepository(companyId: companyId)
    }

    func loadOpportunities() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchAll()
            opportunities = dtos.map { $0.toModel() }
            // Auto-select first non-empty stage
            if let first = PipelineStage.allCases.first(where: { stage in
                opportunities.contains { $0.stage == stage }
            }) {
                selectedStage = first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func advanceStage(opportunity: Opportunity) async {
        guard let nextStage = opportunity.stage.next,
              let repo = repository else { return }
        let originalStage = opportunity.stage
        // Optimistic update
        opportunity.stage = nextStage
        do {
            let updated = try await repo.advanceStage(opportunityId: opportunity.id, to: nextStage)
            opportunity.stage = PipelineStage(rawValue: updated.stage) ?? nextStage
        } catch {
            // Revert on failure
            opportunity.stage = originalStage
            self.error = "Failed to advance stage"
        }
    }

    func markLost(opportunity: Opportunity, reason: String) async {
        guard let repo = repository else { return }
        do {
            _ = try await repo.advanceStage(opportunityId: opportunity.id, to: .lost, lossReason: reason)
            opportunity.stage = .lost
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markWon(opportunity: Opportunity) async {
        guard let repo = repository else { return }
        do {
            _ = try await repo.advanceStage(opportunityId: opportunity.id, to: .won)
            opportunity.stage = .won
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createOpportunity(contactName: String, contactEmail: String?, contactPhone: String?, jobDescription: String?, estimatedValue: Double?, source: String?, companyId: String) async {
        guard let repo = repository else { return }
        let dto = CreateOpportunityDTO(
            companyId: companyId,
            contactName: contactName,
            contactEmail: contactEmail,
            contactPhone: contactPhone,
            jobDescription: jobDescription,
            estimatedValue: estimatedValue,
            source: source
        )
        do {
            let created = try await repo.create(dto)
            opportunities.insert(created.toModel(), at: 0)
            selectedStage = .newLead
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

**Commit:**
```bash
git add OPS/ViewModels/PipelineViewModel.swift
git commit -m "feat: add PipelineViewModel with optimistic stage advancement"
```

---

### Task 9: PipelineView (Kanban — Variant 4)

**Files:**
- Create: `OPS/Views/Pipeline/PipelineTabView.swift`
- Create: `OPS/Views/Pipeline/PipelineView.swift`
- Create: `OPS/Views/Pipeline/OpportunityCard.swift`
- Create: `OPS/Views/Pipeline/PipelineStageStrip.swift`

**Step 1: OpportunityCard**

```swift
// OPS/Views/Pipeline/OpportunityCard.swift
import SwiftUI

struct OpportunityCard: View {
    let opportunity: Opportunity
    let onTap: () -> Void
    let onAdvance: () -> Void
    let onLost: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var showAdvanceConfirm = false

    private var swipeThreshold: CGFloat { 80 }

    var body: some View {
        ZStack {
            // Swipe-right reveal (advance)
            HStack {
                Label("ADVANCE", systemImage: OPSStyle.Icons.stageAdvance)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.black)
                    .padding(.leading, OPSStyle.Layout.spacing3)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.successStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset > 0 ? Double(min(dragOffset / swipeThreshold, 1)) : 0)

            // Swipe-left reveal (lost/flag)
            HStack {
                Spacer()
                Label("LOST", systemImage: OPSStyle.Icons.dealLost)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.trailing, OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset < 0 ? Double(min(-dragOffset / swipeThreshold, 1)) : 0)

            // Card content
            cardContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width > swipeThreshold && !opportunity.stage.isTerminal {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onAdvance()
                            } else if value.translation.width < -swipeThreshold {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onLost()
                            } else {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    private var cardContent: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    if opportunity.isStale {
                        Image(systemName: OPSStyle.Icons.stale)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                    Text(opportunity.contactName.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    if let value = opportunity.estimatedValue {
                        Text(value.formatted(.currency(code: "USD")))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }

                if let desc = opportunity.jobDescription {
                    Text(desc)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                HStack {
                    stageBadge
                    Spacer()
                    Text("[\(opportunity.daysInStage == 1 ? "day 1" : "day \(opportunity.daysInStage)")]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .opsInteractiveCardStyle(cornerRadius: OPSStyle.Layout.cardCornerRadius) {}
        .buttonStyle(PlainButtonStyle())
    }

    private var stageBadge: some View {
        let color = OPSStyle.Colors.pipelineStageColor(for: opportunity.stage)
        return Text(opportunity.stage.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .overlay(
                Capsule().stroke(color, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
```

**Step 2: PipelineStageStrip**

```swift
// OPS/Views/Pipeline/PipelineStageStrip.swift
import SwiftUI

struct PipelineStageStrip: View {
    let stages: [(stage: PipelineStage, count: Int)]
    @Binding var selectedStage: PipelineStage

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(stages, id: \.stage) { item in
                    Button(action: { selectedStage = item.stage }) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Text(item.stage.displayName)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.medium)
                                if item.count > 0 {
                                    Text("·\(item.count)")
                                        .font(OPSStyle.Typography.smallCaption)
                                }
                            }
                            .foregroundColor(
                                selectedStage == item.stage
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                            )

                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(
                                    selectedStage == item.stage
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                                )
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .frame(minWidth: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.4))
        .animation(.easeInOut(duration: 0.2), value: selectedStage)
    }
}
```

**Step 3: PipelineView**

```swift
// OPS/Views/Pipeline/PipelineView.swift
import SwiftUI

struct PipelineView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showNewOpportunitySheet = false
    @State private var selectedOpportunity: Opportunity? = nil
    @State private var showLostSheet = false
    @State private var opportunityToMarkLost: Opportunity? = nil
    @State private var advanceConfirmMessage: String? = nil

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header metrics
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PIPELINE")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text("\(currencyFormatter.string(from: NSNumber(value: viewModel.weightedPipelineValue)) ?? "$0") WEIGHTED · \(viewModel.activeDealsCount) DEALS")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                    // Stage strip
                    PipelineStageStrip(
                        stages: viewModel.stagesWithCounts,
                        selectedStage: $viewModel.selectedStage
                    )

                    Divider()
                        .background(OPSStyle.Colors.separator)

                    // Cards list
                    if viewModel.isLoading && viewModel.opportunities.isEmpty {
                        Spacer()
                        TacticalLoadingBar()  // Use existing loading component
                        Spacer()
                    } else if viewModel.filteredOpportunities.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(viewModel.filteredOpportunities) { opp in
                                    OpportunityCard(
                                        opportunity: opp,
                                        onTap: { selectedOpportunity = opp },
                                        onAdvance: {
                                            Task { await viewModel.advanceStage(opportunity: opp) }
                                        },
                                        onLost: {
                                            opportunityToMarkLost = opp
                                            showLostSheet = true
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .padding(.bottom, 80) // FAB clearance
                        }
                        .refreshable {
                            await viewModel.loadOpportunities()
                        }
                    }
                }

                // FAB
                FloatingActionMenu(
                    items: [
                        .init(label: "New Lead", icon: OPSStyle.Icons.opportunity, action: { showNewOpportunitySheet = true }),
                        .init(label: "Log Activity", icon: OPSStyle.Icons.activityBubble, action: { /* Sprint 2 */ }),
                        .init(label: "Site Visit", icon: OPSStyle.Icons.siteVisitPin, action: { /* Sprint 5 */ })
                    ]
                )
                .padding(OPSStyle.Layout.spacing3)
            }
        }
        .navigationDestination(item: $selectedOpportunity) { opp in
            OpportunityDetailView(opportunity: opp)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showNewOpportunitySheet) {
            OpportunityFormSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showLostSheet) {
            if let opp = opportunityToMarkLost {
                MarkLostSheet(opportunity: opp) { reason in
                    Task { await viewModel.markLost(opportunity: opp, reason: reason) }
                }
            }
        }
        .task {
            if let companyId = appState.company?.id {
                viewModel.setup(companyId: companyId)
                await viewModel.loadOpportunities()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: viewModel.opportunities.isEmpty
                  ? OPSStyle.Icons.pipelineChart
                  : OPSStyle.Icons.filter)
                .font(.system(size: 44))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(viewModel.opportunities.isEmpty ? "NO LEADS YET" : "NO DEALS IN THIS STAGE")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if viewModel.opportunities.isEmpty {
                Text("Create your first lead to get started.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                Button("NEW LEAD") { showNewOpportunitySheet = true }
                    .opsPrimaryButtonStyle()
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
            Spacer()
        }
    }
}
```

**Step 4: PipelineTabView (container with segmented nav)**

```swift
// OPS/Views/Pipeline/PipelineTabView.swift
import SwiftUI

enum PipelineSection: String, CaseIterable {
    case pipeline   = "PIPELINE"
    case estimates  = "ESTIMATES"
    case invoices   = "INVOICES"
    case accounting = "ACCOUNTING"
}

struct PipelineTabView: View {
    @State private var selectedSection: PipelineSection = .pipeline
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control header
            HStack(spacing: 0) {
                ForEach(PipelineSection.allCases, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        VStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .fontWeight(selectedSection == section ? .semibold : .regular)
                                .foregroundColor(
                                    selectedSection == section
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                                )
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(
                                    selectedSection == section
                                    ? OPSStyle.Colors.primaryText
                                    : Color.clear
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(OPSStyle.Colors.background)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(OPSStyle.Colors.separator),
                alignment: .bottom
            )

            // Content
            Group {
                switch selectedSection {
                case .pipeline:   PipelineView().environmentObject(appState)
                case .estimates:  EstimatesListView().environmentObject(appState)   // Sprint 3
                case .invoices:   InvoicesListView().environmentObject(appState)    // Sprint 4
                case .accounting: AccountingDashboard().environmentObject(appState) // Sprint 5
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: selectedSection)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }
}
```

**Step 5: Replace placeholder in tab bar**

Go back to `ContentView.swift`. Replace the placeholder `Text("PIPELINE")` with `PipelineTabView().environmentObject(appState)`.

**Step 6: Build and test in simulator**

Run on iPhone 15 Pro simulator. Confirm:
- Admin role sees 5 tabs, Pipeline tab navigates to PipelineTabView
- Stage strip scrolls horizontally
- Opportunity cards show with correct data
- Swipe right on a card triggers advance (optimistic update visible)
- FAB expands with 3 options

**Step 7: Commit**

```bash
git add OPS/Views/Pipeline/
git commit -m "feat: Pipeline Kanban view with stage strip, opportunity cards, swipe gestures, and FAB"
```

---

### Task 10: OpportunityDetailView

**Files:**
- Create: `OPS/Views/Pipeline/OpportunityDetailView.swift`
- Create: `OPS/Views/Pipeline/ActivityRowView.swift`
- Create: `OPS/Views/Pipeline/FollowUpRowView.swift`
- Create: `OPS/Views/Pipeline/OpportunityFormSheet.swift`
- Create: `OPS/Views/Pipeline/MarkLostSheet.swift`
- Create: `OPS/Views/Pipeline/ActivityFormSheet.swift`

Follow the wireframe in `docs/plans/2026-02-18-ios-major-version-design.md` — Screen 2 spec exactly.

Key implementation notes:
- Use a `@StateObject private var viewModel = OpportunityDetailViewModel()` (create this VM too)
- The three quick-action buttons (CALL / EMAIL / ADVANCE) use `.opsSecondaryButtonStyle()` — NO accent fill
- The segmented control (Activity / Estimates / Invoices) uses the same underline pattern as `PipelineStageStrip`
- Activity rows group into a single `.opsCardStyle()` card with `Divider()` between rows
- System-generated activities (`isSystemGenerated == true`) render in `tertiaryText` instead of `secondaryText`
- FAB expands to: Log Activity / New Estimate / Site Visit

**Commit after completion:**
```bash
git add OPS/Views/Pipeline/
git commit -m "feat: OpportunityDetailView with activity timeline, follow-ups, and tabbed estimates/invoices"
```

---

## Sprint 3 — Estimates

### Task 11: EstimatesListView + EstimateDetailView

**Files:**
- Create: `OPS/Views/Estimates/EstimatesListView.swift`
- Create: `OPS/Views/Estimates/EstimateDetailView.swift`
- Create: `OPS/Views/Estimates/EstimateCard.swift`
- Create: `OPS/ViewModels/EstimateViewModel.swift`

Follow design doc Screen 5 (EstimatesListView) and Screen 6 (EstimateDetailView).

Key notes:
- Filter chips: ALL / DRAFT / SENT / APPROVED — use existing chip/tag styling pattern
- Swipe right on DRAFT card = trigger send flow
- Swipe right on APPROVED card = convert to invoice (calls `EstimateRepository.convertToInvoice`)
- Sticky footer on detail view: button label changes based on status (Send / Approve / Convert)
- `Convert to Invoice` is the ONLY way to create an invoice from an estimate — always calls the Supabase RPC, never manually copies data

**Commit:**
```bash
git add OPS/Views/Estimates/ OPS/ViewModels/EstimateViewModel.swift
git commit -m "feat: EstimatesListView and EstimateDetailView with status-aware actions"
```

---

### Task 12: EstimateFormSheet

**Files:**
- Create: `OPS/Views/Estimates/EstimateFormSheet.swift`
- Create: `OPS/Views/Estimates/LineItemEditSheet.swift`
- Create: `OPS/Views/Estimates/ProductPickerSheet.swift`

Follow design doc Screen 4 (EstimateFormSheet — Variant 4).

Key notes:
- Use existing `StandardSheetToolbar` pattern (Cancel left / TITLE center / Save right)
- Collapsible sections use `▼`/`►` chevrons matching `ProjectFormSheet` pattern
- Sticky footer with running total — use a `VStack` with `Spacer()` + pinned footer
- LINE TOTAL on the line item edit sheet is read-only (server-computed) — use `tertiaryText` + disabled state
- `[+ ADD FROM CATALOG]` opens `ProductPickerSheet` which searches `Product` entities from SwiftData cache
- `SEND ESTIMATE` = `.opsPrimaryButtonStyle()` (white fill, black text) in sticky footer

**Commit:**
```bash
git add OPS/Views/Estimates/EstimateFormSheet.swift OPS/Views/Estimates/LineItemEditSheet.swift OPS/Views/Estimates/ProductPickerSheet.swift
git commit -m "feat: EstimateFormSheet with collapsible sections, line items, and sticky total footer"
```

---

## Sprint 4 — Invoices & Payments

### Task 13: InvoicesListView + InvoiceDetailView + PaymentRecordSheet

**Files:**
- Create: `OPS/Views/Invoices/InvoicesListView.swift`
- Create: `OPS/Views/Invoices/InvoiceDetailView.swift`
- Create: `OPS/Views/Invoices/PaymentRecordSheet.swift`
- Create: `OPS/ViewModels/InvoiceViewModel.swift`

Follow design doc Screens 7.

Key notes:
- Overdue invoices: `errorStatus` badge + due date in `errorStatus` color
- `amountPaid` and `balanceDue` are NEVER updated manually — always re-fetch after recording payment
- Payment amount field pre-fills with `invoice.balanceDue`
- Swipe right on card = opens `PaymentRecordSheet`
- After successful payment record: re-fetch invoice to get DB-trigger-updated balance/status

**Commit:**
```bash
git add OPS/Views/Invoices/
git commit -m "feat: InvoicesListView, InvoiceDetailView, PaymentRecordSheet — invoice lifecycle and payment recording"
```

---

## Sprint 5 — Products, Accounting, Site Visits, Cross-Screen Updates

### Task 14: ProductsListView + ProductFormSheet

**Files:**
- Create: `OPS/Views/Products/ProductsListView.swift`
- Create: `OPS/Views/Products/ProductFormSheet.swift`

Standard list + form sheet pattern. Filter chips: ALL / LABOR / MATERIAL / OTHER.
Deactivating a product sets `is_active = false` — never hard delete (existing line items keep their data).

**Commit:**
```bash
git add OPS/Views/Products/
git commit -m "feat: ProductsListView and ProductFormSheet for service catalog management"
```

---

### Task 15: AccountingDashboard

**Files:**
- Create: `OPS/Views/Accounting/AccountingDashboard.swift`
- Create: `OPS/Network/Supabase/AccountingRepository.swift`

The accounting dashboard is **read-only**. Queries:
1. AR aging buckets — group invoices by `balanceDue > 0` and days since `dueDate`
2. Invoice status counts — group by `status`
3. Top clients by outstanding balance — group by `clientId`, sum `balanceDue`

Use `Recharts`-equivalent in SwiftUI: `Charts` framework (iOS 16+) for the AR aging horizontal bar chart.

```swift
// Aging buckets computed client-side from fetched invoices
struct ARAgingBucket {
    let label: String
    let amount: Double
    let color: Color
}

func computeAgingBuckets(from invoices: [Invoice]) -> [ARAgingBucket] {
    let today = Date()
    var buckets = [(0...30, "0-30d"), (31...60, "31-60d"), (61...90, "61-90d")]
    // ...group by days overdue
}
```

**Commit:**
```bash
git add OPS/Views/Accounting/ OPS/Network/Supabase/AccountingRepository.swift
git commit -m "feat: AccountingDashboard with AR aging chart, invoice status summary, top outstanding clients"
```

---

### Task 16: Update Existing Screens

**Files:**
- Modify: `OPS/Views/JobBoard/ProjectDetailsView.swift` (or wherever project detail is defined)
- Modify: `OPS/Views/JobBoard/TaskDetailsView.swift`
- Modify: `OPS/Views/Schedule/CalendarEventView.swift` (or event rendering code)

**Step 1: Project detail — opportunity badge**

Find the project detail card section. After the existing header content, conditionally add:

```swift
if let oppId = project.opportunityId {
    OpportunityBadgeView(opportunityId: oppId)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
}
```

Create `OpportunityBadgeView` — a small `.opsAccentCardStyle()` row that shows "↑ LINKED OPPORTUNITY" + contact name + stage. Tappable → pushes `OpportunityDetailView`.

**Step 2: Task detail — source attribution**

Find `TaskDetailsView`. Add below the task title/description section:

```swift
if let estimateId = task.sourceEstimateId {
    HStack(spacing: OPSStyle.Layout.spacing2) {
        Image(systemName: OPSStyle.Icons.estimateDoc)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .font(.system(size: 14))
        Text("[AUTO-GENERATED FROM ESTIMATE]")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
        Spacer()
    }
    .padding(.horizontal, OPSStyle.Layout.spacing3)
}
```

This is visible to all roles including Field Crew.

**Step 3: Calendar — site_visit event type**

Find where calendar events are rendered (likely `CalendarEventCard` or similar). Add a branch for `eventType == .siteVisit`:

```swift
// Use siteVisitPin icon instead of task icon
// Use pipelineStageColor(.qualifying) as the event color strip
// Tap action: navigate to SiteVisitDetailView (read-only) instead of TaskDetailsView
```

**Commit:**
```bash
git add OPS/Views/JobBoard/ OPS/Views/Schedule/
git commit -m "feat: add opportunity badge to project detail, task attribution badge, site_visit calendar event type"
```

---

## Sprint 6 — Settings, Polish, Tutorial

### Task 17: Settings — Integrations + Products rows

**Files:**
- Modify: `OPS/Views/Settings/SettingsView.swift`
- Create: `OPS/Views/Settings/IntegrationsSettingsView.swift`

**Step 1: Add new rows to SettingsView**

Find the admin-only section in SettingsView. Add:

```swift
// Admin only
if appState.userRole == .admin {
    NavigationLink(destination: ProductsListView()) {
        SettingsRow(icon: OPSStyle.Icons.productTag,
                    title: "Products & Services",
                    subtitle: "Manage your service catalog")
    }
    NavigationLink(destination: IntegrationsSettingsView()) {
        SettingsRow(icon: OPSStyle.Icons.accountingChart,
                    title: "Integrations",
                    subtitle: "QuickBooks, Sage")
    }
}
```

**Step 2: IntegrationsSettingsView**

Show QuickBooks and Sage connection status. Each uses a `WKWebView` sheet for OAuth. On OAuth redirect callback, store tokens to Supabase `accounting_connections` table via `AccountingRepository`.

**Commit:**
```bash
git add OPS/Views/Settings/
git commit -m "feat: Settings — Products & Services and Integrations rows for admin users"
```

---

### Task 18: Tutorial System Extensions

**Files:**
- Modify: `OPS/Tutorial/TutorialPhaseConfig.swift` (or wherever tutorial phases are defined)
- Create: `OPS/Tutorial/Phases/PipelineTutorialPhase.swift`
- Create: `OPS/Tutorial/Phases/EstimateTutorialPhase.swift`

Add 3 new tutorial phases after the existing 25:
- Phase 26: PIPELINE — "Here's where you manage leads from first contact to closed deal"
- Phase 27: ESTIMATES — "Build a quote on-site and send it to your client in minutes"
- Phase 28: INVOICES — "Convert approved estimates to invoices with one tap — no re-entry"

These phases only trigger for Admin/Office Crew roles. Follow existing phase pattern exactly.

**Commit:**
```bash
git add OPS/Tutorial/
git commit -m "feat: add tutorial phases 26-28 for Pipeline, Estimates, and Invoices"
```

---

### Task 19: Final Polish Pass

**Files:**
- All new view files

**Checklist before this commit:**

- [ ] All new text uses `OPSStyle.Typography` — no `.font(.system(size:))`
- [ ] All new colors use `OPSStyle.Colors` — no hardcoded hex
- [ ] All titles UPPERCASE (`.textCase(.uppercase)` or explicit uppercased strings)
- [ ] All captions/metadata wrapped in `[square brackets]`
- [ ] All touch targets ≥ 56pt
- [ ] `.accessibilityLabel()` on all icon-only buttons
- [ ] Offline state handled on all Supabase-fetching views
- [ ] Empty states on all list views (first-time + filtered-empty variants)
- [ ] Pull-to-refresh on all list views (`.refreshable {}`)
- [ ] Error toast shown on all failed async operations
- [ ] `TacticalLoadingBar` shown during initial load
- [ ] `.padding(.bottom, 80)` on scroll views to clear FAB
- [ ] `FloatingActionMenu` only shows on Pipeline tab (not nested detail screens)

**Commit:**
```bash
git add .
git commit -m "polish: accessibility, empty states, offline handling, touch targets — iOS major version"
```

---

### Task 20: Integration Test Pass

**Manual test script:**

1. Sign in as Admin → confirm 5 tabs
2. Sign in as Field Crew → confirm 4 tabs, no Pipeline visible
3. Create new opportunity → appears in NEW LEAD stage
4. Swipe card right → advances to QUALIFYING with toast confirmation
5. Open opportunity detail → activity timeline shows stage change
6. Log a Note activity → appears at top of timeline
7. Create estimate from opportunity → line items, totals calculate correctly
8. Add line item from catalog → pre-fills from Product data
9. Send estimate → status changes to SENT
10. Approve estimate → Convert to Invoice button appears
11. Convert to Invoice → invoice created, estimate marked CONVERTED
12. Record payment → invoice balance reduces, status changes correctly
13. Go to Accounting → AR aging chart shows outstanding balance
14. Go to Settings → Products & Services and Integrations rows visible
15. Go to existing project that has `opportunityId` → opportunity badge shows
16. Go to task with `sourceEstimateId` → attribution badge shows
17. Open calendar → site_visit event type renders with pin icon
18. Sign in as Field Crew → open a task with sourceEstimateId → attribution badge visible

**Commit after all tests pass:**
```bash
git commit -m "test: manual integration test pass — iOS major version complete"
```

---

## Appendix: Key Decisions

| Decision | Rationale |
|---|---|
| supabase-swift direct | No proxy latency, real-time possible later, same auth pattern as web |
| Firebase JWT bridge | Zero user migration, auth stays on Bubble/Firebase, Supabase RLS just validates the JWT |
| SwiftData for Supabase models | Same caching pattern as Bubble data — local-first, sync in background |
| Invoice balance is DB-read-only | Supabase trigger maintains balance — NEVER update manually or data diverges |
| Convert-to-invoice via RPC only | Atomic at DB level — no race conditions, no partial invoice creation |
| White primary button | Preserves accent scarcity — accent on FAB + stage strip is already two uses per screen |
| Field crew sees task attribution | Low noise, high value — knowing a task came from an estimate is useful context for field workers |
| Products in Settings (not Pipeline tab) | Settings = configuration, not workflow — keeps Pipeline tab lean |
