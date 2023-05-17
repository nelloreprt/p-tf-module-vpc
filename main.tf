# 1. VPC_Creation
resource "aws_vpc" "main" {
  cidr_block       = var.vpc_cidr_block

  tags = {
    merge (var.tags, Name = "${var.env}-vpc-main")
  }
}

#2. Public_subnets
resource "aws_subnet" "public_subnets" {
  vpc_id     = aws_vpc.main.id

  for_each = var.public_subnets
  cidr_block = each.value["cidr_block"]
  availability_zone = each.value["availability_zone"]

  tags = {
    merge( var.tags, Name = "${var.env}-${each.value["name"]}")
  }
}

#3. public_ROUTE_Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
  for_each = var.public_subnets
  tags = {
    merge( var.tags, Name = "${var.env}-${each.value["name"]}")
  }

  # 8. we are adding internet_connection/igw/gateway to Public_Route_Table, so allow all
  route {
  cidr_block = "0.0.0.0/0"      # we are adding internet_connection to Public_Route_Table, so allow all
  gateway_id = aws_internet_gateway.igw.id
  }

  # 13a. # entry in both Public & Private Route_Table
  route {
  # retreiving CIDR block of the Default_vpc using data_source_block
  cidr_block = data.aws_vpc.default_vpc.cidr_block     # enter cidr range of default_vpc      # routing to default_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }
}

#5. public_route_table_association (route-table will be connected to every subnet)
# using output_block we can get subnet_id
resource "aws_route_table_association" "public_route_table_association" {
  for_each = var.public_subnets
  subnet_id      = aws_subnet.public_subnets[each.value["name"]].id     # using output_block we can get subnet_id
  route_table_id = aws_route_table.public_route_table[each.value["name"]].id
}

# --------------------------------------------------------
#3. Private Subnets
resource "aws_subnet" "private_subnets" {
  vpc_id     = aws_vpc.main.id

  for_each = var.private_subnets
  cidr_block = each.value["cidr_block"]
  availability_zone = each.value["availability_zone"]

  tags = {
    merge( var.tags, Name = "${var.env}-${each.value["name"]}")
}
}

#4. private_ROUTE_Table
  resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
  for_each = var.private_subnets
  tags = {
    merge( var.tags, Name = "${var.env}-${each.value["name"]}")
  }

  #11. we need to attach nat_gateway to Private_Route_table (web-az1 & web-az2)
  # nat_gaeway is on Public_subnet, Private_Route_table is attached to Private_subnet
  route {
  cidr_block = "0.0.0.0/0"      # we are adding internet_connection, so allow all
  nat_gateway_id = aws_nat_gateway.nat-gateways[public-split("-", "each.value["name"]")[1]].id
  # we want nat_gateway created in public_subnets >> public-az1 & public-az2
  # but iteration is happening on >> for_each = var.private_subnets >> web-az1, web-az2, app-az1, app-az2, db-az1, db-az2
  }

# without iteration >> hard coding
# public-split("-", "web-az1")[1]

# with iteration >> using for_each >> each.value
# public-split("-", "each.value["name"]")[1]

  # 13b. # entry in both Public & Private Route_Table
  route {
  # retreiving CIDR block of the Default_vpc using data_source_block
  cidr_block = data.aws_vpc.default_vpc.cidr_block     # enter cidr range of default_vpc      # routing to default_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

}

#6. private_route_table_association (route-table will be connected to every subnet)
# using output_block we can get subnet_id
resource "aws_route_table_association" "private_route_table_association" {
  for_each = var.private_subnets
  subnet_id      = aws_subnet.public_subnets[each.value["name"]].id     # using output_block we can get subnet_id
  route_table_id = aws_route_table.public_route_table[each.value["name"]].id
}

#7. adding IGW to VPC (getting internet connection from pole to house)
# for a vpc only one internet gateway is allowed
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
      merge( var.tags, Name = "${var.env}-internet-gateway")
  }
}

#9. creating NAT_Gateway on each public_subnet
resource "aws_nat_gateway" "nat-gateways" {
  for_each = var.public_subnets
  allocation_id = aws_eip.ngw[each.value["name"]].id
  subnet_id     = aws_subnet.public_subnets[each.value["name"]].id

  tags = {
    merge( var.tags, Name = "${var.env}-${each.value["name"]}")
}

#10. eip creation
# the number of elastic_ip depends on the number of Public_Subnets
resource "aws_eip" "ngw" {
  # instance = aws_instance.web.id (not_applicable)
  for_each =  var.public_subnets
  vpc      = true
}
# ---------------------------------------------------------------------------

# after nat gateway creation on public_subnet,
# we need to attach nat_gateway to Private_Route_table (web-az1 & web-az2)

#-------------------------------------------------------------------------------

#12. create peering connection
resource "aws_vpc_peering_connection" "peer" {
  peer_owner_id = data.aws_caller_identity.current.id      # // 1 // peer_owner_id (caller_identity)
  peer_vpc_id   = var.default_vpc_id         # // 2 // TO (default_vpc) >> Target vpc_id to which you want to connect >> in our case it is the default vpc_id
  vpc_id        = aws_vpc.main.id        # // 3 // FROM dev-vpc_id (new_vpc)
  auto_accept = "yes"                    # // 4 // Target vpc has to accept the request manually, since both target_vpc and source_vpc are in same account, we use auto_accept

  tags = merge(var.tags,
    { Name = "${var.env}-vpc-peering" })
  }
}

#--------------------------------------------------------------------------------------------
# on the other side (on the default_vpc) we need to add route(entry) to the default_vpc

#14. Route to default_vpc for the peering to work

// to the Default VPC there will be default_Route_Table, we need to add route to it there
// we will take the help of data.tf


// adding entry in the default_route table to support DEFAULT-VPC
resource "aws_route" "route" {
// 1 // when you create a VPC you will get by default ONE ROUTE_TABLE
route_table_id            = var.default_route_table_id   # enter default_Route_table_Id

// 2 // default_vpc CIDR_range
// " new_vpc cidr range details " we are entering inside the default_route_table using ROUTE
destination_cidr_block    = var.vpc_cidr_block  # enter cidr range of MAIN_vpc (from main.tfvars)

// 3 // how to reach to default_vpc >> using Peering connection
vpc_peering_connection_id = aws_vpc_peering_connection.peer.id

}








