provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

# the lambda code
data "archive_file" "lambda_zip_inline" {
  type        = "zip"
  output_path = "/tmp/lambda-${random_id.id.hex}"
  source {
    content  = <<EOF
module.exports.handler = async (event, context) => {
	console.log(JSON.stringify(event));
	// do some magic ...

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
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.lambda.function_name}"
  retention_in_days = 14
}

# third-party system that calls this lambda

module "third-party-module" {
	source = "./modules/third-party-caller"
	lambda = aws_lambda_function.lambda
}

# tester user
resource "aws_iam_user" "user" {
  name          = "user-${random_id.id.hex}"
  force_destroy = "true"
}

resource "aws_iam_access_key" "user-keys" {
  user = aws_iam_user.user.name
}

resource "aws_iam_user_policy_attachment" "lambda-readonly" {
  user       = aws_iam_user.user.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_ReadOnlyAccess"
}

resource "aws_iam_user_policy_attachment" "logs-readonly" {
  user       = aws_iam_user.user.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
}

output "lambda_arn" {
  value = aws_lambda_function.lambda.arn
}

output "access_key_id" {
  value = aws_iam_access_key.user-keys.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.user-keys.secret
  sensitive = true
}
