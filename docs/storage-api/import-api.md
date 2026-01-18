# Importing and Publishing APIs in API Management

This guide covers importing APIs into Azure API Management and configuring backends to access private services.

## Overview

API Management supports importing APIs from various sources:
- **OpenAPI (Swagger)** - JSON or YAML specifications
- **WSDL** - SOAP web services
- **Azure Resources** - Function Apps, Logic Apps, App Services
- **Manual Definition** - Define operations manually

## Prerequisites

- Azure API Management deployed
- API specification or backend service URL
- Network connectivity to backend (for private backends)

## Import Methods

### Method 1: Import from OpenAPI Specification

#### Via Azure Portal

1. Navigate to **API Management** > **APIs**
2. Click **+ Add API** > **OpenAPI**
3. Configure:
   - **OpenAPI specification**: Upload file or paste URL
   - **Display name**: User-friendly name
   - **Name**: URL-safe identifier
   - **API URL suffix**: Path suffix (e.g., `orders`)
   - **Products**: Associate with products (optional)
4. Click **Create**

#### Via Azure CLI

```bash
# Import from URL
az apim api import \
  --resource-group rg-ai-apim \
  --service-name apim-ai-lab \
  --path "orders" \
  --specification-format OpenAPI \
  --specification-url "https://raw.githubusercontent.com/org/repo/main/openapi.yaml"

# Import from local file
az apim api import \
  --resource-group rg-ai-apim \
  --service-name apim-ai-lab \
  --path "products" \
  --specification-format OpenAPIJson \
  --specification-path ./openapi.json
```

### Method 2: Import Azure Function App

1. Navigate to **API Management** > **APIs**
2. Click **+ Add API** > **Function App**
3. Browse and select your Function App
4. Select functions to expose
5. Configure API settings
6. Click **Create**

### Method 3: Manual API Definition

1. Navigate to **API Management** > **APIs**
2. Click **+ Add API** > **Blank API**
3. Configure:
   - **Display name**: `My API`
   - **Name**: `my-api`
   - **Web service URL**: Backend service URL
   - **API URL suffix**: `myapi`
4. Click **Create**
5. Add operations manually:
   - Click **+ Add operation**
   - Define HTTP method, URL, parameters, responses

## Configure Backend Service

### Public Backend

For publicly accessible backends, set the Web service URL directly:

```
https://my-backend.azurewebsites.net
```

### Private Backend (VNet)

For backends accessible via VNet integration:

1. Ensure APIM has VNet integration enabled
2. Use private endpoint DNS name or private IP:

```
https://my-backend.privatelink.azurewebsites.net
```

Or for internal services:

```
http://10.1.0.10:8080
```

### Backend Entity (Reusable)

Create a named backend for reuse across APIs:

#### Via Portal

1. Go to **API Management** > **Backends**
2. Click **+ Add**
3. Configure:
   - **Name**: `internal-orders-service`
   - **Type**: Custom URL
   - **Runtime URL**: `https://orders.internal.company.com`
   - **Validate certificate chain**: Enable for HTTPS
4. Click **Create**

#### Via Bicep

See [sample-backend.bicep](../../bicep/apim/backends/sample-backend.bicep) for a reusable template.

## Apply Policies

### Set Backend URL Policy

Override backend URL per operation:

```xml
<inbound>
    <base />
    <set-backend-service base-url="https://orders.internal.company.com" />
</inbound>
```

### Use Named Backend

Reference a named backend:

```xml
<inbound>
    <base />
    <set-backend-service backend-id="internal-orders-service" />
</inbound>
```

### Add Headers

Pass custom headers to backend:

```xml
<inbound>
    <base />
    <set-header name="X-API-Key" exists-action="override">
        <value>{{api-key-named-value}}</value>
    </set-header>
</inbound>
```

### Transform Requests

Modify request before sending to backend:

```xml
<inbound>
    <base />
    <!-- Remove client headers -->
    <set-header name="X-Forwarded-For" exists-action="delete" />
    <!-- Add correlation ID -->
    <set-header name="X-Correlation-ID" exists-action="skip">
        <value>@(Guid.NewGuid().ToString())</value>
    </set-header>
</inbound>
```

## Publish to Developer Portal

After importing an API:

1. Go to **API Management** > **Products**
2. Select or create a product (e.g., "Starter", "Unlimited")
3. Click **+ Add API**
4. Select your API
5. Click **Select**

The API is now visible in the developer portal to users with access to that product.

### Subscription Keys

By default, APIs require subscription keys:

- **Header**: `Ocp-Apim-Subscription-Key`
- **Query**: `subscription-key`

To make an API open (no key required):
1. Go to API settings
2. Uncheck **Subscription required**

## Test Your API

### From Portal

1. Go to **API Management** > **APIs** > Select API
2. Click **Test** tab
3. Select operation
4. Add required parameters/headers
5. Click **Send**
6. View response

### From Developer Portal

1. Navigate to developer portal URL
2. Sign in or use test console
3. Select API and operation
4. Try the operation with your subscription key

### From Command Line

```bash
# With subscription key
curl -X GET "https://apim-ai-lab.azure-api.net/orders/v1/orders" \
  -H "Ocp-Apim-Subscription-Key: YOUR_KEY"

# With OAuth token (if JWT validation enabled)
curl -X GET "https://apim-ai-lab.azure-api.net/orders/v1/orders" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Sample API: Echo Service

Create a simple echo API for testing:

### OpenAPI Specification

```yaml
openapi: 3.0.1
info:
  title: Echo API
  version: "1.0"
paths:
  /echo:
    post:
      operationId: echo
      summary: Echo back the request
      requestBody:
        content:
          application/json:
            schema:
              type: object
      responses:
        200:
          description: Echo response
          content:
            application/json:
              schema:
                type: object
```

### Mock Response Policy

For testing without a real backend:

```xml
<inbound>
    <base />
    <mock-response status-code="200" content-type="application/json" />
</inbound>
```

## Troubleshooting

### API Returns 500

- Check backend service is running
- Verify network connectivity (NSG, firewall)
- Enable Application Insights for detailed traces

### Backend Timeout

- Increase timeout in policy:
  ```xml
  <forward-request timeout="60" />
  ```
- Check backend performance

### DNS Resolution Failed

- For private endpoints, ensure DNS resolver is configured
- Check private DNS zones are linked to APIM VNet
- Test resolution from APIM diagnostic console

### SSL Certificate Error

- Ensure certificate chain is valid
- For self-signed certs, disable validation (dev only):
  ```xml
  <set-backend-service backend-id="dev-backend" 
                       validate-certificate-chain="false" />
  ```

## Best Practices

1. **Use versioning** - Version your APIs (`/v1/`, `/v2/`)
2. **Apply rate limiting** - Protect backends from overload
3. **Cache responses** - Reduce backend load for cacheable data
4. **Use named backends** - Centralize backend configuration
5. **Implement health checks** - Monitor backend availability
6. **Document in OpenAPI** - Keep specs up-to-date

## Related Documentation

- [OAuth Setup Guide](./oauth-setup.md)
- [Main APIM Documentation](./README.md)
- [Microsoft Learn: Import APIs](https://docs.microsoft.com/en-us/azure/api-management/import-and-publish)
