resource "random_id" "id" {
  byte_length = 8
}

# the lambda code
data "archive_file" "lambda_zip_inline" {
  type        = "zip"
  output_path = "/tmp/lambda-${random_id.id.hex}"
  source {
    content  = <<EOF
const crypto = require("crypto");
const AWS = require("aws-sdk");

module.exports.handler = async (event, context) => {
	const targetLambda = process.env.LAMBDA_ARN;
	const secret = crypto.randomBytes(32).toString("base64");
console.log(targetLambda);

	const lambda = new AWS.Lambda();

	const res = await lambda.invoke({
		FunctionName: targetLambda,
		Payload: JSON.stringify({secret}),
	}).promise();
console.log(res)
console.log("OK")

	return "OK";
};
EOF
    filename = "main.js"
  }
}

resource "aws_iam_role" "lambda_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [
      var.lambda.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "lambda" {
  function_name    = "function-${random_id.id.hex}"
  filename         = data.archive_file.lambda_zip_inline.output_path
  source_code_hash = data.archive_file.lambda_zip_inline.output_base64sha256
  handler          = "main.handler"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda_role.arn
	environment {
		variables = {
			LAMBDA_ARN = var.lambda.arn
		}
	}
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.lambda.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_event_rule" "scheduler" {
	schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "call_function" {
  rule      = aws_cloudwatch_event_rule.scheduler.name
  arn       = aws_lambda_function.lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduler.arn
}
