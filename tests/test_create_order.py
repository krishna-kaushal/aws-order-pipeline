import json
import os
import sys
import unittest
from unittest.mock import patch, MagicMock

os.environ["ORDERS_TABLE"] = "test-orders"
os.environ["ORDER_QUEUE_URL"] = "http://test-queue"

with patch("boto3.resource") as mock_resource, patch("boto3.client") as mock_client:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
    import create_order

    create_order.dynamodb = mock_resource
    create_order.sqs = mock_client


class TestCreateOrder(unittest.TestCase):
    def setUp(self):
        self.table_mock = MagicMock()
        create_order.dynamodb.Table.reset_mock()
        create_order.dynamodb.Table.return_value = self.table_mock
        create_order.sqs.reset_mock()

    def test_valid_order_returns_201(self):
        event = {
            "body": json.dumps(
                {
                    "product_id": "prod-123",
                    "customer_id": "cust-456",
                    "quantity": 2,
                    "amount": 49.99,
                }
            )
        }

        response = create_order.lambda_handler(event, {})

        self.assertEqual(response["statusCode"], 201)
        body = json.loads(response["body"])
        self.assertIn("order_id", body)
        self.assertEqual(body["status"], "PENDING")
        self.table_mock.put_item.assert_called_once()
        create_order.sqs.send_message.assert_called_once()

    def test_missing_customer_id_returns_400(self):
        event = {
            "body": json.dumps(
                {"product_id": "prod-123", "quantity": 1, "amount": 10}
            )
        }

        response = create_order.lambda_handler(event, {})

        self.assertEqual(response["statusCode"], 400)
        self.table_mock.put_item.assert_not_called()
        create_order.sqs.send_message.assert_not_called()
