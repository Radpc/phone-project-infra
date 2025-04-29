data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main-vpc.id
}

# ===============================================================
# Subnets =======================================================
# ===============================================================
resource "aws_subnet" "subnet-public" {
  count             = var.subnet_count.public
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "subnet-private" {
  count             = var.subnet_count.private
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# Route tables
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.main-vpc.id
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = var.subnet_count.public
  route_table_id = aws_route_table.public-route-table.id
  subnet_id      = aws_subnet.subnet-public[count.index].id
}
resource "aws_route_table_association" "private" {
  count          = var.subnet_count.private
  route_table_id = aws_route_table.private-route-table.id
  subnet_id      = aws_subnet.subnet-private[count.index].id
}


# Security groups #######################################################
resource "aws_security_group" "ecs-sg" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description = "Allow HTTPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
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
    description = "Allow SSH"
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


resource "aws_security_group" "rds-sg" {
  name        = "db_security_group"
  description = "Security group for the db instance"
  vpc_id      = aws_vpc.main-vpc.id

  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs-sg.id]
  }
}

resource "aws_db_subnet_group" "db-subnet-group" {
  name        = "phone-db-subnet-group"
  description = "DB subnet group"
  subnet_ids  = [for subnet in aws_subnet.subnet-private : subnet.id]
}

resource "aws_db_instance" "db_instance" {
  identifier          = "rds-instance"
  engine              = var.settings.database.engine
  engine_version      = var.settings.database.engine_version
  db_name             = var.settings.database.db_name
  username            = var.rds_user
  password            = var.rds_password
  instance_class      = var.settings.database.instance_class
  allocated_storage   = var.settings.database.allocated_storage
  skip_final_snapshot = var.settings.database.skip_final_snapshot

  vpc_security_group_ids = [aws_security_group.rds-sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db-subnet-group.id
}


resource "aws_instance" "instance" {
  count                  = var.settings.web_app.count
  subnet_id              = aws_subnet.subnet-public[count.index].id
  vpc_security_group_ids = [aws_security_group.ecs-sg.id]

  ami           = "ami-0d866da98d63e2b42"
  instance_type = "t2.medium"
  key_name      = "main-key"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y

              sudo apt install docker.io -y
              sudo apt install apache-2 -y
              sudo systemctl start apache2
              sudo chown -R ubuntu:ubuntu /var/www/

              echo "Installing Node.js..."
              if ! command -v nvm &> /dev/null; then
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
              fi
              nvm install node

              if ! command -v pm2 &> /dev/null; then
              npm install -g pm2
              fi

              EOF
}


resource "aws_eip" "eip" {
  count    = var.settings.web_app.count
  instance = aws_instance.instance[count.index].id
}
