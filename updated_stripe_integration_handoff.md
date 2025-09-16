# OPS App - Stripe Subscription Integration Handoff Document

**Implementation Status**: Backend Complete ✅ | iOS Implementation Required ⚠️  
**Last Updated**: January 2025  
**Handoff to**: Claude Code for iOS Implementation

## Executive Summary

This document outlines the completed Stripe subscription system for the OPS app. The Bubble backend and Stripe webhook integration are fully configured and tested. The iOS app requires implementation of the subscription management interface and access control enforcement.

## Business Model Overview

### Subscription Plans
- **Trial**: 30 days, 10 seats, full functionality
- **Starter**: $90/month or $864/year, 3 seats
- **Team**: $140/month or $1,344/year, 5 seats  
- **Business**: $190/month or $1,824/year, 10 seats

### Add-on Services
- **Priority Support**: $57/month flat rate (available for all plans)
- **OPS Turnkey Setup**: $399 one-time data migration service

### Key Business Rules
- All plans have identical features - only seat count differs
- Trial provides business-level functionality (10 seats) for evaluation
- Annual billing provides 20% discount
- Priority support available for all plans (not just Team/Business)
- Data migration is separate one-time purchase, available anytime
- Hard lockout when trial expires or subscription fails
- 7-day grace period for payment failures
- Data preserved during lockouts

## Data Structure - Bubble Implementation

### Company Data Type - Subscription Fields

**Core Subscription Management:**
- `subscriptionStatus` (subscriptionStatus option set): "trial" | "active" | "grace" | "expired" | "cancelled"
- `subscriptionPlan` (subscriptionPlan option set): "trial" | "starter" | "team" | "business"
- `subscriptionEnd` (date): When current billing period ends
- `subscriptionPeriod` (PaymentSchedule option set): "Monthly" | "Annual"

**Seat Management:**
- `maxSeats` (number): Maximum allowed seats based on plan
- `seatedEmployees` (List of Users): Users with app access
- `seatGraceStartDate` (date): When grace period for over-limit seats began

**Trial Management:**
- `trialStartDate` (date): When trial began  
- `trialEndDate` (date): When trial expires (30 days from start)

**Add-on Services:**
- `hasPrioritySupport` (yes/no): Boolean flag for priority support
- `dataSetupPurchased` (yes/no): Boolean flag for turnkey setup purchase
- `dataSetupCompleted` (yes/no): Boolean flag for completed migration
- `dataSetupScheduledDate` (date): Scheduled consultation date

**Stripe Integration:**
- `stripeCustomerId` (text): Stripe customer ID for API calls
- `stripeHold` (text): Used for payment processing states

**QuickBooks Integration (Future):**
- `qbConnected` (yes/no): QuickBooks connection status
- `qbAccessToken` (text): QB API access token
- `qbRefreshToken` (text): QB API refresh token  
- `qbCompanyId` (text): QuickBooks company identifier

### subscriptionPlan Option Set

**Options:** trial, starter, team, business, priority, setup

**Note:** Companies only use "trial", "starter", "team", "business". The "priority" and "setup" options exist for display purposes in the Bubble web app.

**Attributes:**
- `annualPrice` (number): Annual subscription cost in cents
- `Features` (List of texts): Multiline feature descriptions
- `maxSeats` (number): Maximum seats for this plan
- `monthlyPrice` (number): Monthly subscription cost in cents
- `onetimePrice` (number): One-time service cost in cents
- `priceId.annual` (text): Stripe price ID for annual billing
- `priceId.monthly` (text): Stripe price ID for monthly billing
- `priceId.once` (text): Stripe price ID for one-time payments
- `Display` (text): Plan name for UI display

### subscriptionStatus Option Set

**Options:** trial, active, grace, expired, cancelled

**Usage:**
- `trial`: Company in 30-day trial period
- `active`: Valid paid subscription
- `grace`: Payment failed, 7-day grace period active
- `expired`: Grace period ended, access blocked
- `cancelled`: User-initiated cancellation

## Stripe Configuration

### Test Environment Products

**OPS Starter Test** (prod_T0VVmmCWngCeQw)
- Monthly: price_1S4UVEEooJoYGoIwIGvWfSd5 ($90)
- Annual: price_1S4UVJEooJoYGoIwm11ItaKw ($864)
- Metadata: planType = "starter"

**OPS Team Test** (prod_T0VWCM7mcyCTuc)
- Monthly: price_1S4UVyEooJoYGoIwydDGa3jG ($140)
- Annual: price_1S4UVyEooJoYGoIw3aKrVfjQ ($1,344)
- Metadata: planType = "team"

