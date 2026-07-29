import json


def lambda_handler(event, context):
    for record in event.get("Records", []):
        message = json.loads(record["Sns"]["Message"])
        print("NOTIFICATION:", json.dumps(message))
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"received": len(event.get("Records", []))}),
    }
