# OAuth/Entra ID Setup for API Management

This guide covers configuring Azure API Management with OAuth 2.0 and Microsoft Entra ID (Azure AD) for API authentication.

## Overview

APIM supports OAuth 2.0 for protecting APIs. This guide covers:
1. Registering an Entra ID application for your API
2. Configuring APIM OAuth 2.0 authorization server
3. Applying JWT validation policies
4. Testing authenticated API calls

## Prerequisites

- Azure API Management deployed
- Azure subscription with Entra ID (Azure AD) access
- Global Administrator or Application Administrator role for app registrations

## Step 1: Register API Application in Entra ID

### Create App Registration for Your API

1. Navigate to **Azure Portal** > **Microsoft Entra ID** > **App registrations**
2. Click **New registration**
3. Configure:
   - **Name**: `apim-api-{your-api-name}`
   - **Supported account types**: Choose based on your needs:
     - Single tenant: Only accounts in your directory
     - Multi-tenant: Accounts in any Azure AD directory
   - **Redirect URI**: Leave blank for API-only registration

4. Click **Register**

### Configure API Permissions (Expose an API)

1. In your app registration, go to **Expose an API**
2. Click **Add a scope**
3. Set Application ID URI (accept default or customize):
   ```
   api://{application-id}
   ```
4. Add scope:
   - **Scope name**: `access_as_user` (or your custom scope)
   - **Admin consent display name**: Access API
   - **Admin consent description**: Allows the app to access the API on behalf of the signed-in user
   - **State**: Enabled

5. Note the full scope URI:
   ```
   api://{application-id}/access_as_user
   ```

### Create Client Application (Optional)

If you need a client app to call your API:

1. Create another app registration for the client
2. Go to **API permissions** > **Add a permission**
3. Select **My APIs** > Select your API registration
4. Check the scope you created
5. Click **Add permissions**
6. Grant admin consent if required

## Step 2: Configure APIM OAuth 2.0 Server

### Via Azure Portal

1. Navigate to **API Management** > **OAuth 2.0 + OpenID Connect**
2. Click **Add** under OAuth 2.0
3. Configure:

| Setting | Value |
|---------|-------|
| **Display name** | `Entra ID OAuth` |
| **Client registration page URL** | `https://portal.azure.com` |
| **Authorization grant types** | ✅ Authorization code, ✅ Implicit |
| **Authorization endpoint URL** | `https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize` |
| **Token endpoint URL** | `https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token` |
| **Default scope** | `api://{api-app-id}/access_as_user` |
| **Client ID** | `{client-app-id}` |
| **Client secret** | `{client-app-secret}` |

4. Click **Create**

### Get Your Tenant and App IDs

Find your tenant ID:
```bash
az account show --query tenantId -o tsv
```

Find app registration IDs:
```bash
az ad app list --display-name "apim-api" --query "[].appId" -o tsv
```

## Step 3: Apply JWT Validation Policy

### Add Policy to API

1. Go to **API Management** > **APIs** > Select your API
2. Click **Inbound processing** > **Add policy** > **Validate JWT**
3. Or use the policy editor to add manually:

```xml
<policies>
    <inbound>
        <base />
        <validate-jwt header-name="Authorization" 
                      failed-validation-httpcode="401" 
                      failed-validation-error-message="Unauthorized. Access token is missing or invalid."
                      require-expiration-time="true"
                      require-scheme="Bearer">
            <openid-config url="https://login.microsoftonline.com/{tenant-id}/.well-known/openid-configuration" />
            <audiences>
                <audience>api://{api-app-id}</audience>
            </audiences>
            <issuers>
                <issuer>https://sts.windows.net/{tenant-id}/</issuer>
                <issuer>https://login.microsoftonline.com/{tenant-id}/v2.0</issuer>
            </issuers>
        </validate-jwt>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Policy Template

See [jwt-validation.xml](../../bicep/apim/policies/jwt-validation.xml) for a ready-to-use template.

### Key Policy Settings

| Setting | Description |
|---------|-------------|
| `header-name` | HTTP header containing the token (usually `Authorization`) |
| `failed-validation-httpcode` | HTTP status code for invalid tokens (401) |
| `require-scheme` | Token prefix requirement (`Bearer`) |
| `openid-config` | Entra ID OpenID configuration endpoint |
| `audiences` | Valid token audiences (your API's app ID URI) |
| `issuers` | Valid token issuers (Entra ID STS URLs) |

## Step 4: Test Authentication

### Get an Access Token

Using Azure CLI:
```bash
# Login as user
az login

