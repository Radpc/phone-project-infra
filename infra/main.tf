resource "aws_vpc" "main-vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main-vpc.id
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.main-vpc.id
}

# Subnets ##################################################
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "sa-east-1a"
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "sa-east-1a"
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = "sa-east-1b"
}

resource "aws_route_table_association" "public_route_table" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "private_route_table_1" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "private_route_table_2" {
  subnet_id      = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.public-route-table.id
}


# Security groups #######################################################
resource "aws_security_group" "security-group" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Backend API"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RDS Database"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.security-group.id]
}

resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_instance" "instance" {
  ami               = "ami-0d866da98d63e2b42"
  instance_type     = "t2.micro"
  availability_zone = "sa-east-1a"
  key_name          = "main-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y

              echo "Installing Node.js..."
              if ! command -v nvm &> /dev/null; then
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
              fi
              nvm install node

              echo "Installing PM2..."
              if ! command -v pm2 &> /dev/null; then
              npm install -g pm2
              fi

              EOF
}

resource "aws_security_group" "db-security-group" {
  name        = "db_security_group"
  description = "Security group for the db instance"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.security-group.id]
  }
}

resource "aws_db_subnet_group" "db-subnet-group" {
  name        = "db_subnet_group"
  description = "DB subnet group for the RDS"
  subnet_ids  = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
}

resource "aws_db_instance" "db_instance" {
  engine                 = "mysql"
  engine_version         = "8.0.41"
  multi_az               = false
  identifier             = "rds-instance"
  username               = var.rds_user
  password               = var.rds_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 200
  publicly_accessible    = true
  skip_final_snapshot    = true
  availability_zone      = "sa-east-1a"
  vpc_security_group_ids = [aws_db_subnet_group.db-subnet-group.id]
}
