import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

TABLE_NAME = os.environ["ORDERS_TABLE"]
NOTIFICATION_TOPIC_ARN = os.environ["NOTIFICATION_TOPIC_ARN"]


def lambda_handler(event, context):
    processed = 0
    for record in event.get("Records", []):
        order = json.loads(record["body"])
        order_id = order["order_id"]
        amount = order.get("amount", 0)

        if amount > 1000:
            status = "FAILED"
            message = f"Payment failed for order {order_id} (amount {amount} exceeds limit)"
        else:
            status = "COMPLETED"
            message = f"Payment completed for order {order_id}"

        table = dynamodb.Table(TABLE_NAME)
        table.update_item(
            Key={"order_id": order_id},
            UpdateExpression="SET #s = :s",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": status},
        )

        sns.publish(
            TopicArn=NOTIFICATION_TOPIC_ARN,
            Message=json.dumps(
                {"order_id": order_id, "status": status, "message": message}
            ),
            Subject="Order Update",
        )
        processed += 1

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"processed": processed}),
    }