**OPS Business Test** (prod_T0VWPFUuQ0Qe7y)
- Monthly: price_1S4UW4EooJoYGoIwkgk4d8ph ($190)
- Annual: price_1S4UW4EooJoYGoIwaCxXWwUD ($1,824)
- Metadata: planType = "business"

**Priority Support** (add-on for all plans)
- Monthly: price_1S6K5WEooJoYGoIwNU0ZzLmh ($57)

**OPS Turnkey Setup** (one-time service)
- One-time: price_1S6K4WEooJoYGoIwNU0ZzLmh ($399)

### Live Environment Products

**OPS STARTER** (prod_T0CVPIGj4msT8L)
- Monthly: price_1S4C6DEooJoYGoIwhh9HFAfq (CAD $90)
- Annual: price_1S4CElEooJoYGoIwdZ9t6NgL (CAD $864)

**OPS TEAM** (prod_T0CWrBsYiU9siP)
- Monthly: price_1S4C7mEooJoYGoIwwY73nk7m (CAD $140)
- Annual: price_1S4CFkEooJoYGoIwfERwlayD (CAD $1,344)

**OPS BUSINESS** (prod_T0CZkEeSQDdTG6)
- Monthly: price_1S4CA7EooJoYGoIwh13eiY3h (CAD $190)
- Annual: price_1S4CGeEooJoYGoIwnaiXbJZU (CAD $1,824)

## Bubble Webhook Workflows

### Webhook Endpoint Configuration
- **Development**: `https://opsapp.bubbleapps.io/version-test/api/1.1/wf/stripe-webhook`
- **Production**: `https://opsapp.bubbleapps.io/api/1.1/wf/stripe-webhook`

### Workflow: customer.subscription.created

**Trigger**: New subscription created in Stripe

**Logic:**
1. Search for Company where stripeCustomerId = webhook data customer ID
2. Set subscriptionStatus = "active"
3. Extract planType from price metadata to set subscriptionPlan
4. Update maxSeats based on plan
5. Clear trial dates (trialStartDate, trialEndDate)
6. Check for Priority Support in subscription items
7. If Priority Support found: set hasPrioritySupport = true

**Plan Identification:**
```
If price metadata planType = "starter" → subscriptionPlan = "starter", maxSeats = 3
If price metadata planType = "team" → subscriptionPlan = "team", maxSeats = 5  
If price metadata planType = "business" → subscriptionPlan = "business", maxSeats = 10
```

**Priority Support Detection:**
```
If subscription items contain price_1S6K5WEooJoYGoIwNU0ZzLmh → hasPrioritySupport = true
```

### Workflow: customer.subscription.updated

**Trigger**: Subscription modified (plan changes, add-ons)

**Logic:**
1. Search for Company where stripeCustomerId = webhook data customer ID
2. Update subscriptionPlan based on new price metadata
3. Update maxSeats based on new plan
4. Check if company now exceeds seat limit
5. If over limit: set seatGraceStartDate = current date
6. Update Priority Support status based on subscription items

### Workflow: customer.subscription.deleted

**Trigger**: Subscription cancelled in Stripe

**Logic:**
1. Search for Company where stripeCustomerId = webhook data customer ID
2. Set subscriptionStatus = "cancelled"
3. Set hasPrioritySupport = false (priority support ends with subscription)

### Workflow: invoice.payment_succeeded

**Trigger**: Successful payment processed

**Logic:**
1. Search for Company where stripeCustomerId = webhook data customer ID
2. Set subscriptionStatus = "active"
3. Clear seatGraceStartDate (grace period ends)
4. Check if payment was for one-time Turnkey Setup service
5. If Turnkey Setup: set dataSetupPurchased = true
6. Send notification emails for Turnkey Setup purchases

**Turnkey Setup Detection:**
```
If invoice line item price_id = "price_1S6K4WEooJoYGoIwNU0ZzLmh" → dataSetupPurchased = true
```

### Workflow: invoice.payment_failed

**Trigger**: Payment failed or declined

**Logic:**
1. Search for Company where stripeCustomerId = webhook data customer ID
2. Set subscriptionStatus = "grace"
3. Set seatGraceStartDate = current date (starts 7-day grace period)

## Email Notification System

### Ops Contacts Configuration
Bubble uses "Ops Contacts" data type for notification routing:

**Priority Support Contacts:**
- Receives notifications when Priority Support is purchased
- Includes company details and admin contact info

**Data Setup Contacts:**
- Receives notifications when Turnkey Setup is purchased
- Includes company details for consultation scheduling

### Automated Email Triggers

