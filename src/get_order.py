import json
import os
from decimal import Decimal

import boto3


dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["ORDERS_TABLE"]


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return str(o)
        return super().default(o)


def lambda_handler(event, context):
    order_id = event.get("pathParameters", {}).get("order_id")
    if not order_id:
        return _error("order_id is required", 400)

    table = dynamodb.Table(TABLE_NAME)
    response = table.get_item(Key={"order_id": order_id})
    item = response.get("Item")

    if not item:
        return _error("order not found", 404)

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(item, cls=DecimalEncoder),
    }


def _error(message, code):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }
