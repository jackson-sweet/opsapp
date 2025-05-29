#!/bin/bash

# Test the update_company API endpoint to see the actual response format

API_TOKEN="Bearer 411e2fb2b82c4c3fb088cd5b21b42d2f"
BASE_URL="https://thebubbleapp.bubbleapps.io/version-test/api/1.1/wf/update_company"

# Test parameters - replace with actual test data
NAME="Test Company"
EMAIL="test@company.com"
PHONE="555-1234"
INDUSTRY="Construction"
SIZE="10-20"
AGE="5+"
ADDRESS="123 Test St"
USER_ID="1733589251072x373475162598596900"  # Replace with a valid user ID from your testing

echo "Testing update_company API endpoint..."
echo "=================================="

# Make the API call
RESPONSE=$(curl -s -X POST "$BASE_URL" \
  -H "Authorization: $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$NAME"'",
    "email": "'"$EMAIL"'",
    "phone": "'"$PHONE"'",
    "industry": "'"$INDUSTRY"'",
    "size": "'"$SIZE"'",
    "age": "'"$AGE"'",
    "address": "'"$ADDRESS"'",
    "user": "'"$USER_ID"'"
  }')

echo "Raw Response:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

echo ""
echo "Response Analysis:"
echo "=================="

# Check if response contains 'company' field
if echo "$RESPONSE" | jq -e '.company' >/dev/null 2>&1; then
    echo "✓ Found 'company' field"
    COMPANY_TYPE=$(echo "$RESPONSE" | jq -r 'type(.company)')
    echo "  - Type: $COMPANY_TYPE"
    
    if [ "$COMPANY_TYPE" = "string" ]; then
        COMPANY_ID=$(echo "$RESPONSE" | jq -r '.company')
        echo "  - Company ID (string): $COMPANY_ID"
    elif [ "$COMPANY_TYPE" = "object" ]; then
        echo "  - Company object fields:"
        echo "$RESPONSE" | jq '.company | keys[]' 2>/dev/null | sed 's/^/    - /'
    fi
else
    echo "✗ No 'company' field found"
fi

# Check other fields
echo ""
echo "Other fields in response:"
echo "$RESPONSE" | jq -r 'keys[]' 2>/dev/null | grep -v '^company$' | sed 's/^/  - /'