# Makefile Quick Reference Guide

The `Makefile` automates all certificate management operations for the Confluent Cloud Gateway demo. It provides a clean, reusable interface for creating, verifying, and cleaning up certificates.

## Quick Start

```bash
# Create all certificates and configurations
make certs

# Create all Kubernetes secrets
make k8s-secrets

# Verify all certificates are valid
make verify-certs

# Clean up everything
make clean
```

## Available Commands

### Certificate Creation

| Command | Description |
|---------|-------------|
| `make certs` | Create all certificates and configurations (runs all steps below) |
| `make confluent-certs` | Download and convert Confluent Cloud certificates to JKS |
| `make gateway-certs` | Generate self-signed TLS certificates for the gateway |
| `make client-configs` | Create client configuration files with API keys |
| `make convert-to-jks` | Convert PKCS12 truststores to JKS format |

### Kubernetes Secrets

| Command | Description |
|---------|-------------|
| `make k8s-secrets` | Create all Kubernetes secrets in confluent namespace |
| `make list-k8s-secrets` | List all secrets in confluent namespace |
| `make clean-k8s-secrets` | Delete all Kubernetes secrets |

### Verification & Utilities

| Command | Description |
|---------|-------------|
| `make verify-certs` | Verify all certificates are created and valid |
| `make check-env` | Check if required environment variables are set |
| `make help` | Show help message with all available commands |

### Cleanup

| Command | Description |
|---------|-------------|
| `make clean-certs` | Remove all generated certificates and temporary files |
| `make clean-k8s-secrets` | Delete all Kubernetes secrets |
| `make clean` | Complete cleanup (certificates + secrets) |

## Configuration

The Makefile reads configuration from the `.env` file in the project root. Required variables:

```bash
# Cluster endpoints (auto-populated by Terraform)
AWS_CLUSTER_ENDPOINT=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
GCP_CLUSTER_ENDPOINT=pkc-xxxxx.us-west1.gcp.confluent.cloud:9092

# API keys (auto-populated by Terraform)
AWS_CLUSTER_API_KEY=your-key
AWS_CLUSTER_API_SECRET=your-secret
GCP_CLUSTER_API_KEY=your-key
GCP_CLUSTER_API_SECRET=your-secret

# Gateway configuration
GATEWAY_DOMAIN=kafka.cpc.example.com
JKS_PASSWORD=confluent
CLIENT_TRUSTSTORE_PASSWORD=clienttrustpass

# Certificate details
CERT_COUNTRY=US
CERT_STATE=CA
CERT_CITY=Mountain View
CERT_ORG=Confluent
CERT_OU=Engineering
```

## Typical Workflows

### Initial Deployment

```bash
# 1. Deploy infrastructure with Terraform
cd terraform && terraform apply && cd ..
cd confluent-terraform && terraform apply && cd ..

# 2. Create all certificates and secrets
make certs k8s-secrets

# 3. Verify everything is ready
make verify-certs

# 4. Deploy gateway
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent
```

### Re-generate Certificates

```bash
# Clean old certificates
make clean-certs

# Create new certificates
make certs

# Update Kubernetes secrets
make k8s-secrets
```

### Troubleshooting Certificates

```bash
# Verify all certificates exist
make verify-certs

# Check Kubernetes secrets
make list-k8s-secrets

# Re-create just Confluent Cloud certs
make confluent-certs
make k8s-secrets

# Re-create just gateway certs
make gateway-certs
make k8s-secrets
```

### Manual Certificate Operations

```bash
# Download Confluent Cloud certificates only
make confluent-certs

# Convert existing PKCS12 to JKS
make convert-to-jks

# Generate gateway certificates only
make gateway-certs

# Create client configs only
make client-configs
```

## What Gets Created

### Confluent Cloud Certificates

**Files:**
- `/tmp/cc-primary-truststore.jks` - AWS cluster truststore (JKS)
- `/tmp/cc-dr-truststore.jks` - GCP cluster truststore (JKS)
- `/tmp/jksPassword.txt` - Password file in properties format
- `certs/ssl/<cluster-host>/` - Downloaded certificates (PKCS12)

**Kubernetes Secrets:**
- `cc-primary-tls` - AWS cluster TLS secret
- `cc-dr-tls` - GCP cluster TLS secret

### Gateway Certificates

**Files:**
- `gateway-tls-cert/ca-key.pem` - CA private key
- `gateway-tls-cert/cacerts.pem` - CA certificate
- `gateway-tls-cert/gateway-key.pem` - Gateway private key
- `gateway-tls-cert/gateway-cert.pem` - Gateway certificate
- `gateway-tls-cert/fullchain.pem` - Full certificate chain
- `gateway-tls-cert/gateway-san.cnf` - SAN configuration
- `/tmp/gateway-truststore.jks` - Gateway truststore for clients

