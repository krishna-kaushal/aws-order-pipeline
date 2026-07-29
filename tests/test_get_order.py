import json
import os
import sys
import unittest
from decimal import Decimal
from unittest.mock import patch, MagicMock

os.environ["ORDERS_TABLE"] = "test-orders"

with patch("boto3.resource") as mock_resource:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
    import get_order

    get_order.dynamodb = mock_resource


class TestGetOrder(unittest.TestCase):
    def setUp(self):
        self.table_mock = MagicMock()
        get_order.dynamodb.Table.reset_mock()
        get_order.dynamodb.Table.return_value = self.table_mock

    def test_get_existing_order(self):
        self.table_mock.get_item.return_value = {
            "Item": {
                "order_id": "abc-123",
                "product_id": "prod-123",
                "customer_id": "cust-456",
                "quantity": 2,
                "amount": Decimal("49.99"),
                "status": "COMPLETED",
            }
        }

        event = {"pathParameters": {"order_id": "abc-123"}}
        response = get_order.lambda_handler(event, {})

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["order_id"], "abc-123")
        self.assertEqual(body["status"], "COMPLETED")

    def test_get_missing_order_returns_404(self):
        self.table_mock.get_item.return_value = {}

        event = {"pathParameters": {"order_id": "missing"}}
        response = get_order.lambda_handler(event, {})

        self.assertEqual(response["statusCode"], 404)
