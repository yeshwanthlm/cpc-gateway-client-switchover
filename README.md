# Confluent Cloud Gateway Setup for Cluster Switchover

This guide demonstrates how to set up Confluent Gateway on EKS to enable seamless switchover between Confluent Cloud clusters (Primary and DR).

## Architecture Overview

- **Primary Cluster**: `pkc-XXXXXXX.confluent.cloud` (AWS US-East-1)
- **DR Cluster**: `pkc-6XXXXXXX.confluent.cloud` (GCP US-East1)
- **Gateway Endpoint**: `kafka.cpc.yesh.com:9092`
- **EKS Cluster**: Running in AWS us-west-2

## Prerequisites

- EKS cluster with Confluent for Kubernetes operator installed
- Two Confluent Cloud clusters (Primary and DR)
- API keys for both clusters
- Route53 hosted zone for your domain
- kubectl and AWS CLI configured

## Step 0: Have the K8S cluster ready and run the following:

```bash
# make sure to install image tag 0.
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
kubectl create namespace confluent
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes -n confluent
kubectl get pods -n confluent
```

## Step 1: Download Confluent Cloud Certificates

Create truststore files for both clusters:

```bash
cd certs

# Download certificates for primary cluster
./download-cc-certs.sh pkc-oxqxx9.us-east-1.aws.confluent.cloud:9092

# Download certificates for DR cluster
./download-cc-certs.sh pkc-619z3.us-east1.gcp.confluent.cloud:9092
```

This creates truststore files in `ssl/<cluster-name>/` directories.

## Step 2: Create Kubernetes Secrets for Cluster TLS

Create secrets for cluster truststore files:

```bash
# Primary cluster TLS secret
kubectl -n confluent create secret generic cc-primary-tls \
  --from-file=truststore.jks=./certs/ssl/pkc-oxqxx9.us-east-1.aws.confluent.cloud/truststore.p12 \
  --from-file=jksPassword.txt=./certs/ssl/pkc-oxqxx9.us-east-1.aws.confluent.cloud/truststore.password

# DR cluster TLS secret
kubectl -n confluent create secret generic cc-dr-tls \
  --from-file=truststore.jks=./certs/ssl/pkc-619z3.us-east1.gcp.confluent.cloud/truststore.p12 \
  --from-file=jksPassword.txt=./certs/ssl/pkc-619z3.us-east1.gcp.confluent.cloud/truststore.password
```

## Step 3: Create Gateway TLS Certificate

Generate a self-signed certificate for the gateway:

```bash
# Generate CA key and certificate
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -key ca-key.pem -out cacerts.pem -days 365 \
  -subj "/C=US/ST=CA/L=Mountain View/O=Confluent/OU=Engineering/CN=Gateway Test CA"

# Create SAN configuration
cat > gateway-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = Mountain View
O = Confluent
OU = Engineering
CN = kafka.cpc.yesh.com

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kafka.cpc.yesh.com
DNS.2 = *.kafka.cpc.yesh.com
EOF

# Generate gateway certificate
openssl genrsa -out gateway-key.pem 2048
openssl req -new -key gateway-key.pem -out gateway.csr -config gateway-san.cnf
openssl x509 -req -in gateway.csr -CA cacerts.pem -CAkey ca-key.pem \
  -CAcreateserial -out gateway-cert.pem -days 365 -extensions v3_req \
  -extfile gateway-san.cnf

# Create fullchain
cat gateway-cert.pem cacerts.pem > fullchain.pem

# Create Kubernetes secret
kubectl create secret generic gateway-tls -n confluent \
  --from-file=fullchain.pem=fullchain.pem \
  --from-file=privkey.pem=gateway-key.pem \
  --from-file=cacerts.pem=cacerts.pem
```

## Step 4: Create Gateway Truststore Secret

Create a JKS truststore from the gateway CA certificate for client applications:

```bash
# Extract the gateway CA certificate
kubectl get secret gateway-tls -n confluent -o jsonpath='{.data.cacerts\.pem}' | base64 -d > /tmp/gateway-ca.pem

# Create JKS truststore from the CA certificate
keytool -import -trustcacerts -alias gateway-ca \
  -file /tmp/gateway-ca.pem \
  -keystore /tmp/gateway-truststore.jks \
  -storepass clienttrustpass \
  -noprompt

# Create Kubernetes secret with the truststore
kubectl create secret generic gateway-truststore -n confluent \
  --from-file=truststore.jks=/tmp/gateway-truststore.jks \
  --from-literal=password=clienttrustpass
```

**Note**: This truststore is used by client applications to trust the gateway's TLS certificate.

## Step 5: Create Client Configuration Files

Create client properties for both clusters:

**clients/client-primary.properties:**
```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<PRIMARY_API_KEY>" password="<PRIMARY_API_SECRET>";
ssl.truststore.location=/etc/kafka/tls/truststore.jks
ssl.truststore.password=clienttrustpass
ssl.endpoint.identification.algorithm=
```

