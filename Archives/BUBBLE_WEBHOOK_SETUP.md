# Bubble Webhook Setup for iOS Subscription Integration

## Required API Workflows

### 1. create_subscription_with_payment
**Endpoint**: `/wf/create_subscription_with_payment`
**Method**: POST
**Authentication**: Bearer token

**Input Parameters**:
- `price_id` (text): Stripe price ID for the selected plan
- `company_id` (text): Company's unique ID

**Workflow Actions**:
1. **Subscribe user to plan** (Stripe plugin action)
   - Customer: Current Company's stripe_customer_id (or create new if empty)
   - Price: price_id parameter
   - Payment behavior: `allow_incomplete`
   - Metadata: 
     - company_id: company_id parameter
     - user_id: Current User's unique ID
     - platform: "ios"

2. **Create ephemeral key** (Stripe API Connector)
   - Customer: Result of step 1's customer_id
   - API Version: "2023-10-16"

3. **Return data** (Return JSON)
   ```json
   {
     "status": "success",
     "subscription_id": "Result of step 1's subscription_id",
     "client_secret": "Result of step 1's latest_invoice's payment_intent's client_secret", <- THIS IS NOT AVAILABLE FROM ANY OF THE STEPS
     "ephemeral_key": "Result of step 2's ephemeral_key",
     "customer_id": "Result of step 1's customer_id"
   }
   ```

**Error Handling**:
- If any step fails, return:
  ```json
  {
    "status": "error",
    "error": "Error message description"
  }
  ```
  -> WE CANNOT CATCH ERRORS IN BUBBLE WORKFLOWS. BUBBLE WILL AUTOMATICALLY RETURN ERROR IF ONE HAPPENS

### 2. update_subscription_seats
**Endpoint**: `/wf/update_subscription_seats`
**Method**: POST
**Authentication**: Bearer token

**Input Parameters**:
- `company_id` (text): Company's unique ID
- `user_ids` (list of text): List of user IDs to seat
NOTE: MAKE SURE WE INCLUDE ACCOUNT HOLDER'S USER ID ALWAYS IN THIS LIST

**Workflow Actions**:
1. **Make changes to Company**
   - Company: Search for Company by ID
   - Fields to change:
     - seated_employee_ids: user_ids parameter (joined with commas)

2. **Return data**
   ```json
   {
     "status": "success",
     "seated_count": "Count of user_ids",
     "max_seats": "Company's max_seats"
   }
   ```

### 3. cancel_subscription
**Endpoint**: `/wf/cancel_subscription`
**Method**: POST
**Authentication**: Bearer token

**Input Parameters**:
- `company_id` (text): Company's unique ID
- `reason` (text, optional): Cancellation reason
- 'cancelPriority' (bool): cancel priority support also? Yes/No
- 'plan' (subscriptionPlan, list): the company's subscriptionPlans to be cancelled (would be the value in company.subscriptionPlan, plus 'priority' if they want to cancel that too, or just priority)

**Workflow Actions**:
1. **Cancel subscription** (Stripe plugin action)
   - Subscription: Company's stripe_subscription_id
   - Cancel at period end: Yes

2. **Make changes to Company**
   - Fields to change:
     - subscription_status: "cancelled"
     - cancellation_reason: reason parameter
     - cancellation_date: Current date/time

3. **Return data**
   ```json
   {
     "status": "success",
     "effective_date": "Subscription's current_period_end"
   }
   ```

### 4. reactivate_subscription
**Endpoint**: `/wf/reactivate_subscription`
**Method**: POST
**Authentication**: Bearer token

**Input Parameters**:
- `company_id` (text): Company's unique ID

**Workflow Actions**:
1. **Update subscription** (Stripe plugin action)
   - Subscription: Company's stripe_subscription_id
   - Cancel at period end: No

2. **Make changes to Company**
   - Fields to change:
     - subscription_status: "active"
     - cancellation_reason: empty
     - cancellation_date: empty

3. **Return data**
   ```json
   {
     "status": "success",
     "subscription_id": "Company's stripe_subscription_id"
   }
   ```

## Stripe Webhook Handler

### stripe_webhook
**Endpoint**: `/wf/stripe_webhook`
**Method**: POST
**Authentication**: Stripe webhook signature

**Events to Handle**:

1. **customer.subscription.created**
   - Find Company by stripe_customer_id
   - Update Company:
     - stripe_subscription_id: event.data.object.id
     - subscription_status: "active"
     - subscription_start_date: event.data.object.current_period_start

2. **customer.subscription.updated**
   - Find Company by stripe_subscription_id
   - Update Company based on status:
     - If status = "active": subscription_status = "active"
     - If status = "past_due": subscription_status = "grace"
     - If status = "canceled": subscription_status = "expired"

