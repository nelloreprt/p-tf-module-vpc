output "public_subnet_id" {
  value = "aws_subnet.public_subnets"
}

# for doc_db
output "private_subnet_id" {
  value = "aws_subnet.private_subnets"
}