**clients/client-dr.properties:**
```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<DR_API_KEY>" password="<DR_API_SECRET>";
ssl.truststore.location=/etc/kafka/tls/truststore.jks
ssl.truststore.password=clienttrustpass
ssl.endpoint.identification.algorithm=
```

Create secrets:

```bash
kubectl -n confluent create secret generic client-primary \
  --from-file=client-primary.properties=./clients/client-primary.properties

kubectl -n confluent create secret generic client-dr \
  --from-file=client-dr.properties=./clients/client-dr.properties
```

## Step 6: Deploy Confluent Gateway

Apply the gateway configuration:

```bash
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent
```

Wait for the gateway to be ready:

```bash
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=600s -n confluent
```

## Step 7: Configure DNS

Get the LoadBalancer hostname:

```bash
kubectl get svc -n confluent confluent-gateway-bootstrap-lb \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Create a CNAME record in Route53:

```bash
Update route53-update-gateway.json with your LoadBalancer hostname
```

**Note**: Ensure your domain's nameservers are pointing to Route53 nameservers.

## Step 8: Deploy Kafka Tools Pod for Testing

Apply the kafka-tools pod:

```bash
kubectl apply -f kubernetes-resources/kafka-tools.yaml -n confluent
kubectl wait --for=condition=Ready pod/kafka-tools --timeout=120s -n confluent
```

## Step 9: Test Primary Cluster Connection

```bash
kubectl exec -it -n confluent pod/kafka-tools -- bash

# Inside the pod - test primary cluster
kafka-producer-perf-test \
  --topic cpctest \
  --num-records 100 \
  --record-size 10 \
  --throughput 10 \
  --producer-props bootstrap.servers=kafka.cpc.yesh.com:9092 \
  --producer.config /etc/kafka/client-primary/client-primary.properties
```

## Step 10: Switch to DR Cluster

Update the gateway configuration to route to DR:

Edit `kubernetes-resources/gateway.yaml` and change the `streamingDomain` section:

```yaml
routes:
  - name: switchover-route
    endpoint: "kafka.cpc.yesh.com:9092"
    brokerIdentificationStrategy:
      type: port
    streamingDomain:
      name: cc-dr              # Changed from cc-primary
      bootstrapServerId: CC_DR  # Changed from CC_PRIMARY
```

Apply the changes:

```bash
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent

# Restart gateway pods to apply changes
kubectl delete pod -n confluent -l app=confluent-gateway
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=120s -n confluent
```

## Step 11: Test DR Cluster Connection

```bash
kubectl exec -it -n confluent pod/kafka-tools -- bash

# Inside the pod - test DR cluster
kafka-producer-perf-test \
  --topic cpctest \
  --num-records 100 \
  --record-size 10 \
  --throughput 10 \
  --producer-props bootstrap.servers=kafka.cpc.yesh.com:9092 \
  --producer.config /etc/kafka/client-dr/client-dr.properties
```

## Cluster Switchover Process

To switch between clusters:

1. Update the gateway configuration (`streamingDomain` section)
2. Apply the configuration: `kubectl apply -f kubernetes-resources/gateway.yaml -n confluent`
3. Restart gateway pods: `kubectl delete pod -n confluent -l app=confluent-gateway`
4. Clients automatically reconnect to the new cluster through the same endpoint

## Troubleshooting

### DNS Not Resolving

If DNS isn't resolving, verify:
- Route53 record exists: `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>`
- Domain nameservers point to Route53
- DNS propagation (can take up to 48 hours)


### SSL Certificate Errors

If you see SSL hostname verification errors, ensure:
- Gateway certificate includes correct SANs
- `ssl.endpoint.identification.algorithm=` is set in client properties (disables hostname verification)

### Authentication Failures

Verify:
- Correct API keys in client properties
- Gateway is routing to the correct cluster
- Cluster TLS secrets are properly configured

## File Structure

```
.
├── README.md
├── certs/
│   ├── download-cc-certs.sh
│   └── ssl/
├── clients/
│   ├── client-primary.properties
│   └── client-dr.properties
├── kubernetes-resources/
│   ├── gateway.yaml
│   └── kafka-tools.yaml
```

## Key Configuration Details

### Gateway Configuration

- **Streaming Domains**: Define both primary and DR clusters
- **Routes**: Configure the endpoint and active streaming domain
- **Security**: Passthrough authentication (client credentials passed to backend cluster)
- **TLS**: Separate TLS configuration for client-to-gateway and gateway-to-cluster

### Port Mapping

The gateway uses port-based broker identification:
- Port 9092: Bootstrap/initial connection
- Ports 9093-9098+: Individual broker connections

All traffic goes through the LoadBalancer on different ports.

## Production Considerations

1. **DNS**: Use proper DNS with low TTL for faster switchover
2. **Certificates**: Use certificates from a trusted CA
3. **Monitoring**: Monitor gateway metrics and logs
4. **Testing**: Regularly test switchover procedures
5. **Automation**: Automate switchover process with scripts/operators
6. **Client Configuration**: Ensure clients have proper retry and timeout settings

## Resources

- [Confluent Gateway Documentation](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/index.html)
- [Confluent for Kubernetes](https://docs.confluent.io/operator/current/overview.html)
