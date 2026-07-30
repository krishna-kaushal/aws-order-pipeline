import json
import os
import time
import uuid
from decimal import Decimal

import boto3

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE_NAME = os.environ["ORDERS_TABLE"]
IDEMPOTENCY_TABLE = os.environ.get("IDEMPOTENCY_TABLE")
QUEUE_URL = os.environ["ORDER_QUEUE_URL"]


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        product_id = body.get("product_id")
        customer_id = body.get("customer_id")
        quantity = body.get("quantity")
        amount = body.get("amount")

        if not product_id or not customer_id:
            return _error("product_id and customer_id are required", 400)

        try:
            quantity = int(quantity)
            amount = Decimal(str(amount))
        except (TypeError, ValueError):
            return _error("quantity and amount must be valid numbers", 400)

        if quantity <= 0 or amount <= 0:
            return _error("quantity and amount must be positive", 400)

        idempotency_key = _get_header(event, "idempotency-key")
        canonical_payload = _canonical_payload(body)

        if idempotency_key and IDEMPOTENCY_TABLE:
            existing = _check_idempotency(idempotency_key, canonical_payload)
            if existing:
                return existing

        order_id = str(uuid.uuid4())
        order_db = {
            "order_id": order_id,
            "product_id": product_id,
            "customer_id": customer_id,
            "quantity": quantity,
            "amount": amount,
            "status": "PENDING",
        }

        table = dynamodb.Table(TABLE_NAME)
        table.put_item(Item=order_db)

        order_message = {
            "order_id": order_id,
            "product_id": product_id,
            "customer_id": customer_id,
            "quantity": quantity,
            "amount": float(amount),
        }
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(order_message))

        response = {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"order_id": order_id, "status": "PENDING"}),
        }

        if idempotency_key and IDEMPOTENCY_TABLE:
            _store_idempotency(idempotency_key, canonical_payload, response)

        return response
    except Exception as e:
        return _error(str(e), 500)


def _get_header(event, name):
    headers = event.get("headers") or {}
    for key, value in headers.items():
        if key.lower() == name.lower():
            return value
    return None


def _canonical_payload(body):
    return json.dumps(body, sort_keys=True, separators=(",", ":"))


def _check_idempotency(idempotency_key, canonical_payload):
    table = dynamodb.Table(IDEMPOTENCY_TABLE)
    item = table.get_item(Key={"idempotency_key": idempotency_key}).get("Item")

    if not item:
        return None

    if item.get("payload") != canonical_payload:
        return _error("Idempotency-Key already used with different payload", 409)

    return json.loads(item["response"])


def _store_idempotency(idempotency_key, canonical_payload, response):
    table = dynamodb.Table(IDEMPOTENCY_TABLE)
    table.put_item(
        Item={
            "idempotency_key": idempotency_key,
            "payload": canonical_payload,
            "response": json.dumps(response),
            "ttl": int(time.time()) + 86400,
        }
    )


def _error(message, code):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }
