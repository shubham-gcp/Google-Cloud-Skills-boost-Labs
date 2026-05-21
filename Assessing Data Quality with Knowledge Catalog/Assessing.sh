#!/bin/bash

clear

echo "============================================================"
echo "      ASSESSING DATA QUALITY WITH KNOWLEDGE CATALOG         "
echo "============================================================"
echo ""

# ----------------------------------------------------------
# PROJECT INFO
# ----------------------------------------------------------

export PROJECT_ID=$(gcloud config get-value project)

echo "Project ID: $PROJECT_ID"
echo ""

# ----------------------------------------------------------
# USER INPUTS
# ----------------------------------------------------------

read -p "Enter Region: " REGION
read -p "Enter Zone: " ZONE

export REGION=$REGION
export ZONE=$ZONE

echo ""
echo "============================================================"
echo "Configuring gcloud defaults..."
echo "============================================================"

gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# ----------------------------------------------------------
# ENABLE APIs
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Enabling Required APIs..."
echo "============================================================"

gcloud services enable dataplex.googleapis.com
gcloud services enable dataproc.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable storage.googleapis.com

echo ""
echo "Waiting for APIs to stabilize..."
sleep 20

# ----------------------------------------------------------
# CREATE DATAPLEX LAKE
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Creating Dataplex Lake..."
echo "============================================================"

gcloud dataplex lakes create ecommerce-lake \
    --location=$REGION \
    --display-name="Ecommerce Lake"

echo ""
echo "Waiting for lake creation..."
sleep 40

# ----------------------------------------------------------
# CREATE ZONE
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Creating Raw Zone..."
echo "============================================================"

gcloud dataplex zones create customer-contact-raw-zone \
    --location=$REGION \
    --lake=ecommerce-lake \
    --display-name="Customer Contact Raw Zone" \
    --type=RAW \
    --resource-location-type=SINGLE_REGION

echo ""
echo "Waiting for zone activation..."
sleep 60

# ----------------------------------------------------------
# ATTACH BIGQUERY ASSET
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Attaching BigQuery Dataset Asset..."
echo "============================================================"

gcloud dataplex assets create contact-info \
    --location=$REGION \
    --lake=ecommerce-lake \
    --zone=customer-contact-raw-zone \
    --display-name="Contact Info" \
    --resource-type=BIGQUERY_DATASET \
    --resource-name=projects/$PROJECT_ID/datasets/customers

echo ""
echo "Waiting for asset creation..."
sleep 40

# ----------------------------------------------------------
# CREATE DATA QUALITY YAML
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Creating Data Quality YAML Spec..."
echo "============================================================"

cat > dq-customer-raw-data.yaml <<EOF
rules:
- nonNullExpectation: {}
  column: id
  dimension: COMPLETENESS
  threshold: 1

- regexExpectation:
    regex: '^[^@]+[@]{1}[^@]+$'
  column: email
  dimension: CONFORMANCE
  ignoreNull: true
  threshold: .85

postScanActions:
  bigqueryExport:
    resultsTable: projects/$PROJECT_ID/datasets/customers_dq_dataset/tables/dq_results
EOF

echo ""
echo "YAML file created successfully."

# ----------------------------------------------------------
# CREATE BUCKET
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Creating Cloud Storage Bucket..."
echo "============================================================"

gsutil mb -l $REGION gs://$PROJECT_ID-bucket 2>/dev/null

# ----------------------------------------------------------
# UPLOAD YAML
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Uploading YAML File..."
echo "============================================================"

gsutil cp dq-customer-raw-data.yaml gs://$PROJECT_ID-bucket/

# ----------------------------------------------------------
# CREATE DATA QUALITY SCAN
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Creating Dataplex Data Quality Scan..."
echo "============================================================"

gcloud dataplex datascans create data-quality customer-orders-data-quality-job \
    --project=$PROJECT_ID \
    --location=$REGION \
    --data-source-resource="//bigquery.googleapis.com/projects/$PROJECT_ID/datasets/customers/tables/contact_info" \
    --data-quality-spec-file="gs://$PROJECT_ID-bucket/dq-customer-raw-data.yaml"

echo ""
echo "Waiting before triggering execution..."
sleep 20

# ----------------------------------------------------------
# RUN DATA QUALITY SCAN
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Running Data Quality Scan..."
echo "============================================================"

gcloud dataplex datascans run customer-orders-data-quality-job \
    --location=$REGION

echo ""
echo "Waiting for job execution..."
sleep 90

# ----------------------------------------------------------
# OPTIONAL RESULTS QUERY
# ----------------------------------------------------------

echo ""
echo "============================================================"
echo "Checking Results Table..."
echo "============================================================"

bq query --use_legacy_sql=false \
"SELECT * FROM \`$PROJECT_ID.customers_dq_dataset.dq_results\` LIMIT 10"

echo ""
echo "============================================================"
echo "               LAB EXECUTION COMPLETED                      "
echo "============================================================"

echo ""
echo "You can now click:"
echo "1. Check My Progress"
echo "2. Review dq_results table in BigQuery"
echo ""
