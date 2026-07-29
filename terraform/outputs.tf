output "api_endpoint" {
  description = "POST endpoint to create an order"
  value       = "${trimsuffix(aws_apigatewayv2_stage.api.invoke_url, "/")}/orders"
}
