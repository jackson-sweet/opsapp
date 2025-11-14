# Stripe Price ID Configuration Guide

## Current Issue
Your app is using **test mode** Stripe price IDs but Bubble is configured with **live mode** Stripe keys.

## How to Fix

### Option 1: For Testing (Recommended)
Switch Bubble to test mode:
1. Go to Bubble editor → Plugins → Stripe.js 3
2. Click on the plugin settings
3. Replace the live keys with test keys:
   - Use your Stripe **test** publishable key
   - Use your Stripe **test** secret key
4. Save and deploy to test

### Option 2: For Production
Get your live price IDs from Stripe:

1. Go to [Stripe Dashboard](https://dashboard.stripe.com)
2. Make sure you're in **Live Mode** (toggle in top right)
3. Go to Products → Click on each product
4. Find the Price IDs for each plan:

#### Starter Plan ($90/month, $864/year)
- Monthly price ID: `price_1S6Jz1EooJoYGoIwDwx7dQHJ` 
- Annual price ID: `price_1S6Jz1EooJoYGoIwiGXZJ2a7`

#### Team Plan ($140/month, $1344/year)  
- Monthly price ID: `price_1S6Jz6EooJoYGoIwRoQIstPk`
- Annual price ID: `price_1S6Jz6EooJoYGoIwQSRdxhRs`

#### Business Plan ($190/month, $1824/year)
- Monthly price ID: `price_1S6Jz8EooJoYGoIw9u8cb3lx`
- Annual price ID: `price_1S6Jz8EooJoYGoIwB2IUeC6z`

5. Update `/OPS/DataModels/SubscriptionEnums.swift` with the live price IDs:

```swift
case .starter:
    return ("price_live_xxxxx", "price_live_xxxxx")
case .team:
    return ("price_live_xxxxx", "price_live_xxxxx")
case .business:
    return ("price_live_xxxxx", "price_live_xxxxx")
```

## Testing Tips

- Use Stripe test cards: `4242 4242 4242 4242`
- Test both monthly and annual billing
- Verify the webhook endpoints work correctly

## Important Note
Never mix test and live modes - both your iOS app and Bubble backend must use the same mode (either both test or both live).
