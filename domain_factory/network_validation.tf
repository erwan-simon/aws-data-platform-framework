data "aws_route_table" "per_subnet" {
  for_each  = toset(data.aws_subnets.main.ids)
  subnet_id = each.value
}

resource "terraform_data" "network_validation" {
  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.main.ids) > 0
      error_message = "No ${var.use_public_subnets ? "Public" : "Private"} subnets found in VPC ${data.aws_vpc.main.id} (expected tag Tier=${var.use_public_subnets ? "Public" : "Private"}). Check the aws-network-stack deployment."
    }

    precondition {
      condition = alltrue([
        for rt in data.aws_route_table.per_subnet : anytrue([
          for r in rt.routes :
          r.cidr_block == "0.0.0.0/0" && (
            var.use_public_subnets
            ? (r.gateway_id != null && startswith(r.gateway_id, "igw-"))
            : (r.nat_gateway_id != null && r.nat_gateway_id != "")
          )
        ])
      ])
      error_message = var.use_public_subnets ? "At least one selected Public subnet has no 0.0.0.0/0 route via an Internet Gateway — processing tasks would have no internet access." : "At least one selected Private subnet has no 0.0.0.0/0 route via a NAT Gateway — processing tasks would have no internet access. Deploy a NAT (see aws-network-stack) or set use_public_subnets = true."
    }
  }
}