# Get token for your API
az account get-access-token \
  --resource api://{api-app-id} \
  --query accessToken -o tsv
```

Using curl (client credentials flow):
```bash
curl -X POST https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id={client-app-id}" \
  -d "client_secret={client-secret}" \
  -d "scope=api://{api-app-id}/.default" \
  -d "grant_type=client_credentials"
```

### Call API with Token

```bash
TOKEN=$(az account get-access-token --resource api://{api-app-id} --query accessToken -o tsv)

curl -X GET "https://apim-ai-lab.azure-api.net/your-api/endpoint" \
  -H "Authorization: Bearer $TOKEN"
```

### Test Without Token (Should Fail)

```bash
curl -X GET "https://apim-ai-lab.azure-api.net/your-api/endpoint"
# Expected: 401 Unauthorized
```

## Advanced Configurations

### Role-Based Authorization

Add role claims to your JWT validation:

```xml
<validate-jwt ...>
    <required-claims>
        <claim name="roles" match="any">
            <value>API.Read</value>
            <value>API.Write</value>
        </claim>
    </required-claims>
</validate-jwt>
```

Configure roles in your app registration:
1. Go to **App registration** > **App roles**
2. Create roles (e.g., `API.Read`, `API.Write`)
3. Assign roles to users/groups in Enterprise Applications

### Extract Claims to Headers

Pass claims to backend:

```xml
<set-header name="X-User-Id" exists-action="override">
    <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Claims.GetValueOrDefault("oid", ""))</value>
</set-header>
```

### Multi-Tenant Validation

For multi-tenant scenarios, accept tokens from any Azure AD tenant:

```xml
<validate-jwt ...>
    <openid-config url="https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration" />
    <issuers>
        <issuer>https://login.microsoftonline.com/{tenant-id-1}/v2.0</issuer>
        <issuer>https://login.microsoftonline.com/{tenant-id-2}/v2.0</issuer>
    </issuers>
</validate-jwt>
```

## Troubleshooting

### Common Errors

**401 Unauthorized - Token validation failed**
- Check audience matches your API's app ID URI
- Verify issuer URL matches your tenant
- Ensure token hasn't expired

**400 Bad Request - Invalid token format**
- Ensure `Authorization: Bearer {token}` header format
- Check token is a valid JWT (decode at jwt.ms)

**Signature validation failed**
- OpenID configuration URL may be incorrect
- Token may be for wrong tenant

### Debug Token Validation

Add trace policy to see validation details:

```xml
<inbound>
    <trace source="jwt-validation" severity="information">
        <message>@(context.Request.Headers.GetValueOrDefault("Authorization","").Substring(0,50))</message>
    </trace>
    <validate-jwt ...>
</inbound>
```

Enable tracing in APIM and view in Application Insights.

## Security Best Practices

1. **Always use HTTPS** - Never transmit tokens over HTTP
2. **Validate audience** - Prevents tokens issued for other APIs
3. **Validate issuer** - Prevents tokens from untrusted sources
4. **Require expiration** - Reject tokens without expiry
5. **Use short token lifetimes** - Default 1 hour is recommended
6. **Protect client secrets** - Store in Key Vault, not in code
7. **Use managed identity** - For APIM to access Key Vault secrets

## Related Resources

- [Microsoft Entra ID documentation](https://docs.microsoft.com/en-us/azure/active-directory/)
- [APIM JWT validation policy](https://docs.microsoft.com/en-us/azure/api-management/api-management-access-restriction-policies#ValidateJWT)
- [OAuth 2.0 authorization code flow](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow)
