#!/bin/bash
set -e

echo "=============================================="
echo "Mount Sinai Key Vault Test Harness"
echo "=============================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""
echo "Environment:"
echo "  AZURE_CLIENT_ID: ${AZURE_CLIENT_ID:-<not set>}"
echo "  AZURE_TENANT_ID: ${AZURE_TENANT_ID:-<not set>}"
echo "  AZURE_KEY_VAULT_URI: ${AZURE_KEY_VAULT_URI:-<not set>}"
echo "  AZURE_FEDERATED_TOKEN_FILE: ${AZURE_FEDERATED_TOKEN_FILE:-<not set>}"
echo ""

if [ -f "$AZURE_FEDERATED_TOKEN_FILE" ]; then
    echo "✓ Federated token file exists"
else
    echo "✗ Federated token file NOT found at $AZURE_FEDERATED_TOKEN_FILE"
fi
echo ""

case "${1:-diagnostic}" in
    diagnostic)
        echo "Running AKS Key Vault Diagnostic..."
        exec /opt/spark/bin/spark-submit \
            --class org.mountsinai.datascience.batch.medicalMalpractice.AksKeyVaultDiagnostic \
            --master local[*] \
            --conf "spark.driver.extraJavaOptions=-Dconfig.file=/opt/spark-app/application.conf" \
            /opt/spark-app/app.jar
        ;;
    test)
        echo "Running ScalaTest suite..."
        exec java -cp /opt/spark-app/app.jar \
            -Dconfig.file=/opt/spark-app/application.conf \
            org.scalatest.tools.Runner \
            -o -R /opt/spark-app/app.jar \
            -s org.mountsinai.datascience.batch.medicalMalpractice.KeyVaultTest
        ;;
    shell)
        echo "Starting interactive shell..."
        exec /bin/bash
        ;;
    *)
        echo "Running custom command: $@"
        exec "$@"
        ;;
esac
