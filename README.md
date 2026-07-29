# AWS Serverless Order/Payment Pipeline

A minimal, free-tier-friendly event-driven backend that demonstrates how an e-commerce order pipeline works: receive an order, store it, queue it for async payment processing, update the status, and notify.

Built with **Python** and **Terraform** on the **AWS Free Plan** in `ap-south-1`.

## Architecture

```
POST /orders
  |
  v
API Gateway (HTTP API v2)
  |
  v
create_order Lambda
  |           \
  |            \
  v             v
DynamoDB      SQS (order_queue)
(orders)           |
                   v
          process_payment Lambda
                   |
         +---------+---------+
         v                   v
  DynamoDB update       SNS topic
  (status)                |
                          v
                  notify Lambda (logs)
```

## Services used

- API Gateway HTTP API v2
- AWS Lambda (Python 3.12)
- DynamoDB
- SQS with Dead-Letter Queue
- SNS
- CloudWatch Logs (7-day retention)

## Prerequisites

1. AWS Free Plan account with IAM admin user and AWS CLI configured.
2. Terraform >= 1.5
3. Python 3.11+ (only for local testing)
4. `ap-south-1` as default region

## Project layout

```
.
├── Makefile
├── payload.json
├── payload_fail.json
├── requirements.txt
├── src/
│   ├── create_order.py
│   ├── process_payment.py
│   └── notify.py
├── tests/
│   └── test_create_order.py
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

## Deploy

```bash
make init    # terraform init + create build dir
make plan    # terraform plan
make deploy  # terraform apply -auto-approve
```

## Local testing

Run the unit tests before deploying:

```bash
pip install -r requirements.txt
python -m pytest tests/ -v
```

## Test on AWS

After deploy, get the API endpoint:

```bash
terraform -chdir=terraform output -raw api_endpoint
```

Place an order:

```bash
curl -X POST $(terraform -chdir=terraform output -raw api_endpoint) \
  -H "Content-Type: application/json" \
  -d @payload.json
```

Expected response:

```json
{"order_id": "...", "status": "PENDING"}
```

To see the failure path (amount > 1000 is rejected):

```bash
curl -X POST $(terraform -chdir=terraform output -raw api_endpoint) \
  -H "Content-Type: application/json" \
  -d @payload_fail.json
```

Check the DynamoDB table in the console to see the order move from `PENDING` to `COMPLETED` or `FAILED`.

## Destroy

```bash
make destroy
```

This removes all AWS resources and stops any charges.

## Free tier notes

- Keep traffic low to stay within the AWS Free Tier and credits.
- No long-running servers (EC2/RDS/NAT Gateway) are created, so idle cost is $0.
- DynamoDB is set to on-demand for simplicity. If you want to guarantee zero request charges, switch to provisioned mode in `terraform/main.tf`.

## What to say in an interview

- "I built an event-driven order pipeline with API Gateway, Lambda, DynamoDB, SQS, and SNS."
- "I used Terraform so the entire infrastructure is version-controlled and repeatable."
- "I used a Dead-Letter Queue for failed payment processing and CloudWatch for observability."
- "It stays inside the AWS Free Tier, so it costs almost nothing to run."