3. **invoice.payment_succeeded**
   - Find Company by stripe_customer_id
   - Update Company:
     - last_payment_date: current date/time
     - next_billing_date: event.data.object.period_end

4. **invoice.payment_failed**
   - Find Company by stripe_customer_id
   - Update Company:
     - subscription_status: "grace"
     - grace_period_end: current date + 7 days NOTE THERE IS NO grace_period_end FIELD. WE HAVE A RECURRING WORKFLOW SETUP TO CHECK EXPIRED GRACE PERIODS AND SET PLAN STATUS TO EXPIRED ACCORDINGLY.

## Troubleshooting Return Data Issues

### Common Problem: Empty Response from "Return data from API" Action

**Symptoms**: 
- Bubble workflow runs successfully
- All actions appear to complete
- API response returns `{"status": "success", "response": {}}` instead of expected data

**Root Cause**: 
The "Return data from API" action in Bubble requires specific configuration and field reference syntax. Common mistakes include:

1. **Incorrect Field References**: Using incomplete dynamic expressions
2. **Wrapper Objects**: Adding unnecessary status/response wrappers
3. **Missing Data Validation**: Not checking if previous steps actually returned data

### Fix 1: Correct Field Reference Syntax

**WRONG**:
```json
{
  "subscription_id": "Step 1 - Subscribe user to plan"
}
```

**CORRECT**:
```json
{
  "subscription_id": "Step 1 - Subscribe user to plan's subscription id"
}
```

**Key Points**:
- Always specify the exact field after the step name
- Use apostrophe + s + field name: `Step X's field_name`
- For nested objects: `Step X's object's nested_field`

### Fix 2: Raw JSON Return (No Status Wrapper)

**WRONG** (Double-wrapped response):
```json
{
  "status": "success", 
  "response": {
    "subscription_id": "...",
    "client_secret": "..."
  }
}
```

**CORRECT** (Direct object return):
```json
{
  "subscription_id": "Step 1 - Subscribe user to plan's subscription id",
  "client_secret": "Step 1 - Subscribe user to plan's latest invoice's payment intent's client secret",
  "ephemeral_key": "Step 2 - Create ephemeral key's ephemeral key",
  "customer_id": "Step 1 - Subscribe user to plan's customer id"
}
```

### Fix 3: Data Validation Before Return

**Add a condition before the Return Data action**:
- Only when: `Step 1 - Subscribe user to plan's subscription id is not empty`
- This prevents returning data when the Stripe action fails silently

### Fix 4: Test Individual Step Outputs

**Debugging Steps**:
1. Add temporary "Return data" actions after each step to verify output
2. Check Bubble logs for each workflow step
3. Use Bubble's step-by-step debugger in the workflow editor
4. Verify Stripe plugin is properly configured with correct API keys

### Fix 5: Handle Missing Client Secret

**Issue**: `latest_invoice's payment_intent's client_secret` may not exist for some subscription types

**Solution**: Add conditional logic or use alternative approach:
```json
{
  "client_secret": "Step 1 - Subscribe user to plan's latest invoice's payment intent's client secret OR Step 1 - Subscribe user to plan's pending setup intent's client secret"
}
```

### Testing Workflow Data

1. **Enable detailed logging** in Bubble workflow settings
2. **Add debug Return actions** after each step temporarily
3. **Check server logs** for API call details
4. **Use Stripe dashboard** to verify subscription creation
5. **Test with simple static values** first, then add dynamic references

### Common Bubble Field Reference Patterns

```
Stripe Subscription Object:
- subscription_id: "Step X's subscription id"
- customer_id: "Step X's customer id" 
- status: "Step X's status"

Stripe Invoice Object:
- invoice_id: "Step X's latest invoice's id"
- amount: "Step X's latest invoice's amount due"

Stripe Payment Intent:
- client_secret: "Step X's latest invoice's payment intent's client secret"
- payment_method: "Step X's latest invoice's payment intent's payment method"

API Connector Responses:
- ephemeral_key: "Step X's body ephemeral key" (if API returns nested JSON)
- raw_response: "Step X" (entire response object)
```

## Implementation Notes

1. **API Connector Setup**:
   - Add Stripe API if not already configured
   - Base URL: `https://api.stripe.com/v1`
   - Authentication: Bearer token with Stripe secret key

2. **Webhook Security**:
   - Verify Stripe webhook signatures
   - Store webhook endpoint secret in Bubble settings
   - Validate events are from Stripe before processing

3. **Error Handling**:
   - Log all webhook events to a Webhook_Log data type
   - Include timestamp, event type, and processing status
   - Send alert emails for critical failures

4. **Testing**:
   - Use Stripe CLI for local webhook testing
   - Test with Stripe test mode first
   - Verify all subscription states are handled correctly
