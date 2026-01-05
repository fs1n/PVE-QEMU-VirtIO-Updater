function notification_send() {
    # Todo: Implement notification logic here
}

function notification_email_SMTP() {
    # Todo: Implement email notification logic here
}

function notification_email_MSGRAPH() {
    # Config variables
    TENANT_ID="<your tenant id>"
    CLIENT_ID="<your application (client) id>"
    CERT_THUMBPRINT="<your certificate thumbprint>"
    CERT_PATH="./private.key"
    USER_TO_SEND_FROM="sender@yourdomain.com"
    USER_TO_SEND_TO="recipient@yourdomain.com"

    # Current time and expiration time for JWT
    NOW=$(date +%s)
    EXP=$((NOW+3600))

    # Build JWT header and payload
    HEADER='{"alg":"RS256","typ":"JWT","x5t":"'"$CERT_THUMBPRINT"'"}'
    PAYLOAD='{
      "aud": "https://login.microsoftonline.com/'$TENANT_ID'/v2.0",
      "iss": "'$CLIENT_ID'",
      "sub": "'$CLIENT_ID'",
      "jti": "'"$(uuidgen)"'",
      "nbf": '$NOW',
      "exp": '$EXP'
    }'

    # Base64 encode header and payload
    header_base64=$(echo -n "$HEADER" | openssl base64 -e | tr -d '\n=' | tr + - | tr / _)
    payload_base64=$(echo -n "$PAYLOAD" | openssl base64 -e | tr -d '\n=' | tr + - | tr / _)
    jwt_unsigned="$header_base64.$payload_base64"

    # Sign JWT with your private key (PKCS8)
    signature=$(echo -n "$jwt_unsigned" | openssl dgst -sha256 -sign "$CERT_PATH" | openssl base64 -e | tr -d '\n=' | tr + - | tr / _)
    JWT="$jwt_unsigned.$signature"

    # Request access token
    TOKEN_RESP=$(curl -s -X POST \
      "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
      -d "client_id=$CLIENT_ID" \
      -d "scope=https://graph.microsoft.com/.default" \
      -d "grant_type=client_credentials" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
      --data-urlencode "client_assertion=$JWT")

    ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r .access_token)

    # Prepare email body
    read -r -d '' EMAIL_JSON << EOM
    {
      "message": {
        "subject": "Test Email from Bash Script via Graph API",
        "body": {
          "contentType": "Text",
          "content": "This is a test email sent from a bash script using Microsoft Graph!"
        },
        "toRecipients": [
          {
            "emailAddress": {
              "address": "$USER_TO_SEND_TO"
            }
          }
        ]
      },
      "saveToSentItems": "false"
    }
    EOM

    # Send email using Microsoft Graph API
    curl -X POST \
      "https://graph.microsoft.com/v1.0/users/$USER_TO_SEND_FROM/sendMail" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$EMAIL_JSON"
}

function notification_webhook() {
    # Todo: Implement webhook notification logic here
}