**Priority Support Purchase:**
- **To**: Ops Contacts (Priority Support)
- **Subject**: "New Priority Support Customer"
- **Content**: Company name, admin email, phone, plan type

**Turnkey Setup Purchase:**
- **To Admin**: Ops Contacts (Data Setup)
- **Subject**: "New OPS Turnkey Setup Purchase"  
- **Content**: Company details, contact information

- **To Customer**: Company admin email
- **Subject**: "Your OPS Turnkey Setup - Next Steps"
- **Content**: Service expectations, timeline, contact process

## Access Control Logic

### Seat Assignment Rules
- New users automatically assigned seats when joining (if available)
- Seat limits: Trial=10, Starter=3, Team=5, Business=10
- Account holders (userType="company") protected from auto-removal
- When over limit: 7-day grace period to manually remove users
- After grace: oldest users (by creation date) auto-removed

### Access Blocking Conditions
1. **Trial Expired**: trialEndDate < current date AND subscriptionPlan = "trial"
2. **Subscription Expired**: subscriptionStatus = "expired"
3. **Subscription Cancelled**: subscriptionStatus = "cancelled"
4. **Payment Grace Period**: subscriptionStatus = "grace" (warning only, no block)
5. **No Seat Available**: user not in seatedEmployees array

### Grace Period Behavior
- **Duration**: 7 days from seatGraceStartDate
- **Access**: Full app access continues
- **Warnings**: Display banner on every app launch
- **Auto-Resolution**: Remove oldest non-admin users after 7 days
- **Manual Resolution**: Admin removes users or upgrades plan

## Trial Management

### Trial Creation
- **Duration**: 30 days from company creation
- **Seats**: 10 (business-level functionality)
- **Setup**: trialStartDate = company creation, trialEndDate = +30 days
- **Status**: subscriptionStatus = "trial", subscriptionPlan = "trial"

### Trial Expiration
- **Hard Cutoff**: No app access when trialEndDate reached
- **Data Preservation**: All projects, photos, team data retained
- **Recovery**: Immediate restoration upon plan purchase
- **UI**: Plan selection screen with Apple Pay + card options

### Trial Notifications
- **7 Days Before**: "Trial ending soon" banner
- **3 Days Before**: "3 days left" notification
- **1 Day Before**: "Last day" warning
- **Expired**: "Trial expired, choose plan" lockout

## iOS Implementation Requirements

### Subscription Management Features Required
- Plan selection with monthly/annual toggle
- Apple Pay and credit card payment options
- Seat management (admin only)
- Team member termination flow
- Grace period warning system
- Trial countdown display
- Lockout screens with contextual messaging
- Priority support toggle
- Turnkey setup purchase option

### Access Control Integration
- Check subscription status on app launch
- Validate user seat assignment
- Block access for expired/cancelled subscriptions
- Show appropriate warnings during grace periods
- Cache subscription state for offline operation

### Admin-Only Features
- Add/remove team members
- View billing information
- Purchase add-on services
- Manage seat allocation
- Access termination controls

### User Experience Requirements
- Seamless trial-to-paid conversion
- Clear messaging about seat limits
- Context-aware lockout screens
- Grace period warnings on every launch
- Data safety reassurance during lockouts

## Testing & Validation

### Backend Testing Completed
- All webhook events tested in Stripe test mode
- Company data updates verified for each scenario
- Email notifications configured and tested
- Metadata extraction working correctly
- Grace period logic validated

### iOS Testing Required
- Plan purchase flow (Apple Pay + card)
- Seat limit enforcement
- Trial expiration handling
- Grace period warnings
- Payment failure recovery
- Access control validation
- Offline state management

## Business Logic Summary

### Key Principles
1. **Seat-based pricing**: Plans differ only in seat count, not features
2. **Trial generosity**: Full business functionality during 30-day trial
3. **Data safety**: Never lose user data during lockouts
4. **Grace periods**: 7-day buffer for payment issues and seat overages
5. **Admin protection**: Account holders cannot be auto-removed
6. **Immediate activation**: Plan purchases restore access instantly
7. **Flexible add-ons**: Priority support and setup services available separately

### State Transitions
```
New Company → Trial (30 days, 10 seats)
Trial Expires → Plan Selection Required → Hard Lockout
Plan Purchase → Active Subscription → Full Access
Payment Fails → Grace Period → Warnings + Full Access
Grace Expires → Hard Lockout → Plan Selection Required
Manual Cancel → Cancelled → Hard Lockout
Seat Overage → Seat Grace Period → Auto-removal or Manual Fix
```

This system provides enterprise-grade subscription management while maintaining the OPS philosophy of being "invisible until it matters" - users only encounter subscription UI when action is required.