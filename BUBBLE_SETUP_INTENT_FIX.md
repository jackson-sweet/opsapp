# Bubble Setup Intent Customer Association Fix

## Problem
When users try to use a saved payment method, Stripe returns an error:
```
The payment method supplied (pm_xxx) belongs to the Customer cus_xxx. 
Please include the Customer in the 'customer' parameter on the SetupIntent.
```

## Root Cause
The SetupIntent is being created without being attached to the customer that owns the saved payment methods.

## Solution for Bubble Workflow `create_setup_intent`

### Current Flow (Problematic)
1. Create/retrieve Stripe customer for company
2. Create SetupIntent (WITHOUT customer attached)
3. Return customer_id and setup_intent_client_secret separately

### Required Flow (Fixed)
1. Create/retrieve Stripe customer for company
2. Create SetupIntent WITH customer parameter:
   ```javascript
   stripe.setupIntents.create({
     customer: customer_id,  // CRITICAL: Attach the customer
     payment_method_types: ['card'],
     usage: 'off_session',   // For future charges
     metadata: {
       company_id: company_id,
       price_id: price_id
     }
   })
   ```
3. Create ephemeral key for the customer
4. Return all three: customer_id, ephemeral_key, setup_intent_client_secret

## Bubble Workflow Steps

### Step 1: Get or Create Customer
- Check if Company has `stripe_customer_id` field
- If exists: Retrieve the customer from Stripe
- If not: Create new customer with:
  - email: Company's primary user email
  - name: Company name
  - metadata: { company_id: company_id }
- Save the customer ID to Company's `stripe_customer_id` field

### Step 2: Create Setup Intent
**CRITICAL**: Include the customer parameter when calling Stripe API
```javascript
// This is what needs to happen in Bubble's Stripe plugin
const setupIntent = await stripe.setupIntents.create({
  customer: customer_id,  // THIS IS THE CRITICAL MISSING PART
  payment_method_types: ['card'],
  usage: 'off_session',
  metadata: {
    company_id: company_id,
    price_id: price_id
  }
});
```

In Bubble's Stripe Plugin:
- Action: Create a SetupIntent
- **Customer ID**: [Result of Step 1's customer_id] ← THIS FIELD MUST BE SET
- Payment Method Types: card
- Usage: off_session
- Metadata: { company_id: [company_id], price_id: [price_id] }

### Step 3: Create Ephemeral Key
```
Action: Stripe - Create Ephemeral Key
Parameters:
  - customer: Result of Step 1's customer_id
  - stripe_version: '2023-10-16' (or latest)
```

### Step 4: Return Response
```json
{
  "status": "success",
  "response": {
    "client_secret": [SetupIntent's client_secret from Step 2],
    "customer_id": [Customer ID from Step 1],
    "ephemeral_key": [Ephemeral key from Step 3],
    "setup_intent_id": [SetupIntent ID from Step 2],
    "payment_required": true
  }
}
```

## Testing
1. User with saved payment methods should be able to select them
2. New users should be able to add new payment methods
3. The SetupIntent should complete successfully in both cases

## Note for `complete_subscription` Workflow
After the SetupIntent is confirmed:
1. Retrieve the SetupIntent to get the payment_method
2. Attach the payment_method as the default for the customer
3. Create the subscription with the customer and default payment method