**Kubernetes Secrets:**
- `gateway-tls` - Gateway TLS secret
- `gateway-truststore` - Gateway truststore for clients

### Client Configurations

**Files:**
- `clients/client-primary.properties` - AWS cluster client config
- `clients/client-dr.properties` - GCP cluster client config

**Kubernetes Secrets:**
- `client-primary` - AWS cluster client configuration
- `client-dr` - GCP cluster client configuration

## Certificate Validity

All generated certificates are valid for **365 days** (1 year).

To check expiration:
```bash
# Gateway certificate
openssl x509 -in gateway-tls-cert/gateway-cert.pem -noout -dates

# Confluent Cloud certificates
keytool -list -v -keystore /tmp/cc-primary-truststore.jks -storepass confluent
```

To renew certificates:
```bash
# Renew all certificates
make clean-certs
make certs k8s-secrets

# Restart gateway pods to pick up new certificates
kubectl delete pod -n confluent -l app=confluent-gateway
```

## Troubleshooting

### Make fails with "cannot connect to cluster"

**Problem:** Kubernetes cluster not accessible

**Solution:**
```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name my-eks-cluster

# Verify connection
kubectl get nodes
```

### Make fails with "cluster endpoints not set"

**Problem:** AWS_CLUSTER_ENDPOINT or GCP_CLUSTER_ENDPOINT not in .env

**Solution:**
```bash
# Let Makefile extract from Terraform
make confluent-certs

# Or manually add to .env
echo "AWS_CLUSTER_ENDPOINT=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092" >> .env
echo "GCP_CLUSTER_ENDPOINT=pkc-xxxxx.us-west1.gcp.confluent.cloud:9092" >> .env
```

### Keytool errors

**Problem:** "keystore password was incorrect"

**Solution:**
- The Makefile uses correct passwords automatically
- If you created certs manually, ensure JKS format (not PKCS12)
- Run `make clean-certs` and `make certs` to regenerate

### Gateway pod CrashLoopBackOff

**Problem:** Invalid certificate format or password

**Solution:**
```bash
# Check certificate validity
make verify-certs

# Re-create all certificates
make clean-certs
make certs k8s-secrets

# Check gateway logs
kubectl logs -n confluent -l app=confluent-gateway
```

## Integration with Deploy/Destroy Scripts

The `deploy.sh` and `destroy.sh` scripts automatically use the Makefile:

**deploy.sh:**
```bash
# Calls make internally for certificate creation
make certs
make k8s-secrets
make verify-certs
```

**destroy.sh:**
```bash
# Calls make internally for cleanup
make clean-certs
```

You can also use the Makefile independently for more granular control.

## Advanced Usage

### Custom Certificate Validity

Edit the Makefile to change certificate validity (default: 365 days):

```bash
# Find lines with "-days 365" and change to desired value
openssl req -new -x509 ... -days 730  # 2 years
openssl x509 -req ... -days 730       # 2 years
```

### Different Domain Names

Set in `.env`:
```bash
GATEWAY_DOMAIN=kafka.mycompany.com
```

Then regenerate:
```bash
make clean-certs gateway-certs k8s-secrets
```

### Using Production CA

The Makefile generates self-signed certificates. For production, replace with CA-signed certificates:

1. Generate CSR: `make gateway-certs` (creates gateway.csr)
2. Submit CSR to your CA
3. Replace `gateway-cert.pem` with CA-signed certificate
4. Update `fullchain.pem` with CA chain
5. Recreate secret: `kubectl delete secret gateway-tls -n confluent && make k8s-secrets`

## Best Practices

1. **Always use the Makefile** - Don't create certificates manually
2. **Verify after creation** - Run `make verify-certs` after any changes
3. **Store .env safely** - Never commit .env to git (it's gitignored)
4. **Rotate regularly** - Regenerate certificates before 365-day expiry
5. **Test after changes** - Always test gateway connection after certificate updates

## Examples

### Complete Fresh Start

```bash
# Clean everything
make clean

# Create all certificates
make certs

# Create Kubernetes secrets
make k8s-secrets

# Verify
make verify-certs
make list-k8s-secrets
```

### Quick Certificate Rotation

```bash
# Remove old certs
make clean-certs

# Create new ones
make certs k8s-secrets

# Restart gateway
kubectl delete pod -n confluent -l app=confluent-gateway
kubectl wait --for=condition=Ready pod -l app=confluent-gateway -n confluent
```

### Debug Certificate Issues

```bash
# Check what exists
make verify-certs
make list-k8s-secrets

# View certificate details
openssl x509 -in gateway-tls-cert/gateway-cert.pem -noout -text

# List truststore contents
keytool -list -v -keystore /tmp/cc-primary-truststore.jks -storepass confluent
```

## See Also

- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Full deployment guide
- [README.md](README.md) - Detailed manual setup guide
- `.env.example` - Configuration template
