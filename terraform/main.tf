terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project_name
    }
  }
}

locals {
  create_order_fn    = "${var.project_name}-create-order"
  get_order_fn       = "${var.project_name}-get-order"
  process_payment_fn = "${var.project_name}-process-payment"
  notify_fn          = "${var.project_name}-notify"
}

# DynamoDB
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

# SQS
resource "aws_sqs_queue" "order_dlq" {
  name = "${var.project_name}-order-dlq"
}

resource "aws_sqs_queue" "order_queue" {
  name                      = "${var.project_name}-order-queue"
  message_retention_seconds = 86400
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

# SNS
resource "aws_sns_topic" "order_notifications" {
  name = "${var.project_name}-notifications"
}

# IAM
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.order_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.order_notifications.arn
      }
    ]
  })
}

# Lambda packages
data "archive_file" "create_order" {
  type        = "zip"
  source_file = "${path.module}/../src/create_order.py"
  output_path = "${path.module}/../build/create_order.zip"
}

data "archive_file" "process_payment" {
  type        = "zip"
  source_file = "${path.module}/../src/process_payment.py"
  output_path = "${path.module}/../build/process_payment.zip"
}

data "archive_file" "notify" {
  type        = "zip"
  source_file = "${path.module}/../src/notify.py"
  output_path = "${path.module}/../build/notify.zip"
}

data "archive_file" "get_order" {
  type        = "zip"
  source_file = "${path.module}/../src/get_order.py"
  output_path = "${path.module}/../build/get_order.zip"
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "create_order" {
  name              = "/aws/lambda/${local.create_order_fn}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "process_payment" {
  name              = "/aws/lambda/${local.process_payment_fn}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "notify" {
  name              = "/aws/lambda/${local.notify_fn}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "get_order" {
  name              = "/aws/lambda/${local.get_order_fn}"
  retention_in_days = 7
}

# Lambdas
resource "aws_lambda_function" "create_order" {
  function_name    = local.create_order_fn
  handler          = "create_order.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.create_order.output_path
  source_code_hash = data.archive_file.create_order.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      ORDERS_TABLE  = aws_dynamodb_table.orders.name
      ORDER_QUEUE_URL = aws_sqs_queue.order_queue.url
    }
  }

  depends_on = [aws_cloudwatch_log_group.create_order]
}

resource "aws_lambda_function" "process_payment" {
  function_name    = local.process_payment_fn
  handler          = "process_payment.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.process_payment.output_path
  source_code_hash = data.archive_file.process_payment.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      ORDERS_TABLE           = aws_dynamodb_table.orders.name
      NOTIFICATION_TOPIC_ARN = aws_sns_topic.order_notifications.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.process_payment]
}

resource "aws_lambda_function" "notify" {
  function_name    = local.notify_fn
  handler          = "notify.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256
  timeout          = 10
  memory_size      = 128

  depends_on = [aws_cloudwatch_log_group.notify]
}

resource "aws_lambda_function" "get_order" {
  function_name    = local.get_order_fn
  handler          = "get_order.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.get_order.output_path
  source_code_hash = data.archive_file.get_order.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      ORDERS_TABLE = aws_dynamodb_table.orders.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.get_order]
}

# SQS trigger for payment processor
resource "aws_lambda_event_source_mapping" "payment_sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.process_payment.arn
  batch_size       = 1
}

# SNS trigger for notify
resource "aws_lambda_permission" "sns_invoke_notify" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.order_notifications.arn
}

resource "aws_sns_topic_subscription" "notify" {
  topic_arn = aws_sns_topic.order_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notify.arn
}

# API Gateway
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "create_order" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.create_order.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_order" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.create_order.id}"
}

resource "aws_apigatewayv2_integration" "get_order" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_order.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_order" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /orders/{order_id}"
  target    = "integrations/${aws_apigatewayv2_integration.get_order.id}"
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_lambda_permission" "apig_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apig_invoke_get_order" {
  statement_id  = "AllowAPIGatewayInvokeGetOrder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
